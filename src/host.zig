const std = @import("std");
const webui = @import("webui");
const html = @embedFile("html/index.html");
const font_dseg7 = @embedFile("html/DSEG7.ttf");
const font_amiri = @embedFile("html/AmiriQuran.ttf");
const print = std.debug.print;

const TITLE_LABEL = "Title:";
const COUNT_LABEL = "Count:";

const SocketHandler = struct {
    socket_fd: std.posix.fd_t,
    ui_controller: *UIController,
    config: *Config,
    stop: *std.atomic.Value(bool),

    fn run(self: *SocketHandler) !void {
        while (!self.stop.load(.seq_cst)) {
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
                    try self.ui_controller.setCount(self.config.count);
                }
            }
        }
    }
};

const UIController = struct {
    allocator: std.mem.Allocator,
    window: *webui,

    fn setCount(self: *UIController, count: u32) !void {
        var buf: [64]u8 = undefined;
        const set_count_js = try std.fmt.bufPrintZ(&buf, "SetCount({d});", .{count});
        self.window.run(set_count_js);
    }

    fn setTitle(self: *UIController, title: []const u8) !void {
        var buf: [1024]u8 = undefined;
        const set_title_js = try std.fmt.bufPrintZ(&buf, "SetTitle('{s}');", .{title});
        self.window.run(set_title_js);
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
        errdefer config.deinit();

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
        self.logger.deinit();
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

        try file.writeAll(TITLE_LABEL ++ " Your First Counter\n" ++ COUNT_LABEL ++ " 0000");

        self.file = file;
    }

    fn inc(self: *Config) !void {
        self.count += 1;
        _ = try std.fmt.bufPrint(&self.count_str, " {:0>4}", .{self.count});
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

            const title_start = std.mem.indexOf(u8, config_text, TITLE_LABEL) orelse return error.DecodeError;
            const title_value_start = title_start + TITLE_LABEL.len;

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

            const count_start = std.mem.indexOf(u8, config_text[title_value_end..], COUNT_LABEL) orelse return error.DecodeError;
            const count_value_start = title_value_end + count_start + COUNT_LABEL.len;

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
            var buf: [128]u8 = undefined;
            const log_text = try std.fmt.bufPrint(&buf, "{d}\t{s}\t{d}\t{d}\n", .{ timestamp, cmd, count, totalCount });
            try file.writeAll(log_text);
        }
    }
};

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var config = try Config.init(allocator);
    defer config.deinit();
    var stop_flag = std.atomic.Value(bool).init(false);

    print("Config => {s} {s}, {s} {d}\n", .{ TITLE_LABEL, config.title orelse "", COUNT_LABEL, config.count });

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

    var ui_controller = UIController{
        .allocator = allocator,
        .window = &win,
    };

    try ui_controller.setTitle(config.title orelse "");
    try ui_controller.setCount(config.count);

    var socket_handler = SocketHandler{
        .socket_fd = sock_fd,
        .ui_controller = &ui_controller,
        .config = &config,
        .stop = &stop_flag,
    };

    const thread = try std.Thread.spawn(.{}, SocketHandler.run, .{&socket_handler});

    webui.wait();
    webui.clean();

    stop_flag.store(true, .seq_cst);
    std.posix.close(sock_fd);

    thread.join();
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
