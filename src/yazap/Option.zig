const std = @import("std");

tag: Tag,
state: State = .not_seen,
count: u32 = 0,

pub const Tag = enum {
    bool,
    string,
    int,
    float,
};

pub const State = enum {
    not_seen,
    seen,
};
