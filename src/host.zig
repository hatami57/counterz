const std = @import("std");
const webui = @import("webui");
const html = @embedFile("index.html");
const print = std.debug.print;

const SocketHandler = struct {
    allocator: std.mem.Allocator,
    socket_fd: std.posix.fd_t,
    win: *webui,
    counter: i32,

    fn run(self: *SocketHandler) void {
        self.setCounter();

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
                    self.counter += 1;
                    self.setCounter();
                }
            }
        }
    }

    fn setCounter(self: *SocketHandler) void {
        const set_counter_js = std.fmt.allocPrint(self.allocator, "SetCounter({d});", .{self.counter});
        defer self.allocator.free(set_counter_js);

        self.win.run(set_counter_js);
    }
};

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var counter: i32 = 0;
    var title: []u8 = "";

    const socket_path = "/tmp/counterz.sock";
    _ = std.fs.deleteFileAbsolute(socket_path) catch |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    };

    const sock_fd = try std.posix.socket(std.posix.AF.UNIX, std.posix.SOCK.STREAM, 0);
    defer std.posix.close(sock_fd);

    const addr = try std.net.Address.initUnix(socket_path);
    try std.posix.bind(sock_fd, &addr.any, addr.getOsSockLen());
    try std.posix.listen(sock_fd, 128);

    print("Listening on Posix socket {s}\n", .{socket_path});

    var win = webui.newWindow();
    win.setSize(100, 100);
    // win.setFrameless(true);
    win.setHighContrast(true);
    try win.show(html);

    var socket_handler = SocketHandler{
        .allocator = allocator,
        .socket_fd = sock_fd,
        .win = &win,
        .counter = counter,
    };

    const thread = try std.Thread.spawn(.{}, SocketHandler.run, .{&socket_handler});
    thread.detach();

    webui.wait();
    webui.clean();
}
