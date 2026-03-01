const std = @import("std");

tag: Tag,
state: State = .not_seen,
count: u32 = 0,
delim: []const u8 = " ",

pub const Tag = enum {
    boolean,
    string,
    int,
    float,
    // string_slice,
};

pub const State = enum {
    not_seen,
    seen,
};
