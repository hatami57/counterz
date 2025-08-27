const std = @import("std");
const webui = @import("webui");
const html = @embedFile("index.html");
const print = std.debug.print;

const SocketHandler = struct {
    allocator: std.mem.Allocator,
    socket_fd: std.posix.fd_t,
    win: *webui,
    counter: i32,

    fn run(self: *SocketHandler) !void {
        try self.setCounter();

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
                    try self.setCounter();
                }
            }
        }
    }

    fn setCounter(self: *SocketHandler) !void {
        const set_counter_js = try std.fmt.allocPrintZ(self.allocator, "SetCounter({d});", .{self.counter});
        defer self.allocator.free(set_counter_js);

        self.win.run(set_counter_js);
    }
};

const Config = struct {
    title: []u8,
    counter: i32,
};

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var config = Config{ .title = &[_]u8{}, .counter = 0 };
    const filename = "config.txt";

    var file = try ensureConfigExists(filename);
    defer file.close();

    try readConfig(allocator, &file, &config);
    defer allocator.free(config.title);

    print("Config => Title: {s}, Counter: {d}\n", .{ config.title, config.counter });

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
        .counter = config.counter,
    };

    const thread = try std.Thread.spawn(.{}, SocketHandler.run, .{&socket_handler});
    thread.detach();

    webui.wait();
    webui.clean();
}

fn ensureConfigExists(filename: []const u8) !std.fs.File {
    const cwd = std.fs.cwd();
    const file = cwd.openFile(filename, .{ .mode = .read_write }) catch |err| switch (err) {
        error.FileNotFound => {
            return try writeDefaultConfig(filename);
        },
        else => return err,
    };

    const file_info = try file.stat();
    if (file_info.size == 0) {
        file.close();
        return try writeDefaultConfig(filename);
    }

    return file;
}

fn writeDefaultConfig(filename: []const u8) !std.fs.File {
    var file = try std.fs.cwd().createFile(filename, .{});

    try file.writeAll("Title: \nCounter: 0000");

    return file;
}

fn readConfig(allocator: std.mem.Allocator, file: *std.fs.File, config: *Config) !void {
    var buf: [1024]u8 = undefined;

    try file.seekTo(0);

    const bytes_read = try file.readAll(&buf);
    const config_text = buf[0..bytes_read];

    const title_label = "Title:";
    const title_start = std.mem.indexOf(u8, config_text, title_label) orelse return error.DecodeError;
    const title_value_start = title_start + title_label.len;

    const title_line_end = std.mem.indexOf(u8, config_text[title_value_start..], "\n") orelse return error.DecodeError;
    const title_value_end = title_value_start + title_line_end;

    const title_value = config_text[title_value_start..title_value_end];
    const trimmed_title_value = std.mem.trim(u8, title_value, " \r\n\t");

    if (config.title.len != 0) {
        allocator.free(config.title);
        config.title = &[_]u8{};
    }

    config.title = try allocator.alloc(u8, trimmed_title_value.len);
    std.mem.copyForwards(u8, config.title, trimmed_title_value);

    const counter_label = "Counter:";
    const counter_start = std.mem.indexOf(u8, config_text[title_value_end..], counter_label) orelse return error.DecodeError;
    const counter_value_start = title_value_end + counter_start + counter_label.len;

    const counter_line_end = std.mem.indexOf(u8, config_text[counter_value_start..], "\n") orelse (config_text.len - counter_value_start);
    const counter_value_end = counter_value_start + counter_line_end;

    const counter_value = config_text[counter_value_start..counter_value_end];
    const trimmed_counter_value = std.mem.trim(u8, counter_value, " \r\n\r");

    config.counter = try std.fmt.parseInt(i32, trimmed_counter_value, 10);
}
