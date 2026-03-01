# yazap
Yet Another Zig Argument Parser.

A simple CLI argument parser for zig-lang. A current work in progress.
As of now, i32, f32, bool, and []const u8 types can be parsed.

I hope to implement more complex types such as [][]const u8 or std.ArrayList(u8)
in the future.

Examples for how to use the library are provided in the `examples` directory but the
gist of the library is as follows.

```zig
fn main() !void {
    const allocator = std.heap.page_allocator;

    const args = try std.process.ArgIterator.initWithAllocator(allocator);
    var parser = yazap.ArgParser.init(allocator, args);
    defer parser.deinit();

    try parser.addBoolOption("foo");

    var result = try parser.parse();
    defer result.deinit();

    if (result.getBool("foo")) |_| foo() else bar();
}
```

The `get` methods returns an `?ExpectedValue` so the optional needs to 
be unwrapped. How you choose to go about this is up to you.