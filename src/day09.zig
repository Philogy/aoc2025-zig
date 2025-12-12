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

const Axis = enum {
    x,
    y,

    const Self = @This();

    fn flip(self: Self) Self {
        return switch (self) {
            .x => .y,
            .y => .x,
        };
    }
};

const Line = struct {
    inside: Sign,
    plane: u32,
    start: u32,
    end: u32,

    const Self = @This();

    fn from_points(p1: Point, p2: Point) struct { Self, Axis } {
        if (p1.y == p2.y) {
            return .{ .{
                .inside = undefined,
                .plane = p1.y,
                .start = @min(p1.x, p2.x),
                .end = @max(p1.x, p2.x),
            }, .x };
        } else {
            std.debug.assert(p1.x == p2.x);
            return .{ .{
                .inside = undefined,
                .plane = p1.x,
                .start = @min(p1.y, p2.y),
                .end = @max(p1.y, p2.y),
            }, .y };
        }
    }

    fn get_plane(self: Self) u32 {
        return self.plane;
    }

    fn get_start(self: Self) u32 {
        return self.start;
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
};

const Ray = struct {
    plane: u32,
    start: u32,

    const Self = @This();

    fn intersects_parallel(self: Self, line: Line) ?u32 {
        if (self.plane != line.plane) return null;
        if (line.end < self.start) return null;
        return @max(self.start, line.start);
    }

    fn intersects_perpendicular(self: Self, line: Line) ?u32 {
        if (line.plane < self.start) return null;
        if (self.plane < line.start) return null;
        if (self.plane > line.end) return null;
        return line.plane;
    }
};

const Lines = struct {
    x_lines_minx_sorted: []Line,
    y_lines_minx_sorted: []Line,
    y_lines_miny_sorted: []Line,
    x_lines_miny_sorted: []Line,

    alloc: std.mem.Allocator,

    const Self = @This();

    fn end_ptr(slice: anytype) [*]const (@typeInfo(@TypeOf(slice)).pointer.child) {
        const Child = @typeInfo(@TypeOf(slice)).pointer.child;
        const expected_slice: [*]const Child = slice.ptr;
        return expected_slice[slice.len..];
    }

    fn init(alloc: std.mem.Allocator, points: []const Point) !Self {
        const all_lines = try alloc.alloc(Line, points.len * 2);

        var x_lines = std.ArrayList(Line).initBuffer(all_lines[0..points.len]);
        var y_lines = std.ArrayList(Line).initBuffer(all_lines[points.len..]);

        classify_lines(&x_lines, &y_lines, points);

        const x_lines_minx_sorted = x_lines.items;
        const y_lines_minx_sorted = all_lines[x_lines.items.len..points.len];
        const y_lines_miny_sorted = y_lines.items;
        const x_lines_miny_sorted = all_lines[points.len + y_lines.items.len ..];
        @memcpy(y_lines_minx_sorted, y_lines_miny_sorted);
        @memcpy(x_lines_miny_sorted, x_lines_minx_sorted);

        std.debug.assert( //
            0 //
            + x_lines_minx_sorted.len //
            + x_lines_miny_sorted.len //
            + y_lines_minx_sorted.len //
            + y_lines_miny_sorted.len //
            == points.len * 2 //
        );
        std.debug.assert(x_lines_minx_sorted.ptr == all_lines.ptr);
        std.debug.assert(end_ptr(x_lines_minx_sorted) == y_lines_minx_sorted.ptr);
        std.debug.assert(end_ptr(y_lines_minx_sorted) == y_lines_miny_sorted.ptr);
        std.debug.assert(end_ptr(y_lines_miny_sorted) == x_lines_miny_sorted.ptr);

        var lines: Self = .{
            .alloc = alloc,
            .x_lines_minx_sorted = x_lines_minx_sorted,
            .y_lines_minx_sorted = y_lines_minx_sorted,
            .y_lines_miny_sorted = y_lines_miny_sorted,
            .x_lines_miny_sorted = x_lines_miny_sorted,
        };

        lines.build_indices();

        return lines;
    }

    fn line_less_than(comptime line_attr: fn (Line) u32) fn (void, Line, Line) bool {
        return struct {
            fn inner(_: void, lhs: Line, rhs: Line) bool {
                return line_attr(lhs) < line_attr(rhs);
            }
        }.inner;
    }

    fn classify_lines(x_lines: *std.ArrayList(Line), y_lines: *std.ArrayList(Line), points: []const Point) void {
        const bounding_box = get_bounding_box(points);
        const start_index, var last_inside: Sign, var last_line, var last_direction = for (points, 0..) |p1, i| {
            const p2 = points[(i + 1) % points.len];
            const line, const direction = Line.from_points(p1, p2);
            switch (direction) {
                .x => {
                    if (line.plane == bounding_box.y1) {
                        break .{ i, .pos, line, direction };
                    }
                    if (line.plane == bounding_box.y2) {
                        break .{ i, .neg, line, direction };
                    }
                },
                .y => {
                    if (line.plane == bounding_box.x1) {
                        break .{ i, .pos, line, direction };
                    }
                    if (line.plane == bounding_box.x2) {
                        break .{ i, .neg, line, direction };
                    }
                },
            }
        } else unreachable;

        last_line.inside = last_inside;
        switch (last_direction) {
            .x => x_lines.appendAssumeCapacity(last_line),
            .y => y_lines.appendAssumeCapacity(last_line),
        }

        for (1..points.len) |di| {
            const i = (start_index + di) % points.len;
            const j = (i + 1) % points.len;
            var line, const direction = Line.from_points(points[i], points[j]);
            defer last_line = line;
            defer last_direction = direction;

            if (last_direction == direction) {
                line.inside = last_inside;
            } else if ((last_line.start == line.plane) == (last_line.plane == line.start)) {
                line.inside = last_inside;
            } else {
                line.inside = last_inside.flip();
            }
            defer last_inside = line.inside;

            switch (direction) {
                .x => x_lines.appendAssumeCapacity(line),
                .y => y_lines.appendAssumeCapacity(line),
            }
        }
    }

    fn build_indices(self: *Self) void {
        std.sort.pdq(Line, self.x_lines_minx_sorted, {}, line_less_than(Line.get_start));
        std.sort.pdq(Line, self.x_lines_miny_sorted, {}, line_less_than(Line.get_plane));
        std.sort.pdq(Line, self.y_lines_minx_sorted, {}, line_less_than(Line.get_plane));
        std.sort.pdq(Line, self.y_lines_miny_sorted, {}, line_less_than(Line.get_start));
    }

    fn deinit(self: *Self) void {
        const all_lines = self.x_lines_minx_sorted.ptr[0 .. //
            self.x_lines_minx_sorted.len //
            + self.y_lines_minx_sorted.len //
            + self.y_lines_miny_sorted.len //
            + self.x_lines_miny_sorted.len //
            ];
        self.alloc.free(all_lines);

        self.x_lines_minx_sorted = undefined;
        self.y_lines_minx_sorted = undefined;
        self.y_lines_miny_sorted = undefined;
        self.x_lines_miny_sorted = undefined;
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
        wall: Line,
        intersect: u32,
    };

    fn find_intersecting(
        self: *const Self,
        ray: Ray,
        ray_direction: Axis,
        line_direction: Axis,
        index_offset: usize,
    ) struct { ?Intersect, usize } {
        const index = switch (line_direction) {
            .x => switch (ray_direction) {
                .x => self.x_lines_minx_sorted,
                .y => self.x_lines_miny_sorted,
            },
            .y => switch (ray_direction) {
                .x => self.y_lines_minx_sorted,
                .y => self.y_lines_miny_sorted,
            },
        };

        for (index[index_offset..], index_offset..) |line, i| {
            const maybe_intersect = if (ray_direction == line_direction)
                ray.intersects_parallel(line)
            else
                ray.intersects_perpendicular(line);
            const intersect = maybe_intersect orelse continue;
            return .{ .{ .wall = line, .intersect = intersect }, i };
        }

        return .{ null, index.len };
    }

    fn line_in_bounds(
        self: *const Self,
        tracer_direction: Axis,
        tracer_const: Ray,
        line_end: u32,
    ) bool {
        var tracer = tracer_const;
        var parallel_index_offset: usize = 0;
        var perpendicular_index_offset: usize = 0;
        for (0..100000) |_| {
            if (tracer.start >= line_end) {
                return true;
            }

            const parallel_intersect, const new_parallel_index_offset = //
                self.find_intersecting(
                    tracer,
                    tracer_direction,
                    tracer_direction,
                    parallel_index_offset,
                );
            const perpendicular_interesect, const new_perpendicular_index_offset = //
                self.find_intersecting(
                    tracer,
                    tracer_direction,
                    tracer_direction.flip(),
                    perpendicular_index_offset,
                );

            if (parallel_intersect == null and perpendicular_interesect == null) return false;
            var new_start = tracer.start + 1;

            const which_todo: enum { both, only_parallel, only_perpendicular } = which_todo: {
                const parallel = parallel_intersect orelse break :which_todo .both;
                const perpendicular = perpendicular_interesect orelse break :which_todo .both;
                break :which_todo switch (std.math.order(parallel.intersect, perpendicular.intersect)) {
                    .eq => .both,
                    .lt => .only_parallel,
                    .gt => .only_perpendicular,
                };
            };

            if (which_todo != .only_perpendicular) {
                if (parallel_intersect) |intersect| {
                    new_start = @max(new_start, intersect.wall.end);
                }
                parallel_index_offset = new_parallel_index_offset;
            }
            if (which_todo != .only_parallel) {
                if (perpendicular_interesect) |intersect| {
                    const wall = intersect.wall;
                    if (tracer.start < wall.plane and wall.inside == .pos) return false;
                    new_start = @max(new_start, wall.plane);
                }
                perpendicular_index_offset = new_perpendicular_index_offset;
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

        const low_x: Ray = .{ .plane = y1, .start = x1 };
        const low_y: Ray = .{ .plane = x1, .start = y1 };
        const high_x: Ray = .{ .plane = y2, .start = x1 };
        const high_y: Ray = .{ .plane = x2, .start = y1 };

        const in_bounds = ( //
            self.line_in_bounds(.x, low_x, x2) //
            and self.line_in_bounds(.y, low_y, y2) //
            and self.line_in_bounds(.x, high_x, x2) //
            and self.line_in_bounds(.y, high_y, y2) //
        );

        return in_bounds;
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
