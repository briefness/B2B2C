#!/bin/bash
# post_flavorizr.sh
# 一站式 flavor 配置：运行 flavorizr + 注入 Rust 链接配置
#
# 用法:
#   ./scripts/post_flavorizr.sh

set -euo pipefail

echo "📦 运行 flutter_flavorizr..."
flutter pub run flutter_flavorizr

echo ""
echo "🔧 注入 RustCore.xcconfig..."

XCCONFIG_DIR="ios/Flutter"
RUST_INCLUDE='#include "RustCore.xcconfig"'

if [ ! -f "$XCCONFIG_DIR/RustCore.xcconfig" ]; then
  echo "❌ 错误: $XCCONFIG_DIR/RustCore.xcconfig 不存在"
  exit 1
fi

count=0

for file in "$XCCONFIG_DIR"/customer*.xcconfig; do
  [ -f "$file" ] || continue

  if ! grep -qF "$RUST_INCLUDE" "$file"; then
    # 在 Generated.xcconfig include 之后插入
    sed -i '' "/Generated.xcconfig/a\\
$RUST_INCLUDE
" "$file"
    count=$((count + 1))
    echo "✅ 已注入: $(basename "$file")"
  fi
done

if [ $count -eq 0 ]; then
  echo "✓ 所有 flavor xcconfig 已包含 RustCore.xcconfig，无需修改"
else
  echo "✓ 共修复 $count 个 xcconfig 文件"
fi
