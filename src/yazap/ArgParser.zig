const std = @import("std");
const ArgIterator = std.process.ArgIterator;
const Allocator = std.mem.Allocator;
const Option = @import("Option.zig");
const Parser = @This();
const OptionsMap = std.StringHashMap(Option);

gpa: Allocator,
args: ArgIterator,
options: OptionsMap,
unknown_options: std.ArrayList([]const u8) = .{},

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

pub fn addOption(self: *Parser, cmd: []const u8, opt: Option) !void {
    try self.options.put(cmd, opt);
}

pub fn parse(self: *Parser) !void {
    // Need to jump past the name of the program first
    _ = self.args.next();
    while (self.args.next()) |arg| {
        const parse_attempt: ?*Option = self.options.getPtr(arg);
        if (parse_attempt) |result| {
            result.state = .seen;
            result.count += 1;
        } else {
            try self.unknown_options.append(self.gpa, arg);
        }
    }
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
