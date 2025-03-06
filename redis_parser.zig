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

/// Redis Parser Error types
pub const RedisParserError = error{
    InvalidProtocol,
    InvalidLength,
    BufferTooSmall,
    OutOfMemory,
    InvalidPrefix,
    Incomplete,
    Overflow,
    InvalidCharacter,
};

/// Simple Redis Protocol Parser
pub const RedisParser = struct {
    allocator: std.mem.Allocator,
    buffer: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator) RedisParser {
        return RedisParser{
            .allocator = allocator,
            .buffer = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *RedisParser) void {
        self.buffer.deinit();
    }

    pub fn feed(self: *RedisParser, data: []const u8) !void {
        try self.buffer.appendSlice(data);
    }

    pub fn reset(self: *RedisParser) void {
        self.buffer.clearRetainingCapacity();
    }

    /// Parse a Redis value from the buffer
    pub fn parse(self: *RedisParser) RedisParserError!?RedisValue {
        if (self.buffer.items.len == 0) {
            return null;
        }

        const data = self.buffer.items;

        var index: usize = 0;
        const result = try self.parseValue(data, &index);

        // Remove the parsed data from the buffer
        if (index > 0) {
            try self.buffer.replaceRange(0, index, &.{});
        }

        return result;
    }

    fn parseValue(self: *RedisParser, data: []const u8, index: *usize) RedisParserError!RedisValue {
        if (index.* >= data.len) {
            return RedisParserError.Incomplete;
        }

        const type_char = data[index.*];
        index.* += 1; // Move past the type character

        switch (type_char) {
            '+' => return self.parseSimpleString(data, index),
            '-' => return self.parseError(data, index),
            ':' => return self.parseInteger(data, index),
            '$' => return self.parseBulkString(data, index),
            '*' => return self.parseArray(data, index),
            else => return RedisParserError.InvalidPrefix,
        }
    }

    fn readLine(data: []const u8, index: *usize) RedisParserError![]const u8 {
        const start = index.*;
        var i = start;

        // Find the end of the line (CR LF)
        while (i + 1 < data.len) {
            if (data[i] == '\r' and data[i + 1] == '\n') {
                const line = data[start..i];
                index.* = i + 2; // Skip CR LF
                return line;
            }
            i += 1;
        }

        return RedisParserError.Incomplete;
    }

    fn parseSimpleString(self: *RedisParser, data: []const u8, index: *usize) RedisParserError!RedisValue {
        const line = try readLine(data, index);

        const str = try self.allocator.dupe(u8, line);
        errdefer self.allocator.free(str);

        return RedisValue{ .SimpleString = str };
    }

    fn parseError(self: *RedisParser, data: []const u8, index: *usize) RedisParserError!RedisValue {
        const line = try readLine(data, index);

        const str = try self.allocator.dupe(u8, line);
        errdefer self.allocator.free(str);

        return RedisValue{ .Error = str };
    }

    fn parseInteger(self: *RedisParser, data: []const u8, index: *usize) RedisParserError!RedisValue {
        _ = self;
        const line = try readLine(data, index);

        const num = try std.fmt.parseInt(i64, line, 10);

        return RedisValue{ .Integer = num };
    }

    fn parseBulkString(self: *RedisParser, data: []const u8, index: *usize) RedisParserError!RedisValue {
        const len_line = try readLine(data, index);

        const len = try std.fmt.parseInt(isize, len_line, 10);

        if (len == -1) {
            return RedisValue{ .BulkString = null };
        }

        if (len < 0) {
            return RedisParserError.InvalidLength;
        }

        // Check if we have enough data
        if (index.* + @as(usize, @intCast(len)) + 2 > data.len) {
            return RedisParserError.Incomplete;
        }

        const str_start = index.*;
        const str_end = str_start + @as(usize, @intCast(len));
        const str_slice = data[str_start..str_end];

        // Check for CRLF at the end of the string
        if (data[str_end] != '\r' or data[str_end + 1] != '\n') {
            return RedisParserError.InvalidProtocol;
        }

        // Move index past the string and CRLF
        index.* = str_end + 2;

        // Create a copy of the string
        const str = try self.allocator.dupe(u8, str_slice);
        errdefer self.allocator.free(str);

        return RedisValue{ .BulkString = str };
    }

    fn parseArray(self: *RedisParser, data: []const u8, index: *usize) RedisParserError!RedisValue {
        const len_line = try readLine(data, index);

        const len = try std.fmt.parseInt(isize, len_line, 10);

        if (len == -1) {
            return RedisValue{ .Array = null };
        }

        if (len < 0) {
            return RedisParserError.InvalidLength;
        }

        var array = std.ArrayList(RedisValue).init(self.allocator);
        errdefer {
            for (array.items) |item| {
                item.deinit(self.allocator);
            }
            array.deinit();
        }

        var i: usize = 0;
        while (i < len) : (i += 1) {
            // Parse the next element in the array
            const element = try self.parseValue(data, index);
            try array.append(element);
        }

        return RedisValue{ .Array = array };
    }
};

/// Helper function to create a new RedisParser
pub fn createRedisParser(allocator: std.mem.Allocator) RedisParser {
    return RedisParser.init(allocator);
}
