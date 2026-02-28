const std = @import("std");
const ArgIterator = std.process.ArgIterator;
const Allocator = std.mem.Allocator;
const ParseResult = @import("ParseResult.zig");
const Option = @import("Option.zig");
const Parser = @This();
const OptionsMap = std.StringHashMap(Option);
const startsWith = std.mem.startsWith;
const ParseError = error{UnknownType};

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

pub fn addOption(self: *Parser, name: []const u8, comptime T: type) !void {
    switch (@typeInfo(T)) {
        .Int => try self.addIntOption(name),
        .Float => try self.addFloatOption(name),
        .Slice => try self.addStringOption(name),
        .Bool => try self.addBoolOption(name),
        else => return error.UnknownType,
    }
}

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

pub fn parse(self: *Parser) !ParseResult {
    if (self.parsed) return error.AlreadyParsed;
    self.parsed = true;
    var parse_result = ParseResult.init(self.gpa);
    // Need to jump past the name of the program first
    _ = self.args.next();
    while (self.args.next()) |arg| {
        const key = if (startsWith(u8, arg, "--")) arg[2..] else if (startsWith(u8, arg, "-")) arg[1..] else arg;
        const parse_attempt: ?*Option = self.options.getPtr(key);
        if (parse_attempt) |option| {
            option.state = .seen;
            option.count += 1;
            const result: ParseResult.Result = switch (option.tag) {
                .boolean => .{ .boolean = true },
                .int => .{ .int = try self.parseInt() },
                .float => .{ .float = try self.parseFloat() },
                .string => .{ .string = try self.parseString() },
            };
            try parse_result.results.put(key, result);
        } else {
            try self.unknown_options.append(self.gpa, arg);
        }
    }

    return parse_result;
}

fn parseString(self: *Parser) ![]const u8 {
    return self.args.next() orelse return error.TypeMismatch;
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
