const std = @import("std");
const testing = std.testing;
const parser = @import("./core/redis_parser.zig");

const types = @import("./core/types.zig");
const RedisValue = types.RedisValue;

test "parse simple string" {
    var redis_parser = parser.createRedisParser(testing.allocator);
    defer redis_parser.deinit();

    try redis_parser.feed("+OK\r\n");
    const result = try redis_parser.parse();
    defer if (result) |value| value.deinit(testing.allocator);

    try testing.expect(result != null);
    switch (result.?) {
        .SimpleString => |str| try testing.expectEqualStrings("OK", str),
        else => try testing.expect(false),
    }
}

test "array memory leak" {
    var redis_parser = parser.createRedisParser(testing.allocator);
    defer redis_parser.deinit();

    const array_data = "*3\r\n$3\r\nfoo\r\n$3\r\nbar\r\n$3\r\nbaz\r\n";

    for (0..10) |i| {
        redis_parser.reset();
        try redis_parser.feed(array_data);

        const result = try redis_parser.parse();

        defer if (result) |value| value.deinit(testing.allocator);

        if (i == 0) {
            try testing.expect(result != null);
            switch (result.?) {
                .Array => |maybe_array| {
                    try testing.expect(maybe_array != null);
                    try testing.expectEqual(@as(usize, 3), maybe_array.?.items.len);
                },
                else => try testing.expect(false),
            }
        }
    }
}

test "parseArray memory leak" {
    var redis_parser = parser.createRedisParser(testing.allocator);
    defer redis_parser.deinit();

    const nested_array = "*3\r\n$3\r\nkey\r\n*2\r\n$5\r\nfield\r\n$5\r\nvalue\r\n$4\r\ntest\r\n";

    for (0..5) |_| {
        redis_parser.reset();

        try redis_parser.feed(nested_array);

        const result = try redis_parser.parse();

        defer if (result) |value| value.deinit(testing.allocator);

        try testing.expect(result != null);

        switch (result.?) {
            .Array => |maybe_array| {
                try testing.expect(maybe_array != null);
                try testing.expectEqual(@as(usize, 3), maybe_array.?.items.len);
            },
            else => try testing.expect(false),
        }
    }
}

test "nested arrays memory leak" {
    var redis_parser = parser.createRedisParser(testing.allocator);
    defer redis_parser.deinit();

    const nested_array = "*2\r\n*2\r\n$3\r\nfoo\r\n$3\r\nbar\r\n*1\r\n$3\r\nbaz\r\n";

    for (0..3) |_| {
        redis_parser.reset();
        try redis_parser.feed(nested_array);

        const result = try redis_parser.parse();
        defer if (result) |value| value.deinit(testing.allocator);

        try testing.expect(result != null);

        switch (result.?) {
            .Array => |maybe_array| {
                try testing.expect(maybe_array != null);
                try testing.expectEqual(@as(usize, 2), maybe_array.?.items.len);

                switch (maybe_array.?.items[0]) {
                    .Array => |maybe_inner1| {
                        try testing.expect(maybe_inner1 != null);
                        try testing.expectEqual(@as(usize, 2), maybe_inner1.?.items.len);

                        switch (maybe_inner1.?.items[0]) {
                            .BulkString => |maybe_str| {
                                try testing.expect(maybe_str != null);
                                try testing.expectEqualStrings("foo", maybe_str.?);
                            },
                            else => try testing.expect(false),
                        }

                        switch (maybe_inner1.?.items[1]) {
                            .BulkString => |maybe_str| {
                                try testing.expect(maybe_str != null);
                                try testing.expectEqualStrings("bar", maybe_str.?);
                            },
                            else => try testing.expect(false),
                        }
                    },
                    else => try testing.expect(false),
                }

                switch (maybe_array.?.items[1]) {
                    .Array => |maybe_inner2| {
                        try testing.expect(maybe_inner2 != null);
                        try testing.expectEqual(@as(usize, 1), maybe_inner2.?.items.len);

                        switch (maybe_inner2.?.items[0]) {
                            .BulkString => |maybe_str| {
                                try testing.expect(maybe_str != null);
                                try testing.expectEqualStrings("baz", maybe_str.?);
                            },
                            else => try testing.expect(false),
                        }
                    },
                    else => try testing.expect(false),
                }
            },
            else => try testing.expect(false),
        }
    }
}

