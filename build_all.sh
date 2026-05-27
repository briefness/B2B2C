#!/bin/bash
# ============================================================
# B2B2C Wallet — 全平台 × 全租户一键构建脚本
#
# 用法：
#   ./build_all.sh                    # 构建全部 (iOS + Android × 3 租户)
#   ./build_all.sh ios                # 仅 iOS 全租户
#   ./build_all.sh android            # 仅 Android 全租户
#   ./build_all.sh ios customerA      # 仅 iOS customerA
#   ./build_all.sh android customerB  # 仅 Android customerB
#   ./build_all.sh rust               # 仅编译 Rust 核心库 (全架构)
#
# 环境变量 (可选)：
#   BUILD_MODE=release|debug          # 默认 release
#   SKIP_RUST=1                       # 跳过 Rust 编译 (已编译时)
#   OBFUSCATE=1                       # 启用 Dart 代码混淆
# ============================================================

set -e

# ==================== 配置 ====================

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUST_DIR="$PROJECT_ROOT/rust_core"
OUTPUT_DIR="$PROJECT_ROOT/build/outputs"

# 租户列表
FLAVORS=("customerA" "customerB" "customerC")

# 构建模式
BUILD_MODE="${BUILD_MODE:-release}"

# 平台筛选
TARGET_PLATFORM="${1:-all}"
TARGET_FLAVOR="${2:-all}"

# Rust 库名
LIB_NAME="b2b2c_wallet_core"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok()    { echo -e "${GREEN}[  OK]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[FAIL]${NC} $1"; }
log_step()  { echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; echo -e "${BLUE}  $1${NC}"; echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }

# 统计
TOTAL=0
SUCCESS=0
FAILED=0
ARTIFACTS=()

# ==================== Rust 交叉编译 ====================

build_rust() {
    log_step "🦀 编译 Rust 核心库 (全架构)"
    
    cd "$RUST_DIR"
    
    local CARGO_FLAGS="--release"
    if [ "$BUILD_MODE" = "debug" ]; then
        CARGO_FLAGS=""
    fi
    
    # ---------- iOS ----------
    
    log_info "检查 iOS 编译目标..."
    rustup target add aarch64-apple-ios aarch64-apple-ios-sim 2>/dev/null || true
    
    log_info "编译 iOS 真机 (aarch64-apple-ios)..."
    cargo build --target aarch64-apple-ios $CARGO_FLAGS 2>&1 | tail -1
    log_ok "iOS 真机"
    
    log_info "编译 iOS 模拟器 (aarch64-apple-ios-sim)..."
    cargo build --target aarch64-apple-ios-sim $CARGO_FLAGS 2>&1 | tail -1
    log_ok "iOS 模拟器"
    
    # 打包 XCFramework
    local TARGET_DIR="release"
    [ "$BUILD_MODE" = "debug" ] && TARGET_DIR="debug"
    
    local XCFW_DIR="$PROJECT_ROOT/ios/Frameworks"
    rm -rf "$XCFW_DIR/RustCore.xcframework"
    mkdir -p "$XCFW_DIR/Headers"
    
    xcodebuild -create-xcframework \
        -library "$RUST_DIR/target/aarch64-apple-ios/$TARGET_DIR/lib${LIB_NAME}.a" \
        -library "$RUST_DIR/target/aarch64-apple-ios-sim/$TARGET_DIR/lib${LIB_NAME}.a" \
        -output "$XCFW_DIR/RustCore.xcframework" 2>/dev/null
    
    # 生成头文件
    cat > "$XCFW_DIR/Headers/b2b2c_wallet_core.h" << 'HEADER_EOF'
#ifndef B2B2C_WALLET_CORE_H
#define B2B2C_WALLET_CORE_H
#include <stdint.h>
char* generate_mnemonic(int32_t strength);
char* mnemonic_to_seed_hex(const char* mnemonic, const char* passphrase);
int32_t validate_mnemonic(const char* mnemonic);
char* derive_key(const char* seed_hex, const char* path);
char* derive_address(const char* seed_hex, const char* path);
char* sign_transaction(const char* private_key_hex, const char* message_hash_hex, uint64_t chain_id);
char* compute_hmac(const char* key_hex, const char* message_hex);
char* generate_random_bytes(int32_t len);
char* sha256_hash(const char* data_hex);
void free_string(char* ptr);
void free_mnemonic(char* ptr);
char* get_version(void);
#endif
HEADER_EOF
    
    log_ok "XCFramework 已生成"
    
    # ---------- Android ----------
    
    log_info "检查 Android 编译目标..."
    rustup target add aarch64-linux-android x86_64-linux-android 2>/dev/null || true
    
    # 检查 Android NDK
    local NDK_HOME="${ANDROID_NDK_HOME:-${ANDROID_HOME}/ndk/$(ls ${ANDROID_HOME}/ndk/ 2>/dev/null | sort -V | tail -1)}"
    
    if [ -d "$NDK_HOME" ]; then
        log_info "编译 Android arm64-v8a (aarch64-linux-android)..."
        
        local TOOLCHAIN="$NDK_HOME/toolchains/llvm/prebuilt/darwin-x86_64"
        [ -d "$NDK_HOME/toolchains/llvm/prebuilt/darwin-aarch64" ] && TOOLCHAIN="$NDK_HOME/toolchains/llvm/prebuilt/darwin-aarch64"
        
        # 创建 cargo config
        mkdir -p "$RUST_DIR/.cargo"
        cat > "$RUST_DIR/.cargo/config.toml" << CARGO_EOF
[target.aarch64-linux-android]
linker = "${TOOLCHAIN}/bin/aarch64-linux-android24-clang"

[target.x86_64-linux-android]
linker = "${TOOLCHAIN}/bin/x86_64-linux-android24-clang"
CARGO_EOF
        
        cargo build --target aarch64-linux-android $CARGO_FLAGS 2>&1 | tail -1
        log_ok "Android arm64-v8a"
        
        log_info "编译 Android x86_64 (x86_64-linux-android)..."
        cargo build --target x86_64-linux-android $CARGO_FLAGS 2>&1 | tail -1
        log_ok "Android x86_64"
        
        # 复制 .so 到 jniLibs
        local JNILIBS="$PROJECT_ROOT/android/app/src/main/jniLibs"
        mkdir -p "$JNILIBS/arm64-v8a" "$JNILIBS/x86_64"
        
        cp "$RUST_DIR/target/aarch64-linux-android/$TARGET_DIR/lib${LIB_NAME}.so" \
           "$JNILIBS/arm64-v8a/"
        cp "$RUST_DIR/target/x86_64-linux-android/$TARGET_DIR/lib${LIB_NAME}.so" \
           "$JNILIBS/x86_64/"
        
        log_ok "Android .so 已复制到 jniLibs"
    else
        log_warn "Android NDK 未找到，跳过 Android Rust 编译"
        log_warn "设置 ANDROID_NDK_HOME 环境变量后重试"
    fi
    
    cd "$PROJECT_ROOT"
    log_ok "Rust 核心库编译完成"
}

