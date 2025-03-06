const std = @import("std");
const parser = @import("redis_parser.zig");
const types = @import("./types.zig");
const RedisValue = types.RedisValue;
const RedisValueType = types.RedisValueType;

pub const RedisSerializerError = error{
    OutOfMemory,
    InvalidData,
    NoSpaceLeft,
};

/// Redis Serializer
pub const RedisSerializer = struct {
    allocator: std.mem.Allocator,
    buffer: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator) RedisSerializer {
        return RedisSerializer{
            .allocator = allocator,
            .buffer = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *RedisSerializer) void {
        self.buffer.deinit();
    }

    pub fn reset(self: *RedisSerializer) void {
        self.buffer.clearRetainingCapacity();
    }

    /// Serialize a Redis value to the buffer
    pub fn serialize(self: *RedisSerializer, value: RedisValue) RedisSerializerError![]const u8 {
        self.reset();
        try self.serializeValue(value);
        return self.buffer.items;
    }

    /// Serialize multiple Redis values to the buffer
    pub fn serializeMultiple(self: *RedisSerializer, values: []const RedisValue) RedisSerializerError![]const u8 {
        self.reset();

        for (values) |value| {
            try self.serializeValue(value);
        }

        return self.buffer.items;
    }

    fn serializeValue(self: *RedisSerializer, value: RedisValue) RedisSerializerError!void {
        switch (value) {
            .SimpleString => |str| try self.serializeSimpleString(str),
            .Error => |str| try self.serializeError(str),
            .Integer => |num| try self.serializeInteger(num),
            .BulkString => |maybe_str| try self.serializeBulkString(maybe_str),
            .Array => |maybe_array| try self.serializeArray(maybe_array),
            .Null => try self.serializeNull(),
        }
    }

    fn serializeSimpleString(self: *RedisSerializer, str: []const u8) RedisSerializerError!void {
        try self.buffer.append('+');
        try self.buffer.appendSlice(str);
        try self.appendCRLF();
    }

    fn serializeError(self: *RedisSerializer, str: []const u8) RedisSerializerError!void {
        try self.buffer.append('-');
        try self.buffer.appendSlice(str);
        try self.appendCRLF();
    }

    fn serializeInteger(self: *RedisSerializer, num: i64) RedisSerializerError!void {
        try self.buffer.append(':');
        try self.appendFormatted("{d}", .{num});
        try self.appendCRLF();
    }

    fn serializeBulkString(self: *RedisSerializer, maybe_str: ?[]const u8) RedisSerializerError!void {
        try self.buffer.append('$');

        if (maybe_str) |str| {
            try self.appendFormatted("{d}", .{str.len});
            try self.appendCRLF();
            try self.buffer.appendSlice(str);
            try self.appendCRLF();
        } else {
            try self.buffer.appendSlice("-1");
            try self.appendCRLF();
        }
    }

    fn serializeArray(self: *RedisSerializer, maybe_array: ?std.ArrayList(RedisValue)) RedisSerializerError!void {
        try self.buffer.append('*');

        if (maybe_array) |array| {
            try self.appendFormatted("{d}", .{array.items.len});
            try self.appendCRLF();

            for (array.items) |item| {
                try self.serializeValue(item);
            }
        } else {
            try self.buffer.appendSlice("-1");
            try self.appendCRLF();
        }
    }

    fn serializeNull(self: *RedisSerializer) RedisSerializerError!void {
        try self.buffer.appendSlice("$-1");
        try self.appendCRLF();
    }

    fn appendCRLF(self: *RedisSerializer) RedisSerializerError!void {
        try self.buffer.appendSlice("\r\n");
    }

    fn appendFormatted(self: *RedisSerializer, comptime format: []const u8, args: anytype) RedisSerializerError!void {
        // Форматирование с использованием временного буфера
        var temp_buf: [128]u8 = undefined; // Увеличиваем размер буфера для безопасности
        const formatted = try std.fmt.bufPrint(&temp_buf, format, args);
        try self.buffer.appendSlice(formatted);
    }

    /// Create a new Redis value from a string
    pub fn createSimpleString(allocator: std.mem.Allocator, str: []const u8) RedisSerializerError!RedisValue {
        const str_copy = try allocator.dupe(u8, str);
        errdefer allocator.free(str_copy);

        return RedisValue{ .SimpleString = str_copy };
    }

    /// Create a new Redis error value from a string
    pub fn createError(allocator: std.mem.Allocator, str: []const u8) RedisSerializerError!RedisValue {
        const str_copy = try allocator.dupe(u8, str);
        errdefer allocator.free(str_copy);

        return RedisValue{ .Error = str_copy };
    }

    /// Create a new Redis integer value
    pub fn createInteger(num: i64) RedisValue {
        return RedisValue{ .Integer = num };
    }

    /// Create a new Redis bulk string value
    pub fn createBulkString(allocator: std.mem.Allocator, maybe_str: ?[]const u8) RedisSerializerError!RedisValue {
        if (maybe_str) |str| {
            const str_copy = try allocator.dupe(u8, str);
            errdefer allocator.free(str_copy);

            return RedisValue{ .BulkString = str_copy };
        } else {
            return RedisValue{ .BulkString = null };
        }
    }

    /// Create a new Redis array value
    pub fn createArray(allocator: std.mem.Allocator, items: []const RedisValue) RedisSerializerError!RedisValue {
        if (items.len == 0) {
            const array = std.ArrayList(RedisValue).init(allocator);
            return RedisValue{ .Array = array };
        }

        var array = std.ArrayList(RedisValue).init(allocator);
        errdefer array.deinit();

        for (items) |item| {
            var copy: RedisValue = undefined;

            switch (item) {
                .SimpleString => |str| {
                    copy = try createSimpleString(allocator, str);
                },
                .Error => |str| {
                    copy = try createError(allocator, str);
                },
                .Integer => |num| {
                    copy = createInteger(num);
                },
                .BulkString => |maybe_str| {
                    copy = try createBulkString(allocator, maybe_str);
                },
                .Array => |maybe_array| {
                    if (maybe_array) |arr| {
                        // Создаем копию вложенного массива
                        var inner_array = std.ArrayList(RedisValue).init(allocator);
                        errdefer inner_array.deinit();

                        for (arr.items) |inner_item| {
                            var inner_copy: RedisValue = undefined;

                            switch (inner_item) {
                                .SimpleString => |str| {
                                    inner_copy = try createSimpleString(allocator, str);
                                },
                                .Error => |str| {
                                    inner_copy = try createError(allocator, str);
                                },
                                .Integer => |num| {
                                    inner_copy = createInteger(num);
                                },
                                .BulkString => |maybe_inner_str| {
                                    inner_copy = try createBulkString(allocator, maybe_inner_str);
                                },
                                .Array => |_| {
                                    // Для вложенных массивов 2-го уровня просто создаем пустой массив для простоты
                                    inner_copy = RedisValue{ .Array = std.ArrayList(RedisValue).init(allocator) };
                                },
                                .Null => {
                                    inner_copy = RedisValue{ .Null = {} };
                                },
                            }

                            try inner_array.append(inner_copy);
                        }

                        copy = RedisValue{ .Array = inner_array };
                    } else {
                        copy = RedisValue{ .Array = null };
                    }
                },
                .Null => {
                    copy = RedisValue{ .Null = {} };
                },
            }

            try array.append(copy);
        }

        return RedisValue{ .Array = array };
    }

    /// Create a new Redis null value
    pub fn createNull() RedisValue {
        return RedisValue{ .Null = {} };
    }
};

/// Create a new Redis serializer
pub fn createRedisSerializer(allocator: std.mem.Allocator) RedisSerializer {
    return RedisSerializer.init(allocator);
}
