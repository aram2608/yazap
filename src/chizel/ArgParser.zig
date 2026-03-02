const std = @import("std");
const ArgIterator = std.process.ArgIterator;
const Allocator = std.mem.Allocator;
const ParseResult = @import("ParseResult.zig");
const Option = @import("Option.zig");
const Parser = @This();
const OptionsMap = std.StringHashMap(Option);

gpa: Allocator,
options: OptionsMap,
short_map: std.AutoHashMap(u8, []const u8),
buffer: []const u8,
start: usize = 0,
current: usize = 0,
program_name: []const u8 = "",
option_order: std.ArrayList([]const u8) = .empty,
unknown_options: std.ArrayList([]const u8) = .empty,
parsed: bool = false,

/// Create a parser from a `std.process.ArgIterator`.
/// Consumes `argv[0]` as the program name and joins remaining arguments into
/// an internal buffer (max 4096 bytes total).
/// Returns `error.ArgumentBufferOverflow` if the limit is exceeded.
pub fn init(gpa: Allocator, args: ArgIterator) !Parser {
    var temp: [4096]u8 = undefined;
    var pos: usize = 0;
    var temp_args = args;
    const name = temp_args.next().?; // argv[0]
    while (temp_args.next()) |arg| {
        if (pos + arg.len + 1 > temp.len) return error.ArgumentBufferOverflow;
        @memcpy(temp[pos..][0..arg.len], arg);
        temp[pos + arg.len] = ' ';
        pos += arg.len + 1;
    }
    return .{
        .gpa = gpa,
        .program_name = try gpa.dupe(u8, name),
        .buffer = try gpa.dupe(u8, temp[0..pos]),
        .options = OptionsMap.init(gpa),
        .short_map = std.AutoHashMap(u8, []const u8).init(gpa),
    };
}

/// Free all resources owned by the parser.
/// Any `string` or `string_slice` values held by a `ParseResult` produced by
/// this parser become invalid after this call.
pub fn deinit(self: *Parser) void {
    self.gpa.free(self.buffer);
    self.gpa.free(self.program_name);
    self.option_order.deinit(self.gpa);
    self.options.deinit();
    self.unknown_options.deinit(self.gpa);
    self.short_map.deinit();
}

/// Register a command-line option.
///
/// Errors:
/// - `error.ReservedOptionName`             — `"help"` is always built-in.
/// - `error.DuplicateOption`                — the name was already registered.
/// - `error.StringSliceDefaultNotSupported` — use `getStringSlice() orelse &.{...}` instead.
pub fn addOption(self: *Parser, config: Option.Config) !void {
    if (std.mem.eql(u8, config.name, "help")) return error.ReservedOptionName;
    if (self.options.contains(config.name)) return error.DuplicateOption;
    if (config.default) |d| {
        if (d == .string_slice) return error.StringSliceDefaultNotSupported;
    }

    try self.option_order.append(self.gpa, config.name);
    try self.options.put(config.name, .{
        .tag = config.tag,
        .help = config.help,
        .short = config.short,
        .required = config.required,
        .env = config.env,
        .validate = config.validate,
        .default = config.default,
    });
    if (config.short) |s| {
        try self.short_map.put(s, config.name);
    }
}

