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
    inside: Sign,
    plane: u32,
    start: u32,
    end: u32,

    const Self = @This();

    fn from_points(p1: Point, p2: Point) Self {
        if (p1.y == p2.y) {
            return .{
                .direction = .x,
                .inside = undefined,
                .plane = p1.y,
                .start = @min(p1.x, p2.x),
                .end = @max(p1.x, p2.x),
            };
        } else {
            std.debug.assert(p1.x == p2.x);
            return .{
                .direction = .y,
                .inside = undefined,
                .plane = p1.x,
                .start = @min(p1.y, p2.y),
                .end = @max(p1.y, p2.y),
            };
        }
    }

    fn min_x(self: Self) u32 {
        return switch (self.direction) {
            .x => self.start,
            .y => self.plane,
        };
    }

    fn min_y(self: Self) u32 {
        return switch (self.direction) {
            .x => self.plane,
            .y => self.start,
        };
    }

    fn max_x(self: Self) u32 {
        return switch (self.direction) {
            .x => self.end,
            .y => self.plane,
        };
    }

    fn max_y(self: Self) u32 {
        return switch (self.direction) {
            .x => self.plane,
            .y => self.end,
        };
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
    lines: []Line,
    alloc: std.mem.Allocator,
    x_min_index: []u16,
    y_min_index: []u16,

    const Self = @This();

    fn init(alloc: std.mem.Allocator, points: []const Point) !Self {
        const x_min_index = try alloc.alloc(u16, points.len);
        const y_min_index = try alloc.alloc(u16, points.len);
        const inner_lines = blk: {
            var inner_lines = try alloc.alloc(Line, points.len);
            var li: usize = 0;
            for (points, 0..) |p1, i| {
                const p2 = points[(i + 1) % points.len];
                inner_lines[li] = .from_points(p1, p2);
                li += 1;
            }
            break :blk inner_lines;
        };

        var lines: Self = .{
            .lines = inner_lines,
            .alloc = alloc,
            .x_min_index = x_min_index,
            .y_min_index = y_min_index,
        };

        lines.build_indices();
        const bounding_box = get_bounding_box(points);
        lines.map_line_insideness(bounding_box);

        return lines;
    }

    fn furthest_x_less_than(self: *Self, lhs: u16, rhs: u16) bool {
        return self.get_line(lhs).max_x() < self.get_line(rhs).max_x();
    }

    fn furthest_y_less_than(self: *Self, lhs: u16, rhs: u16) bool {
        return self.get_line(lhs).max_y() < self.get_line(rhs).max_y();
    }

    fn build_line_less_than(comptime line_attr: fn (Line) u32) fn (*Self, u16, u16) bool {
        return struct {
            fn inner(self: *Self, lhs: u16, rhs: u16) bool {
                return line_attr(self.get_line(lhs)) < line_attr(self.get_line(rhs));
            }
        }.inner;
    }

    fn build_indices(self: *Self) void {
        for (0..self.lines.len) |i| {
            self.x_min_index[i] = @intCast(i);
            self.y_min_index[i] = @intCast(i);
        }

        std.sort.pdq(u16, self.x_min_index, self, build_line_less_than(Line.min_x));
        std.sort.pdq(u16, self.y_min_index, self, build_line_less_than(Line.min_y));
    }

    fn map_line_insideness(self: *Self, bounding_box: Rectangle) void {
        var last_line: Line, const index = for (0..self.lines.len) |i| {
            const line = self.get_line(i);
            switch (line.direction) {
                .x => {
                    if (line.plane == bounding_box.y1) {
                        self.lines[i].inside = .pos;
                        break .{ line, i };
                    }
                    if (line.plane == bounding_box.y2) {
                        self.lines[i].inside = .neg;
                        break .{ line, i };
                    }
                },
                .y => {
                    if (line.plane == bounding_box.x1) {
                        self.lines[i].inside = .pos;
                        break .{ line, i };
                    }
                    if (line.plane == bounding_box.x2) {
                        self.lines[i].inside = .neg;
                        break .{ line, i };
                    }
                },
            }
        } else unreachable;

        var last_index: usize = index;

        for (1..self.lines.len) |di| {
            const i = (index + di) % self.lines.len;
            defer last_index = i;
            const line = self.get_line(i);
            defer last_line = line;

            const last_inside = self.lines[last_index].inside;
            if (last_line.direction == line.direction) {
                self.lines[i].inside = last_inside;
            } else {
                if ((last_line.start == line.plane) == (last_line.plane == line.start)) {
                    self.lines[i].inside = last_inside;
                } else {
                    self.lines[i].inside = last_inside.flip();
                }
            }
        }
    }

    fn deinit(self: *Self) void {
        self.alloc.free(self.x_min_index);
        self.alloc.free(self.y_min_index);
        self.alloc.free(self.lines);
        self.lines = undefined;
        self.x_min_index = undefined;
        self.y_min_index = undefined;
    }

    fn get_line(self: *const Self, i: usize) Line {
        return self.lines[i];
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
    };

    fn compare_x_index(ctx: struct { *const Self, u32 }, i: u16) std.math.Order {
        const l, const ray_start = ctx;
        return std.math.order(ray_start, l.get_line(i).max_x());
    }

    fn compare_y_index(ctx: struct { *const Self, u32 }, i: u16) std.math.Order {
        const l, const ray_start = ctx;
        return std.math.order(ray_start, l.get_line(i).max_y());
    }

    fn find_intersecting(
        self: *const Self,
        ray: Ray,
        result_buf: []Intersect,
        index_offset: usize,
    ) struct { []const Intersect, usize } {
        var intersects = std.ArrayList(Intersect).initBuffer(result_buf);
        const index = switch (ray.direction) {
            .x => self.x_min_index,
            .y => self.y_min_index,
        };

        var new_index_offset = index_offset;
        for (index[index_offset..], index_offset..) |i, ii| {
            const new_line = self.get_line(i);
            const new = Intersect{
                .line = new_line,
                .intersect = ray.intersects(new_line) orelse continue,
            };
            if (intersects.items.len > 0) {
                const prev = intersects.items[0];
                switch (std.math.order(new.intersect, prev.intersect)) {
                    .eq => intersects.appendAssumeCapacity(new),
                    .lt => unreachable, // min index should guarantee <= intersect ordering.
                    .gt => break,
                }
            } else {
                new_index_offset = ii;
                intersects.appendAssumeCapacity(new);
            }
        } else {
            new_index_offset = index.len;
        }

        return .{ intersects.items, new_index_offset };
    }

    fn line_in_bounds(self: *const Self, tracer_const: Ray, line_end: u32) bool {
        var results_buf: [2]Intersect = undefined;

        var tracer = tracer_const;
        var index_offset: usize = 0;
        for (0..100000) |_| {
            if (tracer.start >= line_end) {
                return true;
            }

            const intersects, index_offset = self.find_intersecting(tracer, &results_buf, index_offset);

            if (intersects.len == 0) return false;

            var new_start = tracer.start + 1;
            for (intersects) |intersect| {
                const wall = intersect.line;
                if (wall.direction == tracer.direction) {
                    new_start = @max(new_start, wall.end);
                } else {
                    new_start = @max(new_start, wall.plane);
                    if (tracer.start < wall.plane and wall.inside != .neg) {
                        return false;
                    }
                }
            }
            tracer.start = new_start;
        }

        unreachable; // likely infinite loop.
    }

    fn rect_in_bounds(self: *const Self, p1: Point, p2: Point) bool {
        const x1 = @min(p1.x, p2.x);
        const y1 = @min(p1.y, p2.y);
        const x2 = @max(p1.x, p2.x);
        const y2 = @max(p1.y, p2.y);

        const low_x: Ray = .{ .direction = .x, .plane = y1, .start = x1 };
        const low_y: Ray = .{ .direction = .y, .plane = x1, .start = y1 };
        const high_x: Ray = .{ .direction = .x, .plane = y2, .start = x1 };
        const high_y: Ray = .{ .direction = .y, .plane = x2, .start = y1 };

        return (self.line_in_bounds(low_x, x2) //
            and self.line_in_bounds(low_y, y2) //
            and self.line_in_bounds(high_x, x2) //
            and self.line_in_bounds(high_y, y2));
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
        if (lines.rect_in_bounds(points[pair.i], points[pair.j])) {
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
