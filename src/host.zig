const std = @import("std");
const webui = @import("webui");
const html = @embedFile("html/index.html");
const font_dseg7 = @embedFile("html/DSEG7.ttf");
const font_amiri = @embedFile("html/AmiriQuran.ttf");
const print = std.debug.print;

const SocketHandler = struct {
    socket_fd: std.posix.fd_t,
    page_controller: *PageController,
    config: *Config,

    fn run(self: *SocketHandler) !void {
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
                    try self.config.inc();
                    try self.page_controller.setCount(self.config.count);
                }
            }
        }
    }
};

const PageController = struct {
    allocator: std.mem.Allocator,
    win: *webui,

    fn setCount(self: *PageController, count: u32) !void {
        const set_count_js = try std.fmt.allocPrintZ(self.allocator, "SetCount({d});", .{count});
        defer self.allocator.free(set_count_js);

        self.win.run(set_count_js);
    }

    fn setTitle(self: *PageController, title: []const u8) !void {
        const set_title_js = try std.fmt.allocPrintZ(self.allocator, "SetTitle('{s}');", .{title});
        defer self.allocator.free(set_title_js);

        self.win.run(set_title_js);
    }
};

const Config = struct {
    const filename = "config.txt";
    const count_len = 4;

    allocator: std.mem.Allocator,
    file: ?std.fs.File,
    title: ?[]u8,
    count: u32,
    count_str: [5]u8,
    count_position_in_file: u64,
    logger: CounterLog,

    fn init(allocator: std.mem.Allocator) !Config {
        var config = Config{
            .allocator = allocator,
            .file = null,
            .title = null,
            .count = 0,
            .count_str = [_]u8{ ' ', '0', '0', '0', '0' },
            .count_position_in_file = 0,
            .logger = try CounterLog.init(allocator),
        };

        try config.ensureExists();
        try config.readConfig();

        return config;
    }

    fn deinit(self: *Config) void {
        if (self.file) |file| {
            file.close();
        }
        if (self.title) |title| {
            self.allocator.free(title);
        }
    }

    fn ensureExists(self: *Config) !void {
        const cwd = std.fs.cwd();
        const file = cwd.openFile(filename, .{ .mode = .read_write }) catch |err| switch (err) {
            error.FileNotFound => {
                try self.writeDefault();
                return;
            },
            else => return err,
        };

        const file_info = try file.stat();
        if (file_info.size == 0) {
            file.close();
            try self.writeDefault();
            return;
        }

        self.file = file;
    }

    fn writeDefault(self: *Config) !void {
        var file = try std.fs.cwd().createFile(filename, .{ .read = true });

        try file.writeAll("Title: Your First Counter\nCount: 0000");

        self.file = file;
    }

    fn inc(self: *Config) !void {
        self.count += 1;
        _ = try std.fmt.bufPrint(&self.count_str, " {:0>4}", .{self.count});
        print("new count: {d}, {s}\n", .{ self.count, self.count_str });
        try self.writeCount();
        try self.logger.write("INC", 1, self.count);
    }

    fn writeCount(self: *Config) !void {
        if (self.file) |file| {
            try file.seekTo(self.count_position_in_file);
            try file.writeAll(self.count_str[0..]);
        }
    }

    fn readConfig(self: *Config) !void {
        var buf: [1024]u8 = undefined;

        if (self.file) |file| {
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

            if (self.title) |title| {
                self.allocator.free(title);
                self.title = null;
            }

            self.title = try self.allocator.alloc(u8, trimmed_title_value.len);
            std.mem.copyForwards(u8, self.title.?, trimmed_title_value);

            const count_label = "Count:";
            const count_start = std.mem.indexOf(u8, config_text[title_value_end..], count_label) orelse return error.DecodeError;
            const count_value_start = title_value_end + count_start + count_label.len;

            const count_line_end = std.mem.indexOf(u8, config_text[count_value_start..], "\n") orelse (config_text.len - count_value_start);
            const count_value_end = count_value_start + count_line_end;

            const count_value = config_text[count_value_start..count_value_end];
            const trimmed_count_value = std.mem.trim(u8, count_value, " \r\n\r");

            self.count = try std.fmt.parseInt(u32, trimmed_count_value, 10);
            self.count_position_in_file = count_value_start;
        }
    }
};

const CounterLog = struct {
    const filename = "log.txt";

    allocator: std.mem.Allocator,
    file: ?std.fs.File,

    fn init(allocator: std.mem.Allocator) !CounterLog {
        const cwd = std.fs.cwd();
        var log = CounterLog{
            .allocator = allocator,
            .file = null,
        };

        log.file = cwd.openFile(filename, .{ .mode = .read_write }) catch |err| switch (err) {
            error.FileNotFound => try cwd.createFile(filename, .{ .read = true }),
            else => return err,
        };

        try log.file.?.seekFromEnd(0);

        return log;
    }

    fn deinit(self: *CounterLog) void {
        if (self.file) |file| {
            file.close();
        }
    }

    fn write(self: *CounterLog, cmd: []const u8, count: u32, totalCount: u32) !void {
        if (self.file) |file| {
            const timestamp = std.time.timestamp();
            const log_text = try std.fmt.allocPrint(self.allocator, "{d}\t{s}\t{d}\t{d}\n", .{ timestamp, cmd, count, totalCount });
            try file.writeAll(log_text);
            self.allocator.free(log_text);
        }
    }
};

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var config = try Config.init(allocator);
    defer config.deinit();

    print("Config => Title: {s}, Count: {d}\n", .{ config.title orelse "", config.count });

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
    win.setFileHandler(htmlFileHandler);
    try win.show(html);

    var page_controller = PageController{
        .allocator = allocator,
        .win = &win,
    };

    try page_controller.setTitle(config.title orelse "");
    try page_controller.setCount(config.count);

    var socket_handler = SocketHandler{
        .socket_fd = sock_fd,
        .page_controller = &page_controller,
        .config = &config,
    };

    const thread = try std.Thread.spawn(.{}, SocketHandler.run, .{&socket_handler});
    thread.detach();

    webui.wait();
    webui.clean();
}

fn htmlFileHandler(filename: []const u8) ?[]const u8 {
    print("request filename: {s}\n", .{filename});
    if (std.mem.eql(u8, filename, "/DSEG7.ttf")) {
        const header =
            "HTTP/1.1 200 OK\r\n" ++
            "Content-Type: font/ttf\r\n" ++
            "Content-Length: " ++
            std.fmt.comptimePrint("{d}", .{font_dseg7.len}) ++
            "\r\n\r\n";

        return header ++ font_dseg7;
    } else if (std.mem.eql(u8, filename, "/AmiriQuran.ttf")) {
        const header =
            "HTTP/1.1 200 OK\r\n" ++
            "Content-Type: font/ttf\r\n" ++
            "Content-Length: " ++
            std.fmt.comptimePrint("{d}", .{font_amiri.len}) ++
            "\r\n\r\n";

        return header ++ font_amiri;
    }

    return null;
}
