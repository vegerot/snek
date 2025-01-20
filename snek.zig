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
    _data: @Vector(2, i32),
    fn init(X: i32, Y: i32) XY {
        return XY{ ._data = @Vector(2, i32){ X, Y } };
    }
    fn vec(self: *const @This()) @Vector(2, i32) {
        return self.*._data;
    }
    fn x(self: *@This()) i32 {
        return self.*._data[0];
    }
    fn y(self: *@This()) i32 {
        return self.*._data[1];
    }
    fn toScreenCoords(self: *@This(), scale: i32) raylib.Vector2 {
        return raylib.Vector2{ .x = @floatFromInt(self.x() * scale), .y = @floatFromInt(self.y() * scale) };
    }
};
fn Snake(maxSize: u32) type {
    const snake = struct {
        // TODO: make this a rope / linked list thingy
        segments: [maxSize]XY,
        len: u16,
        maxLen: u32,
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
    raylib.SetTargetFPS(24);

    var game: Game(20) = .{
        .snake = .{
            .maxLen = 20,
            .len = 10,
            .segments = undefined,
        },
        .fruit = XY.init(0, 1),
    };
    for (game.snake.segments[0..game.snake.len], 0..) |*seg, i| {
        seg.* = XY.init(@intCast(game.snake.len - i), 0);
    }
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

        if (raylib.IsKeyPressed(raylib.KEY_SPACE)) {
            game.snake.len += 1;
            game.snake.segments[game.snake.len] = game.snake.segments[game.snake.len - 1];
        }
        const dirV: XY = switch (dir) {
            .up => XY.init(0, -1),
            .down => XY.init(0, 1),
            .left => XY.init(-1, 0),
            .right => XY.init(1, 0),
        };

        const SCALE = 50;
        const head = &game.snake.segments[0];
        const maybeNextHead = head.vec() + dirV.vec();
        const isNextHeadInBounds = maybeNextHead[0] >= 0 and maybeNextHead[0] < screen.x / SCALE and maybeNextHead[1] >= 0 and maybeNextHead[1] < screen.y / SCALE;
        if (isNextHeadInBounds) {
            var i = game.snake.len;
            // start from back of snake and work forward
            while (i > 1) {
                i -= 1;

                const back = &game.snake.segments[i];
                const front = game.snake.segments[i - 1];

                back.* = front;
            }
            head.* = XY.init(maybeNextHead[0], maybeNextHead[1]);
            std.debug.print("\tSNAKE: {any}\n", .{game.snake.segments});
        } else {
            std.debug.print("\twall\n", .{});
        }
        // DRAW
        raylib.BeginDrawing();
        defer raylib.EndDrawing();
        raylib.ClearBackground(raylib.BLACK);

        const fruitPos = game.fruit.toScreenCoords(SCALE);
        raylib.DrawRectangleRec(raylib.Rectangle{ .x = fruitPos.x, .y = fruitPos.y }, raylib.GREEN);
        for (game.snake.segments[0..game.snake.len], 0..) |seg, p| {
            const snake_seg_size: raylib.Vector2 = .{ .x = SCALE, .y = SCALE };
            const segScreen = seg.toScreenCoords(SCALE);
            const segrec = raylib.Rectangle{
                .x = segScreen.x,
                .y = segScreen.y,
                .width = snake_seg_size.x,
                .height = snake_seg_size.y,
            };
            raylib.DrawRectangleRec(segrec, if (p % 2 == 0) raylib.RED else raylib.BLUE);
        }
    }
}
