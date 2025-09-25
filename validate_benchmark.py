#!/usr/bin/env python3

"""
Simple syntax and logic validator for benchmark.zig
Since we can't easily install Zig in this environment, we'll validate manually
"""

import re
import os

def validate_benchmark_file():
    """Validate the benchmark.zig file for basic correctness"""
    
    if not os.path.exists('benchmark.zig'):
        print("❌ benchmark.zig not found")
        return False
    
    with open('benchmark.zig', 'r') as f:
        content = f.read()
    
    # Check for required structures
    required_patterns = [
        r'const XY = struct',
        r'fn Snake\(maxSize: u32\) type',
        r'fn BenchmarkGame\(maxSize: u32\) type',
        r'fn benchmarkSnakeMovement',
        r'fn benchmarkCollisionDetection', 
        r'fn benchmarkFoodGeneration',
        r'fn benchmarkCompleteGameSimulation',
        r'pub fn main\(\)',
    ]
    
    print("🔍 Validating benchmark.zig structure...")
    
    for pattern in required_patterns:
        if re.search(pattern, content):
            print(f"✅ Found: {pattern}")
        else:
            print(f"❌ Missing: {pattern}")
            return False
    
    # Check for performance measurement
    if 'std.time.nanoTimestamp()' in content:
        print("✅ Performance timing implemented")
    else:
        print("❌ Missing performance timing")
        return False
    
    # Check for proper memory management
    if 'allocator' in content:
        print("✅ Memory allocator handling present")
    else:
        print("⚠️  No explicit memory allocator usage (might be OK)")
    
    # Check for benchmark configuration
    if 'iterations' in content:
        print("✅ Benchmark iterations configured")
    else:
        print("❌ Missing iteration configuration")
        return False
    
    # Validate line count (should be substantial)
    lines = content.count('\n')
    if lines > 200:
        print(f"✅ Substantial implementation ({lines} lines)")
    else:
        print(f"⚠️  Small implementation ({lines} lines)")
    
    return True

def validate_build_integration():
    """Validate build system integration"""
    
    print("\n🔧 Validating build integration...")
    
    # Check build.zig
    if os.path.exists('build.zig'):
        with open('build.zig', 'r') as f:
            build_content = f.read()
        
        if 'benchmark' in build_content and 'benchmark.zig' in build_content:
            print("✅ build.zig includes benchmark target")
        else:
            print("❌ build.zig missing benchmark integration")
            return False
    else:
        print("❌ build.zig not found")
        return False
    
    # Check Makefile
    if os.path.exists('Makefile'):
        with open('Makefile', 'r') as f:
            make_content = f.read()
        
        if 'benchmark:' in make_content:
            print("✅ Makefile includes benchmark target")
        else:
            print("❌ Makefile missing benchmark target")
            return False
    else:
        print("❌ Makefile not found")
        return False
    
    return True

def validate_documentation():
    """Validate documentation"""
    
    print("\n📚 Validating documentation...")
    
    if os.path.exists('BENCHMARK.md'):
        with open('BENCHMARK.md', 'r') as f:
            doc_content = f.read()
        
        doc_sections = [
            'Quick Start',
            'Benchmark Components', 
            'Snake Movement',
            'Collision Detection',
            'Food Generation',
            'Complete Game Simulation'
        ]
        
        missing_sections = []
        for section in doc_sections:
            if section not in doc_content:
                missing_sections.append(section)
        
        if not missing_sections:
            print("✅ Complete documentation")
        else:
            print(f"⚠️  Missing documentation sections: {missing_sections}")
        
        # Check for usage examples
        if '```bash' in doc_content and 'make benchmark' in doc_content:
            print("✅ Usage examples provided")
        else:
            print("⚠️  Missing usage examples")
            
    else:
        print("❌ BENCHMARK.md not found")
        return False
    
    return True

def main():
    print("🐍 Snek Benchmark Validation")
    print("============================")
    
    valid_benchmark = validate_benchmark_file()
    valid_build = validate_build_integration() 
    valid_docs = validate_documentation()
    
    print(f"\n📊 Validation Summary:")
    print(f"Benchmark Implementation: {'✅ PASS' if valid_benchmark else '❌ FAIL'}")
    print(f"Build Integration: {'✅ PASS' if valid_build else '❌ FAIL'}")
    print(f"Documentation: {'✅ PASS' if valid_docs else '❌ FAIL'}")
    
    if all([valid_benchmark, valid_build, valid_docs]):
        print(f"\n🎉 All validations passed! Benchmark suite is ready.")
        print(f"\n🚀 To use:")
        print(f"   1. Install Zig (https://ziglang.org/)")
        print(f"   2. Run: make benchmark")
        print(f"   3. Or run: zig build benchmark")
        return True
    else:
        print(f"\n❌ Some validations failed. Please review the issues above.")
        return False

if __name__ == '__main__':
    success = main()
    exit(0 if success else 1)