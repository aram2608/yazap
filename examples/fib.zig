const std = @import("std");
const yazap = @import("yazap");

fn fibonacci(range: i32) i32 {
    if (range <= 1) return range;

    var a: i32 = 0;
    var b: i32 = 1;
    var c: i32 = 0;
    for (1..@intCast(range)) |_| {
        c = a + b;
        a = b;
        b = c;
    }

    return b;
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const args = try std.process.ArgIterator.initWithAllocator(allocator);
    var parser = yazap.ArgParser.init(allocator, args);
    defer parser.deinit();

    try parser.addOption("foo", .int);

    var result = try parser.parse();
    defer result.deinit();

    if (result.getInt("foo")) |num| {
        const fib = fibonacci(num);
        std.debug.print("The {} fibonacci number is {}\n", .{ num, fib });
    }
}
