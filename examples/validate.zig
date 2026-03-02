const std = @import("std");
const chizel = @import("chizel");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var args = try std.process.ArgIterator.initWithAllocator(allocator);
    defer args.deinit();
    var parser = try chizel.ArgParser.init(allocator, args);
    defer parser.deinit();

    try parser.addOption(.{
        .name = "username",
        .tag = .string,
        .required = true,
        .help = "Username, 3–20 characters (required)",
        .validate = struct {
            fn check(v: chizel.Option.Value) bool {
                return v.string.len >= 3 and v.string.len <= 20;
            }
        }.check,
    });

    try parser.addOption(.{
        .name = "email",
        .tag = .string,
        .required = true,
        .help = "Email address, must contain '@' (required)",
        .validate = struct {
            fn check(v: chizel.Option.Value) bool {
                return std.mem.indexOfScalar(u8, v.string, '@') != null;
            }
        }.check,
    });

    try parser.addOption(.{
        .name = "age",
        .tag = .int,
        .help = "Age in years, 0–150",
        .validate = struct {
            fn check(v: chizel.Option.Value) bool {
                return v.int >= 0 and v.int <= 150;
            }
        }.check,
    });

    try parser.addOption(.{
        .name = "score",
        .tag = .float,
        .help = "Score percentage, 0.0–100.0",
        .validate = struct {
            fn check(v: chizel.Option.Value) bool {
                return v.float >= 0.0 and v.float <= 100.0;
            }
        }.check,
    });

    try parser.addOption(.{
        .name = "tags",
        .tag = .string_slice,
        .help = "Labels to attach, at most 5",
        .validate = struct {
            fn check(v: chizel.Option.Value) bool {
                return v.string_slice.len <= 5;
            }
        }.check,
    });

    var result = try parser.parse();
    defer result.deinit();

    if (result.hadHelp()) {
        try result.printHelp();
        return;
    }

    std.debug.print("username : {s}\n", .{result.getString("username") orelse "-"});
    std.debug.print("email    : {s}\n", .{result.getString("email") orelse "-"});

    if (result.getInt("age")) |a| std.debug.print("age      : {}\n", .{a});
    if (result.getFloat("score")) |s| std.debug.print("score    : {d:.1}\n", .{s});

    if (result.getStringSlice("tags")) |tags| {
        std.debug.print("tags     :", .{});
        for (tags) |t| std.debug.print(" {s}", .{t});
        std.debug.print("\n", .{});
    }
}