/// Parse the argument buffer and return a `ParseResult`.
/// May only be called once per parser instance.
///
/// Resolution order for each option: CLI flag › environment variable › default.
///
/// Errors:
/// - `error.AlreadyParsed`         — called more than once.
/// - `error.MissingValue`          — a non-boolean option had no value after it.
/// - `error.ValidationFailed`      — a `validate` callback returned `false`.
/// - `error.MissingRequiredOption` — a `required` option was absent from CLI and env.
///                                   Skipped when `--help` was passed.
pub fn parse(self: *Parser) !ParseResult {
    if (self.parsed) return error.AlreadyParsed;
    self.parsed = true;
    var parse_result = ParseResult.init(self.gpa);
    errdefer parse_result.deinit();

    while (!self.isEnd()) {
        self.start = self.current;
        const c = self.advance();

        if (c == ' ') continue;

        if (c == '-') {
            var key = self.parseOption();

            // Resolve short options
            if (key.len == 1) {
                if (self.short_map.get(key[0])) |long_name| {
                    key = long_name;
                }
            }

            // Help is always reserved
            if (std.mem.eql(u8, key, "help")) {
                parse_result.had_help = true;
                continue;
            }

            const parse_attempt = self.options.getPtr(key);
            if (parse_attempt) |option| {
                option.count += 1;
                // Non-boolean options require a space then their value.
                if (option.tag != .boolean) {
                    if (self.isEnd() or self.buffer[self.current] != ' ') return error.MissingValue;
                    _ = self.advance(); // skip the space
                }
                self.start = self.current;
                const value = try self.parsePayload(option.tag);

                if (option.validate) |validate_fn| {
                    if (!validate_fn(value)) return error.ValidationFailed;
                }

                // When an option is passed more than once the previous slice
                // needs to get removed from memory.
                if (parse_result.results.get(key)) |old| {
                    if (old.value == .string_slice) self.gpa.free(old.value.string_slice);
                }
                try parse_result.results.put(key, .{ .value = value, .count = option.count });
            } else {
                try self.unknown_options.append(self.gpa, key);
            }
        } else {
            // collect the rest of the token.
            while (!self.isEnd() and !self.checkBuffer(' ')) {
                _ = self.advance();
            }
            try parse_result.positionals.append(self.gpa, self.buffer[self.start..self.current]);
        }
    }

    // Apply env-var fallbacks and static defaults for options not on the CLI.
    var opt_iter = self.options.iterator();
    while (opt_iter.next()) |entry| {
        const name = entry.key_ptr.*;
        const option = entry.value_ptr;
        if (parse_result.results.contains(name)) continue;

        // Env vars have lower priority than CLI but higher than defaults.
        if (option.env) |env_key| {
            if (std.posix.getenv(env_key)) |env_val| {
                const value = try parseEnvValue(self.gpa, option.tag, env_val);
                if (option.validate) |validate_fn| {
                    if (!validate_fn(value)) return error.ValidationFailed;
                }
                try parse_result.results.put(name, .{ .value = value, .count = 1 });
                continue;
            }
        }

        if (option.default) |default_val| {
            try parse_result.results.put(name, .{ .value = default_val, .count = 0 });
        }
    }

    // Verify all required options were satisfied (defaults do not count;
    // must be passed via CLI or env var).  Skip when --help was requested
    // so the user can always see usage without supplying every required flag.
    if (!parse_result.hadHelp()) {
        var req_iter = self.options.iterator();
        while (req_iter.next()) |entry| {
            if (!entry.value_ptr.required) continue;
            const result = parse_result.results.get(entry.key_ptr.*);
            if (result == null or result.?.count == 0) return error.MissingRequiredOption;
        }
    }

    parse_result.help_message = try self.buildHelpMessage();
    return parse_result;
}

fn advance(self: *Parser) u8 {
    if (self.isEnd()) return 0;
    const c: u8 = self.buffer[self.current];
    self.current += 1;
    return c;
}

/// Advance past all characters of an option name and return the name slice
/// with its leading dash(es) stripped.
fn parseOption(self: *Parser) []const u8 {
    while (!self.isEnd() and !self.checkBuffer(' ')) {
        _ = self.advance();
    }
    const prefix_len: usize =
        if (self.start + 1 < self.buffer.len and self.buffer[self.start + 1] == '-') 2 else 1;
    return self.buffer[self.start + prefix_len .. self.current];
}

fn parsePayload(self: *Parser, tag: Option.Tag) !Option.Value {
    return switch (tag) {
        .boolean => .{ .boolean = true },
        .int => .{ .int = try self.parseInt() },
        .float => .{ .float = try self.parseFloat() },
        .string => .{ .string = try self.parseString() },
        .string_slice => .{ .string_slice = try self.parseStringSlice() },
    };
}

fn parseString(self: *Parser) ![]const u8 {
    const arg = self.nextToken();
    if (arg.len == 0) return error.MissingValue;
    return arg;
}

fn parseInt(self: *Parser) !i64 {
    return std.fmt.parseInt(i64, self.nextToken(), 10);
}

fn parseFloat(self: *Parser) !f64 {
    return std.fmt.parseFloat(f64, self.nextToken());
}

fn parseStringSlice(self: *Parser) ![][]const u8 {
    var list: std.ArrayList([]const u8) = .empty;
    errdefer list.deinit(self.gpa);

    // Collect tokens until end of buffer or something that looks like a new
    // flag.  looksLikeOption() permits values such as "-1" or "-3.14" to be
    // part of the slice while still stopping on "--flag" or "-f".
    while (!self.isEnd() and !self.looksLikeOption()) {
        self.start = self.current;
        const token = self.nextToken();
        if (token.len > 0) try list.append(self.gpa, token);
        if (!self.isEnd()) _ = self.advance(); // skip the trailing space
    }

    if (list.items.len == 0) return error.MissingValue;
    return list.toOwnedSlice(self.gpa);
}

fn nextToken(self: *Parser) []const u8 {
    while (!self.isEnd() and !self.checkBuffer(' ')) {
        _ = self.advance();
    }
    return self.buffer[self.start..self.current];
}

fn checkBuffer(self: *const Parser, c: u8) bool {
    return self.peekBuffer() == c;
}

fn peekBuffer(self: *const Parser) u8 {
    if (self.current >= self.buffer.len) return 0;
    return self.buffer[self.current];
}

