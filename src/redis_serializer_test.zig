const std = @import("std");
const testing = std.testing;
const parser = @import("redis_parser.zig");
const serializer = @import("redis_serializer.zig");
const types = @import("types.zig");

const RedisValue = types.RedisValue;

test "serialize simple string" {
    const allocator = testing.allocator;
    var redis_serializer = serializer.createRedisSerializer(allocator);
    defer redis_serializer.deinit();

    const value = try serializer.RedisSerializer.createSimpleString(allocator, "OK");
    defer value.deinit(allocator);

    const result = try redis_serializer.serialize(value);
    try testing.expectEqualStrings("+OK\r\n", result);
}

test "serialize error" {
    const allocator = testing.allocator;
    var redis_serializer = serializer.createRedisSerializer(allocator);
    defer redis_serializer.deinit();

    const value = try serializer.RedisSerializer.createError(allocator, "Error message");
    defer value.deinit(allocator);

    const result = try redis_serializer.serialize(value);
    try testing.expectEqualStrings("-Error message\r\n", result);
}

test "serialize integer" {
    const allocator = testing.allocator;
    var redis_serializer = serializer.createRedisSerializer(allocator);
    defer redis_serializer.deinit();

    const value = serializer.RedisSerializer.createInteger(1000);
    defer value.deinit(allocator);

    const result = try redis_serializer.serialize(value);
    try testing.expectEqualStrings(":1000\r\n", result);
}

test "serialize bulk string" {
    const allocator = testing.allocator;
    var redis_serializer = serializer.createRedisSerializer(allocator);
    defer redis_serializer.deinit();

    const value = try serializer.RedisSerializer.createBulkString(allocator, "foobar");
    defer value.deinit(allocator);

    const result = try redis_serializer.serialize(value);
    try testing.expectEqualStrings("$6\r\nfoobar\r\n", result);
}

test "serialize null bulk string" {
    const allocator = testing.allocator;
    var redis_serializer = serializer.createRedisSerializer(allocator);
    defer redis_serializer.deinit();

    const value = try serializer.RedisSerializer.createBulkString(allocator, null);
    defer value.deinit(allocator);

    const result = try redis_serializer.serialize(value);
    try testing.expectEqualStrings("$-1\r\n", result);
}

test "serialize array" {
    const allocator = testing.allocator;
    var redis_serializer = serializer.createRedisSerializer(allocator);
    defer redis_serializer.deinit();

    var item1 = try serializer.RedisSerializer.createBulkString(allocator, "foo");
    defer item1.deinit(allocator);

    var item2 = try serializer.RedisSerializer.createBulkString(allocator, "bar");
    defer item2.deinit(allocator);

    var items = [_]RedisValue{ item1, item2 };

    const value = try serializer.RedisSerializer.createArray(allocator, &items);
    defer value.deinit(allocator);

    const result = try redis_serializer.serialize(value);
    try testing.expectEqualStrings("*2\r\n$3\r\nfoo\r\n$3\r\nbar\r\n", result);
}

test "serialize null array" {
    const allocator = testing.allocator;
    var redis_serializer = serializer.createRedisSerializer(allocator);
    defer redis_serializer.deinit();

    const value = RedisValue{ .Array = null };
    defer value.deinit(allocator);

    const result = try redis_serializer.serialize(value);
    try testing.expectEqualStrings("*-1\r\n", result);
}

test "serialize nested array" {
    const allocator = testing.allocator;
    var redis_serializer = serializer.createRedisSerializer(allocator);
    defer redis_serializer.deinit();

    var nested_item1 = try serializer.RedisSerializer.createSimpleString(allocator, "Hello");
    defer nested_item1.deinit(allocator);

    var nested_item2 = try serializer.RedisSerializer.createSimpleString(allocator, "World");
    defer nested_item2.deinit(allocator);

    var nested_items = [_]RedisValue{ nested_item1, nested_item2 };

    var nested_array = try serializer.RedisSerializer.createArray(allocator, &nested_items);
    defer nested_array.deinit(allocator);

    var item2 = try serializer.RedisSerializer.createBulkString(allocator, "redis");
    defer item2.deinit(allocator);

    var items = [_]RedisValue{ nested_array, item2 };

    const value = try serializer.RedisSerializer.createArray(allocator, &items);
    defer value.deinit(allocator);

    const result = try redis_serializer.serialize(value);
    try testing.expectEqualStrings("*2\r\n*2\r\n+Hello\r\n+World\r\n$5\r\nredis\r\n", result);
}

