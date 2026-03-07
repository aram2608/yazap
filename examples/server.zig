const std = @import("std");
const chizel = @import("chizel");

const ServerOpts = struct {
    host: []const u8 = "0.0.0.0",
    port: u16 = 3000,
    workers: u8 = 4,
    verbose: bool = false,

    pub const shorts = .{ .host = 'h', .port = 'p', .workers = 'w', .verbose = 'v' };
    pub const help = .{
        .host = "Bind address",
        .port = "Listen port",
        .workers = "Worker thread count",
        .verbose = "Enable verbose logging",
    };
    pub const config = .{ .help_enabled = true };

    pub fn validate_port(value: u16) !void {
        if (value < 1024) return error.PrivilegedPort;
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var args = try std.process.argsWithAllocator(alloc);
    defer args.deinit();

    const arena = std.heap.ArenaAllocator.init(alloc);
    var parser = chizel.Chip(ServerOpts).init(&args, arena);
    defer parser.deinit();

    const result = parser.parse() catch |err| switch (err) {
        error.PrivilegedPort => {
            std.debug.print("error: port must be >= 1024\n", .{});
            return;
        },
        else => return err,
    };

    if (result.had_help) {
        const help = try result.printHelp(alloc);
        defer alloc.free(help);
        std.debug.print("{s}\n", .{help});
        return;
    }

    const o = result.opts;
    std.debug.print("Starting server on {s}:{d} with {} workers (verbose={})\n", .{
        o.host, o.port, o.workers, o.verbose,
    });
}
