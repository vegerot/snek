const std = @import("std");
const rand = std.crypto.random;

// Minimal structures needed for benchmarking (avoiding raylib dependencies)
const XY = struct {
    x: i32,
    y: i32,
    const This = @This();
    
    fn add(self: *const This, that: *const This) This {
        return .{ .x = self.x + that.x, .y = self.y + that.y };
    }
    
    fn isEqual(this: This, that: This) bool {
        return this.x == that.x and this.y == that.y;
    }
};

fn Snake(maxSize: u32) type {
    const snake = struct {
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

fn BenchmarkGame(maxSize: u32) type {
    const game = struct {
        snake: Snake(maxSize),
        food: XY,
        score: usize,
        dir: Dir,
        gameSize: struct { x: i32, y: i32 },
        
        fn init(gameWidth: i32, gameHeight: i32) @This() {
            var newGame: @This() = .{
                .snake = .{
                    .maxLen = maxSize,
                    .len = 1,
                    .segments = undefined,
                },
                .food = .{
                    .x = rand.intRangeAtMost(i32, 0, gameWidth - 1),
                    .y = rand.intRangeAtMost(i32, 0, gameHeight - 1),
                },
                .score = 0,
                .dir = .right,
                .gameSize = .{ .x = gameWidth, .y = gameHeight },
            };
            // Initialize snake at center
            newGame.snake.segments[0] = .{ .x = @divFloor(gameWidth, 2), .y = @divFloor(gameHeight, 2) };
            return newGame;
        }
        
        fn update(self: *@This()) bool {
            const dirV: XY = switch (self.dir) {
                .up => .{ .x = 0, .y = -1 },
                .down => .{ .x = 0, .y = 1 },
                .left => .{ .x = -1, .y = 0 },
                .right => .{ .x = 1, .y = 0 },
                .none => return false, // Invalid state
            };

            const head = &self.snake.segments[0];
            var nextHead = head.add(&dirV);
            
            // Wrap around boundaries
            if (nextHead.x < 0) nextHead.x += self.gameSize.x;
            if (nextHead.y < 0) nextHead.y += self.gameSize.y;
            if (nextHead.x >= self.gameSize.x) nextHead.x -= self.gameSize.x;
            if (nextHead.y >= self.gameSize.y) nextHead.y -= self.gameSize.y;
            
            // Check if touching food
            if (self.snake.isTouchingFood(self.food)) {
                self.score += 1;
                self.snake.len = @intCast(self.score + 1);
                
                // Generate new food
                self.food = .{
                    .x = rand.intRangeAtMost(i32, 0, self.gameSize.x - 1),
                    .y = rand.intRangeAtMost(i32, 0, self.gameSize.y - 1),
                };
            }

            // Update snake segments (move body)
            var i = self.snake.len;
            while (i >= 1) {
                defer i -= 1;
                const back = &self.snake.segments[i];
                const front = self.snake.segments[i - 1];
                back.* = front;
            }
            head.* = nextHead;
            
            // Check self collision
            return self.snake.isTouchingSelf(nextHead) == 0; // Return true if still alive
        }
        
        fn setDirection(self: *@This(), newDir: Dir) void {
            // Prevent immediate reversal
            const isVert = self.dir == .up or self.dir == .down;
            const isInputDirOppositeDir = if (isVert) 
                newDir == .up or newDir == .down 
            else 
                newDir == .left or newDir == .right;
            
            if (!isInputDirOppositeDir) {
                self.dir = newDir;
            }
        }
    };
    return game;
}

// Benchmark functions
fn benchmarkSnakeMovement(allocator: std.mem.Allocator) !u64 {
    const iterations = 100_000;
    var game = BenchmarkGame(1000).init(40, 30);
    
    const start = std.time.nanoTimestamp();
    
    for (0..iterations) |_| {
        if (!game.update()) {
            // Game over, restart
            game = BenchmarkGame(1000).init(40, 30);
        }
    }
    
    const end = std.time.nanoTimestamp();
    _ = allocator; // unused but kept for consistency
    return @intCast(end - start);
}

fn benchmarkCollisionDetection(allocator: std.mem.Allocator) !u64 {
    const iterations = 1_000_000;
    var game = BenchmarkGame(1000).init(40, 30);
    
    // Grow snake to reasonable size for collision testing
    game.snake.len = 50;
    for (0..50) |i| {
        game.snake.segments[i] = .{ .x = @intCast(i % 40), .y = @intCast(@divFloor(i, 40)) };
    }
    
    const start = std.time.nanoTimestamp();
    
    var collisions: u64 = 0;
    for (0..iterations) |i| {
        const testPoint = XY{ .x = @intCast(i % 40), .y = @intCast(@divFloor(i, 40) % 30) };
        collisions += game.snake.isTouchingSelf(testPoint);
    }
    
    const end = std.time.nanoTimestamp();
    _ = allocator; // unused but kept for consistency
    _ = collisions; // Prevent optimization
    return @intCast(end - start);
}

fn benchmarkFoodGeneration(allocator: std.mem.Allocator) !u64 {
    const iterations = 1_000_000;
    
    const start = std.time.nanoTimestamp();
    
    var total: i64 = 0;
    for (0..iterations) |_| {
        const food = XY{
            .x = rand.intRangeAtMost(i32, 0, 39),
            .y = rand.intRangeAtMost(i32, 0, 29),
        };
        total += food.x + food.y;
    }
    
    const end = std.time.nanoTimestamp();
    _ = allocator; // unused but kept for consistency
    _ = total; // Prevent optimization
    return @intCast(end - start);
}

fn benchmarkCompleteGameSimulation(allocator: std.mem.Allocator) !u64 {
    const max_ticks = 10_000;
    var game = BenchmarkGame(1000).init(40, 30);
    
    const start = std.time.nanoTimestamp();
    
    var tick: u32 = 0;
    while (tick < max_ticks) {
        defer tick += 1;
        
        // Simulate some basic AI movement (turn randomly occasionally)
        if (tick % 100 == 0) {
            const directions = [_]Dir{ .up, .down, .left, .right };
            game.setDirection(directions[rand.intRangeAtMost(usize, 0, 3)]);
        }
        
        if (!game.update()) {
            // Game over, record and restart
            game = BenchmarkGame(1000).init(40, 30);
        }
    }
    
    const end = std.time.nanoTimestamp();
    _ = allocator; // unused but kept for consistency
    return @intCast(end - start);
}

// Benchmark runner
const Benchmark = struct {
    name: []const u8,
    func: *const fn (std.mem.Allocator) anyerror!u64,
};

const benchmarks = [_]Benchmark{
    .{ .name = "Snake Movement", .func = benchmarkSnakeMovement },
    .{ .name = "Collision Detection", .func = benchmarkCollisionDetection },
    .{ .name = "Food Generation", .func = benchmarkFoodGeneration },
    .{ .name = "Complete Game Simulation", .func = benchmarkCompleteGameSimulation },
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    std.debug.print("🐍 Snek Benchmark Suite\n");
    std.debug.print("========================\n\n");
    
    for (benchmarks) |benchmark| {
        std.debug.print("Running {s}...\n", .{benchmark.name});
        
        // Run benchmark multiple times and take average
        const runs = 5;
        var total_time: u64 = 0;
        var min_time: u64 = std.math.maxInt(u64);
        var max_time: u64 = 0;
        
        for (0..runs) |run| {
            const time = try benchmark.func(allocator);
            total_time += time;
            min_time = @min(min_time, time);
            max_time = @max(max_time, time);
            
            std.debug.print("  Run {}: {d:.2} ms\n", .{ run + 1, @as(f64, @floatFromInt(time)) / 1_000_000.0 });
        }
        
        const avg_time = total_time / runs;
        std.debug.print("  Average: {d:.2} ms\n", .{@as(f64, @floatFromInt(avg_time)) / 1_000_000.0});
        std.debug.print("  Min: {d:.2} ms\n", .{@as(f64, @floatFromInt(min_time)) / 1_000_000.0});
        std.debug.print("  Max: {d:.2} ms\n", .{@as(f64, @floatFromInt(max_time)) / 1_000_000.0});
        std.debug.print("\n");
    }
    
    std.debug.print("Benchmark complete! 🎯\n");
}