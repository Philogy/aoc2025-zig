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

    var points_buf: [496]Point = undefined;
    var points_list = std.ArrayList(Point).initBuffer(&points_buf);
    {
        var lines_iter = std.mem.splitScalar(u8, source, '\n');
        while (lines_iter.next()) |line| {
            if (line.len == 0) continue;
            try points_list.appendBounded(try Point.parse_from_line(line));
        }
    }
    const points = points_list.items;
    var pairs_by_area = blk: {
        var pairs = try gpa_alloc.alloc(PointPair, points.len * (points.len - 1) / 2);
        var pi: usize = 0;
        for (0..points.len) |i| {
            for (i + 1..points.len) |j| {
                pairs[pi] = .{ .i = @intCast(i), .j = @intCast(j) };
                pi += 1;
            }
        }
        break :blk Queue.fromOwnedSlice(gpa_alloc, pairs, points);
    };
    defer pairs_by_area.deinit();

    try part1(&pairs_by_area, points);
    try part2(gpa_alloc, &pairs_by_area, points);
}

const Point = struct {
    x: u32,
    y: u32,

    const Self = @This();

    fn parse_from_line(line: []const u8) !Self {
        var nums_iter = std.mem.splitScalar(u8, line, ',');
        const xstr = nums_iter.next() orelse return error.MissingNum;
        const ystr = nums_iter.next() orelse return error.MissingNum;
        const x = try std.fmt.parseInt(u32, xstr, 10);
        const y = try std.fmt.parseInt(u32, ystr, 10);
        return .{ .x = x, .y = y };
    }
};

fn diff(a: u32, b: u32) u64 {
    return @intCast(if (a > b) a - b else b - a);
}

const PointPair = struct {
    i: u16,
    j: u16,

    const Self = @This();

    fn area(self: Self, points: []const Point) u64 {
        const a = points[self.i];
        const b = points[self.j];
        return (diff(a.x, b.x) + 1) * (diff(a.y, b.y) + 1);
    }

    fn cmp_pair_area(points: []const Point, a: Self, b: Self) std.math.Order {
        const area_a = a.area(points);
        const area_b = b.area(points);
        return std.math.order(area_a, area_b).invert();
    }
};

const Queue = std.PriorityQueue(PointPair, []const Point, PointPair.cmp_pair_area);

const Sign = enum {
    pos,
    neg,

    const Self = @This();

    fn flip(self: Self) Self {
        return switch (self) {
            .pos => .neg,
            .neg => .pos,
        };
    }
};

const Axis = enum { x, y };

const Line = struct {
    direction: Axis,
    plane: u32,
    start: u32,
    end: u32,

    const Self = @This();

    fn from_points(p1: Point, p2: Point) Self {
        if (p1.y == p2.y) {
            return .{
                .direction = .x,
                .plane = p1.y,
                .start = @min(p1.x, p2.x),
                .end = @max(p1.x, p2.x),
            };
        } else {
            std.debug.assert(p1.x == p2.x);
            return .{
                .direction = .y,
                .plane = p1.x,
                .start = @min(p1.y, p2.y),
                .end = @max(p1.y, p2.y),
            };
        }
    }
};

/// Ray flying infinitely in positive direction if its `direction`.
const Ray = struct {
    direction: Axis,
    plane: u32,
    start: u32,

    const Self = @This();

    fn intersects(self: Self, line: Line) ?u32 {
        if (line.direction == self.direction) {
            if (self.plane != line.plane) return null;
            if (line.end < self.start) return null;
            return @max(self.start, line.start);
        }
        if (line.plane < self.start) return null;
        if (self.plane < line.start) return null;
        if (self.plane > line.end) return null;
        return line.plane;
    }
};

