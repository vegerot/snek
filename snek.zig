const std = @import("std");
const rand = std.crypto.random;

const raylib = @cImport({
    @cInclude("raylib.h");
    @cInclude("raymath.h");
});

const spriteSheetPng = @embedFile("./emoji.png");
const snekPng = @embedFile("./🐍.png");

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
            foodTextureOffset: TextureOffset,
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
            wasWindowFocusedLastFrame: bool,
        },
        drawState: struct {
            snakeTexture: raylib.Texture,
            foodTextures: FoodTextures,
            currentMonitor: i8,
            frameTimes: [1000]f32,
            frameTimeIndex: usize,
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
                    .foodTextureOffset = .{ .scale = SCALE, .texturePos = undefined },
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
                    .wasWindowFocusedLastFrame = true,
                },
                .drawState = .{
                    .snakeTexture = snakeTexture,
                    .foodTextures = foodTextures,
                    .currentMonitor = @intCast(raylib.GetCurrentMonitor()),
                    .frameTimes = std.mem.zeroes([1000]f32),
                    .frameTimeIndex = 0,
                },
            };
            newGame.state.foodTextureOffset = foodTextures.next();
            // note: even though the initial length is 1, I initialize the first TWO positions because they're needed for interpolation
            newGame.state.snake.segments[0] = .{ .x = 1, .y = 0 };
            newGame.state.snake.segments[1] = .{ .x = 0, .y = 0 };
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
            if (raylib.IsWindowResized()) {
                game.resizeGameToWindow();
            }

            const currentMonitor: i8 = @intCast(raylib.GetCurrentMonitor());
            if (currentMonitor != game.drawState.currentMonitor) {
                game.drawState.currentMonitor = currentMonitor;
                raylib.SetTargetFPS(2 * raylib.GetMonitorRefreshRate(currentMonitor));
            }

            if (game.tickState.wasWindowFocusedLastFrame != raylib.IsWindowFocused()) {
                game.log("focus state changed\n", .{});
                if (raylib.IsWindowFocused()) {
                    game.options.isPaused = false;
                    raylib.SetTargetFPS(2 * raylib.GetMonitorRefreshRate(currentMonitor));
                } else {
                    game.options.isPaused = true;
                    raylib.SetTargetFPS(1);
                }
                game.tickState.wasWindowFocusedLastFrame = raylib.IsWindowFocused();
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
                .none => game.Unreachable(),
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
                game.state.foodTextureOffset = foodTextures.next();
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
            const foodPosRec: raylib.Rectangle = .{
                .x = foodPos.x,
                .y = foodPos.y,
                .width = game.state.foodTextureOffset.scale,
                .height = game.state.foodTextureOffset.scale,
            };
            raylib.DrawTexturePro(
                game.drawState.foodTextures.spriteSheetTexture,
                game.state.foodTextureOffset.texturePos,
                foodPosRec,
                .{},
                0,
                raylib.WHITE,
            );
            if (game.options.shouldShowHitbox) {
                raylib.DrawRectangleRec(
                    foodPosRec,
                    raylib.WHITE,
                );
            }
            const scoreDigits = scoreToString(game.state.score);
            raylib.DrawText(&scoreDigits, 10, 3, 69, raylib.PURPLE);
            const shouldDrawHighScore = game.state.score != game.state.highScore;
            if (shouldDrawHighScore) {
                const highScore = scoreToString(game.state.highScore);
                raylib.DrawText(&highScore, 10, 75, 33, raylib.BLUE);
            }

            const COLORS = comptime makeTransColors();
            for (snake.segments[0..snake.len], 0..) |seg, p| {
                const segScreen = seg.toScreenCoords(SCALE);
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
                const shouldInterpolate = game.options.shouldInterpolate and isFpsLargerThanTps and !game.options.isPaused;
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
                        game.Unreachable();
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
                const p99Fps = game.calculateP99Fps();
                raylib.DrawFPS(game.state.screenSize.x - 100, 0);

                // Draw P99 FPS in top-right corner
                var p99Buffer: [20]u8 = undefined;
                const p99Text = std.fmt.bufPrint(&p99Buffer, "P99: {d:.1} FPS", .{p99Fps}) catch "P99: N/A";
                raylib.DrawText(p99Text.ptr, game.state.screenSize.x - 100, 50, 20, raylib.RED);

                const tpsChars = std.fmt.digits2(@intCast(game.options.tps));
                var tpsString: [7]u8 = .{ tpsChars[0], tpsChars[1], ' ', 't', 'p', 's', 0 };
                raylib.DrawText(&tpsString, game.state.screenSize.x - 80, 30, 22, raylib.BLUE);

                // Draw FPS chart in top-right corner
                const chartWidth: i32 = 200;
                const chartHeight: i32 = 60;
                const chartX = game.state.screenSize.x - chartWidth - 32;
                const chartY = 80;

                // Draw chart background
                raylib.DrawRectangle(chartX, chartY, chartWidth, chartHeight, raylib.Color{ .r = 0, .g = 0, .b = 0, .a = 100 });
                raylib.DrawRectangleLines(chartX, chartY, chartWidth, chartHeight, raylib.DARKGRAY);

                // Draw chart title
                raylib.DrawText("FPS", chartX + 5, chartY + 5, 10, raylib.WHITE);

                // Draw FPS data
                const maxSamples = @min(chartWidth, @as(i32, @intCast(game.drawState.frameTimes.len)));
                var minFps: f32 = 1000.0; // Start with a high value
                var maxFps: f32 = 0.0; // Start with a low value

                // Find min/max FPS for scaling
                for (0..@intCast(maxSamples)) |i| {
                    const idx = (game.drawState.frameTimeIndex + game.drawState.frameTimes.len - i - 1) % game.drawState.frameTimes.len;
                    const frameTime = game.drawState.frameTimes[idx];
                    if (frameTime > 0.0001) { // Avoid division by zero or very small values
                        const fps = 1.0 / frameTime;
                        if (fps < minFps) minFps = fps;
                        if (fps > maxFps) maxFps = fps;
                    }
                }

                // Ensure reasonable min/max values
                if (maxFps < 30.0) maxFps = 30.0;
                if (minFps > maxFps - 10.0) minFps = @max(0.0, maxFps - 30.0);

                // Draw horizontal lines (FPS scale)
                const scaleLines = 4;
                for (0..scaleLines) |i| {
                    const y = chartY + chartHeight - @as(i32, @intCast(i)) * (chartHeight / scaleLines);
                    const alpha: u8 = if (i == 0) 200 else 100;
                    raylib.DrawLine(chartX, y, chartX + chartWidth, y, raylib.Color{ .r = 200, .g = 200, .b = 200, .a = alpha });

                    // Draw scale labels
                    var scaleBuffer: [10]u8 = .{0} ** 10;
                    const fpsValue = minFps + (maxFps - minFps) * @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(scaleLines - 1));
                    const scaleText = std.fmt.bufPrint(&scaleBuffer, "{d:.1}", .{fpsValue}) catch "?";
                    raylib.DrawText(scaleText.ptr, chartX + chartWidth + 2, y - 5, 10, raylib.LIGHTGRAY);
                }

                // Draw FPS graph
                for (0..@intCast(maxSamples - 1)) |i| {
                    const idx1 = (game.drawState.frameTimeIndex + game.drawState.frameTimes.len - i - 1) % game.drawState.frameTimes.len;
                    const idx2 = (game.drawState.frameTimeIndex + game.drawState.frameTimes.len - i - 2) % game.drawState.frameTimes.len;

                    const frameTime1 = game.drawState.frameTimes[idx1];
                    const frameTime2 = game.drawState.frameTimes[idx2];

                    const fps1 = if (frameTime1 > 0.0001) 1.0 / frameTime1 else 0.0;
                    const fps2 = if (frameTime2 > 0.0001) 1.0 / frameTime2 else 0.0;

                    const x1 = chartX + chartWidth - @as(i32, @intCast(i));
                    const x2 = chartX + chartWidth - @as(i32, @intCast(i + 1));

                    // Calculate y position based on FPS value (higher FPS = higher on chart)
                    const normalizedFps1 = (fps1 - minFps) / (maxFps - minFps);
                    const normalizedFps2 = (fps2 - minFps) / (maxFps - minFps);

                    const y1 = chartY + chartHeight - @as(i32, @intFromFloat(normalizedFps1 * @as(f32, @floatFromInt(chartHeight))));
                    const y2 = chartY + chartHeight - @as(i32, @intFromFloat(normalizedFps2 * @as(f32, @floatFromInt(chartHeight))));

                    // Color based on FPS (green for high, yellow for medium, red for low)
                    const threshold1 = 60.0; // 60 FPS
                    const threshold2 = 30.0; // 30 FPS
                    const lineColor = if (fps1 >= threshold1)
                        raylib.GREEN
                    else if (fps1 >= threshold2)
                        raylib.YELLOW
                    else
                        raylib.RED;

                    raylib.DrawLine(x1, y1, x2, y2, lineColor);
                }
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
        fn calculateP99Fps(self: *@This()) f32 {
            self.drawState.frameTimes[self.drawState.frameTimeIndex] = raylib.GetFrameTime();
            self.drawState.frameTimeIndex = (self.drawState.frameTimeIndex + 1) % self.drawState.frameTimes.len;

            // make sure to copy frameTimes so we can sort them
            var sortedTimes = self.drawState.frameTimes;
            std.mem.sort(f32, &sortedTimes, {}, std.sort.asc(f32));

            const p99Index = @divFloor(99 * sortedTimes.len, 100);
            return 1 / sortedTimes[p99Index];
        }
        fn Unreachable(self: *@This()) noreturn {
            self.log("game: {}\nsegments: {any}\n", .{ self, self.state.snake.segments[0..self.state.snake.len] });
            unreachable();
        }
    };
    return game;
}

