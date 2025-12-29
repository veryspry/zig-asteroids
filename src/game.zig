const std = @import("std");

pub fn startGameLoop() !void {
    const stdin_file = std.fs.File.stdin();
    var stdout_file = std.fs.File.stdout();

    var fds = [_]std.posix.pollfd{
        .{
            .fd = stdin_file.handle,
            .events = std.posix.POLL.IN,
            .revents = 0,
        },
    };

    while (true) {
        if (try pollKey(stdin_file, fds[0..], 100)) |key| {
            if (key == 'q') break;

            var buf: [32]u8 = undefined;
            const msg = try std.fmt.bufPrint(
                &buf,
                "key: {d} ('{c}')\r\n",
                .{ key, key },
            );
            try stdout_file.writeAll(msg);
        }
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
