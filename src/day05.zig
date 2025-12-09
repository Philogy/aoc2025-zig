const std = @import("std");
const common = @import("common");
const Range = common.Range;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer if (gpa.deinit() == .leak) @panic("leaked memory");

    const gpa_alloc = gpa.allocator();

    var args = try std.process.ArgIterator.initWithAllocator(gpa_alloc);
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
    try part1(gpa_alloc, source);
    try part2(gpa_alloc, source);
}

fn part1(allocator: std.mem.Allocator, source: []const u8) !void {
    var lines_iter = std.mem.splitScalar(u8, source, '\n');
    var fresh_ranges = try std.ArrayList(Range).initCapacity(allocator, 32);
    defer fresh_ranges.deinit(allocator);

    var total_fresh: u32 = 0;

    while (lines_iter.next()) |line| {
        if (line.len == 0) break;

        var start_end_iter = std.mem.splitScalar(u8, line, '-');
        const start_str = start_end_iter.next() orelse return error.InvalidRange;
        const end_str = start_end_iter.next() orelse return error.InvalidRange;
        if (start_end_iter.next() != null) return error.InvalidRange;

        const start = try std.fmt.parseInt(u64, start_str, 10);
        const end = try std.fmt.parseInt(u64, end_str, 10);

        try fresh_ranges.append(allocator, .{ .start = start, .end = end });
    }

    while (lines_iter.next()) |line| {
        const ingredient = try std.fmt.parseInt(u64, line, 10);
        for (fresh_ranges.items) |range| {
            if (range.contains(ingredient)) {
                total_fresh += 1;
                break;
            }
        }
    }

    std.debug.print("part1: {}\n", .{total_fresh});
}

fn part2(allocator: std.mem.Allocator, source: []const u8) !void {
    var lines_iter = std.mem.splitScalar(u8, source, '\n');
    var fresh_ranges = try std.ArrayList(Range).initCapacity(allocator, 32);
    defer fresh_ranges.deinit(allocator);

    var total_fresh: u64 = 0;

    while (lines_iter.next()) |line| {
        if (line.len == 0) break;

        var start_end_iter = std.mem.splitScalar(u8, line, '-');
        const start_str = start_end_iter.next() orelse return error.InvalidRange;
        const end_str = start_end_iter.next() orelse return error.InvalidRange;
        if (start_end_iter.next() != null) return error.InvalidRange;

        const start = try std.fmt.parseInt(u64, start_str, 10);
        const end = try std.fmt.parseInt(u64, end_str, 10);
        var new_range = Range{ .start = start, .end = end };

        var i: usize = 0;
        while (i < fresh_ranges.items.len) {
            const other = fresh_ranges.items.ptr[i];
            if (new_range.merge_if_overlapping(other)) {
                _ = fresh_ranges.swapRemove(i);
            } else {
                i += 1;
            }
        }

        try fresh_ranges.append(allocator, new_range);
    }

    for (fresh_ranges.items) |range| {
        total_fresh += 1 + range.end - range.start;
    }

    std.debug.print("part2: {}\n", .{total_fresh});
}
