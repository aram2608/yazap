const std = @import("std");
const chizel = @import("chizel");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var args = try std.process.ArgIterator.initWithAllocator(allocator);
    defer args.deinit();
    var parser = try chizel.ArgParser.init(allocator, args);
    defer parser.deinit();

    try parser.addOption(.{ .name = "buzz", .tag = .string_slice, .help = "Words to print" });

    var result = try parser.parse();
    defer result.deinit();

    if (result.getStringSlice("buzz")) |slice| {
        for (slice) |s| {
            std.debug.print("{s}\n", .{s});
        }
    } else {
        std.debug.print("buzz: not provided\n", .{});
    }
}