test "parse error" {
    var redis_parser = parser.createRedisParser(testing.allocator);
    defer redis_parser.deinit();

    try redis_parser.feed("-Error message\r\n");
    const result = try redis_parser.parse();
    defer if (result) |value| value.deinit(testing.allocator);

    try testing.expect(result != null);
    switch (result.?) {
        .Error => |msg| try testing.expectEqualStrings("Error message", msg),
        else => try testing.expect(false),
    }
}

test "parse integer" {
    var redis_parser = parser.createRedisParser(testing.allocator);
    defer redis_parser.deinit();

    try redis_parser.feed(":1000\r\n");
    const result = try redis_parser.parse();
    defer if (result) |value| value.deinit(testing.allocator);

    try testing.expect(result != null);
    switch (result.?) {
        .Integer => |num| try testing.expectEqual(@as(i64, 1000), num),
        else => try testing.expect(false),
    }
}

test "parse bulk string" {
    var redis_parser = parser.createRedisParser(testing.allocator);
    defer redis_parser.deinit();

    try redis_parser.feed("$6\r\nfoobar\r\n");
    const result = try redis_parser.parse();
    defer if (result) |value| value.deinit(testing.allocator);

    try testing.expect(result != null);
    switch (result.?) {
        .BulkString => |maybe_str| {
            try testing.expect(maybe_str != null);
            try testing.expectEqualStrings("foobar", maybe_str.?);
        },
        else => try testing.expect(false),
    }
}

test "parse null bulk string" {
    var redis_parser = parser.createRedisParser(testing.allocator);
    defer redis_parser.deinit();

    try redis_parser.feed("$-1\r\n");
    const result = try redis_parser.parse();
    defer if (result) |value| value.deinit(testing.allocator);

    try testing.expect(result != null);
    switch (result.?) {
        .BulkString => |maybe_str| try testing.expect(maybe_str == null),
        else => try testing.expect(false),
    }
}

test "parse array" {
    std.debug.print("\n\n=== TEST: parse array ===\n", .{});

    const allocator = testing.allocator;
    var redis_parser = parser.createRedisParser(allocator);
    defer redis_parser.deinit();

    const input = "*2\r\n$3\r\nfoo\r\n$3\r\nbar\r\n";
    std.debug.print("Input length: {}\n", .{input.len});

    std.debug.print("Input hex dump: ", .{});
    for (input) |c| {
        std.debug.print("{X:0>2} ", .{c});
    }
    std.debug.print("\n", .{});

    try redis_parser.feed(input);

    std.debug.print("Buffer length: {}\n", .{redis_parser.buffer.items.len});
    std.debug.print("Buffer hex dump: ", .{});
    for (redis_parser.buffer.items) |c| {
        std.debug.print("{X:0>2} ", .{c});
    }
    std.debug.print("\n", .{});

    const result = try redis_parser.parse();

    defer if (result) |value| value.deinit(allocator);

    try testing.expect(result != null);

    switch (result.?) {
        .Array => |maybe_array| {
            try testing.expect(maybe_array != null);
            const array = maybe_array.?;
            try testing.expectEqual(@as(usize, 2), array.items.len);

            switch (array.items[0]) {
                .BulkString => |maybe_str| {
                    try testing.expect(maybe_str != null);
                    try testing.expectEqualStrings("foo", maybe_str.?);
                },
                else => {
                    std.debug.print("Expected BulkString, got: {}\n", .{array.items[0]});
                    try testing.expect(false);
                },
            }

            switch (array.items[1]) {
                .BulkString => |maybe_str| {
                    try testing.expect(maybe_str != null);
                    try testing.expectEqualStrings("bar", maybe_str.?);
                },
                else => {
                    std.debug.print("Expected BulkString, got: {}\n", .{array.items[1]});
                    try testing.expect(false);
                },
            }
        },
        else => try testing.expect(false),
    }
}

