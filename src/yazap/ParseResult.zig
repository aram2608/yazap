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
        std.debug.print("Opt: {s} || Value: {}\n", .{ name, result });
    }
}

/// Helper method to return a an expected boolean `Result`.
pub fn expectBool(self: *ParseResult, opt: []const u8) ResultError!bool {
    const exists = self.results.get(opt);
    if (exists) |result| {
        switch (result) {
            .boolean => return result.boolean,
            else => return error.TypeMismatch,
        }
    } else {
        return error.NotFound;
    }
}

pub fn expectInt(self: *ParseResult, opt: []const u8) ResultError!i32 {
    const exists = self.results.get(opt);

    if (exists) |result| {
        switch (result) {
            .int => return result.int,
            else => return error.TypeMismatch,
        }
    } else {
        return error.NotFound;
    }
}

pub fn expectFloat(self: *ParseResult, opt: []const u8) ResultError!f32 {
    const exists = self.results.get(opt);

    if (exists) |result| {
        switch (result) {
            .float => return result.float,
            else => return error.TypeMismatch,
        }
    } else {
        return error.NotFound;
    }
}

pub fn expectString(self: *ParseResult, opt: []const u8) ResultError![]const u8 {
    const exists = self.results.get(opt);
    if (exists) |result| {
        switch (result) {
            .string => return result.string,
            else => return error.TypeMismatch,
        }
    } else {
        return error.NotFound;
    }
}

pub const Result = union(enum) {
    boolean: bool,
    int: i32,
    float: f32,
    string: []const u8,
};
