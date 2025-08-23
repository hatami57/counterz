const std = @import("std");
const print = std.debug.print;

pub fn main() !void {
    const socket_path = "/tmp/zig_counter.sock";
    const sock_fd = try std.posix.socket(std.posix.AF.UNIX, std.posix.SOCK.STREAM, 0);
    defer std.posix.close(sock_fd);

    // Create Unix socket address
    const addr = try std.net.Address.initUnix(socket_path);

    // Connect to server
    try std.posix.connect(sock_fd, &addr.any, addr.getOsSockLen());

    print("Connected to Unix socket: {s}\n", .{socket_path});

    // Send a message
    const message = "inc";
    _ = try std.posix.send(sock_fd, message, 0);
}
