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

    const source = common.strip_end(raw_source);
    try part1(source);
    try part2(source);
}

const DigitAndPosition = struct { digit: u4, pos: usize };

fn max_digit_and_pos(str: []const u8) ?DigitAndPosition {
    var known_best: ?DigitAndPosition = null;
    for (str, 0..) |char, i| {
        const digit: u4 = @intCast(char - '0');
        if (known_best) |best| {
            if (digit > best.digit) {
                known_best = .{ .digit = digit, .pos = i };
            }
        } else {
            known_best = .{ .digit = digit, .pos = i };
        }
    }
    return known_best;
}

fn part1(source: []const u8) !void {
    var sum: u64 = 0;

    var lines_iter = std.mem.splitScalar(u8, source, '\n');
    while (lines_iter.next()) |line| {
        if (line.len < 2) return error.LineTooShort;
        const first_digit = max_digit_and_pos(line[0 .. line.len - 1]) orelse unreachable;
        const second_digit = max_digit_and_pos(line[first_digit.pos + 1 ..]) orelse unreachable;
        sum += @as(u64, first_digit.digit) * 10 + @as(u64, second_digit.digit);
    }

    std.debug.print("part1: {}\n", .{sum});
}

fn part2(source: []const u8) !void {
    var sum: u64 = 0;

    var lines_iter = std.mem.splitScalar(u8, source, '\n');
    while (lines_iter.next()) |line| {
        if (line.len < 12) return error.LineTooShort;
        var num: u64 = 0;
        var start_pos: usize = 0;
        for (0..12) |i| {
            const end_pos = line.len - 11 + i;
            const next_best = max_digit_and_pos(line[start_pos..end_pos]) orelse unreachable;
            num *= 10;
            num += @as(u64, next_best.digit);
            start_pos += next_best.pos + 1;
        }

        sum += num;
    }

    std.debug.print("part2: {}\n", .{sum});
}

test "simple test" {
    const gpa = std.testing.allocator;
    var list: std.ArrayList(i32) = .empty;
    defer list.deinit(gpa); // Try commenting this out and see if zig detects the memory leak!
    try list.append(gpa, 41);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
