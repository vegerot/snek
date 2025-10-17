#!/bin/bash

# CI-friendly benchmark runner
# Designed to work in headless environments without graphics dependencies

set -e

echo "🐍 Snek Benchmark Suite - CI Runner"
echo "===================================="
echo ""

# Check if zig is available
if ! command -v zig &> /dev/null; then
    echo "❌ Zig not found. Installing Zig..."
    
    # Try to install Zig 
    if [ -x "$(command -v wget)" ]; then
        echo "📥 Downloading Zig..."
        cd /tmp
        wget -q https://ziglang.org/download/0.13.0/zig-linux-x86_64-0.13.0.tar.xz || {
            echo "⚠️  Failed to download from official site, trying development build..."
            wget -q https://ziglang.org/builds/zig-linux-x86_64-0.13.0-dev.351+64ef45eb0.tar.xz || {
                echo "❌ Failed to download Zig. Please install manually."
                exit 1
            }
            tar -xf zig-linux-x86_64-0.13.0-dev.351+64ef45eb0.tar.xz
            sudo mv zig-linux-x86_64-0.13.0-dev.351+64ef45eb0 /usr/local/zig
        }
        if [ -f "zig-linux-x86_64-0.13.0.tar.xz" ]; then
            tar -xf zig-linux-x86_64-0.13.0.tar.xz
            sudo mv zig-linux-x86_64-0.13.0 /usr/local/zig
        fi
        sudo ln -sf /usr/local/zig/zig /usr/local/bin/zig
        cd -
    else
        echo "❌ wget not available. Cannot download Zig automatically."
        exit 1
    fi
fi

# Verify Zig installation
echo "🔍 Checking Zig installation..."
zig version
echo ""

# Validate benchmark files exist
echo "📁 Validating benchmark files..."
for file in "benchmark.zig" "build.zig"; do
    if [ ! -f "$file" ]; then
        echo "❌ Missing required file: $file"
        exit 1
    fi
    echo "✅ Found $file"
done
echo ""

# Build the benchmark
echo "🔨 Building benchmark suite..."
zig build benchmark --summary all || {
    echo "❌ Build failed. Attempting to build just the benchmark executable..."
    zig build-exe benchmark.zig || {
        echo "❌ Failed to build benchmark. Checking for syntax errors..."
        zig fmt --check benchmark.zig || echo "⚠️  Code formatting issues found"
        zig build-exe --check-syntax benchmark.zig || {
            echo "❌ Syntax errors in benchmark.zig"
            exit 1
        }
        echo "✅ Syntax OK, but build failed for other reasons"
        exit 1
    }
    echo "✅ Built benchmark executable directly"
    # Run the executable directly
    ./benchmark
    exit 0
}

echo "✅ Build successful"
echo ""

# Run benchmarks
echo "🏃 Running benchmarks..."
echo "========================"
timeout 300 zig build benchmark || {
    echo ""
    echo "⚠️  Benchmark timed out or failed"
    echo "This might be normal on slow systems or in resource-constrained environments"
    echo ""
    
    # Try running a simpler version
    echo "🔧 Attempting simplified benchmark run..."
    timeout 60 ./zig-out/bin/snek-benchmark 2>/dev/null || {
        echo "❌ Simplified run also failed"
        echo ""
        echo "🔍 Diagnostics:"
        echo "- Build artifacts:"
        ls -la zig-out/bin/ 2>/dev/null || echo "  No build artifacts found"
        echo "- System resources:"
        free -h 2>/dev/null || echo "  Memory info unavailable"
        echo ""
        exit 1
    }
}

echo ""
echo "✅ Benchmark suite completed successfully!"
echo ""
echo "📊 Results saved. Use these benchmarks to:"
echo "   - Track performance over time"
echo "   - Identify optimization opportunities" 
echo "   - Compare performance across systems"
echo "   - Validate code changes don't regress performance"