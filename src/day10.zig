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

    var arena = std.heap.ArenaAllocator.init(gpa_alloc);
    const arena_alloc = arena.allocator();
    defer arena.deinit();

    var configs = try std.ArrayList(ButtonConfig).initCapacity(arena_alloc, 16);
    defer configs.deinit(arena_alloc);
    var lines_iter = std.mem.splitScalar(u8, source, '\n');
    while (lines_iter.next()) |line| {
        if (line.len == 0) continue;
        try configs.append(arena_alloc, try ButtonConfig.parse_from_line(arena_alloc, line));
    }
    defer for (configs.items) |*config| {
        config.deinit(arena_alloc);
    };

    try part1(arena_alloc, configs.items);
    try part2();
}

const ButtonConfig = struct {
    desired_end_state: u16,
    buttons: std.ArrayList(u16),

    const Self = @This();

    fn parse_from_line(alloc: std.mem.Allocator, line: []const u8) !Self {
        if (line[0] != '[') return error.InvalidButtonConfig;
        var desired_end_state: u16 = 0;

        const state_end = for (line[1..], 0..) |c, i| {
            if (c == ']') break i + 1;
            if (c == '#') desired_end_state |= @as(u16, 1) << @intCast(i);
        } else return error.InvalidButtonConfig;

        var buttons = try std.ArrayList(u16).initCapacity(alloc, 5);
        std.debug.assert(line[state_end + 2] == '(');
        var buttons_iter = std.mem.splitScalar(u8, line[state_end + 2 ..], ' ');
        _ = while (buttons_iter.next()) |button_str| {
            if (button_str[0] == '{') break button_str;
            var button: u16 = 0;
            for (0..button_str.len / 2) |i| {
                const num_char = button_str[i * 2 + 1];
                const num = num_char - '0';
                std.debug.assert(num < 10);
                button |= @as(u16, 1) << @intCast(num);
            }
            try buttons.append(alloc, button);
        } else return error.InvalidButtonConfig;

        return .{
            .desired_end_state = desired_end_state,
            .buttons = buttons,
        };
    }

    fn deinit(self: *Self, alloc: std.mem.Allocator) void {
        self.buttons.deinit(alloc);
    }

    fn get_min_presses(
        self: *const Self,
        alloc: std.mem.Allocator,
        queue: *OalipeQueue,
    ) !u32 {
        if (self.desired_end_state == 0) return 0;

        queue.reset();
        for (self.buttons.items) |button| {
            try queue.push(self.desired_end_state ^ button, alloc);
        }
        queue.current_frontier = self.buttons.items.len - 1;

        for (0..10_000_000) |_| {
            const cost = queue.cost;
            const state = queue.pop();
            // std.debug.print("{b:010} = {}\n", .{ state, cost });
            if (state == 0) return cost;

            for (self.buttons.items) |button| {
                try queue.push(state ^ button, alloc);
            }
        } else unreachable;
    }
};

const OalipeQueue = struct {
    backing: std.ArrayList(u16),
    cost: u32 = undefined,
    current_frontier: usize = undefined,

    const Self = @This();

    fn init(alloc: std.mem.Allocator) !Self {
        const backing = try std.ArrayList(u16).initCapacity(alloc, 64);
        return .{ .backing = backing };
    }

    fn reset(self: *Self) void {
        self.backing.clearRetainingCapacity();
        self.cost = 1;
        self.current_frontier = 0;
    }

    fn push(self: *Self, state: u16, alloc: std.mem.Allocator) !void {
        try self.backing.append(alloc, state);
    }

    fn pop(self: *Self) u16 {
        const state = self.backing.swapRemove(self.current_frontier);
        if (self.current_frontier == 0) {
            self.current_frontier = self.backing.items.len - 1;
            self.cost += 1;
        } else {
            self.current_frontier -= 1;
        }
        return state;
    }

    fn deinit(self: *Self, alloc: std.mem.Allocator) void {
        self.backing.deinit(alloc);
    }
};

fn part1(alloc: std.mem.Allocator, configs: []const ButtonConfig) !void {
    // for (configs) |config| {
    //     std.debug.print("desired: {b:010}\n", .{config.desired_end_state});
    //     for (config.buttons.items, 0..) |button, i| {
    //         std.debug.print("  [{}] {b:010}\n", .{ i, button });
    //     }
    // }
    //
    var queue = try OalipeQueue.init(alloc);
    defer queue.deinit(alloc);

    var total_min_press: u32 = 0;
    for (configs) |config| {
        total_min_press += try config.get_min_presses(alloc, &queue);
    }

    std.debug.print("part1: {}\n", .{total_min_press});
}
fn part2() !void {}
