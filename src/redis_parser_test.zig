const std = @import("std");
const testing = std.testing;
const parser = @import("redis_parser.zig");

test "parse simple string" {
    var redis_parser = parser.createRedisParser(testing.allocator);
    defer redis_parser.deinit();

    try redis_parser.feed("+OK\r\n");
    const result = try redis_parser.parse();
    defer if (result) |value| value.deinit(testing.allocator);

    try testing.expect(result != null);
    switch (result.?) {
        .SimpleString => |str| try testing.expectEqualStrings("OK", str),
        else => try testing.expect(false), // Неправильный тип
    }
}

test "array memory leak" {
    var redis_parser = parser.createRedisParser(testing.allocator);
    defer redis_parser.deinit();

    // Простой массив
    const array_data = "*3\r\n$3\r\nfoo\r\n$3\r\nbar\r\n$3\r\nbaz\r\n";

    // Несколько циклов для выявления утечек
    for (0..10) |i| {
        redis_parser.reset();
        try redis_parser.feed(array_data);

        const result = try redis_parser.parse();

        // Главное - правильно освободить результат
        defer if (result) |value| value.deinit(testing.allocator);

        // Небольшая проверка, чтобы убедиться, что парсинг работает
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

    // testing.allocator автоматически проверит на утечки
}

test "parseArray memory leak" {
    // Создаем парсер с testing.allocator, который отслеживает утечки
    var redis_parser = parser.createRedisParser(testing.allocator);
    defer redis_parser.deinit();

    // Вложенный массив - структура, которая вызывала утечки памяти
    const nested_array = "*3\r\n$3\r\nkey\r\n*2\r\n$5\r\nfield\r\n$5\r\nvalue\r\n$4\r\ntest\r\n";

    // Проверяем несколько раз, чтобы утечка стала заметной
    for (0..5) |_| {
        // Сбрасываем парсер перед каждой итерацией
        redis_parser.reset();

        // Подаем данные массива
        try redis_parser.feed(nested_array);

        // Парсим и проверяем результат
        const result = try redis_parser.parse();

        // testing.allocator автоматически обнаружит утечку, если
        // не освободить результат
        defer if (result) |value| value.deinit(testing.allocator);

        // Проверяем, что результат не null
        try testing.expect(result != null);

        // Проверяем, что результат - массив
        switch (result.?) {
            .Array => |maybe_array| {
                try testing.expect(maybe_array != null);
                try testing.expectEqual(@as(usize, 3), maybe_array.?.items.len);
            },
            else => try testing.expect(false), // Неправильный тип
        }
    }

    // Если test завершится успешно и нет panic от testing.allocator,
    // значит утечек нет
}

test "nested arrays memory leak" {
    var redis_parser = parser.createRedisParser(testing.allocator);
    defer redis_parser.deinit();

    // Правильно форматированный вложенный массив в формате RESP
    // *2 - массив из 2 элементов:
    //   1. *2 - массив из 2 элементов (foo, bar)
    //   2. *1 - массив из 1 элемента (baz)
    const nested_array = "*2\r\n*2\r\n$3\r\nfoo\r\n$3\r\nbar\r\n*1\r\n$3\r\nbaz\r\n";

    // Парсим его несколько раз
    for (0..3) |_| {
        redis_parser.reset();
        try redis_parser.feed(nested_array);

        const result = try redis_parser.parse();
        defer if (result) |value| value.deinit(testing.allocator);

        try testing.expect(result != null);

        // Проверяем, что это массив правильной структуры
        switch (result.?) {
            .Array => |maybe_array| {
                try testing.expect(maybe_array != null);
                try testing.expectEqual(@as(usize, 2), maybe_array.?.items.len);

                // Проверяем первый элемент - тоже массив из 2 элементов
                switch (maybe_array.?.items[0]) {
                    .Array => |maybe_inner1| {
                        try testing.expect(maybe_inner1 != null);
                        try testing.expectEqual(@as(usize, 2), maybe_inner1.?.items.len);

                        // Проверяем строковые значения
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

                // Проверяем второй элемент - массив из 1 элемента
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
        else => try testing.expect(false), // Неправильный тип
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
        else => try testing.expect(false), // Неправильный тип
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
        else => try testing.expect(false), // Неправильный тип
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
        else => try testing.expect(false), // Неправильный тип
    }
}

test "parse array" {
    std.debug.print("\n\n=== TEST: parse array ===\n", .{});

    const allocator = testing.allocator;
    var redis_parser = parser.createRedisParser(allocator);
    defer redis_parser.deinit();

    // Явно указываем символы \r\n
    const input = "*2\r\n$3\r\nfoo\r\n$3\r\nbar\r\n";
    std.debug.print("Input length: {}\n", .{input.len});

    // Выводим шестнадцатеричное представление входных данных
    std.debug.print("Input hex dump: ", .{});
    for (input) |c| {
        std.debug.print("{X:0>2} ", .{c});
    }
    std.debug.print("\n", .{});

    try redis_parser.feed(input);

    // Проверяем, что данные корректно добавились в буфер
    std.debug.print("Buffer length: {}\n", .{redis_parser.buffer.items.len});
    std.debug.print("Buffer hex dump: ", .{});
    for (redis_parser.buffer.items) |c| {
        std.debug.print("{X:0>2} ", .{c});
    }
    std.debug.print("\n", .{});

    const result = try redis_parser.parse();
    // Важно: освобождаем память в любом случае
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

    // Вложенный массив: массив из двух элементов - массив строк и строка
    try redis_parser.feed("*2\r\n*2\r\n+Hello\r\n+World\r\n$5\r\nredis\r\n");

    const result = try redis_parser.parse();
    // Важно: освобождаем память в любом случае
    defer if (result) |value| value.deinit(allocator);

    try testing.expect(result != null);
    switch (result.?) {
        .Array => |maybe_array| {
            try testing.expect(maybe_array != null);
            const array = maybe_array.?;
            try testing.expectEqual(@as(usize, 2), array.items.len);

            // Проверка первого элемента (вложенный массив)
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

            // Проверка второго элемента (строка)
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

    // Разбор первой команды
    const result1 = try redis_parser.parse();
    defer if (result1) |value| value.deinit(testing.allocator);

    try testing.expect(result1 != null);
    switch (result1.?) {
        .SimpleString => |str| try testing.expectEqualStrings("OK", str),
        else => try testing.expect(false),
    }

    // Разбор второй команды
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

    // Разбор первой команды
    const result1 = try redis_parser.parse();
    defer if (result1) |value| value.deinit(testing.allocator);

    try testing.expect(result1 != null);
    switch (result1.?) {
        .SimpleString => |str| try testing.expectEqualStrings("OK", str),
        else => try testing.expect(false),
    }

    // Попытка разбора второй команды (не завершена)
    try testing.expectError(parser.RedisParserError.Incomplete, redis_parser.parse());

    // Добавление оставшейся части команды
    try redis_parser.feed("0\r\n");

    // Теперь команда должна успешно разобраться
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

    // Здесь мы ожидаем ошибку InvalidPrefix
    const result = redis_parser.parse();
    try testing.expectError(parser.RedisParserError.InvalidPrefix, result);
}
