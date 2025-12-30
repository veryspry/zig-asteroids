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

    var state = try initGameState(allocator, winsize.row * winsize.col);
    defer state.deinit(allocator);

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
                    if (state.player_pos.y < winsize.row - 1) {
                        state.player_pos.y += 1;
                    }
                },
                'a' => {
                    if (state.player_pos.x > 0) {
                        state.player_pos.x -= 1;
                    }
                },
                'd' => {
                    if (state.player_pos.x < winsize.col - 1) {
                        state.player_pos.x += 1;
                    }
                },
                else => {},
            }
        }

        const player_pos = state.player_pos;

        if (player_pos.prev_y != player_pos.y or player_pos.prev_x != player_pos.x) {
            state.dirty_cells.add(player_pos.prev_x, player_pos.prev_y);
            // state.dirty_cells.add(player_pos.x, player_pos.y);
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
    var dirty_cells = game_state.dirty_cells;

    for (dirty_cells.getCells()) |cell| {
        curr_frame.lines[cell.y][cell.x] = ' ';
    }

    dirty_cells.clear();

    // if (player_pos.prev_y != player_pos.y or player_pos.prev_x != player_pos.x) {
    //     curr_frame.lines[player_pos.prev_y][player_pos.prev_x] = ' ';
    // }

    curr_frame.lines[player_pos.y][player_pos.x] = 'x';

    // for (curr_frame.lines, 0..) |_, i| {
    //     if (player_pos.y == i) {
    //         _ = try std.fmt.bufPrint(curr_frame.lines[i][game_state.player_pos.x..], "{s}", .{"x"});
    //      }
    // }
}

fn drawFrame(w: *std.io.Writer, curr_frame: *Frame, prev_frame: ?*Frame) !void {
    for (curr_frame.lines, 0..) |line, i| {
        for (line, 0..) |c, j| {
            var changed = true;

            if (prev_frame) |pf| {
                changed = pf.lines[i][j] != c;
            }

            if (changed) {
                try moveCursor(w, i + 1, j + 1);
                try w.writeByte(c);

                // try clearLine(w);
                // try w.writeAll(line);
                try w.flush();
                // reposition cursor to reset the auto wrap flag
                try moveCursor(w, 1, 1);
            }
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
    const Self = @This();

    player_pos: Pos,
    dirty_cells: DirtyCells,

    pub fn deinit(self: *const Self, allocator: std.mem.Allocator) void {
        self.dirty_cells.deinit(allocator);
    }
};

const DirtyCells = struct {
    const Self = @This();

    cells: []Cell,
    pos: usize,

    pub fn deinit(self: *const Self, allocator: std.mem.Allocator) void {
        allocator.free(self.cells);
    }

    pub fn getCells(self: *Self) []Cell {
        return self.cells[0..self.pos];
    }

    pub fn add(self: *Self, x: u16, y: u16) void {
        if (self.pos >= self.cells.len) {
            // TODO implement "wrapping" in case buffer gets full
            return;
        }

        self.cells[self.pos] = Cell{
            .x = x,
            .y = y,
        };

        self.pos += 1;
    }

    pub fn clear(self: *Self) void {
        self.pos = 0;
    }
};

const Cell = struct {
    x: u16,
    y: u16,
};

const Pos = struct {
    x: u16,
    y: u16,
    prev_x: u16,
    prev_y: u16,
};

fn initGameState(allocator: std.mem.Allocator, max_dirty_cells: u32) !GameState {
    const dirty_cells = try allocator.alloc(Cell, max_dirty_cells);
    return GameState{
        .player_pos = Pos{
            .x = 0,
            .y = 0,
            .prev_x = 0,
            .prev_y = 0,
        },
        .dirty_cells = DirtyCells{
            .cells = dirty_cells,
            .pos = 0,
        },
    };
}
