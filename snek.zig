const std = @import("std");
const rand = std.crypto.random;

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

fn makeTransColors() [7]raylib.Color {
    var COLORS = [_]raylib.Color{ raylib.RED, raylib.ORANGE, raylib.YELLOW, raylib.GREEN, raylib.BLUE, raylib.MAGENTA, raylib.VIOLET };
    for (&COLORS) |*color| {
        color.*.a = 0xEE;
    }
    return COLORS;
}

fn Game(maxSize: u32) type {
    const game = struct {
        snake: Snake(maxSize),
        fruit: XY,
        score: usize,
        isGodMode: bool,
        fn init(comptime screen: raylib.Vector2) @This() {
            var newGame: Game(maxSize) = .{
                .snake = .{
                    .maxLen = 20,
                    .len = 1,
                    .segments = undefined,
                },
                .fruit = XY{
                    .x = rand.intRangeAtMost(i32, 0, screen.x / SCALE - 1),
                    .y = rand.intRangeAtMost(i32, 0, screen.y / SCALE - 1),
                },
                .score = 0,
                .isGodMode = false,
            };
            for (newGame.snake.segments[0..newGame.snake.len], 0..) |*seg, i| {
                seg.* = .{ .x = @intCast(newGame.snake.len - i), .y = 0 };
            }
            return newGame;
        }
        fn reset(self: *@This()) void {
            std.debug.print("\treset!", .{});
            self.snake.len = 1;
            self.score = 0;
        }
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

const Texture = struct {
    texture: raylib.Texture2D,
    scale: f32,
};

fn generateFruits() [2]Texture {
    const files = [_][*c]const u8{ "./🍏.png", "./🍌.png" };
    var ret: [2]Texture = undefined;
    for (files, &ret) |file, *myTex| {
        const image = raylib.LoadImage(file);
        std.debug.assert(image.data != null);
        myTex.texture = raylib.LoadTextureFromImage(image);
        std.debug.assert(myTex.texture.width == myTex.texture.height);
        myTex.scale = SCALE / @as(f32, @floatFromInt(myTex.texture.width));
    }
    return ret;
}

const SCALE = 50;
pub fn main() void {
    raylib.SetConfigFlags(raylib.FLAG_WINDOW_TRANSPARENT);
    const screen: raylib.Vector2 = .{ .x = 1200, .y = 800 };
    raylib.InitWindow(screen.x, screen.y, "snek");
    defer raylib.CloseWindow();
    const fruitTextures = generateFruits();
    std.debug.print("hi {any}", .{fruitTextures});
    raylib.SetTargetFPS(raylib.GetMonitorRefreshRate(raylib.GetCurrentMonitor()));
    raylib.SetTargetFPS(30);
    const snakeTexture = raylib.LoadTextureFromImage(raylib.LoadImage("./🐍.png"));
    std.debug.assert(snakeTexture.width == snakeTexture.height);
    const snakeTextureScale: f32 = SCALE / @as(f32, @floatFromInt(snakeTexture.width));

    const gameSize = screen.x / SCALE * screen.y / SCALE;
    var game = Game(gameSize).init(screen);
    var dir: Dir = .right;
    var f: i32 = 0;
    var fruitT: Texture = fruitTextures[rand.intRangeAtMost(u16, 0, 1)];
    while (!raylib.WindowShouldClose()) {
        var lose = false;
        // UPDATE
        {
            f += 1;
            std.debug.print("\n**FRAME {}\n", .{f});
            defer std.debug.print("---------\n", .{});

            // / input
            if (raylib.IsKeyPressed(raylib.KEY_DOWN)) {
                dir = if (dir != .down) .down else .up;
            } else if (raylib.IsKeyDown(raylib.KEY_UP)) {
                dir = .up;
            } else if (raylib.IsKeyDown(raylib.KEY_LEFT)) {
                dir = .left;
            } else if (raylib.IsKeyDown(raylib.KEY_RIGHT)) {
                dir = .right;
            }

            if (raylib.IsKeyPressed(raylib.KEY_SPACE)) {
                std.debug.print("\tdebug: add 1 point\n", .{});

                game.score += 1;
                game.snake.len += 1;
                game.snake.segments[game.snake.len] = game.snake.segments[game.snake.len - 1];
            }

            if (raylib.IsKeyPressed(raylib.KEY_R)) {
                std.debug.print("\tdebug: reset\n", .{});
                game = @TypeOf(game).init(screen);
            }

            if (raylib.IsKeyPressed(raylib.KEY_G)) {
                std.debug.print("\tdebug: godmode\n", .{});
                game.isGodMode = true;
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
                std.debug.print("\t💀 touched yourself\n", .{});
                lose = true;
            }
            if (game.snake.isTouchingFruit(game.fruit)) {
                game.score += 1;
                game.snake.len += 1;

                game.snake.segments[game.snake.len - 1] = game.snake.segments[game.snake.len - 2];

                game.fruit = .{
                    .x = rand.intRangeAtMost(i32, 0, screen.x / SCALE - 1),
                    .y = rand.intRangeAtMost(i32, 0, screen.y / SCALE - 1),
                };
                fruitT = fruitTextures[rand.intRangeAtMost(u16, 0, 1)];
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
            } else {
                std.debug.print("\t💥 touched wall\n", .{});
                lose = true;
            }
            if (lose) {
                if (!game.isGodMode and game.snake.len >= 2 and game.score > 0) {
                    game.snake.len -= 1;
                    game.score -= 1;
                }
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
            raylib.DrawRectangleLinesEx(raylib.Rectangle{ .x = 0, .y = 0, .width = screen.x, .height = screen.y }, 3, raylib.BLACK);

            const fruitPos = game.fruit.toScreenCoords(SCALE);
            raylib.DrawTextureEx(fruitT.texture, fruitPos, 0, fruitT.scale, raylib.WHITE);
            var score: [3]u8 = undefined;
            const scoreDigits = std.fmt.digits2(game.score);
            score[0] = scoreDigits[0];
            score[1] = scoreDigits[1];
            score[2] = 0; // null-terminate
            raylib.DrawText(&score, 10, 3, 69, raylib.PURPLE);
            for (game.snake.segments[0..game.snake.len], 0..) |seg, p| {
                const segScreen = seg.toScreenCoords(SCALE);
                const COLORS = makeTransColors();
                if (p == 0) {
                    raylib.DrawTextureEx(snakeTexture, segScreen, 0, snakeTextureScale, raylib.WHITE);
                } else {
                    // todo: snake emoji
                    raylib.DrawTextureEx(snakeTexture, segScreen, 0, snakeTextureScale, COLORS[p % COLORS.len]);
                    //raylib.DrawRectangleRec(segrec, COLORS[p % COLORS.len]);
                }
            }
            raylib.DrawFPS(screen.x - 100, 0);
        }
    }
}
