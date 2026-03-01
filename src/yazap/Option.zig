const std = @import("std");

tag: Tag,
count: u32 = 0,

pub const Tag = enum {
    boolean,
    string,
    int,
    float,
    string_slice,
};
