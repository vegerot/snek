
build: zig-out/bin/snek
zig-out/bin/snek: build.zig snek.zig
	zig build

play: zig-out/bin/snek
	zig build play

benchmark: zig-out/bin/snek-benchmark
	zig build benchmark

zig-out/bin/snek-benchmark: build.zig benchmark.zig
	zig build

