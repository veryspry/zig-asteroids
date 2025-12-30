const std = @import("std");
const frame = @import("frame.zig");
const Frame = frame.Frame;
const getWinSize = frame.getWinSize;
const initFrame = frame.initFrame;

const MAX_ASTEROIDS = 50;

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

    var state = try initGameState(allocator, winsize);
    defer state.deinit(allocator);

    var frameA = try initFrame(allocator, winsize);
    var frameB = try initFrame(allocator, winsize);
    defer {
        frameA.deinit(allocator);
        frameB.deinit(allocator);
    }

    var curr_frame: *Frame = &frameA;
    var prev_frame: ?*Frame = null;

    var asteroid_count: u16 = undefined;

    while (true) {
        if (try pollKey(stdin_file, fds[0..], 100)) |key| {
            if (key == 'q') break;

            if (state.status == GameStatus.playing) {
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
            } else {
                switch (key) {
                    'n' => {
                        state.status = GameStatus.playing;
                        continue;
                    },
                    else => {},
                }
            }
        }

        if (state.status == GameStatus.playing) {
            const player_pos = state.player_pos;

            if (player_pos.prev_y != player_pos.y or player_pos.prev_x != player_pos.x) {
                state.dirty_cells.add(player_pos.prev_x, player_pos.prev_y);
            }

            for (state.asteroids.getPoses(), 0..) |*pos, i| {
                pos.prev_x = pos.x;
                pos.prev_y = pos.y;
                state.dirty_cells.add(pos.prev_x, pos.prev_y);

                if (pos.y >= winsize.row - 1) {
                    state.asteroids.removeAt(i);
                } else {
                    pos.y += 1;
                }
            }

            if (!state.asteroids.isFull()) {
                asteroid_count = randomAsteroidCount();

                while (asteroid_count > 0) {
                    // TODO don't show an asteroid in the same place
                    // TODO "pad" them a little bit so they don't get too close
                    const ast_pos = randomXCoordinate(winsize);
                    state.asteroids.add(ast_pos, 1);
                    asteroid_count -= 1;
                }
            }

            for (state.asteroids.getPoses()) |pos| {
                if (player_pos.x == pos.x and player_pos.y == pos.y) {
                    // lose
                }
            }
        }

        try renderContent(curr_frame, &state, winsize);
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

fn renderContent(curr_frame: *Frame, game_state: *GameState, winsize: std.posix.winsize) !void {
    var dirty_cells = game_state.dirty_cells;
    for (dirty_cells.getCells()) |cell| {
        curr_frame.lines[cell.y][cell.x] = ' ';
    }

    dirty_cells.clear();

    if (game_state.status == GameStatus.playing) {
        const player_pos = game_state.player_pos;
        var asteroids = game_state.asteroids;

        curr_frame.lines[player_pos.y][player_pos.x] = 'x';

        for (asteroids.getPoses()) |pos| {
            curr_frame.lines[pos.y][pos.x] = '#';
        }
    } else {
        const msg = switch (game_state.status) {
            .idle => "To start a new game press [n]",
            .lost => "You lost!!! To start a new game press [n]",
            else => "",
        };

        const center_row = winsize.row / 2;
        const start_col = (winsize.col / 2) - (msg.len / 2);

        for (msg, 0..) |char, i| {
            // TODO the following casts are potentially not safe if the cast usize is greater than u16 can hold
            const x: u16 = @intCast(start_col + i);
            const y: u16 = @intCast(center_row);
            curr_frame.lines[y][x] = char;
            game_state.dirty_cells.add(x, y);
        }
    }
}

fn writeCenteredTextToFrame(f: *Frame, winsize: std.posix.winsize, msg: []const u8) void {
    const center_row = winsize.row / 2;
    const start_col = (winsize.col / 2) - (msg.len / 2);

    for (msg, 0..) |char, i| {
        f.lines[center_row][start_col + i] = char;
    }
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

const GameStatus = enum { idle, playing, lost, won };

const GameState = struct {
    const Self = @This();

    status: GameStatus,
    player_pos: Pos,
    asteroids: Asteroids,
    dirty_cells: DirtyCells,

    pub fn deinit(self: *const Self, allocator: std.mem.Allocator) void {
        self.dirty_cells.deinit(allocator);
        self.asteroids.deinit(allocator);
    }
};

const Asteroids = struct {
    const Self = @This();

    poses: []Pos,
    current_idx: usize,

    pub fn deinit(self: *const Self, allocator: std.mem.Allocator) void {
        allocator.free(self.poses);
    }

    pub fn add(self: *Self, x: u16, y: u16) void {
        if (self.current_idx >= self.poses.len) {
            // TODO implement "wrapping" in case buffer gets full
            return;
        }

        self.poses[self.current_idx] = Pos{
            .x = x,
            .y = y,
            .prev_x = x,
            .prev_y = y,
        };

        self.current_idx += 1;
    }

    pub fn removeAt(self: *Self, idx: usize) void {
        std.debug.assert(idx < self.current_idx);
        const last_idx = self.current_idx - 1;
        self.poses[idx] = self.poses[last_idx];
        self.current_idx -= 1;
    }

    pub fn getPoses(self: *Self) []Pos {
        return self.poses[0..self.current_idx];
    }

    pub fn isFull(self: *Self) bool {
        return self.current_idx >= MAX_ASTEROIDS;
    }
};

const DirtyCells = struct {
    const Self = @This();

    cells: []Cell,
    current_idx: usize,

    pub fn deinit(self: *const Self, allocator: std.mem.Allocator) void {
        allocator.free(self.cells);
    }

    pub fn getCells(self: *Self) []Cell {
        return self.cells[0..self.current_idx];
    }

    pub fn add(self: *Self, x: u16, y: u16) void {
        if (self.current_idx >= self.cells.len) {
            // TODO implement "wrapping" in case buffer gets full
            return;
        }

        self.cells[self.current_idx] = Cell{
            .x = x,
            .y = y,
        };

        self.current_idx += 1;
    }

    pub fn clear(self: *Self) void {
        self.current_idx = 0;
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

fn initGameState(allocator: std.mem.Allocator, winsize: std.posix.winsize) !GameState {
    const max_dirty_cells = winsize.row * winsize.col;
    const dirty_cells = try allocator.alloc(Cell, max_dirty_cells);
    const asteroid_poses = try allocator.alloc(Pos, MAX_ASTEROIDS);

    return GameState{
        .status = GameStatus.idle,
        .player_pos = Pos{
            .x = winsize.col / 2,
            .y = winsize.row - 1,
            .prev_x = 0,
            .prev_y = 0,
        },
        .asteroids = Asteroids{
            .poses = asteroid_poses,
            .current_idx = 0,
        },
        .dirty_cells = DirtyCells{
            .cells = dirty_cells,
            .current_idx = 0,
        },
    };
}

const seed: u64 = 12345;
var prng = std.Random.DefaultPrng.init(seed);
var random = prng.random();

fn randomXCoordinate(winsize: std.posix.winsize) u16 {
    return random.uintLessThan(u16, winsize.col);
}

fn randomAsteroidCount() u16 {
    return random.uintLessThan(u16, 2);
}