# ==================== Flutter iOS 构建 ====================

build_ios_flavor() {
    local FLAVOR="$1"
    local TOTAL_IDX="$2"
    
    log_info "[$TOTAL_IDX] 构建 iOS $FLAVOR ($BUILD_MODE)..."
    
    TOTAL=$((TOTAL + 1))
    
    local FLUTTER_FLAGS="--$BUILD_MODE"
    [ "${OBFUSCATE}" = "1" ] && FLUTTER_FLAGS="$FLUTTER_FLAGS --obfuscate --split-debug-info=$OUTPUT_DIR/debug-info/ios/$FLAVOR"
    
    if flutter build ios $FLUTTER_FLAGS --flavor "$FLAVOR" --no-codesign 2>&1 | tail -5; then
        log_ok "iOS $FLAVOR 构建成功"
        SUCCESS=$((SUCCESS + 1))
        ARTIFACTS+=("iOS/$FLAVOR: build/ios/iphoneos/Runner.app")
    else
        log_error "iOS $FLAVOR 构建失败"
        FAILED=$((FAILED + 1))
    fi
}

# ==================== Flutter Android 构建 ====================

build_android_flavor() {
    local FLAVOR="$1"
    local TOTAL_IDX="$2"
    
    log_info "[$TOTAL_IDX] 构建 Android $FLAVOR ($BUILD_MODE)..."
    
    TOTAL=$((TOTAL + 1))
    
    local FLUTTER_FLAGS="--$BUILD_MODE"
    [ "${OBFUSCATE}" = "1" ] && FLUTTER_FLAGS="$FLUTTER_FLAGS --obfuscate --split-debug-info=$OUTPUT_DIR/debug-info/android/$FLAVOR"
    
    if flutter build apk $FLUTTER_FLAGS --flavor "$FLAVOR" 2>&1 | tail -5; then
        log_ok "Android $FLAVOR APK 构建成功"
        SUCCESS=$((SUCCESS + 1))
        
        # 复制产物到统一输出目录
        local APK_DIR="$OUTPUT_DIR/apk/$FLAVOR"
        mkdir -p "$APK_DIR"
        find build/app/outputs/flutter-apk -name "*${FLAVOR}*" -name "*.apk" -exec cp {} "$APK_DIR/" \; 2>/dev/null
        ARTIFACTS+=("Android/$FLAVOR: $APK_DIR/")
    else
        log_error "Android $FLAVOR APK 构建失败"
        FAILED=$((FAILED + 1))
    fi
}

