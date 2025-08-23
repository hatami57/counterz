const std = @import("std");
const webui = @import("webui");
const html = @embedFile("index.html");
const print = std.debug.print;

const SocketHandler = struct {
    socket_fd: std.posix.fd_t,
    win: *webui,

    fn run(self: *SocketHandler) void {
        while (true) {
            const client_fd = std.posix.accept(self.socket_fd, null, null, 0) catch |err| {
                print("Error accepting connection: {}\n", .{err});
                continue;
            };
            defer std.posix.close(client_fd);

            var buf: [64]u8 = undefined;
            const n = std.posix.recv(client_fd, buf[0..], 0) catch |err| {
                print("Error in reading stream: {}\n", .{err});
                continue;
            };

            if (n > 0) {
                const msg = buf[0..n];
                print("Received message: {s}\n", .{msg});

                if (std.mem.eql(u8, msg, "inc")) {
                    self.win.run("Increment();");
                }
            }
        }
    }
};

pub fn main() !void {
    // var gpa = std.heap.DebugAllocator(.{}){};
    // defer _ = gpa.deinit();
    // var allocator = gpa.allocator();

    const socket_path = "/tmp/zig_counter.sock";
    _ = std.fs.deleteFileAbsolute(socket_path) catch |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    };

    const sock_fd = try std.posix.socket(std.posix.AF.UNIX, std.posix.SOCK.STREAM, 0);
    defer std.posix.close(sock_fd);

    const addr = try std.net.Address.initUnix(socket_path);
    try std.posix.bind(sock_fd, &addr.any, addr.getOsSockLen());
    try std.posix.listen(sock_fd, 128);

    print("Listening on Unix socket {s}\n", .{socket_path});

    var win = webui.newWindow();
    try win.show(html);

    var socket_handler = SocketHandler{
        .socket_fd = sock_fd,
        .win = &win,
    };

    const thread = try std.Thread.spawn(.{}, SocketHandler.run, .{&socket_handler});
    thread.detach();

    webui.wait();
    webui.clean();
}