fn scoreToString(score: usize) [3:0]u8 {
    var ret = [3:0]u8{ 0, 0, 0 };
    std.debug.assert(score < 1000);

    const scoreAsU8: u8 = @intCast(score);

    const ones = scoreAsU8 % 10;
    const tens = (scoreAsU8 / 10) % 10;
    const hundreds = (scoreAsU8 / (10 * 10)) % 10;
    const scoreDigits: [3]u8 = .{ hundreds, tens, ones };
    var startIdx: usize = if (scoreDigits[0] != 0) 0 else if (scoreDigits[1] != 0) 1 else 2;
    var i: usize = 0;
    while (startIdx < scoreDigits.len) {
        defer startIdx += 1;
        defer i += 1;
        ret[i] = scoreDigits[startIdx] + '0';
    }

    return ret;
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

const FoodTextures = struct {
    const texturesCount = 67;
    spriteSheetTexture: raylib.Texture2D,
    textures: [texturesCount]TextureOffset,
    fn generateFoods() !FoodTextures {
        const spritesheetImage = raylib.LoadImageFromMemory(".png", spriteSheetPng, spriteSheetPng.len);
        std.debug.assert(spritesheetImage.data != null);
        const spriteSheetTexture = raylib.LoadTextureFromImage(spritesheetImage);
        const avgHeight = 96; //px
        const avgWidth = 96; // px
        // // height=96px, average width=954px/10=95
        // const textureCount = 10;
        var self: @This() = .{ .spriteSheetTexture = spriteSheetTexture, .textures = undefined };
        for (&self.textures, 0..) |*food, i| {
            const fi: f32 = @floatFromInt(i);
            food.*.texturePos = .{
                .x = fi * avgWidth,
                .y = 0,
                .width = avgWidth,
                .height = avgHeight,
            };
            food.*.scale = SCALE;
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

fn sign(x: i32) i32 {
    if (x < 0) return -1;
    if (x > 0) return 1;
    return 0;
}

const SCALE = 50;
pub fn main() !void {
    raylib.SetConfigFlags(raylib.FLAG_WINDOW_TRANSPARENT | raylib.FLAG_WINDOW_RESIZABLE);
    // Setting high DPI breaks resizing.  See https://github.com/raysan5/raylib/issues/4908
    // raylib.SetConfigFlags(raylib.FLAG_WINDOW_HIGHDPI);
    raylib.InitWindow(1280, 800, "snek");
    defer raylib.CloseWindow();
    std.debug.assert(raylib.IsWindowReady());

    const initialScreen: XY = .{ .x = raylib.GetScreenWidth(), .y = raylib.GetScreenHeight() };

    const foodTextures = try FoodTextures.generateFoods();
    defer foodTextures.unload();

    var snakeImage = raylib.LoadImageFromMemory(".png", snekPng, snekPng.len);
    std.debug.assert(snakeImage.data != null);
    raylib.ImageFlipHorizontal(&snakeImage);
    const snakeTexture = raylib.LoadTextureFromImage(snakeImage);
    raylib.SetWindowIcon(snakeImage);
    std.debug.assert(snakeTexture.id != 0);
    std.debug.assert(snakeTexture.width == snakeTexture.height);

    // TODO: don't hardcode game size
    var game = Game(1 << 15).init(initialScreen, snakeTexture, foodTextures);
    defer game.log("{}\n", .{game});

    raylib.SetTargetFPS(2 * raylib.GetMonitorRefreshRate(game.drawState.currentMonitor));

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
