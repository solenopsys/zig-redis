const std = @import("std");
const testing = std.testing;
const parser = @import("core/redis_parser.zig");
const serializer = @import("core/redis_serializer.zig");
const convertors = @import("core/convertors.zig");
const types = @import("core/types.zig");

const RedisValue = types.RedisValue;
const RedisConversionUtils = convertors.RedisConversionUtils;

test "convert string to RedisValue" {
    const allocator = testing.allocator;

    // String slice
    const str_slice = "test string";
    const value1 = try RedisConversionUtils.toRedisValue(allocator, str_slice);
    defer value1.deinit(allocator);

    try testing.expect(value1 == .BulkString);
    try testing.expect(value1.BulkString != null);
    try testing.expectEqualStrings("test string", value1.BulkString.?);

    // String literal
    const value2 = try RedisConversionUtils.toRedisValue(allocator, "string literal");
    defer value2.deinit(allocator);

    try testing.expect(value2 == .BulkString);
    try testing.expect(value2.BulkString != null);
    try testing.expectEqualStrings("string literal", value2.BulkString.?);

    // Array of u8
    var char_array = [_]u8{ 'a', 'b', 'c' };
    const value3 = try RedisConversionUtils.toRedisValue(allocator, &char_array);
    defer value3.deinit(allocator);

    try testing.expect(value3 == .BulkString);
    try testing.expect(value3.BulkString != null);
    try testing.expectEqualStrings("abc", value3.BulkString.?);
}

test "convert integer to RedisValue" {
    const allocator = testing.allocator;

    // i64
    const value1 = try RedisConversionUtils.toRedisValue(allocator, @as(i64, 12345));
    defer value1.deinit(allocator);

    try testing.expect(value1 == .Integer);
    try testing.expectEqual(@as(i64, 12345), value1.Integer);

    // i32
    const value2 = try RedisConversionUtils.toRedisValue(allocator, @as(i32, -54321));
    defer value2.deinit(allocator);

    try testing.expect(value2 == .Integer);
    try testing.expectEqual(@as(i64, -54321), value2.Integer);

    // usize
    const value3 = try RedisConversionUtils.toRedisValue(allocator, @as(usize, 9999));
    defer value3.deinit(allocator);

    try testing.expect(value3 == .Integer);
    try testing.expectEqual(@as(i64, 9999), value3.Integer);

    // u8
    const value4 = try RedisConversionUtils.toRedisValue(allocator, @as(u8, 255));
    defer value4.deinit(allocator);

    try testing.expect(value4 == .Integer);
    try testing.expectEqual(@as(i64, 255), value4.Integer);
}

test "convert optional to RedisValue" {
    const allocator = testing.allocator;

    // Some value (string)
    const some_string: ?[]const u8 = "optional string";
    const value1 = try RedisConversionUtils.toRedisValue(allocator, some_string);
    defer value1.deinit(allocator);

    try testing.expect(value1 == .BulkString);
    try testing.expect(value1.BulkString != null);
    try testing.expectEqualStrings("optional string", value1.BulkString.?);

    // Some value (integer)
    const some_integer: ?i64 = 42;
    const value2 = try RedisConversionUtils.toRedisValue(allocator, some_integer);
    defer value2.deinit(allocator);

    try testing.expect(value2 == .Integer);
    try testing.expectEqual(@as(i64, 42), value2.Integer);

    // None value
    const none_value: ?[]const u8 = null;
    const value3 = try RedisConversionUtils.toRedisValue(allocator, none_value);
    defer value3.deinit(allocator);

    try testing.expect(value3 == .Null);
}

test "convert pointer to RedisValue" {
    const allocator = testing.allocator;

    // Integer pointer
    var num: i32 = 100;
    const value1 = try RedisConversionUtils.toRedisValue(allocator, &num);
    defer value1.deinit(allocator);

    try testing.expect(value1 == .Integer);
    try testing.expectEqual(@as(i64, 100), value1.Integer);
}

test "convert existing RedisValue" {
    const allocator = testing.allocator;

    var original = try serializer.RedisSerializer.createBulkString(allocator, "already a RedisValue");
    defer original.deinit(allocator);

    const value = try RedisConversionUtils.toRedisValue(allocator, original);
    // Not deinit-ing value because it's the same as original

    try testing.expect(value == .BulkString);
    try testing.expect(value.BulkString != null);
    try testing.expectEqualStrings("already a RedisValue", value.BulkString.?);
}

