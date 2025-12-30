const std = @import("std");
const game = @import("game.zig");
const startGameLoop = game.startGameLoop;

pub fn main() !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file = std.fs.File.stdout();
    var stdout_writer = stdout_file.writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    try displayAltBuffer(stdout);
    defer displayMainBuffer(stdout) catch {};

    const stdin_fd = std.posix.STDIN_FILENO;
    const original_termios = try enableRawMode(stdin_fd);
    defer restoreMode(stdin_fd, original_termios);

    // TODO hideCursor() and showCursor() aren't working properly
    try hideCursor(stdout);
    defer showCursor(stdout) catch {};

    try startGameLoop();
}

fn enableRawMode(fd: std.posix.fd_t) !std.posix.termios {
    const original_termios = try std.posix.tcgetattr(fd);

    var raw_termios = original_termios;

    raw_termios.lflag.ECHO = false; // don't show typed chars
    raw_termios.lflag.ICANON = false; // disable line buffering
    raw_termios.lflag.ISIG = true; // disable Ctrl+C, Ctrl+Z by setting to false
    raw_termios.iflag.IXON = false;

    raw_termios.cc[@intFromEnum(std.posix.V.MIN)] = 1;
    raw_termios.cc[@intFromEnum(std.posix.V.TIME)] = 0;

    try std.posix.tcsetattr(fd, .FLUSH, raw_termios);

    return original_termios;
}

fn restoreMode(fd: std.posix.fd_t, original: std.posix.termios) void {
    std.posix.tcsetattr(fd, .FLUSH, original) catch {};
}

fn displayAltBuffer(w: *std.io.Writer) !void {
    const alt_buf_sequence = "\x1B[?1049h";
    try w.print("{s}", .{alt_buf_sequence});
    try w.flush();
}

fn displayMainBuffer(w: *std.io.Writer) !void {
    const main_buf_sequence = "\x1B[?1049l";
    try w.print("{s}", .{main_buf_sequence});
    try w.flush();
}

fn hideCursor(w: *std.io.Writer) !void {
    try w.writeAll("\x1B[?25l");
    try w.flush();
}

fn showCursor(w: *std.io.Writer) !void {
    try w.writeAll("\x1b[?25h");
    try w.flush();
}