# ==================== 主流程 ====================

main() {
    echo ""
    echo "╔══════════════════════════════════════════════════╗"
    echo "║     B2B2C Wallet — 全平台 × 全租户构建系统       ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo ""
    echo "  平台:   $TARGET_PLATFORM"
    echo "  租户:   $TARGET_FLAVOR"
    echo "  模式:   $BUILD_MODE"
    echo "  混淆:   ${OBFUSCATE:-0}"
    echo ""
    
    local START_TIME=$(date +%s)
    
    mkdir -p "$OUTPUT_DIR"
    
    # ---------- 1. Rust 编译 ----------
    
    if [ "${SKIP_RUST}" != "1" ] && { [ "$TARGET_PLATFORM" = "all" ] || [ "$TARGET_PLATFORM" = "rust" ]; }; then
        build_rust
    else
        log_info "跳过 Rust 编译 (SKIP_RUST=1 或仅构建 Flutter)"
    fi
    
    [ "$TARGET_PLATFORM" = "rust" ] && { log_ok "Rust 构建完成"; exit 0; }
    
    # ---------- 2. Flutter pub get ----------
    
    log_step "📦 Flutter 依赖"
    cd "$PROJECT_ROOT"
    flutter pub get 2>&1 | tail -1
    log_ok "依赖就绪"
    
    # ---------- 3. 筛选要构建的 flavors ----------
    
    local BUILD_FLAVORS=()
    if [ "$TARGET_FLAVOR" = "all" ]; then
        BUILD_FLAVORS=("${FLAVORS[@]}")
    else
        BUILD_FLAVORS=("$TARGET_FLAVOR")
    fi
    
    # ---------- 4. iOS 构建 ----------
    
    if [ "$TARGET_PLATFORM" = "all" ] || [ "$TARGET_PLATFORM" = "ios" ]; then
        log_step "🍎 iOS 构建 (${#BUILD_FLAVORS[@]} 个租户)"
        
        local idx=1
        for flavor in "${BUILD_FLAVORS[@]}"; do
            build_ios_flavor "$flavor" "$idx/${#BUILD_FLAVORS[@]}"
            idx=$((idx + 1))
        done
    fi
    
    # ---------- 5. Android 构建 ----------
    
    if [ "$TARGET_PLATFORM" = "all" ] || [ "$TARGET_PLATFORM" = "android" ]; then
        log_step "🤖 Android 构建 (${#BUILD_FLAVORS[@]} 个租户)"
        
        local idx=1
        for flavor in "${BUILD_FLAVORS[@]}"; do
            build_android_flavor "$flavor" "$idx/${#BUILD_FLAVORS[@]}"
            idx=$((idx + 1))
        done
    fi
    
    # ---------- 6. 输出摘要 ----------
    
    local END_TIME=$(date +%s)
    local DURATION=$((END_TIME - START_TIME))
    local MINUTES=$((DURATION / 60))
    local SECONDS=$((DURATION % 60))
    
    echo ""
    echo "╔══════════════════════════════════════════════════╗"
    echo "║                   构建摘要                       ║"
    echo "╠══════════════════════════════════════════════════╣"
    printf "║  总计: %-3s  成功: %-3s  失败: %-3s               ║\n" "$TOTAL" "$SUCCESS" "$FAILED"
    printf "║  耗时: %dm %ds                                  ║\n" "$MINUTES" "$SECONDS"
    echo "╠══════════════════════════════════════════════════╣"
    
    if [ ${#ARTIFACTS[@]} -gt 0 ]; then
        echo "║  产物:                                          ║"
        for artifact in "${ARTIFACTS[@]}"; do
            printf "║    %-46s║\n" "$artifact"
        done
    fi
    
    echo "╚══════════════════════════════════════════════════╝"
    
    if [ "$FAILED" -gt 0 ]; then
        exit 1
    fi
}

main
