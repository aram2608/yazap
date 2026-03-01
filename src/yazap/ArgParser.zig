const std = @import("std");
const ArgIterator = std.process.ArgIterator;
const Allocator = std.mem.Allocator;
const ParseResult = @import("ParseResult.zig");
const Option = @import("Option.zig");
const Parser = @This();
const OptionsMap = std.StringHashMap(Option);
const startsWith = std.mem.startsWith;

gpa: Allocator,
args: ArgIterator,
options: OptionsMap,
unknown_options: std.ArrayList([]const u8) = .{},
parsed: bool = false,

pub fn init(gpa: Allocator, args: ArgIterator) Parser {
    return .{
        .gpa = gpa,
        .args = args,
        .options = OptionsMap.init(gpa),
    };
}

pub fn deinit(self: *Parser) void {
    self.args.deinit();
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

pub fn addBoolOption(self: *Parser, name: []const u8) !void {
    try self.options.put(name, .{ .tag = .boolean });
}

pub fn addIntOption(self: *Parser, name: []const u8) !void {
    try self.options.put(name, .{ .tag = .int });
}

pub fn addFloatOption(self: *Parser, name: []const u8) !void {
    try self.options.put(name, .{ .tag = .float });
}

pub fn addStringOption(self: *Parser, name: []const u8) !void {
    try self.options.put(name, .{ .tag = .string });
}

// pub fn addStringSliceOption(self: *Parser, name: []const u8, delim: []const u8) !void {
//     try self.options.put(name, .{ .tag = .string_slice, .delim = delim });
// }

pub fn parse(self: *Parser) !ParseResult {
    if (self.parsed) return error.AlreadyParsed;
    self.parsed = true;
    var parse_result = ParseResult.init(self.gpa);
    // Need to jump past the name of the program first
    _ = self.args.next();
    while (self.args.next()) |arg| {
        const key = if (isOption(arg)) arg[2..] else arg;
        const parse_attempt: ?*Option = self.options.getPtr(key);
        if (parse_attempt) |option| {
            option.state = .seen;
            option.count += 1;
            const value = try self.parsePayload(option);
            try parse_result.results.put(key, .{ .value = value, .count = option.count });
        } else {
            try self.unknown_options.append(self.gpa, arg);
        }
    }

    return parse_result;
}

fn parsePayload(self: *Parser, opt: *Option) !ParseResult.Result.Value {
    return switch (opt.tag) {
        .boolean => .{ .boolean = true },
        .int => .{ .int = try self.parseInt() },
        .float => .{ .float = try self.parseFloat() },
        .string => .{ .string = try self.parseString() },
        // .string_slice => .{ .string_slice = try self.parseStringSlice() },
    };
}

/// TODO: Add option trimming so that --foo and -f are equivalent.
fn isOption(arg: [:0]const u8) bool {
    return if (startsWith(u8, arg, "--")) true else false;
}

// fn parseStringSlice(self:* Parser) ![][]const u8 {

// }

fn parseString(self: *Parser) ![]const u8 {
    return self.args.next() orelse return error.MissingValue;
}

fn parseInt(self: *Parser) !i32 {
    const arg = self.args.next() orelse return error.MissingValue;
    return std.fmt.parseInt(i32, arg, 10);
}

fn parseFloat(self: *Parser) !f32 {
    const arg = self.args.next() orelse return error.MissingValue;
    return std.fmt.parseFloat(f32, arg);
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
