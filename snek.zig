const std = @import("std");

const raylib = @cImport({
    @cInclude("raylib.h");
    @cInclude("raymath.h");
});

fn buildEnumFromC(comptime import: anytype, comptime prefix: []const u8) type {
    comptime var enum_fields: [1024]std.builtin.Type.EnumField = undefined;
    comptime var count = 0;

    inline for (std.meta.declarations(import)) |decl| {
        if (decl.name.len < prefix.len + 1) {
            continue;
        }

        @setEvalBranchQuota(10000);
        if (std.mem.eql(u8, decl.name[0..prefix.len], prefix)) {
            enum_fields[count] = .{
                .name = decl.name[prefix.len + 1 ..],
                .value = @field(import, decl.name),
            };
            count += 1;
        }
    }

    return @Type(
        .{ .Enum = .{
            .tag_type = u16,
            .fields = enum_fields[0..count],
            .decls = &.{},
            .is_exhaustive = true,
        } },
    );
}

const Key = buildEnumFromC(raylib, "KEY");

fn Game(maxSize: u32) type {
    const game = struct {
        snake: Snake(maxSize),
        fruit: XY,
    };
    return game;
}

const XY = struct {
    x: i32,
    y: i32,
    const This = @This();
    fn toScreenCoords(self: *const @This(), scale: i32) raylib.Vector2 {
        return raylib.Vector2{ .x = @floatFromInt(self.x * scale), .y = @floatFromInt(self.y * scale) };
    }
    fn add(self: *const This, that: *const This) This {
        return .{ .x = self.x + that.x, .y = self.y + that.y };
    }
    fn isEqual(this: This, that: This) bool {
        return this.x == that.x and this.y == that.y;
    }
};

fn Snake(maxSize: u32) type {
    const snake = struct {
        // TODO: make this a rope / linked list thingy
        segments: [maxSize]XY,
        len: u16,
        maxLen: u32,
        fn isTouchingFruit(self: *const @This(), fruit: XY) bool {
            return self.segments[0].x == fruit.x and self.segments[0].y == fruit.y;
        }
        fn isTouchingSelf(self: *const @This(), nextHead: XY) bool {
            for (self.segments[1..self.len]) |seg| {
                if (seg.isEqual(nextHead)) {
                    return true;
                }
            }
            return false;
        }
    };
    return snake;
}

const Dir = enum { up, down, left, right };

pub fn main() void {
    raylib.SetConfigFlags(raylib.FLAG_WINDOW_TRANSPARENT);
    const screen: raylib.Vector2 = .{ .x = 1600, .y = 900 };
    raylib.InitWindow(screen.x, screen.y, "snek");
    defer raylib.CloseWindow();
    raylib.SetTargetFPS(raylib.GetMonitorRefreshRate(raylib.GetCurrentMonitor()));
    raylib.SetTargetFPS(24);

    var game: Game(20) = .{
        .snake = .{
            .maxLen = 20,
            .len = 2,
            .segments = undefined,
        },
        .fruit = XY{ .x = 1, .y = 3 },
    };
    for (game.snake.segments[0..game.snake.len], 0..) |*seg, i| {
        seg.* = .{ .x = @intCast(game.snake.len - i), .y = 0 };
    }
    var dir: Dir = .right;
    var f: i32 = 0;
    while (!raylib.WindowShouldClose()) {
        const SCALE = 50;
        var lose = false;
        // UPDATE
        {
            f += 1;
            std.debug.print("\n**FRAME {}\n", .{f});
            defer std.debug.print("---------\n", .{});

            // / input
            if (raylib.IsKeyPressed(raylib.KEY_DOWN)) {
                dir = if (dir != .down) .down else .up;
                std.debug.print("\t@@@DOWN@@@: \n", .{});
            } else if (raylib.IsKeyDown(raylib.KEY_UP)) {
                dir = .up;
            } else if (raylib.IsKeyDown(raylib.KEY_LEFT)) {
                dir = .left;
            } else if (raylib.IsKeyDown(raylib.KEY_RIGHT)) {
                dir = .right;
            }

            if (raylib.IsKeyPressed(raylib.KEY_SPACE)) {
                game.snake.len += 1;
                game.snake.segments[game.snake.len] = game.snake.segments[game.snake.len - 1];
            }
            const dirV: XY = switch (dir) {
                .up => .{ .x = 0, .y = -1 },
                .down => .{ .x = 0, .y = 1 },
                .left => .{ .x = -1, .y = 0 },
                .right => .{ .x = 1, .y = 0 },
            };

            const head = &game.snake.segments[0];
            const maybeNextHead = head.add(&dirV);
            const isNextHeadInBounds = maybeNextHead.x >= 0 and maybeNextHead.x < screen.x / SCALE and maybeNextHead.y >= 0 and maybeNextHead.y < screen.y / SCALE;
            if (game.snake.isTouchingSelf(maybeNextHead)) {
                std.debug.print("\tself\n", .{});
                lose = true;
            }
            if (game.snake.isTouchingFruit(game.fruit)) {
                game.snake.len += 1;
                game.snake.segments[game.snake.len - 1] = game.snake.segments[game.snake.len - 2];

                game.fruit.y += 1;
            }
            if (isNextHeadInBounds) {
                var i = game.snake.len;
                // start from back of snake and work forward
                while (i > 1) {
                    i -= 1;

                    const back = &game.snake.segments[i];
                    const front = game.snake.segments[i - 1];

                    back.* = front;
                }
                head.* = maybeNextHead;
                std.debug.print("\tSNAKE: {any}\n", .{game.snake.segments});
            } else {
                std.debug.print("\twall\n", .{});
            }
        }

        // DRAW
        {
            raylib.BeginDrawing();
            defer raylib.EndDrawing();
            raylib.ClearBackground(raylib.Color{ .a = 0x01 });
            if (lose) {
                raylib.ClearBackground(raylib.Color{ .r = 0xFF, .a = 0x80 });
            }

            const fruitPos = game.fruit.toScreenCoords(SCALE);
            raylib.DrawRectangleRec(raylib.Rectangle{ .x = fruitPos.x, .y = fruitPos.y, .width = SCALE, .height = SCALE }, raylib.GREEN);
            for (game.snake.segments[0..game.snake.len], 0..) |seg, p| {
                const snake_seg_size: raylib.Vector2 = .{ .x = SCALE, .y = SCALE };
                const segScreen = seg.toScreenCoords(SCALE);
                const segrec = raylib.Rectangle{
                    .x = segScreen.x,
                    .y = segScreen.y,
                    .width = snake_seg_size.x,
                    .height = snake_seg_size.y,
                };
                const red = raylib.Color{ .r = 0x99, .a = 0xF0 };
                const blue = raylib.Color{ .b = 0x99, .a = 0xF0 };
                raylib.DrawRectangleRec(segrec, if (p % 2 == 0) red else blue);
            }
        }
    }
}
