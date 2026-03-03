//! ParseResult — the output of `ArgParser.parse()`.
//!
//! Holds every resolved option value, the list of positional arguments, and
//! the pre-built help message.  All accessor functions (`getInt`, `getString`,
//! etc.) return `null` when the option was absent and had no default.
//!
//! ## Lifetime
//!
//! `ParseResult` borrows memory from the `ArgParser` that produced it.
//! Specifically, `getString` and `getStringSlice` return slices that point
//! into the parser's internal buffer or the process environment block.
//! Those slices are valid only while the `ArgParser` is alive.
//!
//! Always deinit in this order:
//!
//! ```zig
//! defer parser.deinit();   // second
//! defer result.deinit();   // first
//! ```

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

/// Initialise an empty result.
///
/// This is an internal function called by `ArgParser.parse()`.
/// Do not call it directly; construct a `ParseResult` through `ArgParser`.
pub fn init(gpa: Allocator) ParseResult {
    return .{
        .gpa = gpa,
        .results = ResultMap.init(gpa),
        .positionals = .empty,
    };
}

/// Free all resources owned by this result.
///
/// Frees heap-allocated `string_slice` outer slices and the help message
/// buffer.  `string` values and `string_slice` inner strings are slices into
/// the parser's buffer and the process environment block respectively; they
/// are not freed here.
///
/// Call `ArgParser.deinit()` *after* this, never before.
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

/// Returns the parsed `i64` value for `opt`.
///
/// Returns `null` when the option was absent with no default, or when `opt`
/// was registered with a tag other than `.int`.
pub fn getInt(self: *const ParseResult, opt: []const u8) ?i64 {
    const result = self.results.get(opt) orelse return null;
    return switch (result.value) {
        .int => |v| v,
        else => null,
    };
}

/// Returns the parsed `f64` value for `opt`.
///
/// Returns `null` when the option was absent with no default, or when `opt`
/// was registered with a tag other than `.float`.
pub fn getFloat(self: *const ParseResult, opt: []const u8) ?f64 {
    const result = self.results.get(opt) orelse return null;
    return switch (result.value) {
        .float => |v| v,
        else => null,
    };
}

/// Returns the parsed string for `opt`.
///
/// Returns `null` when the option was absent with no default, or when `opt`
/// was registered with a tag other than `.string`.
///
/// **Lifetime:** the returned slice points into the parser's internal buffer
/// (for CLI values) or the process environment block (for env-var fallbacks).
/// It is valid until `ArgParser.deinit()` is called.  Do not store it beyond
/// the scope in which the parser lives.
pub fn getString(self: *const ParseResult, opt: []const u8) ?[]const u8 {
    const result = self.results.get(opt) orelse return null;
    return switch (result.value) {
        .string => |v| v,
        else => null,
    };
}

/// Returns the parsed string list for `opt`.
///
/// Returns `null` when the option was absent (`.string_slice` has no default
/// support), or when `opt` was registered with a tag other than `.string_slice`.
///
/// **Lifetime:** the returned outer slice (`[][]const u8`) is heap-allocated
/// and freed by `deinit()`.  The inner strings point into the parser's buffer
/// or the process environment block and must not be freed by the caller.  All
/// pointers become invalid after `ArgParser.deinit()`.
///
/// If you need a fallback when the option is absent, use:
/// ```zig
/// const tags = result.getStringSlice("tags") orelse &.{};
/// ```
pub fn getStringSlice(self: *const ParseResult, opt: []const u8) ?[][]const u8 {
    const result = self.results.get(opt) orelse return null;
    return switch (result.value) {
        .string_slice => |v| v,
        else => null,
    };
}

/// Returns all positional (non-flag) arguments in the order they appeared.
///
/// Positional arguments are tokens that do not start with `-`.  They can be
/// freely mixed with flags on the command line.  The one exception is
/// `.string_slice` options: they are greedy and consume all following bare
/// words until the next flag, so place positionals before a `.string_slice`
/// option or after all options to avoid ambiguity.
///
/// The returned slice is backed by this `ParseResult` and is valid until
/// `deinit()` is called.
pub fn getPositionals(self: *const ParseResult) []const []const u8 {
    return self.positionals.items;
}

/// Returns `true` when `opt` was supplied on the CLI or via an env-var fallback.
///
/// A static `default` value does **not** count as "present" — `isPresent`
/// returns `false` for options that were resolved only from their default.
///
/// This is the canonical accessor for `.boolean` options.  It also works for
/// any other tag when you only care whether the user explicitly supplied the
/// flag rather than what value it holds.
pub fn isPresent(self: *const ParseResult, opt: []const u8) bool {
    const result = self.results.get(opt) orelse return false;
    return switch (result.value) {
        .boolean => |v| v,
        else => result.count > 0,
    };
}

/// Returns the number of times `opt` appeared on the command line.
///
/// Returns `0` when the option was absent, resolved from an env-var, or
/// resolved from a default.  Returns `1` for an env-var fallback.
///
/// Useful for stacking boolean flags to express a verbosity level:
///
/// ```zig
/// // ./myapp -v -v -v
/// const level = result.getCount("verbose"); // 3
/// ```
pub fn getCount(self: *const ParseResult, opt: []const u8) u32 {
    const result = self.results.get(opt) orelse return 0;
    return result.count;
}

/// Returns `true` if `--help` or `-h` was present in the arguments.
///
/// When `true`, required-option checks were skipped during `parse()`, so other
/// results may be absent or incomplete.  Always check this before reading any
/// other values:
///
/// ```zig
/// if (result.hadHelp()) {
///     try result.printHelp();
///     return;
/// }
/// ```
pub fn hadHelp(self: *const ParseResult) bool {
    return self.had_help;
}

/// Write the generated help message to stdout.
///
/// The message is built by `ArgParser.parse()` from the registered options and
/// their metadata (name, short alias, type hint, help text, required/env/default
/// annotations).  Options are listed in registration order; `--help` is always
/// last.
///
/// Call this after checking `hadHelp()`:
///
/// ```zig
/// if (result.hadHelp()) {
///     try result.printHelp();
///     return;
/// }
/// ```
pub fn printHelp(self: *const ParseResult) !void {
    const msg = self.help_message orelse return;
    try std.fs.File.stdout().writeAll(msg);
}

/// Print all resolved option values to a `Writer`.
///
/// Intended for debugging only.  Output order is non-deterministic (HashMap
/// iteration order).  Values include those resolved from CLI flags, env-var
/// fallbacks, and static defaults.
///
/// Output format: `Opt: <name> || Value: <value> || Count: <n>\n`
pub fn dumpResults(self: *const ParseResult, writer: anytype) !void {
    var iter = self.results.iterator();
    while (iter.next()) |pair| {
        try writer.print("Opt: {s} || Value: {} || Count: {}\n", .{ pair.key_ptr.*, pair.value_ptr.value, pair.value_ptr.count });
    }
}

pub const Result = struct {
    value: Option.Value,
    count: u32,
};
