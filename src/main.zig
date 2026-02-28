const std = @import("std");
const yazap = @import("yazap");

pub fn foo() void {
    std.debug.print("FOOOO\n", .{});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.ArgIterator.initWithAllocator(allocator);
    var parser = yazap.ArgParser.init(allocator, args);
    defer parser.deinit();

    try parser.addBoolOption("foo");
    try parser.addBoolOption("bar");
    try parser.addStringOption("baz");

    var result = try parser.parse();
    defer result.deinit();

    parser.dumpOptions();
    parser.dumpUnknown();

    result.dumpResults();

    const foo_result = try result.expectBool("foo");
    if (foo_result) {
        foo();
    }
}