test "serialize multiple values" {
    const allocator = testing.allocator;
    var redis_serializer = serializer.createRedisSerializer(allocator);
    defer redis_serializer.deinit();

    var value1 = try serializer.RedisSerializer.createSimpleString(allocator, "OK");
    defer value1.deinit(allocator);

    var value2 = serializer.RedisSerializer.createInteger(1000);
    defer value2.deinit(allocator);

    var values = [_]RedisValue{ value1, value2 };

    const result = try redis_serializer.serializeMultiple(&values);
    try testing.expectEqualStrings("+OK\r\n:1000\r\n", result);
}

test "roundtrip serialization and parsing" {
    const allocator = testing.allocator;
    var redis_serializer = serializer.createRedisSerializer(allocator);
    defer redis_serializer.deinit();

    var redis_parser = parser.createRedisParser(allocator);
    defer redis_parser.deinit();

    var nested_item1 = try serializer.RedisSerializer.createSimpleString(allocator, "Hello");
    defer nested_item1.deinit(allocator);

    var nested_item2 = try serializer.RedisSerializer.createSimpleString(allocator, "World");
    defer nested_item2.deinit(allocator);

    var nested_items = [_]RedisValue{ nested_item1, nested_item2 };

    var nested_array = try serializer.RedisSerializer.createArray(allocator, &nested_items);
    defer nested_array.deinit(allocator);

    var item2 = try serializer.RedisSerializer.createBulkString(allocator, "redis");
    defer item2.deinit(allocator);

    var items = [_]RedisValue{ nested_array, item2 };

    const original_value = try serializer.RedisSerializer.createArray(allocator, &items);
    defer original_value.deinit(allocator);

    const serialized = try redis_serializer.serialize(original_value);

    try redis_parser.feed(serialized);
    const parsed_value = try redis_parser.parse();
    defer if (parsed_value) |value| value.deinit(allocator);

    try testing.expect(parsed_value != null);

    const reserialized = try redis_serializer.serialize(parsed_value.?);

    try testing.expectEqualStrings(serialized, reserialized);
}

test "binary data in bulk string" {
    const allocator = testing.allocator;
    var redis_serializer = serializer.createRedisSerializer(allocator);
    defer redis_serializer.deinit();

    const binary_data = [_]u8{ 0, 1, 2, 3, 0xFF, 0x7F, 0, 'a' };

    const value = try serializer.RedisSerializer.createBulkString(allocator, &binary_data);
    defer value.deinit(allocator);

    const result = try redis_serializer.serialize(value);

    try testing.expectEqualStrings("$8\r\n\x00\x01\x02\x03\xFF\x7F\x00a\r\n", result);

    var redis_parser = parser.createRedisParser(allocator);
    defer redis_parser.deinit();

    try redis_parser.feed(result);
    const parsed_value = try redis_parser.parse();
    defer if (parsed_value) |p| p.deinit(allocator);

    try testing.expect(parsed_value != null);
    try testing.expect(parsed_value.? == .BulkString);
    try testing.expect(parsed_value.?.BulkString != null);
    try testing.expectEqualSlices(u8, &binary_data, parsed_value.?.BulkString.?);
}

test "memory leak in BulkString deinit" {
    const allocator = testing.allocator;

    for (0..1000) |i| {
        var buf: [64]u8 = undefined;
        const str = try std.fmt.bufPrint(&buf, "Test string #{d} for memory leak detection", .{i});

        const value = try serializer.RedisSerializer.createBulkString(allocator, str);

        value.deinit(allocator);
    }
}

test "memory leak in nested Array with BulkString" {
    const allocator = testing.allocator;

    for (0..100) |_| {
        var strings = std.ArrayList(RedisValue).init(allocator);
        defer strings.deinit();

        for (0..10) |j| {
            var buf: [64]u8 = undefined;
            const str = try std.fmt.bufPrint(&buf, "Nested string #{d}", .{j});
            const str_value = try serializer.RedisSerializer.createBulkString(allocator, str);
            try strings.append(str_value);
        }

        const array = try serializer.RedisSerializer.createArray(allocator, strings.items);

        for (strings.items) |item| {
            item.deinit(allocator);
        }

        array.deinit(allocator);
    }
}

test "BulkString create-parse-deinit cycle" {
    const allocator = testing.allocator;

    {
        const original_str = "Test string for parsing cycle";
        const value = try serializer.RedisSerializer.createBulkString(allocator, original_str);

        var redis_serializer = serializer.createRedisSerializer(allocator);
        defer redis_serializer.deinit();

        const serialized = try redis_serializer.serialize(value);

        value.deinit(allocator);

        var redis_parser = parser.createRedisParser(allocator);
        defer redis_parser.deinit();

        try redis_parser.feed(serialized);
        const parsed_value = (try redis_parser.parse()) orelse unreachable;

        parsed_value.deinit(allocator);
    }
}
