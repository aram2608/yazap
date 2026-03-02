const std = @import("std");
const chizel = @import("chizel");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var args = try std.process.ArgIterator.initWithAllocator(allocator);
    defer args.deinit();
    var parser = try chizel.ArgParser.init(allocator, args);
    defer parser.deinit();

    try parser.addOption(.{
        .name = "host",
        .tag = .string,
        .env = "APP_HOST",
        .default = .{ .string = "localhost" },
        .help = "Server host (env: APP_HOST)",
    });

    try parser.addOption(.{
        .name = "port",
        .short = 'p',
        .tag = .int,
        .env = "APP_PORT",
        .default = .{ .int = 8080 },
        .help = "Port to listen on, 1–65535 (env: APP_PORT)",
        .validate = struct {
            fn check(v: chizel.Option.Value) bool {
                return v.int >= 1 and v.int <= 65535;
            }
        }.check,
    });

    try parser.addOption(.{
        .name = "workers",
        .short = 'w',
        .tag = .int,
        .default = .{ .int = 4 },
        .help = "Worker thread count, 1–16",
        .validate = struct {
            fn check(v: chizel.Option.Value) bool {
                return v.int >= 1 and v.int <= 16;
            }
        }.check,
    });

    try parser.addOption(.{
        .name = "timeout",
        .tag = .float,
        .default = .{ .float = 30.0 },
        .help = "Request timeout in seconds (must be > 0)",
        .validate = struct {
            fn check(v: chizel.Option.Value) bool {
                return v.float > 0.0;
            }
        }.check,
    });

    try parser.addOption(.{
        .name = "verbose",
        .short = 'v',
        .tag = .boolean,
        .help = "Enable verbose logging",
    });

    var result = try parser.parse();
    defer result.deinit();

    if (result.hadHelp()) {
        try result.printHelp();
        return;
    }

    const host = result.getString("host") orelse "localhost";
    const port = result.getInt("port") orelse 8080;
    const workers = result.getInt("workers") orelse 4;
    const timeout = result.getFloat("timeout") orelse 30.0;
    const verbose = result.isPresent("verbose");

    std.debug.print("Starting server\n", .{});
    std.debug.print("  host:    {s}\n", .{host});
    std.debug.print("  port:    {}\n", .{port});
    std.debug.print("  workers: {}\n", .{workers});
    std.debug.print("  timeout: {d:.1}s\n", .{timeout});
    if (verbose) std.debug.print("  verbose: on\n", .{});
}
