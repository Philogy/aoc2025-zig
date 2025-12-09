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

    const raw_source = std.fs.cwd().readFileAlloc(gpa_alloc, file_path, 0xffffffff) catch |err| {
        std.debug.panic(
            "Failed to load file \"{s}\" (err: {})",
            .{ file_path, err },
        );
    };
    defer gpa_alloc.free(raw_source);

    try part1(raw_source);
    try part2(raw_source);
}

const DELTAS: []const isize = &.{ -1, 0, 1 };

fn part1(source: []const u8) !void {
    var total: u64 = 0;
    const width = std.mem.indexOfScalar(u8, source, '\n') orelse return error.NoNewline;
    const height = source.len / (width + 1);

    for (0..width) |ux| {
        for (0..height) |uy| {
            const char_index = uy * (width + 1) + ux;
            if (source[char_index] != '@') continue;

            var adj: u8 = 0;
            for (DELTAS) |dx| {
                for (DELTAS) |dy| {
                    if (dx == 0 and dy == 0) continue;
                    const x = @as(isize, @intCast(ux)) + dx;
                    if (x < 0 or width <= x) continue;
                    const y = @as(isize, @intCast(uy)) + dy;
                    if (y < 0 or height <= y) continue;

                    const neighbor_index = @as(usize, @intCast(y)) * (width + 1) + @as(usize, @intCast(x));
                    switch (source[neighbor_index]) {
                        '@' => adj += 1,
                        '.' => {},
                        else => |char| std.debug.panic("Unexpected char: '{c}'", .{char}),
                    }
                }
            }

            if (adj < 4) {
                total += 1;
            }
        }
    }

    std.debug.print("part1: {}\n", .{total});
}

fn part2(source: []u8) !void {
    var total: u64 = 0;
    const width = std.mem.indexOfScalar(u8, source, '\n') orelse return error.NoNewline;
    const height = source.len / (width + 1);

    var removed: u64 = 1;
    while (removed > 0) {
        removed = 0;
        for (0..width) |ux| {
            for (0..height) |uy| {
                const char_index = uy * (width + 1) + ux;
                if (source[char_index] != '@') continue;

                var adj: u8 = 0;
                for (DELTAS) |dx| {
                    for (DELTAS) |dy| {
                        if (dx == 0 and dy == 0) continue;
                        const x = @as(isize, @intCast(ux)) + dx;
                        if (x < 0 or width <= x) continue;
                        const y = @as(isize, @intCast(uy)) + dy;
                        if (y < 0 or height <= y) continue;

                        const neighbor_index = @as(usize, @intCast(y)) * (width + 1) + @as(usize, @intCast(x));
                        switch (source[neighbor_index]) {
                            '@' => adj += 1,
                            '.' => {},
                            else => |char| std.debug.panic("Unexpected char: '{c}'", .{char}),
                        }
                    }
                }

                if (adj < 4) {
                    source[char_index] = '.';
                    removed += 1;
                }
            }
        }

        total += removed;
    }

    std.debug.print("part2: {}\n", .{total});
}
