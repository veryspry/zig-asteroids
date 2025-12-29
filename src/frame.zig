const std = @import("std");

const Frame = extern struct {
    const Self = @This();

    row: u16,
    col: u16,
    lines: [][]u8,

    pub fn deinit(self: *const Self, allocator: std.mem.Allocator) void {
        for (self.lines) |line| {
            allocator.free(line);
        }
        allocator.free(self.lines);
    }
};
