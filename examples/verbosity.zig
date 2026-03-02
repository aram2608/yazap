const std = @import("std");
const chizel = @import("chizel");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var args = try std.process.ArgIterator.initWithAllocator(allocator);
    defer args.deinit();
    var parser = try chizel.ArgParser.init(allocator, args);
    defer parser.deinit();

    try parser.addOption(.{
        .name = "verbose",
        .short = 'v',
        .tag = .boolean,
        .help = "Increase verbosity (repeat up to 3 times)",
    });

    try parser.addOption(.{
        .name = "format",
        .short = 'f',
        .tag = .string,
        .default = .{ .string = "text" },
        .help = "Output format: text or json",
        .validate = struct {
            fn check(v: chizel.Option.Value) bool {
                const s = v.string;
                return std.mem.eql(u8, s, "text") or std.mem.eql(u8, s, "json");
            }
        }.check,
    });

    try parser.addOption(.{
        .name = "threshold",
        .tag = .float,
        .default = .{ .float = 0.5 },
        .help = "Detection threshold, 0.0–1.0",
        .validate = struct {
            fn check(v: chizel.Option.Value) bool {
                return v.float >= 0.0 and v.float <= 1.0;
            }
        }.check,
    });

    var result = try parser.parse();
    defer result.deinit();

    if (result.hadHelp()) {
        try result.printHelp();
        return;
    }

    const level = result.getCount("verbose");
    const format = result.getString("format") orelse "text";
    const threshold = result.getFloat("threshold") orelse 0.5;

    const level_name = switch (level) {
        0 => "ERROR",
        1 => "WARN",
        2 => "INFO",
        else => "DEBUG",
    };

    std.debug.print("Log level : {} ({s})\n", .{ level, level_name });
    std.debug.print("Format    : {s}\n", .{format});
    std.debug.print("Threshold : {d:.2}\n", .{threshold});
}
