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

    const source = std.fs.cwd().readFileAlloc(gpa_alloc, file_path, 0xffffffff) catch |err| {
        std.debug.panic(
            "Failed to load file \"{s}\" (err: {})",
            .{ file_path, err },
        );
    };
    defer gpa_alloc.free(source);

    try part1(source);
    try part2(source);
}

fn sum_matching(range_start: u64, range_end: u64, unit_digits: u5, repetitions: u5) u64 {
    const digs_factor = std.math.pow(u64, 10, unit_digits);
    const mul_mask = mask: {
        var mask_inner: u64 = 0;
        for (0..repetitions) |_| {
            mask_inner *= digs_factor;
            mask_inner += 1;
        }
        break :mask mask_inner;
    };
    var sum: u64 = 0;
    const min_with_digs = digs_factor / 10;
    for (min_with_digs..digs_factor) |unit| {
        const num: u64 = mul_mask * unit;
        if (range_start <= num) {
            if (num <= range_end) {
                sum += num;
            } else {
                break;
            }
        }
    }
    return sum;
}

fn part1(unstripped_source: []const u8) !void {
    const source = common.strip_end(unstripped_source);
    var ranges_iter = std.mem.splitScalar(u8, source, ',');

    var sum: u64 = 0;

    while (ranges_iter.next()) |range| {
        var start_end = std.mem.splitScalar(u8, range, '-');
        const start_str = start_end.next() orelse return error.InvalidRange;
        const end_str = start_end.next() orelse return error.InvalidRange;
        if (start_end.next() != null) return error.InvalidRange;
        const range_start = try std.fmt.parseInt(u64, start_str, 10);
        const range_end = try std.fmt.parseInt(u64, end_str, 10);

        for (start_str.len..end_str.len + 1) |size| {
            if (size % 2 == 1) continue;
            sum += sum_matching(range_start, range_end, @intCast(size / 2), 2);
        }
    }

    std.debug.print("part1: {}\n", .{sum});
}

const FOUND_CAPACITY = 64;

const FoundStore = struct {
    matching: [FOUND_CAPACITY]u64 = undefined,
    digits: [FOUND_CAPACITY]u5 = undefined,
    len: u8 = 0,

    fn push(self: *FoundStore, digits: u5, matching: u64) error{FoundOverflow}!void {
        if (self.len == FOUND_CAPACITY) return error.FoundOverflow;
        self.matching[self.len] = matching;
        self.digits[self.len] = digits;
        self.len += 1;
    }

    fn reset(self: *FoundStore) void {
        self.len = 0;
    }

    fn get_sum_adjustment(self: *const FoundStore, digits: u5) u64 {
        var adjustment: u64 = 0;
        for (self.digits[0..self.len], self.matching[0..self.len]) |prev_digits, matching| {
            if (digits % prev_digits == 0) adjustment += matching;
        }
        return adjustment;
    }
};

fn part2(unstripped_source: []const u8) !void {
    const source = common.strip_end(unstripped_source);
    var ranges_iter = std.mem.splitScalar(u8, source, ',');

    var sum: u64 = 0;
    var found = FoundStore{};

    while (ranges_iter.next()) |range| {
        var start_end = std.mem.splitScalar(u8, range, '-');
        const start_str = start_end.next() orelse return error.InvalidRange;
        const end_str = start_end.next() orelse return error.InvalidRange;
        if (start_end.next() != null) return error.InvalidRange;
        const range_start = try std.fmt.parseInt(u64, start_str, 10);
        const range_end = try std.fmt.parseInt(u64, end_str, 10);

        for (start_str.len..end_str.len + 1) |digits| {
            found.reset();
            for (1..digits) |pattern_size| {
                if (digits % pattern_size != 0) continue;
                const matching = sum_matching(range_start, range_end, @intCast(pattern_size), @intCast(digits / pattern_size));

                const pattern_digits: u5 = @intCast(pattern_size);
                const adjusted_matching = matching - found.get_sum_adjustment(pattern_digits);
                sum += adjusted_matching;
                try found.push(pattern_digits, adjusted_matching);
            }
        }
    }

    std.debug.print("part2: {}\n", .{sum});
}
