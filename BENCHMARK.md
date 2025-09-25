# 🐍 Snek Benchmark Suite

This benchmark suite measures the performance of key components in the Snek game engine.

## Quick Start

Run all benchmarks:
```bash
make benchmark
# OR
zig build benchmark
```

## Benchmark Components

### 1. Snake Movement (`benchmarkSnakeMovement`)
- **What it measures**: Core game update loop performance
- **Iterations**: 100,000 game ticks
- **Focus**: Snake segment updates, boundary wrapping, basic game state transitions
- **Key insight**: How fast the core game loop can run

### 2. Collision Detection (`benchmarkCollisionDetection`)  
- **What it measures**: Self-collision detection efficiency
- **Iterations**: 1,000,000 collision checks
- **Focus**: Algorithm efficiency for detecting when snake hits itself
- **Key insight**: Performance scales with snake length

### 3. Food Generation (`benchmarkFoodGeneration`)
- **What it measures**: Random food placement performance
- **Iterations**: 1,000,000 food placements
- **Focus**: Random number generation and coordinate calculation
- **Key insight**: RNG overhead in game loop

### 4. Complete Game Simulation (`benchmarkCompleteGameSimulation`)
- **What it measures**: Full game loop with simulated AI player
- **Iterations**: 10,000 game ticks with random direction changes
- **Focus**: Complete gameplay scenarios including growth, collisions, resets
- **Key insight**: Real-world performance under typical gameplay

## Interpreting Results

### Good Performance Indicators
- **Snake Movement**: < 5ms for 100k iterations
- **Collision Detection**: < 10ms for 1M checks  
- **Food Generation**: < 2ms for 1M generations
- **Complete Simulation**: < 50ms for 10k ticks

### Performance Analysis
Each benchmark runs 5 times and reports:
- **Average**: Mean execution time
- **Min**: Best case performance  
- **Max**: Worst case performance

Use these metrics to:
- Identify performance bottlenecks
- Validate optimizations
- Compare performance across different hardware
- Track performance regressions

## Implementation Details

### Headless Operation
The benchmark suite runs without graphics dependencies:
- No raylib/OpenGL calls
- Pure game logic testing
- Minimal memory allocations
- Deterministic behavior (where possible)

### Game Configuration
- **Grid Size**: 40×30 (1200 cells)
- **Max Snake Size**: 1000 segments
- **AI Behavior**: Random direction changes every 100 ticks
- **Boundary**: Wrapping (snake appears on opposite side)

### Customization
To modify benchmark parameters, edit `benchmark.zig`:

```zig
// Change iteration counts
const iterations = 100_000;  // Reduce for faster testing

// Change game size  
var game = BenchmarkGame(1000).init(80, 60);  // Larger grid

// Change AI frequency
if (tick % 50 == 0) {  // More frequent direction changes
```

## Adding New Benchmarks

1. Create a new benchmark function:
```zig
fn benchmarkMyFeature(allocator: std.mem.Allocator) !u64 {
    const start = std.time.nanoTimestamp();
    
    // Your benchmark code here
    
    const end = std.time.nanoTimestamp();
    return @intCast(end - start);
}
```

2. Add to the benchmarks array:
```zig
const benchmarks = [_]Benchmark{
    // existing benchmarks...
    .{ .name = "My Feature", .func = benchmarkMyFeature },
};
```

## Platform Notes

- **Linux**: Tested on Ubuntu/Debian systems
- **macOS**: Should work with Zig installed via homebrew
- **Windows**: Should work with Zig from ziglang.org
- **Performance**: Results vary by CPU, memory, and compiler optimization level

## Building from Source

```bash
# Debug build (slower, good for development)
zig build benchmark

# Release build (optimized, best for real measurements)  
zig build benchmark -Doptimize=ReleaseFast
```

## Troubleshooting

### Build Issues
- Ensure Zig 0.11+ is installed
- Check `build.zig` contains benchmark target
- Verify `benchmark.zig` compiles independently

### Performance Issues
- Run with `-Doptimize=ReleaseFast` for accurate measurements
- Close other applications during benchmarking
- Run multiple times and compare averages
- Consider CPU thermal throttling on laptops

---

*Built with ❤️ for performance analysis of the Snek game engine*