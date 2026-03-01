const std = @import("std");
const ArgIterator = std.process.ArgIterator;
const Allocator = std.mem.Allocator;
const ParseResult = @import("ParseResult.zig");
const Option = @import("Option.zig");
const Parser = @This();
const OptionsMap = std.StringHashMap(Option);

gpa: Allocator,
options: OptionsMap,
buffer: []const u8,
start: usize = 0,
current: usize = 0,
unknown_options: std.ArrayList([]const u8) = .empty,
parsed: bool = false,

// TODO: Store the program name so a help message can be added for each argument
// With the program name
pub fn init(gpa: Allocator, args: ArgIterator) !Parser {
    var temp: [4096]u8 = undefined;
    var pos: usize = 0;
    var temp_args = args;
    _ = temp_args.skip(); // skip argv[0]
    while (temp_args.next()) |arg| {
        if (pos + arg.len + 1 > temp.len) @panic("argument buffer overflow");
        @memcpy(temp[pos..][0..arg.len], arg);
        temp[pos + arg.len] = ' ';
        pos += arg.len + 1;
    }
    return .{
        .gpa = gpa,
        .buffer = try gpa.dupe(u8, temp[0..pos]),
        .options = OptionsMap.init(gpa),
    };
}

pub fn deinit(self: *Parser) void {
    self.gpa.free(self.buffer);
    self.options.deinit();
    self.unknown_options.deinit(self.gpa);
}

/// TODO: Look into Type reification for custom `Options`.
/// Need custom option and matching `Result`.
// pub fn addOption(self: *Parser, name: []const u8, comptime T: type) !void {
//     switch (@typeInfo(T)) {
//         .int => try self.addIntOption(name),
//         .float => try self.addFloatOption(name),
//         .pointer => |p| if (p.size == .slice and p.child == u8) try self.addStringOption(name) else return error.UnknownType,
//         .bool => try self.addBoolOption(name),
//         else => return error.UnknownType,
//     }
// }
//

pub fn addOption(self: *Parser, name: []const u8, tag: Option.Tag) !void {
    try switch (tag) {
        .boolean => self.addBoolOption(name),
        .float => self.addFloatOption(name),
        .int => self.addIntOption(name),
        .string => self.addStringOption(name),
        .string_slice => self.addStringSliceOption(name),
    };
}

// Internal helpers //

fn addBoolOption(self: *Parser, name: []const u8) !void {
    try self.options.put(name, .{ .tag = .boolean });
}

fn addIntOption(self: *Parser, name: []const u8) !void {
    try self.options.put(name, .{ .tag = .int });
}

fn addFloatOption(self: *Parser, name: []const u8) !void {
    try self.options.put(name, .{ .tag = .float });
}

fn addStringOption(self: *Parser, name: []const u8) !void {
    try self.options.put(name, .{ .tag = .string });
}

fn addStringSliceOption(self: *Parser, name: []const u8) !void {
    try self.options.put(name, .{ .tag = .string_slice });
}

pub fn parse(self: *Parser) !ParseResult {
    if (self.parsed) return error.AlreadyParsed;
    self.parsed = true;
    var parse_result = ParseResult.init(self.gpa);

    while (!self.isEnd()) {
        self.start = self.current;
        const c = self.advance();

        if (c == ' ') continue;

        const key = switch (c) {
            '-' => self.parseOption(),
            else => break,
        };
        const parse_attempt = self.options.getPtr(key);
        if (parse_attempt) |option| {
            option.count += 1;
            // Results that store a value need a space then their value
            if (option.tag != .boolean) {
                if (self.isEnd() or self.buffer[self.current] != ' ') return error.MissingValue;
                // The current position needs skipped over
                _ = self.advance();
            }
            self.start = self.current;
            const value = try self.parsePayload(option.tag);
            try parse_result.results.put(key, .{ .value = value, .count = option.count });
        } else {
            try self.unknown_options.append(self.gpa, key);
        }
    }

    return parse_result;
}

fn advance(self: *Parser) u8 {
    if (self.isEnd()) return 0;
    const c: u8 = self.buffer[self.current];
    self.current += 1;
    return c;
}

fn parseOption(self: *Parser) []const u8 {
    while (!self.isEnd() and !self.checkBuffer(' ')) {
        _ = self.advance();
    }
    const prefix_len: usize = if (self.start + 1 < self.buffer.len and self.buffer[self.start + 1] == '-') 2 else 1;
    return self.buffer[self.start + prefix_len .. self.current];
}

fn parsePayload(self: *Parser, tag: Option.Tag) !ParseResult.Result.Value {
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

fn parseInt(self: *Parser) !i32 {
    return std.fmt.parseInt(i32, self.nextToken(), 10);
}

fn parseFloat(self: *Parser) !f32 {
    return std.fmt.parseFloat(f32, self.nextToken());
}

fn parseStringSlice(self: *Parser) ![][]const u8 {
    var list: std.ArrayList([]const u8) = .empty;
    errdefer list.deinit(self.gpa);

    while (!self.isEnd() and !self.checkBuffer('-')) {
        self.start = self.current;
        const token = self.nextToken();
        if (token.len > 0) try list.append(self.gpa, token);
        if (!self.isEnd()) _ = self.advance();
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

pub fn dumpUnknown(self: *const Parser) void {
    for (self.unknown_options.items) |result| {
        std.debug.print("Unknown opt: {s}\n", .{result});
    }
}

pub fn dumpOptions(self: *const Parser) void {
    var iter = self.options.iterator();
    while (iter.next()) |opt| {
        std.debug.print("Key: {s} || Value: {}\n", .{ opt.key_ptr.*, opt.value_ptr.* });
    }
}
