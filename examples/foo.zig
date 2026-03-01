const std = @import("std");
const yazap = @import("yazap");

fn foo() void {
    std.debug.print("FOOOOOOOOOOO\n", .{});
}

fn bar() void {
    std.debug.print("No foo was provided and I am sad\n", .{});
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const args = try std.process.ArgIterator.initWithAllocator(allocator);
    var parser = yazap.ArgParser.init(allocator, args);
    defer parser.deinit();

    try parser.addOption("foo", .boolean);

    var result = try parser.parse();
    defer result.deinit();

    if (result.getBool("foo")) |_| foo() else bar();
}
