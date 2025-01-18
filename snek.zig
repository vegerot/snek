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
    };
    return game;
}

fn Snake(size: u32) type {
    const snake = struct {
        // TODO: make this a rope / linked list thingy
        segments: [size]raylib.Vector2,
        len: u16,
    };
    return snake;
}

const Dir = enum { up, down, left, right };

pub fn main() void {
    // raylib.SetConfigFlags(raylib.FLAG_WINDOW_TRANSPARENT);
    const screen: raylib.Vector2 = .{ .x = 1600, .y = 900 };
    raylib.InitWindow(screen.x, screen.y, "snek");
    defer raylib.CloseWindow();
    raylib.SetTargetFPS(raylib.GetMonitorRefreshRate(raylib.GetCurrentMonitor()));
    raylib.SetTargetFPS(2);

    var game: Game(20) = .{ .snake = .{ .len = 10, .segments = undefined } };
    for (game.snake.segments[0..game.snake.len], 0..) |*seg, i| {
        seg.* = .{ .x = @floatFromInt(100 * (game.snake.len - i)), .y = @floatFromInt(0) };
    }
    const snake_seg_size: raylib.Vector2 = .{ .x = 100, .y = 100 };
    const speed = 200;
    var dir: Dir = .right;
    var f: i32 = 0;
    while (!raylib.WindowShouldClose()) {
        // UPDATE
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

        const dt = 1; //raylib.GetFrameTime();
        var i = game.snake.len;
        while (i > 1) {
            i -= 1;

            const tail = &game.snake.segments[i];
            const head = game.snake.segments[i - 1];
            std.debug.print("\thead: {any}, tail: {any}\n", .{ head, tail.* });
            const diff = raylib.Vector2Subtract(head, tail.*);
            if (diff.x != 0 and diff.y != 0) {
                std.debug.print("\t😠fuck\n", .{});
            }
            const v = raylib.Vector2Scale(raylib.Vector2Normalize(diff), speed);
            const distanceMoved: raylib.Vector2 = .{ .x = v.x * dt, .y = v.y * dt };
            tail.* = raylib.Vector2Add(tail.*, distanceMoved);
            std.debug.print("\t**head***: {any}, tail: {any}\n", .{ head, tail });
            std.debug.print("\tdiff.x: {d}, diff.y: {d}\n\tdistancedMoved: {}, newcurr: {}\n", .{ diff.x, diff.y, distanceMoved, tail });
        }
        {
            const v: raylib.Vector2 = switch (dir) {
                .left => .{ .x = -speed, .y = 0 },
                .right => .{ .x = speed, .y = 0 },
                .up => .{ .x = 0, .y = -speed },
                .down => .{ .x = 0, .y = speed },
            };
            const distanceMoved: raylib.Vector2 = .{ .x = v.x * dt, .y = v.y * dt };
            game.snake.segments[0] = raylib.Vector2Add(game.snake.segments[0], distanceMoved);
        }

        // DRAW
        raylib.BeginDrawing();
        defer raylib.EndDrawing();
        raylib.ClearBackground(raylib.BLACK);

        for (game.snake.segments[0..game.snake.len], 0..) |pos, p| {
            const pp: u8 = @intCast(p);
            const segment_rectangle = raylib.Rectangle{ .x = pos.x, .y = pos.y, .width = snake_seg_size.x, .height = snake_seg_size.y };
            raylib.DrawRectangleLinesEx(segment_rectangle, 5, raylib.Color{ .r = std.math.pow(u8, pp, 2) % 0x99, .g = (pp * 2 + 0x49) % 0x99, .b = ((0x99 - pp) * (pp % 2)) % 0x99, .a = 0x99 });
        }
    }
}
