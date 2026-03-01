const std = @import("std");
const yazap = @import("yazap");

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

    const foo_val = result.getBool("foo") orelse false;
    std.debug.print("foo: {}\n", .{foo_val});

    const bar_present = result.isPresent("bar");
    std.debug.print("bar present: {}\n", .{bar_present});

    if (result.getString("baz")) |s| {
        std.debug.print("baz: {s}\n", .{s});
    } else {
        std.debug.print("baz: not provided\n", .{});
    }
}