const Lines = struct {
    points: []const Point,
    bounding_box: Rectangle,
    alloc: std.mem.Allocator,
    inside: []Sign,
    // x_index: []u16,
    // y_index: []u16,

    const Self = @This();

    fn init(alloc: std.mem.Allocator, points: []const Point) !Self {
        const inside = try alloc.alloc(Sign, points.len);
        // const x_index = try alloc.alloc(u16, points.len);
        // const y_index = try alloc.alloc(u16, points.len);
        //
        // build_indices(x_index, y_index, points);

        var lines: Self = .{
            .points = points,
            .inside = inside,
            .bounding_box = get_bounding_box(points),
            .alloc = alloc,
        };

        lines.map_line_insideness();

        return lines;
    }

    fn build_indices(x_index: []u16, y_index: []u16, points: []const Point) void {
        for (0..points.len) |i| {
            x_index[i] = @intCast(i);
            y_index[i] = @intCast(i);
        }
    }

    fn map_line_insideness(self: *Self) void {
        var last_line: Line, const index = for (0..self.points.len) |i| {
            const line = self.get_line(i);
            switch (line.direction) {
                .x => {
                    if (line.plane == self.bounding_box.y1) {
                        self.inside[i] = .pos;
                        break .{ line, i };
                    }
                    if (line.plane == self.bounding_box.y2) {
                        self.inside[i] = .neg;
                        break .{ line, i };
                    }
                },
                .y => {
                    if (line.plane == self.bounding_box.x1) {
                        self.inside[i] = .pos;
                        break .{ line, i };
                    }
                    if (line.plane == self.bounding_box.x2) {
                        self.inside[i] = .neg;
                        break .{ line, i };
                    }
                },
            }
        } else unreachable;

        var last_index: usize = index;

        for (1..self.points.len) |di| {
            const i = (index + di) % self.points.len;
            defer last_index = i;
            const line = self.get_line(i);
            defer last_line = line;

            const last_inside = self.inside[last_index];
            if (last_line.direction == line.direction) {
                self.inside[i] = last_inside;
            } else {
                if ((last_line.start == line.plane) == (last_line.plane == line.start)) {
                    self.inside[i] = last_inside;
                } else {
                    self.inside[i] = last_inside.flip();
                }
            }
        }
    }

    fn deinit(self: *Self) void {
        self.alloc.free(self.inside);
        self.inside = undefined;
    }

    fn get_line(self: *const Self, i: usize) Line {
        std.debug.assert(i < self.points.len);
        const p1 = self.points.ptr[i];
        const p2 = self.points.ptr[(i + 1) % self.points.len];
        return .from_points(p1, p2);
    }

    fn get_bounding_box(points: []const Point) Rectangle {
        var x1 = points[0].x;
        var x2 = points[0].x;
        var y1 = points[0].y;
        var y2 = points[0].y;
        for (points[1..]) |point| {
            x1 = @min(x1, point.x);
            x2 = @max(x2, point.x);
            y1 = @min(y1, point.y);
            y2 = @max(y2, point.y);
        }
        return .{
            .x1 = x1,
            .y1 = y1,
            .x2 = x2,
            .y2 = y2,
        };
    }

    const Intersect = struct {
        line: Line,
        intersect: u32,
        inside: Sign,
    };

    fn find_intersecting(self: *const Self, ray: Ray, result_buf: []Intersect) []const Intersect {
        var intersects = std.ArrayList(Intersect).initBuffer(result_buf);

        for (0..self.points.len) |i| {
            const new_line = self.get_line(i);
            const new = Intersect{
                .line = new_line,
                .intersect = ray.intersects(new_line) orelse continue,
                .inside = self.inside[i],
            };

            if (intersects.items.len == 0) {
                intersects.appendAssumeCapacity(new);
            } else {
                const prev = intersects.items[0];
                switch (std.math.order(new.intersect, prev.intersect)) {
                    .eq => intersects.appendAssumeCapacity(new),
                    .lt => {
                        intersects.clearRetainingCapacity();
                        intersects.appendAssumeCapacity(new);
                    },
                    .gt => {},
                }
            }
        }

        return intersects.items;
    }

    fn line_in_bounds(self: *const Self, line_to_trace: Line) bool {
        var results_buf: [2]Intersect = undefined;

        var tracer: Ray = .{
            .direction = line_to_trace.direction,
            .plane = line_to_trace.plane,
            .start = line_to_trace.start,
        };
        for (0..100000) |_| {
            if (tracer.start >= line_to_trace.end) {
                return true;
            }

            const intersects = self.find_intersecting(tracer, &results_buf);
            if (intersects.len == 0) return false;

            var new_start = tracer.start + 1;
            for (intersects) |intersect| {
                const wall = intersect.line;
                if (wall.direction == tracer.direction) {
                    new_start = @max(new_start, wall.end);
                } else {
                    new_start = @max(new_start, wall.plane);
                    if (tracer.start < wall.plane and intersect.inside != .neg) {
                        return false;
                    }
                }
            }
            tracer.start = new_start;
        }

        unreachable;
    }

    fn rect_in_bounds(self: *const Self, i: u16, j: u16) bool {
        const p1 = self.points[i];
        const p2 = self.points[j];
        const x1 = @min(p1.x, p2.x);
        const y1 = @min(p1.y, p2.y);
        const x2 = @max(p1.x, p2.x);
        const y2 = @max(p1.y, p2.y);

        const low_x: Line = .{ .direction = .x, .plane = y1, .start = x1, .end = x2 };
        const low_y: Line = .{ .direction = .y, .plane = x1, .start = y1, .end = y2 };
        const high_x: Line = .{ .direction = .x, .plane = y2, .start = x1, .end = x2 };
        const high_y: Line = .{ .direction = .y, .plane = x2, .start = y1, .end = y2 };

        return (self.line_in_bounds(low_x) and self.line_in_bounds(low_y) and self.line_in_bounds(high_x) and self.line_in_bounds(high_y));
    }
};

const Rectangle = struct {
    x1: u32,
    y1: u32,
    x2: u32,
    y2: u32,
};

fn part1(pairs_by_area: *Queue, points: []const Point) !void {
    const largest_area = pairs_by_area.peek().?.area(points);
    std.debug.print("part1: {}\n", .{largest_area});
}

fn part2(gpa: std.mem.Allocator, points_by_area: *Queue, points: []const Point) !void {
    var lines = try Lines.init(gpa, points);
    defer lines.deinit();

    const best_area = while (points_by_area.removeOrNull()) |pair| {
        if (lines.rect_in_bounds(pair.i, pair.j)) {
            break pair.area(points);
        }
    } else {
        return error.NoRectangleFound;
    };

    std.debug.print("part2: {}\n", .{best_area});
}

test "hello" {
    const gpa = std.testing.allocator;
    const points: []const Point = &.{
        .{ .x = 10, .y = 10 },
        .{ .x = 30, .y = 10 },
        .{ .x = 30, .y = 20 },
        .{ .x = 10, .y = 20 },
    };

    var lines = try Lines.init(gpa, points);
    defer lines.deinit();

    try std.testing.expect(lines.line_in_bounds(.{
        .direction = .x,
        .plane = 15,
        .start = 10,
        .end = 30,
    }));
    try std.testing.expect(!lines.line_in_bounds(.{
        .direction = .x,
        .plane = 15,
        .start = 9,
        .end = 30,
    }));
    try std.testing.expect(lines.line_in_bounds(.{
        .direction = .x,
        .plane = 15,
        .start = 18,
        .end = 30,
    }));
}
