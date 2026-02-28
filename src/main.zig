const std = @import("std");
const yazap = @import("yazap");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.ArgIterator.initWithAllocator(allocator);
    var parser = yazap.ArgParser.init(allocator, args);
    defer parser.deinit();

    try parser.addOption("foo", .{ .tag = .bool });
    try parser.addOption("bar", .{ .tag = .bool });

    try parser.parse();

    parser.dumpOptions();
    parser.dumpUnknown();
}
