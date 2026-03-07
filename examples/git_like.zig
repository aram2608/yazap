const std = @import("std");
const chizel = @import("chizel");

const Commands = union(enum) {
    clone: struct {
        depth: u32 = 0,
        bare: bool = false,

        pub const shorts = .{ .depth = 'd' };
        pub const help = .{
            ._cmd = "Clone a repository",
            .depth = "Shallow clone depth (0 = full)",
            .bare = "Create a bare repository",
        };
    },
    commit: struct {
        message: []const u8 = "",
        all: bool = false,
        amend: bool = false,

        pub const shorts = .{ .message = 'm', .all = 'a' };
        pub const help = .{
            ._cmd = "Record changes",
            .message = "Commit message",
            .all = "Stage all tracked changes",
            .amend = "Amend previous commit",
        };

        pub fn validate_message(value: []const u8) !void {
            if (value.len == 0) return error.EmptyMessage;
        }
    },
    status: struct {
        short: bool = false,
        branch: bool = true,

        pub const shorts = .{ .short = 's' };
        pub const help = .{
            ._cmd = "Show working tree status",
            .short = "Short format output",
            .branch = "Show branch info",
        };
    },

    pub const help = .{
        .clone = "Clone a repository",
        .commit = "Record changes to the repository",
        .status = "Show working tree status",
    };
    pub const config = .{ .help_enabled = true };
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var args = try std.process.argsWithAllocator(alloc);
    defer args.deinit();

    const arena = std.heap.ArenaAllocator.init(alloc);
    var parser = chizel.Chizel(Commands).init(&args, arena);
    defer parser.deinit();

    const result = parser.parse() catch |err| switch (err) {
        error.EmptyMessage => {
            std.debug.print("error: commit message cannot be empty\n", .{});
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

    switch (result.opts) {
        .clone => |o| {
            std.debug.print("Cloning (depth={}, bare={})\n", .{ o.depth, o.bare });
            for (result.positionals) |pos| std.debug.print("  url: {s}\n", .{pos});
        },
        .commit => |o| {
            std.debug.print("Committing: \"{s}\" (all={}, amend={})\n", .{ o.message, o.all, o.amend });
        },
        .status => |o| {
            std.debug.print("Status (short={}, branch={})\n", .{ o.short, o.branch });
        },
    }
}
