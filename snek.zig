const std = @import("std");
const rand = std.crypto.random;

const builtin = @import("builtin");

const raylib = @cImport({
    @cInclude("raylib.h");
    @cInclude("raymath.h");
});

const freetypetest = @cImport({
    @cInclude("freetype-glyph-render.c");
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
            food: XY,
            score: usize,
            highScore: usize,
            dir: Dir,
            foodTexture: raylib.Texture2D,
            screenSize: XY,
        },
        /// state that's only needed for this tick or frame
        tickState: struct {
            shouldAdvanceFrame: bool,
            tickCount: i64,
            didLogThisTick: bool,
            inputDir: [2]Dir,
            bufferedDir: Dir,
            loseCnt: usize,
        },
        drawState: struct {
            snakeTexture: raylib.Texture,
            foodTextures: FoodTextures,
        },
        options: struct {
            gameSize: struct { x: i32, y: i32 },
            isGodMode: bool,
            isTransparent: bool,
            isPaused: bool,
            shouldInterpolate: bool,
            shouldBufferInput: bool,
            shouldShowHitbox: bool,
            isFullScreen: bool,
            tps: u32,
            showFps: bool,
        },
        fn init(screen: XY, snakeTexture: raylib.Texture, foodTextures: FoodTextures) @This() {
            var newGame: Game(maxSize) = .{
                .state = .{
                    .snake = .{
                        .maxLen = maxSize,
                        .len = 1,
                        .segments = undefined,
                    },
                    .food = XY{
                        .x = rand.intRangeAtMost(i32, 0, @divFloor(screen.x, SCALE) - 1),
                        .y = rand.intRangeAtMost(i32, 0, @divFloor(screen.y, SCALE) - 1),
                    },
                    .score = 0,
                    .highScore = 0,
                    .dir = .right,
                    .foodTexture = undefined,
                    .screenSize = screen,
                },
                .options = .{
                    .gameSize = .{ .x = @divFloor(screen.x, SCALE), .y = @divFloor(screen.y, SCALE) },
                    .isGodMode = false,
                    .isTransparent = true,
                    .isPaused = false,
                    .shouldInterpolate = true,
                    .shouldShowHitbox = false,
                    .shouldBufferInput = true,
                    .isFullScreen = false,
                    .tps = 10,
                    .showFps = false,
                },
                .tickState = .{
                    .shouldAdvanceFrame = false,
                    .tickCount = 0,
                    .inputDir = .{ .none, .none },
                    .bufferedDir = .none,
                    .loseCnt = 0,
                    .didLogThisTick = false,
                },
                .drawState = .{
                    .snakeTexture = snakeTexture,
                    .foodTextures = foodTextures,
                },
            };
            // TODO: drawstate
            newGame.state.foodTexture = foodTextures.next();
            for (newGame.state.snake.segments[0..newGame.state.snake.len], 0..) |*seg, i| {
                seg.* = .{ .x = @intCast(newGame.state.snake.len - i), .y = 0 };
            }
            return newGame;
        }
        fn incrementScore(self: *@This()) void {
            self.setScore(self.state.score + 1);
            self.log("score: {}\n", .{self.state.score});
        }
        fn setScore(self: *@This(), score: usize) void {
            self.state.score = score;
            if (self.state.score > self.state.highScore) {
                self.state.highScore = self.state.score;
            }
            var snake = &self.state.snake;
            snake.len = @intCast(self.state.score + 1);
            self.setTps(self.calculateTpsFromScore());

            // FIXME: this is buggy if we increase the snake len by more than
            // one at once, which we don't do yet
            if (snake.len >= 1) snake.segments[snake.len] = snake.segments[snake.len - 1];
            if (snake.len >= 2) snake.segments[snake.len - 1] = snake.segments[snake.len - 2];
        }
        fn setTps(self: *@This(), tps: u32) void {
            if (tps >= 1) {
                self.options.tps = tps;
            } else {
                self.options.tps = 1;
            }
        }
        fn calculateTpsFromScore(self: *@This()) u32 {
            const initialTps = 10; // TODO: put this somewhere else
            const maxTpsPhase1 = 45; // TODO: put this somewhere else
            var newTps: u32 = 0;
            const averageOfScoreAndHighScore = @divFloor(self.state.score + self.state.highScore, 2);
            const scoreForPhase1 = maxTpsPhase1 - initialTps; // 35
            const scoreForPhase2 = 100;
            if (self.state.score <= scoreForPhase1) {
                const maybeNewTps = initialTps + averageOfScoreAndHighScore;
                newTps = @intCast(std.math.clamp(maybeNewTps, initialTps, maxTpsPhase1));
            } else if (self.state.score <= scoreForPhase2) {
                newTps = maxTpsPhase1 + @as(u32, @intCast((averageOfScoreAndHighScore + initialTps) - maxTpsPhase1)) / 4;
            } else {
                newTps = @intCast(averageOfScoreAndHighScore % 100);
            }
            // self.log("tps: {}, score: {}, averageOfScoreAndHighScore: {}, highScore: {}\n", .{ newTps, self.state.score, averageOfScoreAndHighScore, self.state.highScore });
            return newTps;
        }
        fn input(game: *@This()) void {
            var inputDirOffset: u1 = if (game.tickState.inputDir[0] == .none) 0 else 1;
            if (raylib.IsKeyPressed(raylib.KEY_DOWN) or raylib.IsKeyPressed(raylib.KEY_S)) {
                game.tickState.inputDir[inputDirOffset] = .down;
                inputDirOffset = 1;
            }
            if (raylib.IsKeyPressed(raylib.KEY_UP) or raylib.IsKeyPressed(raylib.KEY_W)) {
                game.tickState.inputDir[inputDirOffset] = .up;
                inputDirOffset = 1;
            }
            if (raylib.IsKeyPressed(raylib.KEY_LEFT) or raylib.IsKeyPressed(raylib.KEY_A)) {
                game.tickState.inputDir[inputDirOffset] = .left;
                inputDirOffset = 1;
            }
            if (raylib.IsKeyPressed(raylib.KEY_RIGHT) or raylib.IsKeyPressed(raylib.KEY_D)) {
                game.tickState.inputDir[inputDirOffset] = .right;
                inputDirOffset = 1;
            }

            if (raylib.IsKeyPressed(raylib.KEY_F)) {
                game.toggleFullscreen();
            }

            if (raylib.IsKeyPressed(raylib.KEY_SPACE) or raylib.IsKeyPressed(raylib.KEY_P)) {
                game.options.isPaused = !game.options.isPaused;
            }

            if (raylib.IsKeyPressed(raylib.KEY_R)) {
                game.log("\tdebug: reset\n", .{});
                game.* = Game(maxSize).init(game.state.screenSize, game.drawState.snakeTexture, game.drawState.foodTextures);
            }

            // debug stuff

            game.tickState.shouldAdvanceFrame = raylib.IsKeyPressed(raylib.KEY_N);

            if (raylib.IsKeyPressed(raylib.KEY_I)) game.options.shouldInterpolate = !game.options.shouldInterpolate;

            const isShiftPressed = raylib.IsKeyDown(raylib.KEY_RIGHT_SHIFT) or raylib.IsKeyDown(raylib.KEY_LEFT_SHIFT);
            if (!isShiftPressed and raylib.IsKeyPressed(raylib.KEY_PERIOD)) {
                game.log("\tcheat: add 1 point\n", .{});

                game.incrementScore();
            }
            if (isShiftPressed and raylib.IsKeyPressed(raylib.KEY_PERIOD)) {
                game.log("debug: speed up 🏎️\n", .{});
                game.setTps(game.options.tps + 1);
            }
            if (isShiftPressed and raylib.IsKeyPressed(raylib.KEY_COMMA)) {
                game.log("debug: slow down 🐌\n", .{});
                game.setTps(game.options.tps - 1);
            }

            if (raylib.IsKeyPressed(raylib.KEY_G)) {
                game.log("\tdebug: godmode\n", .{});
                game.options.isGodMode = !game.options.isGodMode;
            }

            if (raylib.IsKeyPressed(raylib.KEY_T)) {
                game.options.isTransparent = !game.options.isTransparent;
            }
            if (raylib.IsKeyPressed(raylib.KEY_H)) {
                game.options.shouldShowHitbox = !game.options.shouldShowHitbox;
            }
            if (raylib.IsKeyPressed(raylib.KEY_B)) {
                game.options.shouldBufferInput = !game.options.shouldBufferInput;
            }

            if (raylib.IsKeyPressed(raylib.KEY_X)) {
                game.log("\tdebug: show fps\n", .{});
                game.options.showFps = !game.options.showFps;
            }

            if (raylib.IsKeyPressed(raylib.KEY_ONE)) {
                std.debug.print("debug: 1tps 🐌\n", .{});
                game.setTps(1);
            }
        }
        fn maybeUpdate(game: *@This(), timeSinceLastUpdateNs: u64) bool {
            if (!raylib.IsWindowFocused()) {
                game.options.isPaused = true;
            }
            if (raylib.IsWindowResized()) {
                game.resizeGameToWindow();
            }

            const dontRunPhysics = (game.options.isPaused and !game.tickState.shouldAdvanceFrame);
            const nanoSecPerTick = std.time.ns_per_s / game.options.tps;
            const isTimeToRunPhysics = timeSinceLastUpdateNs > nanoSecPerTick;
            const willRunPhysics = isTimeToRunPhysics and !dontRunPhysics;
            if (willRunPhysics) {
                game.update(game.drawState.foodTextures);
            }
            // print gamestate while in frame advance mode
            // pro-tip: you can also use this to print the game state whenever
            // you want
            if (game.tickState.shouldAdvanceFrame) {
                game.log("game: {}\nsegments: {any}\n", .{ game, game.state.snake.segments[0..game.state.snake.len] });
            }
            return willRunPhysics;
        }
        fn update(game: *@This(), foodTextures: FoodTextures) void {
            const snake = &game.state.snake;
            game.tickState.loseCnt = 0;
            game.tickState.tickCount += 1;
            game.tickState.didLogThisTick = false;
            defer game.tickState.inputDir = .{ .none, .none };

            const isVert = game.state.dir == .up or game.state.dir == .down;

            const inputDir = game.tickState.inputDir[0];
            const isInputDirOppositeDir = if (isVert) inputDir == .up or inputDir == .down else inputDir == .left or inputDir == .right;
            const bufferedDir = game.tickState.bufferedDir;
            const isBufferedDirOppositeDir = if (isVert) bufferedDir == .up or bufferedDir == .down else bufferedDir == .left or bufferedDir == .right;
            if (inputDir != .none and !isInputDirOppositeDir) {
                game.state.dir = inputDir;
            } else if (bufferedDir != .none and !isBufferedDirOppositeDir) {
                game.state.dir = bufferedDir;
                game.tickState.bufferedDir = .none;
            }

            if (game.tickState.inputDir[1] != .none and game.options.shouldBufferInput) {
                game.tickState.bufferedDir = game.tickState.inputDir[1];
            }

            const dirV: XY = switch (game.state.dir) {
                .up => .{ .x = 0, .y = -1 },
                .down => .{ .x = 0, .y = 1 },
                .left => .{ .x = -1, .y = 0 },
                .right => .{ .x = 1, .y = 0 },
                .none => unreachable(),
            };

            const head = &snake.segments[0];
            var nextHead = head.add(&dirV);
            if (nextHead.x < 0) {
                nextHead.x += game.options.gameSize.x;
                game.setTps(game.options.tps - 1);
            }
            if (nextHead.y < 0) {
                nextHead.y += game.options.gameSize.y;
                game.setTps(game.options.tps - 1);
            }
            if (nextHead.x >= game.options.gameSize.x) {
                nextHead.x -= game.options.gameSize.x;
                game.setTps(game.options.tps - 1);
            }
            if (nextHead.y >= game.options.gameSize.y) {
                nextHead.y -= game.options.gameSize.y;
                game.setTps(game.options.tps - 1);
            }
            if (snake.isTouchingFood(game.state.food)) {
                game.incrementScore();

                game.state.food = .{
                    .x = rand.intRangeAtMost(i32, 0, game.options.gameSize.x - 1),
                    .y = rand.intRangeAtMost(i32, 0, game.options.gameSize.y - 1),
                };
                game.state.foodTexture = foodTextures.next();
            }

            // update snake segments
            {
                var i = snake.len;
                // start from back of snake and work forward
                while (i >= 1) {
                    defer i -= 1;

                    const back = &snake.segments[i];
                    const front = snake.segments[i - 1];

                    back.* = front;
                }
                head.* = nextHead;
            }
            if (snake.isTouchingSelf(nextHead) != 0) {
                game.log("\t💀 touched yourself\n", .{});
                game.tickState.loseCnt = snake.isTouchingSelf(nextHead);
            }
            if (game.tickState.loseCnt != 0) {
                if (!game.options.isGodMode and snake.len >= 2 and game.state.score > 0) {
                    game.setScore(@intCast(game.tickState.loseCnt - 1));
                }
            }
        }
        fn draw(game: *@This(), timeSinceLastUpdateNs: u64) void {
            raylib.BeginDrawing();
            defer raylib.EndDrawing();

            const snake = &game.state.snake;

            if (game.options.isTransparent) {
                raylib.ClearBackground(raylib.Color{ .a = 0x10 });
            } else {
                raylib.ClearBackground(raylib.Color{ .a = 0xF0 });
            }
            raylib.DrawRectangleLinesEx(
                raylib.Rectangle{
                    .x = 0,
                    .y = 0,
                    .width = @floatFromInt(game.state.screenSize.x),
                    .height = @floatFromInt(game.state.screenSize.y),
                },
                3,
                raylib.BLACK,
            );

            if (game.options.isPaused) {
                var textWidth = raylib.MeasureText("PAUSED", 50);
                raylib.DrawText("PAUSED", @divFloor(game.state.screenSize.x, 2) - @divFloor(textWidth, 2), @divFloor(game.state.screenSize.y, 2), 50, raylib.RED);
                textWidth = raylib.MeasureText("Press SPACE to unpause", 20);
                raylib.DrawText("Press SPACE to unpause", @divFloor(game.state.screenSize.x, 2) - @divFloor(textWidth, 2), @divFloor(game.state.screenSize.y, 2) + 50, 20, raylib.RED);
            }

            const foodPos = game.state.food.toScreenCoords(SCALE);
            raylib.DrawTextureV(
                game.state.foodTexture,
                foodPos,
                raylib.WHITE,
            );
            if (game.options.shouldShowHitbox) {
                const foodPosRec: raylib.Rectangle = .{
                    .x = foodPos.x,
                    .y = foodPos.y,
                    .width = SCALE,
                    .height = SCALE,
                };
                raylib.DrawRectangleRec(
                    foodPosRec,
                    raylib.WHITE,
                );
            }
            var score: [3]u8 = undefined;
            const scoreDigits = std.fmt.digits2(game.state.score % 100);
            score[0] = scoreDigits[0];
            score[1] = scoreDigits[1];
            score[2] = 0; // null-terminate
            raylib.DrawText(&score, 10, 3, 69, raylib.PURPLE);
            const shouldDrawHighScore = game.state.score != game.state.highScore;
            if (shouldDrawHighScore) {
                var highScore: [3]u8 = undefined;
                const highScoreDigits = std.fmt.digits2(game.state.highScore % 100);
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
                const ticksPerNanoSec = @as(f32, @floatFromInt(game.options.tps)) / std.time.ns_per_s;
                const nsSinceLastFrame: f32 = @floatFromInt(timeSinceLastUpdateNs);
                const pct = 1 - nsSinceLastFrame * ticksPerNanoSec;
                const pctClamped = std.math.clamp(pct, 0, 1);
                const fps = raylib.GetFPS();
                const isFpsLargerThanTps = fps > game.options.tps;
                var expectedPosition = snake.segments[p + 1];
                const isNextSegmentAcrossWrap = snake.segments[p + 1].sub(&snake.segments[p]).magnitude2() > 2;
                if (isNextSegmentAcrossWrap) {
                    const interpolateHorizAmt = -sign(snake.segments[p + 1].sub(&snake.segments[p]).x);
                    const interpolateVertAmt = -sign(snake.segments[p + 1].sub(&snake.segments[p]).y);
                    expectedPosition.x = snake.segments[p].x + interpolateHorizAmt;
                    expectedPosition.y = snake.segments[p].y + interpolateVertAmt;
                }
                const shouldInterpolate = game.options.shouldInterpolate and isFpsLargerThanTps;
                const interpolatedPosition: raylib.Vector2 = raylib.Vector2Lerp(
                    segScreen,
                    expectedPosition.toScreenCoords(SCALE),
                    if (shouldInterpolate) pctClamped else 0,
                );

                var rotation: f32 = 0;

                const isHead = p == 0;
                const isPrevSegmentAcrossWrap = p > 0 and snake.segments[p].sub(&snake.segments[p - 1]).magnitude2() > 2;
                if (isHead) {
                    const dir = game.state.dir;
                    if (dir == .right) {
                        rotation = 0;
                    } else if (dir == .down) {
                        rotation = 90;
                    } else if (dir == .left) {
                        rotation = 180;
                    } else if (dir == .up) {
                        rotation = 270;
                    }
                } else if (isPrevSegmentAcrossWrap) {
                    const subbed = snake.segments[p - 1].sub(&snake.segments[p]);
                    const wrapDir = .{ .x = sign(subbed.x), .y = sign(subbed.y) };
                    if (wrapDir.x == 1 and wrapDir.y == 0) {
                        rotation = 180;
                    } else if (wrapDir.x == 0 and wrapDir.y == 1) {
                        rotation = 270;
                    } else if (wrapDir.x == -1 and wrapDir.y == 0) {
                        rotation = 0;
                    } else if (wrapDir.x == 0 and wrapDir.y == -1) {
                        rotation = 90;
                    } else {
                        game.log("wrapDir: {}\n", .{wrapDir});
                        unreachable();
                    }
                } else {
                    const prevSeg = &snake.segments[p - 1];
                    const diff = seg.sub(prevSeg);
                    if (diff.x == 1) {
                        rotation = 180;
                    } else if (diff.x == -1) {
                        rotation = 0;
                    } else if (diff.y == 1) {
                        rotation = 270;
                    } else if (diff.y == -1) {
                        rotation = 90;
                    }
                }
                const origin: raylib.Vector2 = if (rotation == 0)
                    .{ .x = 0, .y = 0 }
                else if (rotation == 90)
                    .{ .x = 0, .y = SCALE }
                else if (rotation == 180)
                    .{ .x = SCALE, .y = SCALE }
                else
                    .{ .x = SCALE, .y = 0 };

                const snakeTexture = game.drawState.snakeTexture;
                raylib.DrawTexturePro(
                    snakeTexture,
                    .{ .x = 0, .y = 0, .width = @floatFromInt(snakeTexture.width), .height = @floatFromInt(snakeTexture.height) },
                    .{ .x = interpolatedPosition.x, .y = interpolatedPosition.y, .height = SCALE, .width = SCALE },
                    origin,
                    rotation,
                    color,
                );
                if (game.options.shouldShowHitbox) {
                    raylib.DrawRectanglePro(
                        .{ .x = segScreen.x, .y = segScreen.y, .width = SCALE, .height = SCALE },
                        .{ .x = 0, .y = 0 },
                        0,
                        color,
                    );
                }
            }
            if (game.options.showFps) {
                raylib.DrawFPS(game.state.screenSize.x - 100, 0);
            }
        }
        fn toggleFullscreen(self: *@This()) void {
            self.log("BEFORE: screenSize: {}, gameSize: {}\n", .{ self.state.screenSize, self.options.gameSize });
            defer self.log("AFTER: screenSize: {}, gameSize: {}\n", .{ self.state.screenSize, self.options.gameSize });
            if (self.options.isFullScreen) {
                raylib.RestoreWindow();
            } else {
                raylib.MaximizeWindow();
            }
            self.options.isFullScreen = !self.options.isFullScreen;
            self.resizeGameToWindow();
        }
        fn resizeGameToWindow(self: *@This()) void {
            {
                // HACK: `raylib.GetScreenWidth/Height` won't return the correct values until
                // after a few draws
                // raylib.SetTargetFPS(2400);
                // defer raylib.SetTargetFPS(240);
                for (0..9) |_| {
                    raylib.BeginDrawing();
                    raylib.EndDrawing();
                }
            }
            self.state.screenSize = .{ .x = raylib.GetScreenWidth(), .y = raylib.GetScreenHeight() };
            self.options.gameSize = .{ .x = @divFloor(self.state.screenSize.x, SCALE), .y = @divFloor(self.state.screenSize.y, SCALE) };

            for (self.state.snake.segments[0..self.state.snake.len], 0..) |*seg, i| {
                seg.* = .{ .x = @mod(@as(i32, @intCast(self.state.snake.len - i)), self.options.gameSize.x - 2), .y = @divFloor(@as(i32, @intCast(i)), self.options.gameSize.y - 2) };
            }
            self.state.dir = .right;
            self.tickState.inputDir = .{ .none, .none };
            self.state.food = .{
                .x = rand.intRangeAtMost(i32, 0, self.options.gameSize.x - 1),
                .y = rand.intRangeAtMost(i32, 0, self.options.gameSize.y - 1),
            };
        }
        fn log(self: *@This(), comptime fmt: []const u8, args: anytype) void {
            if (!self.tickState.didLogThisTick) {
                std.debug.print("---------\n", .{});
                self.tickState.didLogThisTick = true;
                std.debug.print("\n**TICK {}\n", .{self.tickState.tickCount});
            }
            std.debug.print("\t", .{});
            std.debug.print(fmt, args);
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
    fn sub(self: *const This, that: *const This) This {
        return .{ .x = self.x - that.x, .y = self.y - that.y };
    }
    fn magnitude2(self: *const This) i32 {
        return self.x * self.x + self.y * self.y;
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
        fn isTouchingFood(self: *const @This(), food: XY) bool {
            return self.segments[0].x == food.x and self.segments[0].y == food.y;
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

const Dir = enum { none, up, down, left, right };

const TextureOffset = struct {
    scale: f32,
    texturePos: raylib.Rectangle,
};

// @@@: There's gotta be a better way to do this
fn FoodTexturesG(texturesCount: usize) type {
    const foodTextures = struct {
        textures: [texturesCount]raylib.Texture2D,
        fn init(foodChars: *const [texturesCount]u32) @This() {
            var self: @This() = undefined;
            for (&self.textures, foodChars) |*food, foodChar| {
                std.debug.print("foodChar: {}\n", .{foodChar});
                const spritesheetImage: raylib.Image = charToImage(foodChar);
                std.debug.assert(spritesheetImage.data != null);
                const spriteSheetTexture = raylib.LoadTextureFromImage(spritesheetImage);
                std.debug.assert(spriteSheetTexture.id != 0);
                food.* = spriteSheetTexture;
            }
            return self;
        }
        fn next(self: *const @This()) raylib.Texture2D {
            return self.textures[rand.intRangeAtMost(u16, 0, texturesCount - 1)];
        }
        fn unload(self: *const @This()) void {
            //raylib.UnloadTexture(self.spriteSheetTexture);
            _ = self;
        }
    };
    return foodTextures;
}
// @@@: There's gotta be a better way to do this
const foodSymbols: [67]u32 = .{
    '🍏', '🍎', '🍐', '🍊', '🍋', '🍌', '🍉', '🍇', '🍓', '🍈', '🍒', '🍑', '🍍', '🥭', '🥥', '🥝', '🍅', '🍆', '🌽', '🥕', '🥔', '🥬', '🥒', '🥦', '🍞', '🥖', '🥯', '🥨', '🥞', '🧇', '🍳', '🍔', '🍟', '🍕', '🌭', '🥗', '🍝', '🍜', '🍲', '🍣', '🍱', '🍤', '🍙', '🍚', '🍛', '🍥', '🍦', '🍧', '🍨', '🍩', '🍪', '🎂', '🍰', '🧁', '🍫', '🍬', '🍭', '🍮', '🍯', '🥛', '☕', '🍵', '🍺', '🍻', '🥂', '🍷', '🥃',
};
const FoodTextures = FoodTexturesG(foodSymbols.len);

fn sign(x: i32) i32 {
    if (x < 0) return -1;
    if (x > 0) return 1;
    return 0;
}

const c = @cImport({
    @cInclude("stdio.h");
    @cInclude("stdlib.h");
    @cInclude("string.h");
});
const FT = @cImport({
    @cInclude("freetype/freetype.h");
    @cInclude("ft2build.h");
    @cInclude("freetype/ftmodapi.h");
    if (builtin.os.tag == .macos) {
        @cInclude("rsvg.c");
    }
});

// Function to save the RGBA buffer as a PPM file (for visualization)
fn save_rgba_to_ppm(filename: [*:0]const u8, buffer: [*]u8, width: c_int, height: c_int) void {
    const fp = c.fopen(filename, "wb");
    if (fp == null) {
        _ = c.printf("Failed to open file for writing: %s\n", filename);
        return;
    }

    // Write PPM header
    _ = c.fprintf(fp, "P6\n%d %d\n255\n", width, height);

    // Write RGB data (ignore alpha)
    var i: c_int = 0;
    while (i < height) : (i += 1) {
        var j: c_int = 0;
        while (j < width) : (j += 1) {
            const idx = @as(usize, @intCast((i * width + j) * 4));
            const r = @as(u8, buffer[idx]);
            const g = @as(u8, buffer[idx + 1]);
            const b = @as(u8, buffer[idx + 2]);

            _ = c.fputc(r, fp);
            _ = c.fputc(g, fp);
            _ = c.fputc(b, fp);
        }
    }

    _ = c.fclose(fp);
    _ = c.printf("Saved output to %s\n", filename);
}

const font_path = switch (builtin.os.tag) {
    .windows => "C:\\Windows\\Fonts\\SEGUIEMJ.TTF",
    .macos => "/System/Library/Fonts/Apple Color Emoji.ttc",
    // TODO: make Noto work
    .linux => "./seguiemj.ttf",
    else => "./seguiemj.ttf",
};
const font = @embedFile(font_path);
pub fn charToImage(character: u32) raylib.Image {
    // Default parameters
    // const size_px: c_int = SCALE;

    // Initialize FreeType
    var library: FT.FT_Library = undefined;
    var erro = FT.FT_Init_FreeType(&library);
    if (erro != 0) {
        _ = c.printf("Failed to initialize FreeType: %d\n", erro);
        std.debug.assert(false);
    }
    if (builtin.os.tag == .macos) {
        erro = FT.FT_Property_Set(library, "ot-svg", "svg-hooks", &FT.rsvg_hooks);
        if (erro != 0) {
            _ = c.printf("Failed to add svg hooks: %d(%s)\n", erro, FT.FT_Error_String(erro));
            //std.debug.assert(false);
        }
    }

    // idea: return a struct with a cleanup method that calls FT_Done_Face and FT_Done_FreeType
    //defer std.debug.assert(FT.FT_Done_FreeType(library) == 0);

    // Load font face
    var face: FT.FT_Face = undefined;
    erro = FT.FT_Open_Face(library, &.{
        .flags = FT.FT_OPEN_MEMORY,
        .memory_base = font.ptr,
        .memory_size = font.len,
    }, 0, &face);
    if (erro != 0) {
        _ = c.printf("Failed to load font: %d(%s)\n", erro, FT.FT_Error_String(erro));
        std.debug.assert(false);
    }

    var i: usize = 0;
    while (i < face.*.num_fixed_sizes) {
        defer i += 1;
        const size: FT.FT_Bitmap_Size = face.*.available_sizes[i];
        std.debug.print("Size: {}: width = {}, height = {}, x_ppem = {}, y_ppem = {}\n", .{ i, size.width, size.height, size.x_ppem, size.y_ppem });
    }
    //defer std.debug.assert(FT.FT_Done_Face(face) == 0);

    // Get glyph index
    const glyph_index = FT.FT_Get_Char_Index(face, character);
    if (glyph_index == 0) {
        _ = c.printf("Character not found in font\n");
        _ = FT.FT_Done_Face(face);
        _ = FT.FT_Done_FreeType(library);
        std.debug.assert(false);
    }

    // Set font size
    erro = FT.FT_Set_Pixel_Sizes(face, 0, 52);
    if (erro != 0) {
        _ = c.printf("Failed to set font size: %d(%s)\n", erro, FT.FT_Error_String(erro));
        std.debug.assert(false);
    }

    // Load and render the glyph
    erro = FT.FT_Load_Glyph(face, glyph_index, FT.FT_LOAD_COLOR);
    if (erro != 0) {
        _ = c.printf("Failed to load glyph: %d(%s)\n", erro, FT.FT_Error_String(erro));
        std.debug.assert(false);
    }

    // Render the glyph to a bitmap with anti-aliasing
    erro = FT.FT_Render_Glyph(face.*.glyph, FT.FT_RENDER_MODE_NORMAL);
    if (erro != 0) {
        _ = c.printf("Failed to render glyph: %d(%s)\n", erro, FT.FT_Error_String(erro));
        std.debug.assert(erro == 0);
    }
    const bitmap = face.*.glyph.*.bitmap;

    // BGRA -> RGBA
    i = 0;
    while (i < bitmap.width * bitmap.rows * 4) : (i += 4) {
        const r: u8 = bitmap.buffer[i];
        bitmap.buffer[i] = bitmap.buffer[i + 2];
        bitmap.buffer[i + 2] = r;
    }

    var result: raylib.Image = undefined;
    result.width = @intCast(bitmap.width);
    result.height = @intCast(bitmap.rows);
    result.mipmaps = 1;
    result.data = bitmap.buffer;
    result.format = raylib.PIXELFORMAT_UNCOMPRESSED_R8G8B8A8;
    return result;
}

const SCALE = 50;
pub fn main() !void {
    raylib.SetConfigFlags(raylib.FLAG_WINDOW_TRANSPARENT | raylib.FLAG_WINDOW_RESIZABLE);
    raylib.InitWindow(1280, 800, "snek");
    defer raylib.CloseWindow();
    std.debug.assert(raylib.IsWindowReady());

    const initialScreen: XY = .{ .x = raylib.GetScreenWidth(), .y = raylib.GetScreenHeight() };

    const foodTextures = FoodTextures.init(&foodSymbols);
    defer foodTextures.unload();

    raylib.SetTargetFPS(2 * raylib.GetMonitorRefreshRate(raylib.GetCurrentMonitor()));

    var snakeImage = charToImage('🐍');
    std.debug.assert(snakeImage.data != null);
    raylib.ImageFlipHorizontal(&snakeImage);
    const snakeTexture = raylib.LoadTextureFromImage(snakeImage);
    raylib.SetWindowIcon(snakeImage);
    std.debug.assert(snakeTexture.id != 0);
    std.debug.print("snakeTexture: {}\n", .{snakeTexture});
    // std.debug.assert(snakeTexture.width == snakeTexture.height);

    // TODO: don't hardcode game size
    var game = Game(1 << 15).init(initialScreen, snakeTexture, foodTextures);
    defer game.log("{}\n", .{game});

    var timeWhenLastUpdated = try std.time.Instant.now();

    while (!raylib.WindowShouldClose()) {

        // INPUT
        game.input();

        // UPDATE
        const now = try std.time.Instant.now();
        var timeSinceLastUpdate = now.since(timeWhenLastUpdated);
        const didUpdate = game.maybeUpdate(timeSinceLastUpdate);
        if (didUpdate) {
            timeWhenLastUpdated = now;
            timeSinceLastUpdate = 0;
        }
        // DRAW
        game.draw(timeSinceLastUpdate);
    }
}

// ideas:
// slower
// always on top
// click through
