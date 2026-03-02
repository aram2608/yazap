const std = @import("std");

tag: Tag,
help: []const u8 = "",
count: u32 = 0,
short: ?u8 = null,
required: bool = false,
env: ?[]const u8 = null,
validate: ?*const fn (Value) bool = null,
default: ?Value = null,

/// Input passed to `ArgParser.addOption`. All fields except `name` and `tag` are optional.
pub const Config = struct {
    /// Long flag name (e.g. `"verbose"` maps to `--verbose`).
    name: []const u8,
    /// Single-character short alias (e.g. `'v'` maps `-v` to `--verbose`).
    short: ?u8 = null,
    /// Value type. Determines which `get*` accessor to use on `ParseResult`.
    tag: Tag,
    /// Text shown next to the flag in `--help` output.
    help: []const u8 = "",
    /// Return `error.MissingRequiredOption` from `parse()` when the flag is absent
    /// from both CLI and env. Satisfied by a CLI flag or an env-var fallback;
    /// a `default` alone does not count.
    required: bool = false,
    /// Environment variable to consult when the flag is absent from the CLI.
    /// CLI takes precedence; env takes precedence over `default`.
    env: ?[]const u8 = null,
    /// Called immediately after the value is parsed (CLI or env).
    /// Return `false` to surface `error.ValidationFailed` from `parse()`.
    validate: ?*const fn (Value) bool = null,
    /// Value to use when the flag is absent from both CLI and env.
    /// `string_slice` defaults are not supported; use `getStringSlice() orelse &.{...}`.
    default: ?Value = null,
};

/// Discriminator for the type of value an option holds.
pub const Tag = enum {
    /// Presence flag. No value token is consumed; the flag being present means `true`.
    boolean,
    /// A single word, returned as `[]const u8`.
    string,
    /// A decimal integer, stored as `i64`.
    int,
    /// A floating-point number, stored as `f64`.
    float,
    /// One or more space-separated words. Greedy: consumes tokens until the next flag.
    string_slice,
};

/// The parsed value stored in a `ParseResult`. The active field matches the option's `Tag`.
pub const Value = union(enum) {
    boolean: bool,
    int: i64,
    float: f64,
    string: []const u8,
    string_slice: [][]const u8,
};