test "convert slice to RedisValues" {
    const allocator = testing.allocator;

    // String slice - создаем настоящий slice вместо фиксированного массива
    var strings_array = [_][]const u8{ "one", "two", "three" };
    const strings_slice: []const []const u8 = &strings_array;
    var result1 = try RedisConversionUtils.sliceToRedisValues(allocator, strings_slice);
    defer {
        for (result1.items) |item| {
            item.deinit(allocator);
        }
        result1.deinit();
    }

    try testing.expectEqual(@as(usize, 3), result1.items.len);
    try testing.expect(result1.items[0] == .BulkString);
    try testing.expectEqualStrings("one", result1.items[0].BulkString.?);
    try testing.expect(result1.items[1] == .BulkString);
    try testing.expectEqualStrings("two", result1.items[1].BulkString.?);
    try testing.expect(result1.items[2] == .BulkString);
    try testing.expectEqualStrings("three", result1.items[2].BulkString.?);

    // Integer slice
    var integers_array = [_]i64{ 1, 2, 3 };
    const integers_slice: []const i64 = &integers_array;
    var result2 = try RedisConversionUtils.sliceToRedisValues(allocator, integers_slice);
    defer {
        for (result2.items) |item| {
            item.deinit(allocator);
        }
        result2.deinit();
    }

    try testing.expectEqual(@as(usize, 3), result2.items.len);
    try testing.expect(result2.items[0] == .Integer);
    try testing.expectEqual(@as(i64, 1), result2.items[0].Integer);
    try testing.expect(result2.items[1] == .Integer);
    try testing.expectEqual(@as(i64, 2), result2.items[1].Integer);
    try testing.expect(result2.items[2] == .Integer);
    try testing.expectEqual(@as(i64, 3), result2.items[2].Integer);

    // Mixed slice using RedisValues directly
    var val1 = try serializer.RedisSerializer.createBulkString(allocator, "mixed");
    var val2 = serializer.RedisSerializer.createInteger(42);
    var redis_values_array = [_]RedisValue{ val1, val2 };
    const redis_values_slice: []const RedisValue = &redis_values_array;
    var result3 = try RedisConversionUtils.argsToRedisValues(allocator, redis_values_slice);

    // Cleanup without deinit-ing items because they're managed by val1 and val2
    result3.deinit();
    val1.deinit(allocator);
    val2.deinit(allocator);
}

test "convert tuple to RedisValues" {
    const allocator = testing.allocator;

    // Simple tuple - используем явные типы для числовых значений
    const tuple1 = .{ "command", @as(i64, 123), "arg" };
    var result1 = try RedisConversionUtils.tupleToRedisValues(allocator, tuple1);
    defer {
        for (result1.items) |item| {
            item.deinit(allocator);
        }
        result1.deinit();
    }

    try testing.expectEqual(@as(usize, 3), result1.items.len);
    try testing.expect(result1.items[0] == .BulkString);
    try testing.expectEqualStrings("command", result1.items[0].BulkString.?);
    try testing.expect(result1.items[1] == .Integer);
    try testing.expectEqual(@as(i64, 123), result1.items[1].Integer);
    try testing.expect(result1.items[2] == .BulkString);
    try testing.expectEqualStrings("arg", result1.items[2].BulkString.?);

    // Tuple with optional
    const tuple2 = .{ "key", @as(?[]const u8, null) };
    var result2 = try RedisConversionUtils.tupleToRedisValues(allocator, tuple2);
    defer {
        for (result2.items) |item| {
            item.deinit(allocator);
        }
        result2.deinit();
    }

    try testing.expectEqual(@as(usize, 2), result2.items.len);
    try testing.expect(result2.items[0] == .BulkString);
    try testing.expectEqualStrings("key", result2.items[0].BulkString.?);
    try testing.expect(result2.items[1] == .Null);
}

