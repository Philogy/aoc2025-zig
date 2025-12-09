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

    try part1(gpa_alloc, points.items, iter_count);
    try part2(gpa_alloc, points.items);
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

const DistanceMatrix = struct {
    distances: [][]u64,

    const Self = @This();

    fn init(alloc: std.mem.Allocator, points: []const Point) !Self {
        var distances = try alloc.alloc([]u64, points.len);
        for (distances) |*row| {
            row.* = try alloc.alloc(u64, points.len);
        }
        for (points, 0..) |p1, i| {
            for (points, 0..) |p2, j| {
                const d = p1.dist(&p2);
                if (i != j) std.debug.assert(d != 0);
                distances[i][j] = d;
            }
        }
        return .{ .distances = distances };
    }

    fn deinit(self: *Self, alloc: std.mem.Allocator) void {
        for (self.distances) |row| {
            alloc.free(row);
        }
        alloc.free(self.distances);

        self.distances = undefined;
    }

    fn get(self: *const Self, i: usize, j: usize) ?u64 {
        return self.distances[i][j];
    }

    fn set(self: *const Self, i: usize, j: usize, d: u64) !void {
        self.distances[i][j] = d;
    }

    const Indices = struct { usize, usize };

    fn get_smallest_non_zero(self: *const Self, points: []const Point) ?Indices {
        var smallest_distance: u64 = std.math.maxInt(u64);
        var best_pair: ?Indices = null;

        for (0..points.len) |i| {
            for (i + 1..points.len) |j| {
                const d = self.distances[i][j];
                if (d != 0 and smallest_distance > d) {
                    smallest_distance = d;
                    best_pair = .{ i, j };
                }
            }
        }

        return best_pair;
    }
};

fn part1(gpa: std.mem.Allocator, points: []const Point, iters: u32) !void {
    var dist_matrix = try gpa.alloc([]u64, points.len);
    for (dist_matrix) |*row| {
        row.* = try gpa.alloc(u64, points.len);
    }
    defer {
        for (dist_matrix) |row| {
            gpa.free(row);
        }
        gpa.free(dist_matrix);
    }
    for (points, 0..) |p1, i| {
        for (points, 0..) |p2, j| {
            const d = p1.dist(&p2);
            if (i != j) std.debug.assert(d != 0);
            dist_matrix[i][j] = d;
        }
    }

    var circuits = try gpa.alloc(u16, points.len);
    defer gpa.free(circuits);
    for (0..points.len) |i| {
        circuits[i] = @intCast(i);
    }

    for (0..iters) |_| {
        var smallest_distance: u64 = std.math.maxInt(u64);
        var best_pair: ?struct { usize, usize } = null;

        for (0..points.len) |i| {
            for (i + 1..points.len) |j| {
                const d = dist_matrix[i][j];
                if (d != 0 and smallest_distance > d) {
                    smallest_distance = d;
                    best_pair = .{ i, j };
                }
            }
        }

        const i, const j = best_pair orelse @panic("Ran out of pairs");
        dist_matrix[i][j] = 0;
        dist_matrix[j][i] = 0;

        const parent_circuit = circuits[i];
        const child_circuit = circuits[j];
        for (circuits) |*circuit| {
            if (circuit.* == child_circuit) {
                circuit.* = parent_circuit;
            }
        }
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

fn connect_circuits(circuits: []u16, parent: u16, child: u16) bool {
    if (parent == child) return false;
    for (circuits) |*circuit| {
        if (circuit.* == child) {
            circuit.* = parent;
        }
    }

    const first = circuits[0];
    for (circuits[1..]) |circuit| {
        if (circuit != first) {
            return false;
        }
    }

    return true;
}

fn part2(gpa: std.mem.Allocator, points: []const Point) !void {
    var distances = try DistanceMatrix.init(gpa, points);
    defer distances.deinit(gpa);

    var circuits = try gpa.alloc(u16, points.len);
    defer gpa.free(circuits);
    for (0..points.len) |i| {
        circuits[i] = @intCast(i);
    }

    while (true) {
        const i, const j = distances.get_smallest_non_zero(points) orelse @panic("Ran out of pairs");
        try distances.set(i, j, 0);
        try distances.set(j, i, 0);

        const parent_circuit = circuits[i];
        const child_circuit = circuits[j];
        if (connect_circuits(circuits, parent_circuit, child_circuit)) {
            const multiplied_x: u64 = @as(u64, @intCast(points[i].x)) * @as(u64, @intCast(points[j].x));
            std.debug.print("part2: {}\n", .{multiplied_x});
            return;
        }
    }
}