fn isEnd(self: *const Parser) bool {
    return self.current >= self.buffer.len;
}

/// Returns true when the current position looks like the start of a flag
/// (`--anything` or `-<alpha>`).  Values such as `-1` or `-3.14` return false,
/// so they are not mistakenly treated as option starters in string-slice parsing.
fn looksLikeOption(self: *const Parser) bool {
    if (self.current >= self.buffer.len) return false;
    if (self.buffer[self.current] != '-') return false;
    if (self.current + 1 >= self.buffer.len) return false;
    const next = self.buffer[self.current + 1];
    return next == '-' or std.ascii.isAlphabetic(next);
}

fn parseEnvValue(gpa: Allocator, tag: Option.Tag, raw: []const u8) !Option.Value {
    return switch (tag) {
        .boolean => .{ .boolean = std.mem.eql(u8, raw, "1") or
            std.mem.eql(u8, raw, "true") or
            std.mem.eql(u8, raw, "yes") },
        .int => .{ .int = try std.fmt.parseInt(i64, raw, 10) },
        .float => .{ .float = try std.fmt.parseFloat(f64, raw) },
        .string => .{ .string = raw }, // env block is valid for the process lifetime
        .string_slice => blk: {
            var list: std.ArrayList([]const u8) = .empty;
            errdefer list.deinit(gpa);
            var it = std.mem.splitScalar(u8, raw, ' ');
            while (it.next()) |part| {
                if (part.len > 0) try list.append(gpa, part);
            }
            break :blk .{ .string_slice = try list.toOwnedSlice(gpa) };
        },
    };
}

fn buildHelpMessage(self: *Parser) ![]u8 {
    const prefix = "--";
    const col_gap: usize = 2;
    // Short-flag column: "-s, " (4 chars) or "    " (4-space padding).
    const short_col: usize = 4;

    var buff = std.Io.Writer.Allocating.init(self.gpa);
    errdefer buff.deinit();

    try buff.writer.print("Usage: {s} [OPTIONS]\nOptions:\n", .{self.program_name});

    // Seed with the built-in --help so it is included in alignment calculations.
    var max_left: usize = short_col + prefix.len + "help".len;
    for (self.option_order.items) |name| {
        const opt = self.options.get(name).?;
        const hint = typeHint(opt.tag);
        const left = short_col + prefix.len + name.len + if (hint.len > 0) 1 + hint.len else 0;
        if (left > max_left) max_left = left;
    }

    for (self.option_order.items) |name| {
        const opt = self.options.get(name).?;
        const hint = typeHint(opt.tag);
        var left: usize = short_col + prefix.len + name.len;

        if (opt.short) |s| {
            try buff.writer.print("-{c}, ", .{s});
        } else {
            try buff.writer.print("    ", .{});
        }

        try buff.writer.print("{s}{s}", .{ prefix, name });
        if (hint.len > 0) {
            try buff.writer.print(" {s}", .{hint});
            left += 1 + hint.len;
        }
        try buff.writer.splatByteAll(' ', max_left - left + col_gap);
        try buff.writer.print("{s}", .{opt.help});

        if (opt.required) try buff.writer.print(" (required)", .{});
        if (opt.env) |env_key| try buff.writer.print(" [${s}]", .{env_key});
        if (opt.default) |d| {
            switch (d) {
                .boolean => |v| try buff.writer.print(" (default: {})", .{v}),
                .int => |v| try buff.writer.print(" (default: {})", .{v}),
                .float => |v| try buff.writer.print(" (default: {})", .{v}),
                .string => |v| try buff.writer.print(" (default: {s})", .{v}),
                .string_slice => {}, // guarded against in addOption
            }
        }
        try buff.writer.print("\n", .{});
    }

    // --help is always listed last.
    const help_left = short_col + prefix.len + "help".len;
    try buff.writer.print("    {s}help", .{prefix});
    try buff.writer.splatByteAll(' ', max_left - help_left + col_gap);
    try buff.writer.print("Print this help message\n", .{});

    return buff.toOwnedSlice();
}

fn typeHint(tag: Option.Tag) []const u8 {
    return switch (tag) {
        .boolean => "",
        .int => "<int>",
        .float => "<float>",
        .string => "<string>",
        .string_slice => "<string...>",
    };
}

/// Write unknown (unregistered) option names to `writer`.
pub fn dumpUnknown(self: *const Parser, writer: anytype) !void {
    for (self.unknown_options.items) |name| {
        try writer.print("Unknown opt: {s}\n", .{name});
    }
}

/// Write registered option names and their tags to `writer`.
pub fn dumpOptions(self: *const Parser, writer: anytype) !void {
    var iter = self.options.iterator();
    while (iter.next()) |opt| {
        try writer.print("Key: {s} || Tag: {s}\n", .{ opt.key_ptr.*, @tagName(opt.value_ptr.tag) });
    }
}
