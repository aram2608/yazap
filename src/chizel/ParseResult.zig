const std = @import("std");
const ResultMap = std.StringHashMap(Result);
const Allocator = std.mem.Allocator;
const Option = @import("Option.zig");
const ParseResult = @This();

gpa: Allocator,
results: ResultMap,
positionals: std.ArrayList([]const u8),
had_help: bool = false,
/// Null until `ArgParser.parse()` completes successfully.
help_message: ?[]u8 = null,

/// Initialise an empty result. Called internally by `ArgParser.parse()`.
pub fn init(gpa: Allocator) ParseResult {
    return .{
        .gpa = gpa,
        .results = ResultMap.init(gpa),
        .positionals = .empty,
    };
}

/// Free all resources owned by this result.
/// Call `ArgParser.deinit()` after this, never before.
pub fn deinit(self: *ParseResult) void {
    var iter = self.results.valueIterator();
    while (iter.next()) |result| {
        switch (result.value) {
            .string_slice => |slice| self.gpa.free(slice),
            else => {},
        }
    }
    if (self.help_message) |msg| self.gpa.free(msg);
    self.positionals.deinit(self.gpa);
    self.results.deinit();
}

/// Returns the parsed `i64` value for `opt`, or `null` if absent or wrong type.
pub fn getInt(self: *const ParseResult, opt: []const u8) ?i64 {
    const result = self.results.get(opt) orelse return null;
    return switch (result.value) {
        .int => |v| v,
        else => null,
    };
}

/// Returns the parsed `f64` value for `opt`, or `null` if absent or wrong type.
pub fn getFloat(self: *const ParseResult, opt: []const u8) ?f64 {
    const result = self.results.get(opt) orelse return null;
    return switch (result.value) {
        .float => |v| v,
        else => null,
    };
}

/// Returns the parsed string for `opt`, or `null` if absent or wrong type.
/// The slice points into the parser's internal buffer; it is valid until `ArgParser.deinit()`.
pub fn getString(self: *const ParseResult, opt: []const u8) ?[]const u8 {
    const result = self.results.get(opt) orelse return null;
    return switch (result.value) {
        .string => |v| v,
        else => null,
    };
}

/// Returns the parsed string list for `opt`, or `null` if absent or wrong type.
/// The outer slice is heap-allocated and freed by `deinit()`. The inner strings
/// point into the parser's buffer (or env block) and must not be freed by the caller.
pub fn getStringSlice(self: *const ParseResult, opt: []const u8) ?[][]const u8 {
    const result = self.results.get(opt) orelse return null;
    return switch (result.value) {
        .string_slice => |v| v,
        else => null,
    };
}

/// Returns all positional (non-flag) arguments in the order they appeared.
/// The returned slice is valid for the lifetime of this `ParseResult`.
pub fn getPositionals(self: *const ParseResult) []const []const u8 {
    return self.positionals.items;
}

/// Whether the flag was present on the CLI or satisfied via an env-var fallback.
/// This is the canonical way to test boolean flags; it also works for any other
/// option type when you only care about presence rather than the parsed value.
pub fn isPresent(self: *const ParseResult, opt: []const u8) bool {
    const result = self.results.get(opt) orelse return false;
    return result.count > 0;
}

/// Returns how many times `opt` appeared on the command line.
/// Useful for repeated flags such as `-v -v -v` to indicate verbosity level.
pub fn getCount(self: *const ParseResult, opt: []const u8) u32 {
    const result = self.results.get(opt) orelse return 0;
    return result.count;
}

/// Returns `true` if `--help` was present in the arguments.
/// When true, required-option checks are skipped and other results may be incomplete.
/// Check this first and call `printHelp()` before reading any other values.
pub fn hadHelp(self: *const ParseResult) bool {
    return self.had_help;
}

/// Write the help message to stdout.
pub fn printHelp(self: *const ParseResult) !void {
    const msg = self.help_message orelse return;
    try std.fs.File.stdout().writeAll(msg);
}

/// Print all parsed results to stderr. Intended for debugging only.
pub fn dumpResults(self: *const ParseResult) void {
    var iter = self.results.iterator();
    while (iter.next()) |pair| {
        const name = pair.key_ptr.*;
        const result = pair.value_ptr.*;
        std.debug.print("Opt: {s} || Value: {} || Count: {}\n", .{ name, result.value, result.count });
    }
}

pub const Result = struct {
    value: Option.Value,
    count: u32,
};
