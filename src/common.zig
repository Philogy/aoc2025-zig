//! By convention, root.zig is the root source file when making a library.
const std = @import("std");

pub fn pad_string_left(buffer: []u8, str: []const u8, width: usize) std.Io.Writer.Error![]const u8 {
    var writer = std.Io.Writer.fixed(buffer);
    try writer.alignBufferOptions(str, .{ .width = width, .alignment = .left });
    return writer.buffered();
}

pub fn strip_end(str: []const u8) []const u8 {
    var i = str.len;
    return while (i > 0) {
        i -= 1;
        switch (str[i]) {
            '\n', '\r', '\t', ' ' => {},
            else => break str[0 .. i + 1],
        }
    } else &.{};
}

pub const Range = struct {
    start: u64,
    end: u64,

    const Self = @This();

    pub fn contains(self: *const Self, value: u64) bool {
        return self.start <= value and value <= self.end;
    }

    pub fn overlaps(self: Self, other: Self) bool {
        const left, const right = if (self.start <= other.start) .{ self, other } else .{ other, self };
        return right.start <= left.end;
    }

    pub fn merge_if_overlapping(self: *Self, other: Self) bool {
        if (self.overlaps(other)) {
            self.start = @min(self.start, other.start);
            self.end = @max(self.end, other.end);
            return true;
        }

        return false;
    }
};

const CleanSplitIterator = struct {
    inner: std.mem.SplitIterator(u8, .scalar),

    const Self = @This();

    pub fn next(self: *Self) ?[]const u8 {
        while (self.inner.next()) |segment| {
            if (segment.len > 0) return segment;
        }
        return null;
    }
};

pub fn split_cleaned(str: []const u8, delimiter: u8) CleanSplitIterator {
    return .{ .inner = std.mem.splitScalar(u8, str, delimiter) };
}
