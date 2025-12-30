const std = @import("std");

pub const Frame = struct {
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

    pub fn clear(self: *Self) void {
        for (self.lines) |line| {
            @memset(line, ' ');
        }
    }
};

pub fn initFrame(allocator: std.mem.Allocator, winsize: std.posix.winsize) !Frame {
    const lines = try allocator.alloc([]u8, winsize.row);

    for (lines) |*line| {
        line.* = try allocator.alloc(u8, winsize.col);
        @memset(line.*, ' ');
    }

    const frame: Frame = .{
        .row = winsize.row,
        .col = winsize.col,
        .lines = lines,
    };

    return frame;
}

pub fn getWinSize(f: *std.fs.File) !std.posix.winsize {
    var winsize: std.c.winsize = undefined;
    const fd = f.handle;
    const rc = std.c.ioctl(fd, std.c.T.IOCGWINSZ, @intFromPtr(&winsize));
    if (@as(isize, rc) < 0) {
        return error.IoctIError; // handle error appropriately
    }

    return winsize;
}
