const std = @import("std");
const chizel = @import("chizel");

fn foo() void {
    std.debug.print("FOOOOOOOOOOO\n", .{});
}

fn bar() void {
    std.debug.print("No foo was provided and I am sad\n", .{});
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var args = try std.process.ArgIterator.initWithAllocator(allocator);
    defer args.deinit();
    var parser = try chizel.ArgParser.init(allocator, args);
    defer parser.deinit();

    try parser.addOption(.{ .name = "foo", .tag = .boolean, .help = "Run foo" });

    var result = try parser.parse();
    defer result.deinit();

    if (result.isPresent("foo")) foo() else bar();
}
