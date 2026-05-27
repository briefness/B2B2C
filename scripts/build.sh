#!/bin/bash
# B2B2C Wallet 多租户打包脚本
# 
# 使用方式:
#   ./scripts/build.sh android customerA
#   ./scripts/build.sh ios customerA
#   ./scripts/build.sh all all

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查 Flutter
check_flutter() {
    if ! command -v flutter &> /dev/null; then
        log_error "Flutter not found. Please install Flutter first."
        exit 1
    fi
    
    log_info "Flutter version: $(flutter --version | head -1)"
}

# 检查 Rust
check_rust() {
    if ! command -v cargo &> /dev/null; then
        log_error "Rust not found. Please install Rust first."
        exit 1
    fi
    
    log_info "Rust version: $(rustc --version)"
}

# 构建 Rust 核心库
build_rust_core() {
    local target=$1
    log_info "Building Rust core for $target..."
    
    cd rust_core
    
    case $target in
        android)
            log_info "Building for Android..."
            cargo build --release --target aarch64-linux-android
            cargo build --release --target armv7-linux-androideabi
            cargo build --release --target x86_64-linux-android
            cargo build --release --target i686-linux-android
            ;;
        ios)
            log_info "Building for iOS..."
            cargo build --release --target aarch64-apple-ios
            cargo build --release --target x86_64-apple-ios
            ;;
        all)
            log_info "Building for all platforms..."
            cargo build --release
            ;;
    esac
    
    cd ..
    log_info "Rust core built successfully!"
}

# 构建 Flutter
build_flutter() {
    local platform=$1
    local flavor=$2
    local output_dir="build/$platform"
    
    mkdir -p "$output_dir"
    
    case $platform in
        android)
            log_info "Building Android APK for $flavor..."
            if [ "$flavor" == "all" ]; then
                for f in customerA customerB customerC; do
                    log_info "Building $f..."
                    flutter build apk --flavor $f --obfuscate --split-debug-info=./symbols/$f
                done
            else
                flutter build apk --flavor $flavor --obfuscate --split-debug-info=./symbols/$flavor
            fi
            ;;
        ios)
            log_info "Building iOS for $flavor..."
            if [ "$flavor" == "all" ]; then
                for f in customerA customerB customerC; do
                    log_info "Building $f..."
                    flutter build ios --simulator --no-codesign --flavor $f
                done
            else
                flutter build ios --simulator --no-codesign --flavor $flavor
            fi
            ;;
        all)
            log_info "Building all platforms..."
            $0 android all
            $0 ios all
            ;;
    esac
    
    log_info "Build completed!"
}

# 显示帮助
show_help() {
    echo "B2B2C Wallet Build Script"
    echo ""
    echo "Usage:"
    echo "  $0 <platform> [flavor]"
    echo ""
    echo "Platforms:"
    echo "  android    Build Android APK"
    echo "  ios        Build iOS app"
    echo "  all        Build all platforms"
    echo ""
    echo "Flavors:"
    echo "  customerA  Customer A configuration"
    echo "  customerB  Customer B configuration"
    echo "  customerC  Customer C configuration"
    echo "  all        Build all flavors"
    echo ""
    echo "Examples:"
    echo "  $0 android customerA"
    echo "  $0 ios all"
    echo "  $0 all all"
}

# 主函数
main() {
    local platform=${1:-all}
    local flavor=${2:-all}
    
    log_info "Starting B2B2C Wallet build..."
    log_info "Platform: $platform, Flavor: $flavor"
    
    check_flutter
    check_rust
    
    # 获取依赖
    log_info "Getting dependencies..."
    flutter pub get
    
    # 构建
    build_flutter "$platform" "$flavor"
    
    log_info "Build process completed!"
}

# 执行
main "$@"
