const std = @import("std");
const common = @import("common");

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
    try part1(source);
    try part2(source);
}

fn part1(source: []const u8) !void {
    var lines_iter = std.mem.splitScalar(u8, source, '\n');
    const nums1_str = lines_iter.next() orelse return error.MissingLine;
    const nums2_str = lines_iter.next() orelse return error.MissingLine;
    const nums3_str = lines_iter.next() orelse return error.MissingLine;
    const nums4_str = lines_iter.next() orelse return error.MissingLine;
    const ops_str = lines_iter.next() orelse return error.MissingLine;

    var grand_sum: u64 = 0;
    var nums1_iter = common.split_cleaned(nums1_str, ' ');
    var nums2_iter = common.split_cleaned(nums2_str, ' ');
    var nums3_iter = common.split_cleaned(nums3_str, ' ');
    var nums4_iter = common.split_cleaned(nums4_str, ' ');
    var ops_iter = common.split_cleaned(ops_str, ' ');
    while (nums1_iter.next()) |num1_str| {
        const num1 = try std.fmt.parseInt(u64, num1_str, 10);
        const num2 = try std.fmt.parseInt(u64, nums2_iter.next() orelse return error.OutOfSyncRows, 10);
        const num3 = try std.fmt.parseInt(u64, nums3_iter.next() orelse return error.OutOfSyncRows, 10);
        const num4 = try std.fmt.parseInt(u64, nums4_iter.next() orelse return error.OutOfSyncRows, 10);
        const op = ops_iter.next() orelse return error.OutOfSyncRows;
        grand_sum += switch (op[0]) {
            '+' => num1 + num2 + num3 + num4,
            '*' => num1 * num2 * num3 * num4,
            else => |c| std.debug.panic("Unknown op: '{c}'", .{c}),
        };
    }

    std.debug.print("part1: {}\n", .{grand_sum});
}

fn part2(source: []const u8) !void {
    var lines_iter = std.mem.splitScalar(u8, source, '\n');
    const nums = [4][]const u8{
        lines_iter.next() orelse return error.MissingLine,
        lines_iter.next() orelse return error.MissingLine,
        lines_iter.next() orelse return error.MissingLine,
        lines_iter.next() orelse return error.MissingLine,
    };
    const ops_str = lines_iter.next() orelse return error.MissingLine;

    var ops_iter = common.split_cleaned(ops_str, ' ');

    var char_index: usize = 0;
    var grand_sum: u64 = 0;
    while (ops_iter.next()) |op| {
        var acc: ?u64 = null;
        var empty = false;
        while (!empty and char_index < nums[0].len) {
            empty = true;
            var num: u64 = 0;
            for (nums) |num_str| {
                switch (num_str[char_index]) {
                    ' ' => {},
                    '0'...'9' => |char| {
                        num *= 10;
                        num += @intCast(char - '0');
                        empty = false;
                    },
                    else => |char| std.debug.panic("Unexpected digit '{c}'", .{char}),
                }
            }
            if (!empty) {
                if (acc) |num_acc| {
                    acc = switch (op[0]) {
                        '*' => num_acc * num,
                        '+' => num_acc + num,
                        else => |other_op| std.debug.panic("Invalid operand '{c}'", .{other_op}),
                    };
                } else {
                    acc = num;
                }
            }
            char_index += 1;
        }

        grand_sum += acc.?;
    }

    std.debug.print("part2: {}\n", .{grand_sum});
}
