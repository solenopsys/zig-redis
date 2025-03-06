const std = @import("std");

/// Redis Value Types
pub const RedisValueType = enum {
    SimpleString,
    Error,
    Integer,
    BulkString,
    Array,
    Null,
};

/// Redis Value Union
pub const RedisValue = union(RedisValueType) {
    SimpleString: []const u8,
    Error: []const u8,
    Integer: i64,
    BulkString: ?[]const u8,
    Array: ?std.ArrayList(RedisValue),
    Null: void,

    pub fn deinit(self: RedisValue, allocator: std.mem.Allocator) void {
        switch (self) {
            .SimpleString => |str| allocator.free(str),
            .Error => |str| allocator.free(str),
            .Integer => {}, // целочисленные значения не требуют освобождения памяти
            .BulkString => |maybe_str| if (maybe_str) |str| allocator.free(str),
            .Array => |array| {
                if (array) |arr| {
                    for (arr.items) |item| {
                        item.deinit(allocator);
                    }
                    arr.deinit();
                }
            },
            .Null => {},
        }
    }
};
