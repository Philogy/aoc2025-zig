const std = @import("std");
const common = @import("common");

const DIAL_START = 50;
const DIAL_SIZE = 100;

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

    const manifold = TachyonManifold.init(source).?;
    try part1(&manifold);
    try part2(&manifold);
}

const TachyonManifold = struct {
    image: []const u8,
    width: usize,
    height: usize,

    const Self = @This();

    fn init(image: []const u8) ?Self {
        const width = std.mem.indexOfScalar(u8, image, '\n') orelse return null;
        const height = image.len / (width + 1);
        return .{ .image = image, .width = width, .height = height };
    }

    const Object = enum { source, splitter, empty };

    const GetError = error{ OutOfBounds, InvalidPixel, NoSource };

    fn find_source(self: *const TachyonManifold) GetError!struct { usize, usize } {
        for (0..self.height) |y| {
            for (0..self.width) |x| {
                const obj = try self.get(x, y);
                if (obj == .source) return .{ x, y };
            }
        }
        return error.NoSource;
    }

    fn get(self: *const TachyonManifold, x: usize, y: usize) GetError!Object {
        if (x >= self.width) return error.OutOfBounds;
        if (y >= self.height) return error.OutOfBounds;
        const char_index = y * (self.width + 1) + x;
        return switch (self.image.ptr[char_index]) {
            'S' => .source,
            '^' => .splitter,
            '.' => .empty,
            else => |char| {
                std.debug.print("self.image.len: {}\n", .{self.image.len});
                std.debug.print("char_index: {}\n", .{char_index});
                std.debug.print("invalid_char: '{c}'\n", .{char});
                return error.InvalidPixel;
            },
        };
    }
};

fn Beams(comptime beam_count: comptime_int) type {
    return struct {
        state: [BEAM_STATE_BYTES]u8 = .{0} ** BEAM_STATE_BYTES,
        bit_in_use: u1 = 0,

        const BEAM_STATES = 2;
        const BEAM_COUNT = beam_count;
        const STATES_PER_BYTE = 8 / BEAM_STATES;
        const BEAM_STATE_BYTES = BEAM_COUNT / STATES_PER_BYTE;

        const Self = @This();

        fn reset_next(self: *Self) void {
            const keep_mask: u8 = @as(u8, 0b01010101) << self.bit_in_use;
            for (&self.state) |*cell| {
                cell.* &= keep_mask;
            }
        }

        fn use_next(self: *Self) void {
            self.bit_in_use ^= 1;
            self.reset_next();
        }

        fn set_next(self: *Self, i: usize) void {
            if (i >= BEAM_COUNT) unreachable;
            const cell_index = i / STATES_PER_BYTE;
            const cell_shift: u3 = @intCast((i % STATES_PER_BYTE) * BEAM_STATES);
            self.state[cell_index] |= (@as(u8, 0b10) >> self.bit_in_use) << cell_shift;
        }

        fn get(self: *const Self, i: usize) bool {
            if (i >= BEAM_COUNT) unreachable;
            const cell_index = i / STATES_PER_BYTE;
            const cell_shift: u3 = @intCast((i % STATES_PER_BYTE) * BEAM_STATES);
            const check_mask = (@as(u8, 0b01) << self.bit_in_use) << cell_shift;
            return (self.state[cell_index] & check_mask) != 0;
        }
    };
}

fn part1(manifold: *const TachyonManifold) !void {
    const source_x, const source_y = try manifold.find_source();
    if (source_y != 0) return error.NoSourceAtStart;
    if (manifold.width > 256) return error.ManifoldTooLarge;

    var beams = Beams(256){};
    beams.set_next(source_x);

    var total_splits: u64 = 0;

    for (1..manifold.height) |y| {
        beams.use_next();
        for (0..manifold.width) |x| {
            if (!beams.get(x)) continue;
            const obj = try manifold.get(x, y);
            if (obj == .splitter) {
                total_splits += 1;
                beams.set_next(x - 1);
                beams.set_next(x + 1);
            } else {
                beams.set_next(x);
            }
        }
    }

    std.debug.print("part1: {}\n", .{total_splits});
}

const Ray = struct { x: u8, paths: u64 };

fn push_ray(list: *std.ArrayList(Ray), new_ray: Ray) !void {
    for (list.items) |*existing_ray| {
        if (existing_ray.x == new_ray.x) {
            existing_ray.paths += new_ray.paths;
            return;
        }
    }

    try list.appendBounded(new_ray);
}

fn part2(manifold: *const TachyonManifold) !void {
    const source_x, const source_y = try manifold.find_source();
    if (source_y != 0) return error.NoSourceAtStart;
    if (manifold.width > 256) return error.ManifoldTooLarge;

    var buf1: [200]Ray = undefined;
    var buf2: [200]Ray = undefined;
    var rays1 = std.ArrayList(Ray).initBuffer(&buf1);
    var rays2 = std.ArrayList(Ray).initBuffer(&buf2);

    var next = &rays1;
    var current = &rays2;
    current.appendAssumeCapacity(.{ .x = @intCast(source_x), .paths = 1 });

    for (1..manifold.height) |y| {
        next.clearRetainingCapacity();

        for (current.items) |ray| {
            const obj = try manifold.get(ray.x, y);
            if (obj == .splitter) {
                if (ray.x == 0 or ray.x == manifold.width - 1) return error.RaySplitOutOfBounds;
                try push_ray(next, .{ .x = ray.x - 1, .paths = ray.paths });
                try push_ray(next, .{ .x = ray.x + 1, .paths = ray.paths });
            } else {
                try push_ray(next, ray);
            }
        }

        const tmp = current;
        current = next;
        next = tmp;
    }

    var total_paths: u64 = 0;
    for (next.items) |ray| {
        total_paths += ray.paths;
    }

    std.debug.print("part2: {}\n", .{total_paths});
}