test "convert different args to RedisValues" {
    const allocator = testing.allocator;

    // Single string arg
    {
        var result = try RedisConversionUtils.argsToRedisValues(allocator, "GET");
        defer {
            for (result.items) |item| {
                item.deinit(allocator);
            }
            result.deinit();
        }

        try testing.expectEqual(@as(usize, 1), result.items.len);
        try testing.expect(result.items[0] == .BulkString);
        try testing.expectEqualStrings("GET", result.items[0].BulkString.?);
    }

    // Tuple args с явными типами
    {
        var result = try RedisConversionUtils.argsToRedisValues(allocator, .{ "SET", "key", "value" });
        defer {
            for (result.items) |item| {
                item.deinit(allocator);
            }
            result.deinit();
        }

        try testing.expectEqual(@as(usize, 3), result.items.len);
        try testing.expectEqualStrings("SET", result.items[0].BulkString.?);
        try testing.expectEqualStrings("key", result.items[1].BulkString.?);
        try testing.expectEqualStrings("value", result.items[2].BulkString.?);
    }

    // Slice args
    {
        var args_array = [_][]const u8{ "LPUSH", "list", "item1", "item2" };
        const args_slice: []const []const u8 = &args_array;
        var result = try RedisConversionUtils.argsToRedisValues(allocator, args_slice);
        defer {
            for (result.items) |item| {
                item.deinit(allocator);
            }
            result.deinit();
        }

        try testing.expectEqual(@as(usize, 4), result.items.len);
        try testing.expectEqualStrings("LPUSH", result.items[0].BulkString.?);
        try testing.expectEqualStrings("list", result.items[1].BulkString.?);
        try testing.expectEqualStrings("item1", result.items[2].BulkString.?);
        try testing.expectEqualStrings("item2", result.items[3].BulkString.?);
    }
}

test "convert and serialize through Redis protocol" {
    const allocator = testing.allocator;
    var redis_serializer = serializer.createRedisSerializer(allocator);
    defer redis_serializer.deinit();

    // Convert string to RedisValue, then serialize
    const str_value = try RedisConversionUtils.toRedisValue(allocator, "hello");
    defer str_value.deinit(allocator);

    const str_serialized = try redis_serializer.serialize(str_value);
    try testing.expectEqualStrings("$5\r\nhello\r\n", str_serialized);

    // Convert integer to RedisValue, then serialize
    const int_value = try RedisConversionUtils.toRedisValue(allocator, @as(i64, 42));
    defer int_value.deinit(allocator);

    const int_serialized = try redis_serializer.serialize(int_value);
    try testing.expectEqualStrings(":42\r\n", int_serialized);

    // Convert tuple to RedisValues, create array, then serialize
    const cmd = .{ "SET", "mykey", @as(i64, 123) };
    var args = try RedisConversionUtils.tupleToRedisValues(allocator, cmd);
    defer {
        for (args.items) |item| {
            item.deinit(allocator);
        }
        args.deinit();
    }

    const array_value = try serializer.RedisSerializer.createArray(allocator, args.items);
    defer array_value.deinit(allocator);

    const array_serialized = try redis_serializer.serialize(array_value);
    try testing.expectEqualStrings("*3\r\n$3\r\nSET\r\n$5\r\nmykey\r\n:123\r\n", array_serialized);
}

test "roundtrip conversion" {
    const allocator = testing.allocator;
    var redis_serializer = serializer.createRedisSerializer(allocator);
    defer redis_serializer.deinit();

    var redis_parser = parser.createRedisParser(allocator);
    defer redis_parser.deinit();

    // Convert tuple to RedisValues, create array, then serialize
    // Используем числа 1/0 вместо bool, так как bool не поддерживается
    const cmd = .{ "HSET", "user:1000", "name", "John", "age", @as(i64, 30), "active", @as(i64, 1) };
    var args = try RedisConversionUtils.tupleToRedisValues(allocator, cmd);
    defer {
        for (args.items) |item| {
            item.deinit(allocator);
        }
        args.deinit();
    }

    const array_value = try serializer.RedisSerializer.createArray(allocator, args.items);
    defer array_value.deinit(allocator);

    const serialized = try redis_serializer.serialize(array_value);

    try redis_parser.feed(serialized);
    const parsed_value = try redis_parser.parse();
    defer if (parsed_value) |value| value.deinit(allocator);

    try testing.expect(parsed_value != null);
    const reserialized = try redis_serializer.serialize(parsed_value.?);

    try testing.expectEqualStrings(serialized, reserialized);
}
