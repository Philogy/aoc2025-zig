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
    const iter_count = if (args.next()) |iter_count_str| try std.fmt.parseInt(u32, iter_count_str, 10) else 1000;

    const source = std.fs.cwd().readFileAlloc(gpa_alloc, file_path, 0xffffffff) catch |err| {
        std.debug.panic(
            "Failed to load file \"{s}\" (err: {})",
            .{ file_path, err },
        );
    };
    defer gpa_alloc.free(source);

    var points = try std.ArrayList(Point).initCapacity(gpa_alloc, 1024);
    defer points.deinit(gpa_alloc);

    var lines_iter = std.mem.splitScalar(u8, common.strip_end(source), '\n');
    while (lines_iter.next()) |line| {
        try points.append(gpa_alloc, try Point.parse_from_line(line));
    }

    var distances = try DistanceFinder.init(gpa_alloc, points.items);
    defer distances.deinit();

    try part1(gpa_alloc, &distances, points.items, iter_count);
    try part2(gpa_alloc, &distances, points.items);
}

const Point = struct {
    x: u32,
    y: u32,
    z: u32,

    const Self = @This();

    fn dist(self: *const Self, o: *const Self) u64 {
        const dx: u64 = @intCast(if (self.x > o.x) self.x - o.x else o.x - self.x);
        const dy: u64 = @intCast(if (self.y > o.y) self.y - o.y else o.y - self.y);
        const dz: u64 = @intCast(if (self.z > o.z) self.z - o.z else o.z - self.z);
        return dx * dx + dy * dy + dz * dz;
    }

    fn parse_from_line(line: []const u8) !Self {
        var nums_iter = std.mem.splitScalar(u8, line, ',');
        const x = try std.fmt.parseInt(u32, nums_iter.next() orelse return error.MissingComponent, 10);
        const y = try std.fmt.parseInt(u32, nums_iter.next() orelse return error.MissingComponent, 10);
        const z = try std.fmt.parseInt(u32, nums_iter.next() orelse return error.MissingComponent, 10);

        return .{ .x = x, .y = y, .z = z };
    }
};

const DistanceFinder = struct {
    distances: Queue,

    const Self = @This();
    const Queue = std.PriorityQueue(PointPair, void, pair_compare);

    const PointPair = struct { i: u16, j: u16, distance: u64 };

    fn pair_compare(_: void, a: PointPair, b: PointPair) std.math.Order {
        if (a.distance < b.distance) return .lt;
        if (a.distance > b.distance) return .gt;
        return .eq;
    }

    fn init(alloc: std.mem.Allocator, points: []const Point) !Self {
        const total_points = points.len * (points.len - 1) / 2;
        var distances = try alloc.alloc(PointPair, total_points);

        var bi: usize = 0;
        for (points, 0..) |p1, i| {
            for (points[i + 1 ..], (i + 1)..) |p2, j| {
                const d = p1.dist(&p2);
                distances[bi] = .{
                    .i = @intCast(i),
                    .j = @intCast(j),
                    .distance = d,
                };
                bi += 1;
            }
        }
        return .{ .distances = Queue.fromOwnedSlice(alloc, distances, {}) };
    }

    fn return_popped(self: *Self, pairs: []const PointPair) void {
        self.distances.addSlice(pairs) catch unreachable;
    }

    fn deinit(self: *Self) void {
        self.distances.deinit();
    }

    fn get(self: *const Self, i: usize, j: usize) ?u64 {
        return self.distances[i][j];
    }

    fn set(self: *const Self, i: usize, j: usize, d: u64) !void {
        self.distances[i][j] = d;
    }

    fn get_smallest(self: *Self) ?PointPair {
        return self.distances.removeOrNull();
    }
};

fn part1(
    gpa: std.mem.Allocator,
    distances: *DistanceFinder,
    points: []const Point,
    iters: u32,
) !void {
    var circuits = try gpa.alloc(u16, points.len);
    defer gpa.free(circuits);
    for (0..points.len) |i| {
        circuits[i] = @intCast(i);
    }

    var best_pairs = try std.ArrayList(DistanceFinder.PointPair).initCapacity(gpa, iters);
    defer {
        distances.return_popped(best_pairs.items);
        best_pairs.deinit(gpa);
    }

    for (0..iters) |_| {
        const pair = distances.get_smallest() orelse @panic("Ran out of pairs");
        const i = pair.i;
        const j = pair.j;

        const parent_circuit = circuits[i];
        const child_circuit = circuits[j];
        _ = update_circuits(circuits, parent_circuit, child_circuit);

        best_pairs.appendAssumeCapacity(pair);
    }

    var member_count = try gpa.alloc(u16, points.len);
    @memset(member_count, 0);

    defer gpa.free(member_count);
    for (circuits) |circuit| {
        member_count[circuit] += 1;
    }

    std.sort.block(u16, member_count, {}, std.sort.desc(u16));

    var final_product: u64 = 1;
    for (0..3) |i| {
        final_product *= @intCast(member_count[i]);
    }

    std.debug.print("part1: {}\n", .{final_product});
}

fn update_circuits(circuits: []u16, parent: u16, child: u16) enum { connected_all, more_todo } {
    if (parent == child) return .more_todo;
    for (circuits) |*circuit| {
        if (circuit.* == child) {
            circuit.* = parent;
        }
    }

    const first = circuits[0];
    for (circuits[1..]) |circuit| {
        if (circuit != first) {
            return .more_todo;
        }
    }
    return .connected_all;
}

fn part2(gpa: std.mem.Allocator, distances: *DistanceFinder, points: []const Point) !void {
    var circuits = try gpa.alloc(u16, points.len);
    defer gpa.free(circuits);
    for (0..points.len) |i| {
        circuits[i] = @intCast(i);
    }

    while (true) {
        const pair = distances.get_smallest() orelse @panic("Ran out of pairs");
        const i = pair.i;
        const j = pair.j;

        const parent_circuit = circuits[i];
        const child_circuit = circuits[j];
        if (update_circuits(circuits, parent_circuit, child_circuit) == .connected_all) {
            const multiplied_x: u64 = @as(u64, @intCast(points[i].x)) * @as(u64, @intCast(points[j].x));
            std.debug.print("part2: {}\n", .{multiplied_x});
            return;
        }
    }
}
