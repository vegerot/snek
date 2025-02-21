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
        color.*.a = 0xE0;
    }
    return COLORS;
}

fn Game(maxSize: u32) type {
    const game = struct {
        state: struct {
            snake: Snake(maxSize),
            fruit: XY,
            score: usize,
            highScore: usize,
            dir: Dir,
            fruitTextureOffset: TextureOffset,
        },
        /// state that's only needed for this tick or frame
        tickState: struct {
            shouldAdvanceFrame: bool,
            frameCount: i64,
            nextDir: Dir,
            loseCnt: usize,
            isNextHeadInBounds: bool,
        },
        options: struct {
            gameSize: struct { x: i16, y: i16 },
            isGodMode: bool,
            isTransparent: bool,
            isPaused: bool,
            shouldInterpolate: bool,
        },
        fn init(comptime screen: raylib.Vector2) @This() {
            var newGame: Game(maxSize) = .{
                .state = .{
                    .snake = .{
                        .maxLen = maxSize,
                        .len = 1,
                        .segments = undefined,
                    },
                    .fruit = XY{
                        .x = rand.intRangeAtMost(i32, 0, screen.x / SCALE - 1),
                        .y = rand.intRangeAtMost(i32, 0, screen.y / SCALE - 1),
                    },
                    .score = 0,
                    .highScore = 0,
                    .dir = .right,
                    .fruitTextureOffset = .{ .scale = SCALE, .texturePos = undefined },
                },
                .options = .{
                    .gameSize = .{ .x = screen.x / SCALE, .y = screen.y / SCALE },
                    .isGodMode = false,
                    .isTransparent = true,
                    .isPaused = false,
                    .shouldInterpolate = true,
                },
                .tickState = .{
                    .shouldAdvanceFrame = false,
                    .frameCount = 0,
                    .nextDir = .right,
                    .loseCnt = 0,
                    .isNextHeadInBounds = true,
                },
            };
            for (newGame.state.snake.segments[0..newGame.state.snake.len], 0..) |*seg, i| {
                seg.* = .{ .x = @intCast(newGame.state.snake.len - i), .y = 0 };
            }
            return newGame;
        }
        fn reset(self: *@This()) void {
            std.debug.print("\treset!", .{});
            self.snake.len = 1;
            self.score = 0;
        }
        fn incrementScore(self: *@This()) void {
            self.state.score += 1;
            if (self.state.score > self.state.highScore) {
                self.state.highScore = self.state.score;
            }
            std.debug.print("score: {}\n", .{self.state.score});
        }
        fn update(game: *@This(), fruitTextures: FruitTextures) void {
            // std.debug.print("\n**FRAME {}\n", .{game.frameCount});
            // defer std.debug.print("---------\n", .{});
            const snake = &game.state.snake;
            game.tickState.loseCnt = 0;

            game.state.dir = game.tickState.nextDir;
            const dirV: XY = switch (game.state.dir) {
                .up => .{ .x = 0, .y = -1 },
                .down => .{ .x = 0, .y = 1 },
                .left => .{ .x = -1, .y = 0 },
                .right => .{ .x = 1, .y = 0 },
            };

            const head = &snake.segments[0];
            const maybeNextHead = head.add(&dirV);
            game.tickState.isNextHeadInBounds = maybeNextHead.x >= 0 and maybeNextHead.x < game.options.gameSize.x and maybeNextHead.y >= 0 and maybeNextHead.y < game.options.gameSize.y;
            if (snake.isTouchingSelf(maybeNextHead) != 0) {
                std.debug.print("\t💀 touched yourself\n", .{});
                game.tickState.loseCnt = snake.isTouchingSelf(maybeNextHead);
            }
            if (snake.isTouchingFruit(game.state.fruit)) {
                game.incrementScore();
                snake.len += 1;

                snake.segments[snake.len - 1] = snake.segments[snake.len - 2];

                game.state.fruit = .{
                    .x = rand.intRangeAtMost(i32, 0, game.options.gameSize.x - 1),
                    .y = rand.intRangeAtMost(i32, 0, game.options.gameSize.y - 1),
                };
                game.state.fruitTextureOffset = fruitTextures.next();
            }
            if (game.tickState.isNextHeadInBounds) {
                var i = snake.len;
                // start from back of snake and work forward
                while (i >= 1) {
                    defer i -= 1;

                    const back = &snake.segments[i];
                    const front = snake.segments[i - 1];

                    back.* = front;
                }
                head.* = maybeNextHead;
            } else {
                std.debug.print("\t💥 touched wall\n", .{});
                game.tickState.loseCnt = snake.len - 1;
            }
            if (game.tickState.loseCnt != 0) {
                if (!game.options.isGodMode and snake.len >= 2 and game.state.score > 0) {
                    snake.len = @intCast(game.tickState.loseCnt);
                    game.state.score = @intCast(game.tickState.loseCnt - 1);
                }
            }
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
        // 0 = head
        segments: [maxSize]XY,
        len: u16,
        maxLen: u32,
        fn isTouchingFruit(self: *const @This(), fruit: XY) bool {
            return self.segments[0].x == fruit.x and self.segments[0].y == fruit.y;
        }
        fn isTouchingSelf(self: *const @This(), nextHead: XY) usize {
            for (self.segments[1..self.len], 0..) |seg, i| {
                if (seg.isEqual(nextHead)) {
                    return i + 1;
                }
            }
            return 0;
        }
    };
    return snake;
}

const Dir = enum { up, down, left, right };

const TextureOffset = struct {
    scale: f32,
    texturePos: raylib.Rectangle,
};

const FruitTextures = struct {
    const texturesCount = 10;
    spriteSheetTexture: raylib.Texture2D,
    textures: [texturesCount]TextureOffset,
    fn generateFruits() !FruitTextures {
        const spriteSheetTexture = raylib.LoadTexture("./emoji.png");
        const avgHeight = 96; //px
        const avgWidth = 96; // px
        // // height=96px, average width=954px/10=95
        // const textureCount = 10;
        var self: @This() = .{ .spriteSheetTexture = spriteSheetTexture, .textures = undefined };
        for (&self.textures, 0..) |*fruit, i| {
            const fi: f32 = @floatFromInt(i);
            fruit.*.texturePos = .{
                .x = fi * avgWidth,
                .y = 0,
                .width = avgWidth,
                .height = avgHeight,
            };
            fruit.*.scale = SCALE;
        }
        return self;
    }
    fn next(self: *const @This()) TextureOffset {
        return self.textures[rand.intRangeAtMost(u16, 0, texturesCount - 1)];
    }
    fn unload(self: *const @This()) void {
        raylib.UnloadTexture(self.spriteSheetTexture);
    }
};

const SCALE = 50;
pub fn main() !void {
    raylib.SetConfigFlags(raylib.FLAG_WINDOW_TRANSPARENT);
    const screen: raylib.Vector2 = .{ .x = 2400, .y = 1600 };
    raylib.InitWindow(screen.x, screen.y, "snek");
    defer raylib.CloseWindow();

    const fruitTextures = try FruitTextures.generateFruits();
    defer fruitTextures.unload();

    raylib.SetTargetFPS(raylib.GetMonitorRefreshRate(raylib.GetCurrentMonitor()));

    const snakeImage = raylib.LoadImage("./🐍.png");
    const snakeTexture = raylib.LoadTextureFromImage(snakeImage);
    raylib.SetWindowIcon(snakeImage);
    std.debug.assert(snakeTexture.id != 0);
    std.debug.assert(snakeTexture.width == snakeTexture.height);
    const snakeTextureScale: f32 = SCALE / @as(f32, @floatFromInt(snakeTexture.width));
    const font = raylib.LoadFont("./emoji.ttf");
    defer raylib.UnloadFont(font);
    std.debug.assert(font.texture.id != 0);

    const gameSize = screen.x / SCALE * screen.y / SCALE;
    var game = Game(gameSize).init(screen);
    game.state.fruitTextureOffset = fruitTextures.next();
    var startTime = try std.time.Instant.now();
    while (!raylib.WindowShouldClose()) {
        game.tickState.frameCount += 1;
        // input
        {
            if (raylib.IsKeyPressed(raylib.KEY_DOWN) and game.state.dir != .up) {
                game.tickState.nextDir = .down;
            } else if (raylib.IsKeyPressed(raylib.KEY_UP) and game.state.dir != .down) {
                game.tickState.nextDir = .up;
            } else if (raylib.IsKeyPressed(raylib.KEY_LEFT) and game.state.dir != .right) {
                game.tickState.nextDir = .left;
            } else if (raylib.IsKeyPressed(raylib.KEY_RIGHT) and game.state.dir != .left) {
                game.tickState.nextDir = .right;
            }

            if (raylib.IsKeyPressed(raylib.KEY_SPACE) or raylib.IsKeyPressed(raylib.KEY_P)) {
                game.options.isPaused = !game.options.isPaused;
            }
            game.tickState.shouldAdvanceFrame = raylib.IsKeyPressed(raylib.KEY_F);

            if (raylib.IsKeyPressed(raylib.KEY_I)) game.options.shouldInterpolate = !game.options.shouldInterpolate;

            if (raylib.IsKeyPressed(raylib.KEY_PERIOD)) {
                std.debug.print("\tcheat: add 1 point\n", .{});

                game.incrementScore();
                game.state.snake.len += 1;
                game.state.snake.segments[game.state.snake.len] = game.state.snake.segments[game.state.snake.len - 1];
            }

            if (raylib.IsKeyPressed(raylib.KEY_R)) {
                std.debug.print("\tdebug: reset\n", .{});
                game = @TypeOf(game).init(screen);
            }

            if (raylib.IsKeyPressed(raylib.KEY_G)) {
                std.debug.print("\tdebug: godmode\n", .{});
                game.options.isGodMode = !game.options.isGodMode;
            }

            if (raylib.IsKeyPressed(raylib.KEY_T)) {
                game.options.isTransparent = !game.options.isTransparent;
            }
        }
        // UPDATE
        const now = try std.time.Instant.now();
        const tps = 30;
        {
            if (!raylib.IsWindowFocused()) {
                game.options.isPaused = true;
            }

            const dontRunPhysics = (game.options.isPaused and !game.tickState.shouldAdvanceFrame);
            const isTimeToRunPhysics = now.since(startTime) > std.time.ns_per_s / tps;
            const shouldRunPhysics = isTimeToRunPhysics and !dontRunPhysics;
            if (shouldRunPhysics) {
                game.update(fruitTextures);
                startTime = now;
            }
        }
        // DRAW
        {
            raylib.BeginDrawing();
            defer raylib.EndDrawing();
            const snake = &game.state.snake;
            if (game.options.isTransparent) {
                raylib.ClearBackground(raylib.Color{ .a = 0x10 });
            } else {
                raylib.ClearBackground(raylib.Color{ .a = 0xF0 });
            }
            if (game.tickState.loseCnt != 0 and game.state.score > 0) {
                std.debug.print("loseCnt: {}, score: {}\n", .{ game.tickState.loseCnt, game.state.score });
                raylib.ClearBackground(raylib.Color{ .r = 0x80, .a = 0x80 });
            }
            raylib.DrawRectangleLinesEx(raylib.Rectangle{ .x = 0, .y = 0, .width = screen.x, .height = screen.y }, 3, raylib.BLACK);

            const fruitPos = game.state.fruit.toScreenCoords(SCALE);
            const fruitPosRec: raylib.Rectangle = .{
                .x = fruitPos.x,
                .y = fruitPos.y,
                .width = game.state.fruitTextureOffset.scale,
                .height = game.state.fruitTextureOffset.scale,
            };
            raylib.DrawTexturePro(
                fruitTextures.spriteSheetTexture,
                game.state.fruitTextureOffset.texturePos,
                fruitPosRec,
                .{},
                0,
                raylib.WHITE,
            );
            var score: [3]u8 = undefined;
            const scoreDigits = std.fmt.digits2(game.state.score);
            score[0] = scoreDigits[0];
            score[1] = scoreDigits[1];
            score[2] = 0; // null-terminate
            raylib.DrawText(&score, 10, 3, 69, raylib.PURPLE);
            if (game.state.score != game.state.highScore) {
                var highScore: [3]u8 = undefined;
                const highScoreDigits = std.fmt.digits2(game.state.highScore);
                highScore[0] = highScoreDigits[0];
                highScore[1] = highScoreDigits[1];
                highScore[2] = 0; // null-terminate
                raylib.DrawText(&highScore, 10, 75, 33, raylib.BLUE);
            }
            for (snake.segments[0..snake.len], 0..) |seg, p| {
                const segScreen = seg.toScreenCoords(SCALE);
                const COLORS = makeTransColors();
                const isSnakeHead = p == 0;
                const color = if (isSnakeHead) raylib.WHITE else COLORS[p % COLORS.len];
                const pct = 1 - @as(f32, @floatFromInt(now.since(startTime))) / (@as(f32, std.time.ns_per_s) / tps);
                const pctClamped = std.math.clamp(pct, 0, 1);
                const shouldInterpolate = game.options.shouldInterpolate and (game.tickState.isNextHeadInBounds or (p == snake.len - 1 and p != 0));
                const interpolatedPosition: raylib.Vector2 = raylib.Vector2Lerp(segScreen, snake.segments[p + 1].toScreenCoords(SCALE), if (shouldInterpolate) pctClamped else 0);
                raylib.DrawTextureEx(snakeTexture, interpolatedPosition, 0, snakeTextureScale, color);
            }
            raylib.DrawFPS(screen.x - 100, 0);
        }
    }
}
