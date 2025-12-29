const std = @import("std");
const frame = @import("frame.zig");
const Frame = frame.Frame;
const getWinSize = frame.getWinSize;
const initFrame = frame.initFrame;

pub fn startGameLoop() !void {
    const stdin_file = std.fs.File.stdin();
    var stdout_file = std.fs.File.stdout();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const winsize = try getWinSize(&stdout_file);

    const output_buf_size = winsize.row * winsize.col;
    var stdout_buf = try allocator.alloc(u8, output_buf_size);
    defer allocator.free(stdout_buf);

    var stdout_writer = stdout_file.writer(stdout_buf[0..]);
    const stdout = &stdout_writer.interface;

    var fds = [_]std.posix.pollfd{
        .{
            .fd = stdin_file.handle,
            .events = std.posix.POLL.IN,
            .revents = 0,
        },
    };

    var state = initGameState();

    var frameA = try initFrame(allocator, winsize);
    var frameB = try initFrame(allocator, winsize);
    defer {
        frameA.deinit(allocator);
        frameB.deinit(allocator);
    }

    var curr_frame: *Frame = &frameA;
    var prev_frame: ?*Frame = null;

    while (true) {
        if (try pollKey(stdin_file, fds[0..], 100)) |key| {
            if (key == 'q') break;

            state.player_pos.prev_x = state.player_pos.x;
            state.player_pos.prev_y = state.player_pos.y;
            switch (key) {
                'w' => {
                    if (state.player_pos.y > 0) {
                        state.player_pos.y -= 1;
                    }
                },
                's' => {
                    if (state.player_pos.y < winsize.row) {
                        state.player_pos.y += 1;
                    }
                },
                'a' => {
                    if (state.player_pos.x > 0) {
                        state.player_pos.x -= 1;
                    }
                },
                'd' => {
                    if (state.player_pos.x < winsize.col) {
                        state.player_pos.x += 1;
                    }
                },
                else => {},
            }

            // var buf: [32]u8 = undefined;
            // const msg = try std.fmt.bufPrint(
            //     &buf,
            //     "key: {d} ('{c}')\r\n",
            //     .{ key, key },
            // );
            // try stdout_file.writeAll(msg);
        }

        try renderContent(curr_frame, &state);

        try drawFrame(stdout, curr_frame, prev_frame);

        prev_frame = curr_frame;
        curr_frame = if (curr_frame == &frameA) &frameB else &frameA;
    }
}

fn pollKey(stdin: std.fs.File, fds: []std.posix.pollfd, timeout_ms: i32) !?u8 {
    const rc = try std.posix.poll(fds, timeout_ms);
    if (rc == 0) return null; // timeout

    if (fds[0].revents & std.posix.POLL.IN != 0) {
        var buf: [1]u8 = undefined;
        const n = try stdin.read(&buf);
        if (n == 1) return buf[0];
    }

    fds[0].revents = 0;

    return null;
}

fn renderContent(curr_frame: *Frame, game_state: *GameState) !void {
    const player_pos = game_state.player_pos;

    if (player_pos.prev_y != player_pos.y or player_pos.prev_x != player_pos.x) {
        curr_frame.lines[player_pos.prev_y][player_pos.prev_x] = ' ';
    }

    curr_frame.lines[player_pos.y][player_pos.x] = 'x';

    // for (curr_frame.lines, 0..) |_, i| {
    //     if (player_pos.y == i) {
    //         _ = try std.fmt.bufPrint(curr_frame.lines[i][game_state.player_pos.x..], "{s}", .{"x"});
    //      }
    // }
}

fn drawFrame(w: *std.io.Writer, curr_frame: *Frame, prev_frame: ?*Frame) !void {
    // todo take prev_frame and do diffing
    for (curr_frame.lines, 0..) |line, i| {
        var changed = true;

        if (prev_frame) |pf| {
            changed = !std.mem.eql(u8, pf.lines[i], line);
        }

        if (changed) {
            try moveCursor(w, i + 1, 1);
            try clearLine(w);
            try w.writeAll(line);
            try w.flush();
            // reposition cursor to reset the auto wrap flag
            try moveCursor(w, 1, 1);
        }
    }
}

// Moves the cursor position. Note that row and col are 1 index NOT 0 indexed
fn moveCursor(writer: anytype, row: usize, col: usize) !void {
    try writer.print("\x1b[{d};{d}H", .{ row, col });
}

fn clearLine(writer: anytype) !void {
    try writer.writeAll("\x1b[2K");
}

const GameState = struct {
    player_pos: Pos,
};

const Pos = struct {
    x: u16,
    y: u16,
    prev_x: u16,
    prev_y: u16,
};

fn initGameState() GameState {
    return GameState{
        .player_pos = Pos{
            .x = 0,
            .y = 0,
            .prev_x = 0,
            .prev_y = 0,
        },
    };
}
