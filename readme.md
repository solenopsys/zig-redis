zig build-exe -O ReleaseFast bench.zig && ./bench

```
Redis Benchmark
Running benchmark with 100000 iterations
Warming up with 1000 iterations...

Serialization Results:
Total time: 8.42 ms
Operations per second: 11881979.62
Time per operation: 84.161 ns

Deserialization Results:
Total time: 4115.83 ms
Operations per second: 24296.42
Time per operation: 41158.329 ns
```

Нужны  оптимизации парсеса
- SIMD-оптимизация
- Пул памяти
- Zero-copy парсинг
- Оптимизация чтения строк

