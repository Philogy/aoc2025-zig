const std = @import("std");
const common = @import("common");

const DIAL_START = 50;
const DIAL_SIZE = 100;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer if (gpa.deinit() == .leak) @panic("leaked memory");

    const gpa_alloc = gpa.allocator();
    var arena = std.heap.ArenaAllocator.init(gpa_alloc);
    defer arena.deinit();

    const arena_allocator = arena.allocator();

    var args = try std.process.ArgIterator.initWithAllocator(arena_allocator);
    defer args.deinit();

    _ = args.next() orelse @panic("Missing [PATH] argument ");
    const file_path = args.next() orelse @panic("Missing [PATH] argument");

    const source = std.fs.cwd().readFileAlloc(gpa_alloc, file_path, 0xffffffff) catch {
        std.debug.panic("Failed to load file \"{s}\"", .{file_path});
    };
    defer gpa_alloc.free(source);

    try part1(source);
    try part2(source);
}

fn part1(source: []const u8) !void {
    var dial: i32 = DIAL_START;
    var line_iter = std.mem.splitScalar(u8, source, '\n');
    var times_reached_zero: u32 = 0;

    while (line_iter.next()) |line| {
        if (line.len == 0) continue;

        switch (line.ptr[0]) {
            'R' => {
                const turn = try std.fmt.parseInt(u24, line[1..], 10);
                dial = @mod(dial + turn, 100);
            },
            'L' => {
                const turn = try std.fmt.parseInt(u24, line[1..], 10);
                dial = @mod(dial - turn, 100);
            },
            else => std.debug.panic("Input contained invalid line: \"{s}\"", .{line}),
        }

        if (dial == 0) {
            times_reached_zero += 1;
        }
    }

    std.debug.print("part1: {}\n", .{times_reached_zero});
}

fn part2(source: []const u8) !void {
    var dial_position: u32 = DIAL_START;
    var line_iter = std.mem.splitScalar(u8, source, '\n');
    var times_reached_zero: u32 = 0;

    while (line_iter.next()) |line| {
        if (line.len == 0) continue;

        std.debug.assert(dial_position < DIAL_SIZE);

        switch (line.ptr[0]) {
            'R' => {
                const turn = try std.fmt.parseInt(u32, line[1..], 10);
                dial_position += turn;
                times_reached_zero += @divFloor(dial_position, DIAL_SIZE);
                dial_position = @mod(dial_position, DIAL_SIZE);
            },
            'L' => {
                const turn = try std.fmt.parseInt(u32, line[1..], 10);
                dial_position = (if (dial_position > 0) DIAL_SIZE - dial_position else 0) + turn;
                const reached_naive = @divFloor(dial_position, DIAL_SIZE);
                times_reached_zero += reached_naive;
                dial_position = DIAL_SIZE - @mod(dial_position, DIAL_SIZE);
                if (dial_position == DIAL_SIZE) dial_position = 0;
            },
            else => std.debug.panic("Input contained invalid line: \"{s}\"", .{line}),
        }

        // var buf: [32]u8 = undefined;
        // const padded_line = common.pad_string_left(&buf, line, 4) catch unreachable;
        // std.debug.print("{s} => {:>3} [{}]\n", .{ padded_line, dial_position, times_reached_zero });
    }

    std.debug.print("part2: {}\n", .{times_reached_zero});
}

test "simple test" {
    const gpa = std.testing.allocator;
    var list: std.ArrayList(i32) = .empty;
    defer list.deinit(gpa); // Try commenting this out and see if zig detects the memory leak!
    try list.append(gpa, 41);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
