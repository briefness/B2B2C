#!/bin/bash
# ============================================================
# B2B2C Wallet - Rust 核心库 iOS 交叉编译脚本
# 
# 功能：
#   1. 编译 iOS 真机 (aarch64-apple-ios)
#   2. 编译 iOS 模拟器 (aarch64-apple-ios-sim)
#   3. 打包为 XCFramework (Xcode 自动选择正确架构)
#
# 用法：
#   ./build_ios.sh          # 编译 Release
#   ./build_ios.sh debug    # 编译 Debug
# ============================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
RUST_DIR="$SCRIPT_DIR"
IOS_DIR="$PROJECT_ROOT/ios"

# 库名 (与 Cargo.toml [lib].name 一致)
LIB_NAME="b2b2c_wallet_core"

# 编译模式
PROFILE="${1:-release}"
if [ "$PROFILE" = "debug" ]; then
    CARGO_FLAG=""
    TARGET_DIR="debug"
else
    CARGO_FLAG="--release"
    TARGET_DIR="release"
fi

echo "🔨 B2B2C Wallet Rust Core - iOS Build"
echo "   Profile: $PROFILE"
echo "   Lib: lib${LIB_NAME}.a"
echo ""

# ==================== 检查环境 ====================

echo "📋 检查编译目标..."
if ! rustup target list --installed | grep -q "aarch64-apple-ios"; then
    echo "   添加 aarch64-apple-ios..."
    rustup target add aarch64-apple-ios
fi

if ! rustup target list --installed | grep -q "aarch64-apple-ios-sim"; then
    echo "   添加 aarch64-apple-ios-sim..."
    rustup target add aarch64-apple-ios-sim
fi

echo "   ✅ 编译目标就绪"
echo ""

# ==================== 编译 ====================

cd "$RUST_DIR"

echo "🏗️  编译 iOS 真机 (aarch64-apple-ios)..."
cargo build --target aarch64-apple-ios $CARGO_FLAG 2>&1 | tail -3
echo "   ✅ 真机编译完成"

echo "🏗️  编译 iOS 模拟器 (aarch64-apple-ios-sim)..."
cargo build --target aarch64-apple-ios-sim $CARGO_FLAG 2>&1 | tail -3
echo "   ✅ 模拟器编译完成"

# ==================== 打包 XCFramework ====================

DEVICE_LIB="$RUST_DIR/target/aarch64-apple-ios/$TARGET_DIR/lib${LIB_NAME}.a"
SIM_LIB="$RUST_DIR/target/aarch64-apple-ios-sim/$TARGET_DIR/lib${LIB_NAME}.a"

# 验证产物
if [ ! -f "$DEVICE_LIB" ]; then
    echo "❌ 真机库不存在: $DEVICE_LIB"
    exit 1
fi

if [ ! -f "$SIM_LIB" ]; then
    echo "❌ 模拟器库不存在: $SIM_LIB"
    exit 1
fi

echo ""
echo "📦 打包 XCFramework..."

XCFRAMEWORK_DIR="$IOS_DIR/Frameworks"
XCFRAMEWORK_PATH="$XCFRAMEWORK_DIR/RustCore.xcframework"

# 清理旧的 XCFramework
rm -rf "$XCFRAMEWORK_PATH"
mkdir -p "$XCFRAMEWORK_DIR"

# 创建 XCFramework
xcodebuild -create-xcframework \
    -library "$DEVICE_LIB" \
    -library "$SIM_LIB" \
    -output "$XCFRAMEWORK_PATH" 2>&1 | tail -3

echo "   ✅ XCFramework 已生成: $XCFRAMEWORK_PATH"

# ==================== 生成头文件 ====================

HEADER_DIR="$XCFRAMEWORK_PATH/../Headers"
mkdir -p "$HEADER_DIR"

cat > "$HEADER_DIR/b2b2c_wallet_core.h" << 'EOF'
#ifndef B2B2C_WALLET_CORE_H
#define B2B2C_WALLET_CORE_H

#include <stdint.h>

// 助记词
char* generate_mnemonic(int32_t strength);
char* mnemonic_to_seed_hex(const char* mnemonic, const char* passphrase);
int32_t validate_mnemonic(const char* mnemonic);

// 密钥派生
char* derive_key(const char* seed_hex, const char* path);
char* derive_address(const char* seed_hex, const char* path);

// 签名
char* sign_transaction(const char* private_key_hex, const char* message_hash_hex, uint64_t chain_id);

// 加密工具
char* compute_hmac(const char* key_hex, const char* message_hex);
char* generate_random_bytes(int32_t len);
char* sha256_hash(const char* data_hex);

// 内存管理
void free_string(char* ptr);
void free_mnemonic(char* ptr);

// 版本
char* get_version(void);

#endif
EOF

echo "   ✅ C 头文件已生成"

# ==================== 输出摘要 ====================

echo ""
echo "============================================================"
echo "✅ 构建完成!"
echo ""
echo "   XCFramework: $XCFRAMEWORK_PATH"
echo "   Header:      $HEADER_DIR/b2b2c_wallet_core.h"
echo ""
echo "   真机库大小:   $(du -h "$DEVICE_LIB" | cut -f1)"
echo "   模拟器库大小: $(du -h "$SIM_LIB" | cut -f1)"
echo ""
echo "下一步: 在 Xcode 中链接 XCFramework"
echo "   1. Runner.xcworkspace → Runner target → Build Phases"
echo "   2. Link Binary With Libraries → 添加 RustCore.xcframework"
echo "   3. Build Settings → Header Search Paths → 添加 \$(PROJECT_DIR)/Frameworks/Headers"
echo "============================================================"
