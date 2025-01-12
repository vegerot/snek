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

fn Game(size: u32) type {
    const game = struct {
        snake: Snake(size),
    };
    return game;
}

fn Snake(size: u32) type {
    const snake = struct {
        // TODO: make this a rope / linked list thingy
        positions: [size]raylib.Vector2,
        len: u16,
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
    raylib.SetTargetFPS(2);

    var game: Game(4) = .{ .snake = .{ .len = 4, .positions = undefined } };
    for (game.snake.positions[0..game.snake.len], 0..) |*pos, i| {
        pos.* = .{ .x = @floatFromInt(10 * (game.snake.len - i)), .y = @floatFromInt(0) };
    }
    const snake_rec_size: raylib.Vector2 = .{ .x = 10, .y = 10 };
    const speed = 50;
    var dir: Dir = .right;
    while (!raylib.WindowShouldClose()) {
        // UPDATE

        // / input
        if (raylib.IsKeyDown(raylib.KEY_DOWN)) {
            dir = .down;
            std.debug.print("DOWN: \n", .{});
        } else if (raylib.IsKeyDown(raylib.KEY_UP)) {
            dir = .up;
        } else if (raylib.IsKeyDown(raylib.KEY_LEFT)) {
            dir = .left;
        } else if (raylib.IsKeyDown(raylib.KEY_RIGHT)) {
            dir = .right;
        }

        std.debug.print("**all***: {any}\n", .{game.snake.positions});
        const dt = raylib.GetFrameTime();
        var i = game.snake.len;
        while (i > 1) {
            i -= 1;

            const curr = &game.snake.positions[i];
            const prev = game.snake.positions[i - 1];
            const diff = raylib.Vector2Subtract(prev, curr.*);
            const v: raylib.Vector2 = if (diff.x > 0) dist: {
                break :dist .{
                    .x = speed,
                    .y = 0,
                };
            } else if (diff.x < 0) .{
                .x = -speed,
                .y = 0,
            } else if (diff.y > 0) .{
                .x = 0,
                .y = speed,
            } else .{
                .x = 0,
                .y = -speed,
            };
            const distanceMoved: raylib.Vector2 = .{ .x = v.x * dt, .y = v.y * dt };
            curr.* = raylib.Vector2Add(curr.*, distanceMoved);
            std.debug.print("diff: {}, distancedMoved: {}, curr: {}\n", .{ diff, distanceMoved, curr });
        }
        const v: raylib.Vector2 = switch (dir) {
            .left => .{ .x = -speed, .y = 0 },
            .right => .{ .x = speed, .y = 0 },
            .up => .{ .x = 0, .y = -speed },
            .down => .{ .x = 0, .y = speed },
        };
        const distanceMoved: raylib.Vector2 = .{ .x = v.x * dt, .y = v.y * dt };
        game.snake.positions[0] = raylib.Vector2Add(game.snake.positions[0], distanceMoved);
        // DRAW
        raylib.BeginDrawing();
        defer raylib.EndDrawing();
        raylib.ClearBackground(raylib.BLACK);

        for (game.snake.positions[0..game.snake.len]) |pos| {
            raylib.DrawRectangleV(pos, snake_rec_size, raylib.GREEN);
        }
    }
}
