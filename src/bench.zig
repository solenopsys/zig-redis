const std = @import("std");
const parser = @import("redis_parser.zig");
const serializer = @import("redis_serializer.zig");
const time = std.time;

const Config = struct {
    method: []const u8,
    hash: []const u8,
    date: []const u8,
    iterations: usize,
    warmup_iterations: usize,
};

const BenchmarkMetrics = struct {
    total_time_ns: i128,
    ops_per_second: f64,
    time_per_op_ns: f64,

    pub fn calculate(iterations: usize, total_time_ns: i128) BenchmarkMetrics {
        const time_per_op = @as(f64, @floatFromInt(total_time_ns)) / @as(f64, @floatFromInt(iterations));
        const ops_per_sec = 1_000_000_000.0 / time_per_op;

        return .{
            .total_time_ns = total_time_ns,
            .ops_per_second = ops_per_sec,
            .time_per_op_ns = time_per_op,
        };
    }

    pub fn print(self: BenchmarkMetrics, writer: std.fs.File.Writer, label: []const u8) !void {
        try writer.print("\n{s} Results:\n", .{label});
        try writer.print("Total time: {d:.2} ms\n", .{@as(f64, @floatFromInt(self.total_time_ns)) / 1_000_000.0});
        try writer.print("Operations per second: {d:.2}\n", .{self.ops_per_second});
        try writer.print("Time per operation: {d:.3} ns\n", .{self.time_per_op_ns});
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var stdout = std.io.getStdOut().writer();
    try stdout.print("Redis Benchmark\n", .{});

    const config = Config{
        .method = "method1",
        .hash = "xczsfs423432424234234",
        .date = "4335",
        .iterations = 100_000,
        .warmup_iterations = 1_000,
    };

    try runBenchmark(allocator, stdout, config);
}

fn runBenchmark(allocator: std.mem.Allocator, writer: std.fs.File.Writer, config: Config) !void {
    try writer.print("Running benchmark with {d} iterations\n", .{config.iterations});

    var redis_serializer = serializer.createRedisSerializer(allocator);
    defer redis_serializer.deinit();

    var redis_parser = parser.createRedisParser(allocator);
    defer redis_parser.deinit();

    const method = try serializer.RedisSerializer.createBulkString(allocator, config.method);
    defer method.deinit(allocator);

    const hash = try serializer.RedisSerializer.createBulkString(allocator, config.hash);
    defer hash.deinit(allocator);

    const date = try serializer.RedisSerializer.createBulkString(allocator, config.date);
    defer date.deinit(allocator);

    var items = [_]parser.RedisValue{ method, hash, date };
    const redis_value = try serializer.RedisSerializer.createArray(allocator, &items);
    defer redis_value.deinit(allocator);

    if (config.warmup_iterations > 0) {
        try writer.print("Warming up with {d} iterations...\n", .{config.warmup_iterations});
        try executeWarmup(allocator, &redis_serializer, &redis_parser, redis_value, config.warmup_iterations);
    }

    const serialization_metrics = try benchmarkSerialization(allocator, &redis_serializer, redis_value, config.iterations);
    const deserialization_metrics = try benchmarkDeserialization(allocator, &redis_serializer, &redis_parser, redis_value, config.iterations);

    try serialization_metrics.print(writer, "Serialization");
    try deserialization_metrics.print(writer, "Deserialization");
}

fn executeWarmup(
    allocator: std.mem.Allocator,
    redis_serializer: *serializer.RedisSerializer,
    redis_parser: *parser.RedisParser,
    redis_value: parser.RedisValue,
    iterations: usize,
) !void {
    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        redis_serializer.reset();
        const serialized_data = try redis_serializer.serialize(redis_value);

        redis_parser.reset();
        try redis_parser.feed(serialized_data);
        const parsed_value = try redis_parser.parse();

        if (parsed_value) |value| {
            value.deinit(allocator);
        }
    }
}

fn benchmarkSerialization(
    allocator: std.mem.Allocator,
    redis_serializer: *serializer.RedisSerializer,
    redis_value: parser.RedisValue,
    iterations: usize,
) !BenchmarkMetrics {
    const start_time = time.nanoTimestamp();
    var serialized_data: []const u8 = undefined;

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        redis_serializer.reset();
        serialized_data = try redis_serializer.serialize(redis_value);
    }
    _ = allocator; // Suppress unused variable warning if needed

    const end_time = time.nanoTimestamp();
    return BenchmarkMetrics.calculate(iterations, end_time - start_time);
}

fn benchmarkDeserialization(
    allocator: std.mem.Allocator,
    redis_serializer: *serializer.RedisSerializer,
    redis_parser: *parser.RedisParser,
    redis_value: parser.RedisValue,
    iterations: usize,
) !BenchmarkMetrics {
    redis_serializer.reset();
    const serialized_data = try redis_serializer.serialize(redis_value);

    const start_time = time.nanoTimestamp();
    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        redis_parser.reset();
        try redis_parser.feed(serialized_data);
        const parsed_value = try redis_parser.parse();

        if (parsed_value) |value| {
            value.deinit(allocator);
        }
    }

    const end_time = time.nanoTimestamp();
    return BenchmarkMetrics.calculate(iterations, end_time - start_time);
}
