
build: zig-out/bin/snek
zig-out/bin/snek: build.zig snek.zig
	zig build

play: zig-out/bin/snek
	zig build play

