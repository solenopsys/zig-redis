const std = @import("std");
const types = @import("types.zig");
const RedisSerializer = @import("redis_serializer.zig").RedisSerializer;
//-----------------------------------------------------------------------
// Utility for type conversion - completely separate module
//-----------------------------------------------------------------------

/// Utilities for type conversion
pub const RedisConversionUtils = struct {
    /// Create a Redis integer value
    pub fn createInteger(value: i64) types.RedisValue {
        return .{ .Integer = value };
    }

    /// Check if a type is a string literal (sentinel-terminated array)
    fn isStringLiteral(comptime T: type) bool {
        const info = @typeInfo(T);
        if (info == .Pointer) {
            const ptr_info = info.Pointer;
            if (ptr_info.size == .Many and ptr_info.sentinel != null) {
                // Check if it's a zero-terminated array of u8
                return ptr_info.child == u8 and @as(*const u8, @ptrCast(ptr_info.sentinel.?)).* == 0;
            }
        }
        return false;
    }

    /// Convert arbitrary type to RedisValue
    pub fn toRedisValue(allocator: std.mem.Allocator, value: anytype) !types.RedisValue {
        const T = @TypeOf(value);

        if (T == types.RedisValue) {
            return value;
        } else if (T == []const u8 or T == []u8) {
            // Handle both mutable and immutable slices of u8
            return try RedisSerializer.createBulkString(allocator, value);
        } else if (comptime isStringLiteral(T)) {
            // Handle string literals (fixed-size arrays)
            return try RedisSerializer.createBulkString(allocator, value);
        } else if (comptime @typeInfo(T) == .Array and @typeInfo(T).Array.child == u8) {
            // Handle array of u8
            return try RedisSerializer.createBulkString(allocator, &value);
        } else if (T == i64 or T == i32 or T == u64 or T == u32 or T == usize or T == u8 or T == i8) {
            return createInteger(@intCast(value));
        } else if (@typeInfo(T) == .Optional) {
            if (value) |v| {
                return try toRedisValue(allocator, v);
            } else {
                return types.RedisValue{ .Null = {} };
            }
        } else if (@typeInfo(T) == .Pointer and @typeInfo(T).Pointer.size == .One) {
            // Handle single-item pointers by dereferencing
            return try toRedisValue(allocator, value.*);
        } else {
            @compileError("Unsupported type for Redis conversion: " ++ @typeName(T));
        }
    }

    /// Convert a list of arbitrary values to a list of RedisValue
    pub fn sliceToRedisValues(allocator: std.mem.Allocator, values: anytype) !std.ArrayList(types.RedisValue) {
        var result = std.ArrayList(types.RedisValue).init(allocator);
        errdefer {
            for (result.items) |item| {
                item.deinit(allocator);
            }
            result.deinit();
        }

        // Process slice with values of any type
        const slice_type = @TypeOf(values);
        const info = @typeInfo(slice_type);

        if (info != .Pointer or info.Pointer.size != .Slice) {
            @compileError("Expected slice, got " ++ @typeName(slice_type));
        }

        for (values) |value| {
            const redis_value = try toRedisValue(allocator, value);
            try result.append(redis_value);
        }

        return result;
    }

    /// Convert a tuple of values to an array of RedisValue
    pub fn tupleToRedisValues(allocator: std.mem.Allocator, tuple: anytype) !std.ArrayList(types.RedisValue) {
        var result = std.ArrayList(types.RedisValue).init(allocator);
        errdefer {
            for (result.items) |item| {
                item.deinit(allocator);
            }
            result.deinit();
        }

        const tuple_type = @TypeOf(tuple);
        const type_info = @typeInfo(tuple_type);

        if (type_info != .Struct or !type_info.Struct.is_tuple) {
            @compileError("Expected tuple, got " ++ @typeName(tuple_type));
        }

        inline for (type_info.Struct.fields) |field| {
            const value = @field(tuple, field.name);
            const redis_value = try toRedisValue(allocator, value);
            try result.append(redis_value);
        }

        return result;
    }

    /// Convert arguments to RedisValue for a command
    pub fn argsToRedisValues(allocator: std.mem.Allocator, args: anytype) !std.ArrayList(types.RedisValue) {
        const args_type = @TypeOf(args);
        const type_info = @typeInfo(args_type);

        // Empty arguments
        if (args_type == void) {
            return std.ArrayList(types.RedisValue).init(allocator);
        }
        // RedisValue slice
        else if (type_info == .Pointer and
            type_info.Pointer.size == .Slice and
            type_info.Pointer.child == types.RedisValue)
        {
            var result = std.ArrayList(types.RedisValue).init(allocator);
            try result.appendSlice(args);
            return result;
        }
        // Slice of arbitrary values
        else if (type_info == .Pointer and type_info.Pointer.size == .Slice) {
            return sliceToRedisValues(allocator, args);
        }
        // Tuple of arguments
        else if (type_info == .Struct and type_info.Struct.is_tuple) {
            return tupleToRedisValues(allocator, args);
        }
        // Single argument
        else {
            var result = std.ArrayList(types.RedisValue).init(allocator);
            const redis_value = try toRedisValue(allocator, args);
            try result.append(redis_value);
            return result;
        }
    }
};
