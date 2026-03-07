const std = @import("std");
const chizel = @import("chizel");

const BuildOpts = struct {
    release: bool = false,
    target: []const u8 = "native",
    jobs: u8 = 1,
    output: []const u8 = "out",

    pub const shorts = .{ .release = 'r', .target = 't', .jobs = 'j', .output = 'o' };
    pub const help = .{
        .release = "Build in release mode",
        .target = "Compilation target triple",
        .jobs = "Parallel job count",
        .output = "Output directory",
    };
    pub const config = .{ .help_enabled = true, .allow_unknown = false };

    pub fn validate_jobs(value: u8) !void {
        if (value == 0) return error.ZeroJobs;
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var args = try std.process.argsWithAllocator(alloc);
    defer args.deinit();

    const arena = std.heap.ArenaAllocator.init(alloc);
    var parser = chizel.Chip(BuildOpts).init(&args, arena);
    defer parser.deinit();

    const result = parser.parse() catch |err| switch (err) {
        error.ZeroJobs => {
            std.debug.print("error: --jobs must be >= 1\n", .{});
            return;
        },
        else => return err,
    };

    if (result.had_help) {
        const help = try result.printHelp(alloc);
        defer alloc.free(help);
        std.debug.print("{s}\n", .{help});
        return;
    }

    const o = result.opts;
    std.debug.print("Building target={s} jobs={} release={} -> {s}/\n", .{
        o.target, o.jobs, o.release, o.output,
    });

    for (result.positionals) |src| {
        std.debug.print("  compiling: {s}\n", .{src});
    }
}