test "parse null array" {
    var redis_parser = parser.createRedisParser(testing.allocator);
    defer redis_parser.deinit();

    try redis_parser.feed("*-1\r\n");
    const result = try redis_parser.parse();
    defer if (result) |value| value.deinit(testing.allocator);

    try testing.expect(result != null);
    switch (result.?) {
        .Array => |maybe_array| try testing.expect(maybe_array == null),
        else => try testing.expect(false),
    }
}

test "parse nested array" {
    const allocator = testing.allocator;
    var redis_parser = parser.createRedisParser(allocator);
    defer redis_parser.deinit();

    try redis_parser.feed("*2\r\n*2\r\n+Hello\r\n+World\r\n$5\r\nredis\r\n");

    const result = try redis_parser.parse();

    defer if (result) |value| value.deinit(allocator);

    try testing.expect(result != null);
    switch (result.?) {
        .Array => |maybe_array| {
            try testing.expect(maybe_array != null);
            const array = maybe_array.?;
            try testing.expectEqual(@as(usize, 2), array.items.len);

            switch (array.items[0]) {
                .Array => |nested_maybe_array| {
                    try testing.expect(nested_maybe_array != null);
                    const nested_array = nested_maybe_array.?;
                    try testing.expectEqual(@as(usize, 2), nested_array.items.len);

                    switch (nested_array.items[0]) {
                        .SimpleString => |str| try testing.expectEqualStrings("Hello", str),
                        else => {
                            std.debug.print("Expected SimpleString, got: {}\n", .{nested_array.items[0]});
                            try testing.expect(false);
                        },
                    }

                    switch (nested_array.items[1]) {
                        .SimpleString => |str| try testing.expectEqualStrings("World", str),
                        else => {
                            std.debug.print("Expected SimpleString, got: {}\n", .{nested_array.items[1]});
                            try testing.expect(false);
                        },
                    }
                },
                else => {
                    std.debug.print("Expected Array, got: {}\n", .{array.items[0]});
                    try testing.expect(false);
                },
            }

            switch (array.items[1]) {
                .BulkString => |maybe_str| {
                    try testing.expect(maybe_str != null);
                    try testing.expectEqualStrings("redis", maybe_str.?);
                },
                else => {
                    std.debug.print("Expected BulkString, got: {}\n", .{array.items[1]});
                    try testing.expect(false);
                },
            }
        },
        else => try testing.expect(false),
    }
}

test "parse multiple commands" {
    var redis_parser = parser.createRedisParser(testing.allocator);
    defer redis_parser.deinit();

    try redis_parser.feed("+OK\r\n:1000\r\n");

    const result1 = try redis_parser.parse();
    defer if (result1) |value| value.deinit(testing.allocator);

    try testing.expect(result1 != null);
    switch (result1.?) {
        .SimpleString => |str| try testing.expectEqualStrings("OK", str),
        else => try testing.expect(false),
    }

    const result2 = try redis_parser.parse();
    defer if (result2) |value| value.deinit(testing.allocator);

    try testing.expect(result2 != null);
    switch (result2.?) {
        .Integer => |num| try testing.expectEqual(@as(i64, 1000), num),
        else => try testing.expect(false),
    }
}

test "parse incomplete command" {
    var redis_parser = parser.createRedisParser(testing.allocator);
    defer redis_parser.deinit();

    try redis_parser.feed("+OK\r\n:100");

    const result1 = try redis_parser.parse();
    defer if (result1) |value| value.deinit(testing.allocator);

    try testing.expect(result1 != null);
    switch (result1.?) {
        .SimpleString => |str| try testing.expectEqualStrings("OK", str),
        else => try testing.expect(false),
    }

    try testing.expectError(parser.RedisParserError.Incomplete, redis_parser.parse());

    try redis_parser.feed("0\r\n");

    const result3 = try redis_parser.parse();
    defer if (result3) |value| value.deinit(testing.allocator);

    try testing.expect(result3 != null);
    switch (result3.?) {
        .Integer => |num| try testing.expectEqual(@as(i64, 1000), num),
        else => try testing.expect(false),
    }
}

test "parse invalid command" {
    var redis_parser = parser.createRedisParser(testing.allocator);
    defer redis_parser.deinit();

    try redis_parser.feed("X Invalid Command\r\n");

    const result = redis_parser.parse();
    try testing.expectError(parser.RedisParserError.InvalidPrefix, result);
}
