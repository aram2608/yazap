const std = @import("std");
const ResultMap = std.StringHashMap(Result);
const Allocator = std.mem.Allocator;
const ParseResult = @This();
const ResultError = error{ NotFound, TypeMismatch };

results: ResultMap,

pub fn init(gpa: Allocator) ParseResult {
    return .{
        .results = ResultMap.init(gpa),
    };
}

pub fn deinit(self: *ParseResult) void {
    self.results.deinit();
}

/// Helper method to dump the `Results`.
/// Primarily used for debugging.
pub fn dumpResults(self: *const ParseResult) void {
    var iter = self.results.iterator();
    while (iter.next()) |pair| {
        const name = pair.key_ptr.*;
        const result = pair.value_ptr.*;
        std.debug.print("Opt: {s} || Value: {} || Count: {}\n", .{ name, result.value, result.count });
    }
}

/// Helper method to return an expected boolean `Result`.
pub fn expectBool(self: *ParseResult, opt: []const u8) ResultError!bool {
    const exists = self.results.get(opt);
    if (exists) |result| {
        switch (result.value) {
            .boolean => return result.value.boolean,
            else => return error.TypeMismatch,
        }
    } else {
        return error.NotFound;
    }
}

/// Helper method to return an expected int `Result`.
pub fn expectInt(self: *ParseResult, opt: []const u8) ResultError!i32 {
    const exists = self.results.get(opt);
    if (exists) |result| {
        switch (result.value) {
            .int => return result.value.int,
            else => return error.TypeMismatch,
        }
    } else {
        return error.NotFound;
    }
}

pub fn expectFloat(self: *ParseResult, opt: []const u8) ResultError!f32 {
    const exists = self.results.get(opt);
    if (exists) |result| {
        switch (result.value) {
            .float => return result.value.float,
            else => return error.TypeMismatch,
        }
    } else {
        return error.NotFound;
    }
}

pub fn expectString(self: *ParseResult, opt: []const u8) ResultError![]const u8 {
    const exists = self.results.get(opt);
    if (exists) |result| {
        switch (result.value) {
            .string => return result.value.string,
            else => return error.TypeMismatch,
        }
    } else {
        return error.NotFound;
    }
}

pub fn getBool(self: *const ParseResult, opt: []const u8) ?bool {
    const result = self.results.get(opt) orelse return null;
    return switch (result.value) {
        .boolean => |v| v,
        else => null,
    };
}

pub fn getInt(self: *const ParseResult, opt: []const u8) ?i32 {
    const result = self.results.get(opt) orelse return null;
    return switch (result.value) {
        .int => |v| v,
        else => null,
    };
}

pub fn getFloat(self: *const ParseResult, opt: []const u8) ?f32 {
    const result = self.results.get(opt) orelse return null;
    return switch (result.value) {
        .float => |v| v,
        else => null,
    };
}

pub fn getString(self: *const ParseResult, opt: []const u8) ?[]const u8 {
    const result = self.results.get(opt) orelse return null;
    return switch (result.value) {
        .string => |v| v,
        else => null,
    };
}

pub fn isPresent(self: *const ParseResult, opt: []const u8) bool {
    const result = self.results.get(opt) orelse return false;
    return result.count > 0;
}

pub fn getCount(self: *const ParseResult, opt: []const u8) u32 {
    const result = self.results.get(opt) orelse return 0;
    return result.count;
}

pub const Result = struct {
    value: Value,
    count: u32,

    pub const Value = union(enum) {
        boolean: bool,
        int: i32,
        float: f32,
        string: []const u8,
        // string_slice: [][]const u8,
    };
};
