# B2B2C 虚拟币钱包 App

基于白皮书设计的工业级 B2B2C 加密货币钱包应用，采用 Rust 核心 + Flutter UI 的沙箱混合原生架构。

> **最近审计**: 2026-06-05 完成全量安全审计，修复 13 项安全问题（含 2 项致命级），详见 [安全审计](#安全审计)。

## 架构概览

```
                    ┌───────────────────────────────┐
                    │     Flutter 业务表现层      │
                    └──────────────┬──────────────┘
                                   │
                         [ Dart FFI / Method Channel ]
                                   │
┌────────────────┐    ┌───────────┴───────────┐    ┌────────────────┐
│  Android TEE   │    │     原生宿主层        │    │   iOS SE       │
│  KeyStore      │    │   Android/iOS Native   │    │   Keychain     │
└────────────────┘    └───────────┬───────────┘    └────────────────┘
                                   │
                         [ C-ABI / Dynamic Library ]
                                   │
                    ┌──────────────┴──────────────┐
                    │     Rust 核心加密层         │
                    │  • BIP39/44 密钥派生       │
                    │  • Secp256k1 签名          │
                    │  • AES-GCM 加密            │
                    │  • Zeroize 内存安全        │
                    └─────────────────────────────┘
```

## 目录结构

```
B2B2C/
├── rust_core/                 # Rust 核心库
│   ├── src/
│   │   ├── lib.rs             # 库入口
│   │   ├── error.rs           # 错误类型
│   │   ├── memory.rs          # 内存安全（Zeroize）
│   │   ├── mnemonic.rs        # BIP39 助记词
│   │   ├── key_derivation.rs  # BIP32/44 HD 钱包
│   │   ├── signing.rs         # 交易签名
│   │   ├── crypto_utils.rs    # 加密工具
│   │   └── ffi.rs             # FFI 接口
│   ├── tests/                 # Rust 单元测试
│   ├── words/                 # BIP39 词表
│   ├── build_ios.sh           # iOS 构建脚本
│   ├── Cargo.toml
│   └── Cargo.lock
│
├── lib/                       # Flutter 应用
│   ├── main.dart              # 入口（Flavor 解析 + 启动）
│   ├── app.dart               # MaterialApp 根组件
│   ├── flavors.dart           # Flavor 枚举与品牌配置
│   ├── pages/
│   │   └── my_home_page.dart  # 首页
│   └── src/
│       ├── core/
│       │   ├── ffi/           # Dart FFI 绑定
│       │   │   └── wallet_ffi.dart
│       │   ├── security/      # 安全服务
│       │   │   ├── security_service.dart
│       │   │   ├── security_config_service.dart
│       │   │   ├── secure_storage_service.dart
│       │   │   ├── secure_keyboard_service.dart
│       │   │   └── method_channel_service.dart
│       │   ├── network/       # 安全网络服务
│       │   │   └── secure_network_service.dart
│       │   ├── business/      # 业务核心
│       │   │   ├── config_signature_service.dart
│       │   │   └── m_of_n_auth_service.dart
│       │   └── crypto/        # 加密工具（预留）
│       ├── dapp/              # DApp 浏览器
│       │   ├── dapp_browser_page.dart
│       │   ├── dapp_browser_service.dart
│       │   ├── dapp_sandbox_service.dart
│       │   └── web3_provider.dart
│       ├── services/          # 业务服务
│       │   └── wallet_service.dart
│       ├── models/            # 数据模型（预留）
│       ├── utils/             # 工具类（预留）
│       └── ui/
│           ├── pages/         # 页面
│           │   └── wallet_pages.dart
│           ├── widgets/       # 组件
│           │   ├── secure_keyboard.dart
│           │   └── anti_reverse_shield.dart
│           └── themes/        # 主题
│               ├── tenant_theme_service.dart
│               └── theme_provider.dart
│
├── assets/                    # 静态资源
│   ├── fonts/                 # 字体
│   ├── icons/                 # 图标
│   └── images/                # 图片
│
├── android/                   # Android 原生
│   └── app/src/main/kotlin/
│       └── com/b2b2c/wallet/
│
├── ios/                       # iOS 原生
│   └── Runner/
│
├── config/                    # 配置文件
│   ├── app_config.json        # 应用安全配置
│   ├── flavors.json           # 多租户品牌配置
│   ├── app.yaml               # 应用元数据
│   └── security_config.example.json  # 安全配置示例
│
├── docs/                      # 文档
│   ├── SECURITY_ANALYSIS.md   # 安全分析报告
│   └── SECURITY_CONFIG_GUIDE.md  # 安全配置指南
│
├── scripts/                   # 构建脚本
│   ├── build.sh               # 单平台/租户构建
│   └── post_flavorizr.sh      # Flavorizr 后置脚本
│
├── test/                      # Flutter 测试
│
├── build_all.sh               # 全平台全租户一键构建
│
├── .github/workflows/         # CI/CD
│   └── build.yml
│
├── pubspec.yaml               # Flutter 依赖声明
└── analysis_options.yaml      # Lint 规则
```

## 多租户（Flavor）

项目通过 `flutter_flavorizr` 实现白标多租户，当前支持 3 个租户：

| Flavor      | 应用名称           | 主色调  | Bundle ID / Application ID      |
| ----------- | ------------------ | ------- | ------------------------------- |
| customerA   | Customer A Wallet  | 🔵 蓝 `#1E88E5` | `com.b2b2c.wallet.customerA`   |
| customerB   | Customer B Wallet  | 🟣 紫 `#7B1FA2` | `com.b2b2c.wallet.customerB`   |
| customerC   | Customer C Wallet  | 🟢 青 `#00897B` | `com.b2b2c.wallet.customerC`   |

Flavor 配置入口：[flavors.dart](lib/flavors.dart)、[flavors.json](config/flavors.json)。

## 安全特性

### 1. 核心层安全
- **Rust 内存安全**: 使用 `zeroize` 宏，私钥、链码使用后自动物理擦除（`ExtendedKey` 实现 `ZeroizeOnDrop`）
- **BIP39/44 标准**: 遵循行业标准助记词和 HD 钱包规范
- **Secp256k1 签名**: 椭圆曲线签名，支持 EIP-155 重放保护（V 值使用 `u64` 支持大 chain_id）
- **AES-GCM 认证加密**: 支持 AAD（附加认证数据）上下文绑定，防止密文跨上下文解密
- **FFI 内存管理**: Rust 返回指针使用配对的 `free_string` 释放（分配器匹配），敏感参数释放前置零

### 2. 传输层安全
- **SSL Pinning**: 硬编码证书哈希校验（需在生产构建前替换占位符）
- **HMAC 验签**: 请求头包含 Nonce + Timestamp + 签名
- **明文流量禁止**: Android `network_security_config.xml` + `usesCleartextTraffic=false`

> ⚠️ **注意**: 防重放（Nonce 去重 + 时间窗口校验）的客户端侧实现尚未完成，需服务端配合。

### 3. 应用层安全
- **反调试**: 原生层检测 Frida/Xposed/Substrate 等 Hook 框架（Kotlin `BiometricHelper`）
- **安全键盘**: 每次随机打乱键位，防止输入录制（`secure_keyboard.dart`）
- **FLAG_SECURE**: 全局防止截屏和屏幕录制（`MainActivity.kt`）
- **M-of-N 多签认证**: 多方签名授权服务（`m_of_n_auth_service.dart`）
- **配置签名校验**: 防止配置文件被篡改（`config_signature_service.dart`）
- **安全检测 fail-closed**: Release 模式下安全检测异常时假定设备已被入侵
- **Hive Box 加密**: 本地数据使用 AES-256 加密，密钥存于 Keychain/EncryptedSharedPreferences
- **占位符编译期拦截**: Release 构建时自动检测未替换的占位符配置，阻止启动
- **allowBackup 禁用**: 防止通过 `adb backup` 导出用户数据

### 4. DApp 交互安全
- **ABI 解析**: 解析合约方法签名，识别高危操作（Approve、SetApprovalForAll）
- **风险分级警告**: 低/中/高/极高四级风险提示
- **Web3 沙箱**: 私钥永远不离开安全区域
- **域名白名单**: 仅白名单内的域名注入 Web3 Provider
- **eth_sign 禁用**: 默认拒绝 `eth_sign`（可伪造交易签名），引导使用 `personal_sign`

详见 [安全分析报告](docs/SECURITY_ANALYSIS.md) 和 [安全配置指南](docs/SECURITY_CONFIG_GUIDE.md)。

## 安全审计

### 审计概要（2026-06-05）

| 等级 | 发现 | 已修复 | 说明 |
|------|------|--------|------|
| P0 致命 | 2 | 2 | 助记词加密密钥未持久化、FFI 内存泄漏+分配器不匹配 |
| P1 严重 | 4 | 3 | SSL/HMAC/公钥占位符编译期拦截（防重放需服务端配合）|
| P2 高危 | 5 | 4 | eth_sign 禁用、AAD 传递、Zeroize、V 值溢出（RLP 编码待实现）|
| P3 中危 | 4 | 4 | Manifest 加固、fail-closed、Hive 加密 |
| P4 建议 | 3 | 0 | 低优先级增强项 |

### 生产环境检查清单

发布到生产环境前，**必须**完成以下事项：

- [ ] 替换 `SecurityConfigService` 中所有环境的 SSL 证书哈希（当前为占位符 `AAAA...`）
- [ ] 替换 HMAC 密钥（当前为 `*_hmac_key_placeholder`），改为认证握手动态下发
- [ ] 替换 `ConfigSignatureService.builtinPublicKey` 中的 B2B 签名公钥
- [ ] 实现 Android 原生层生物识别（`authenticate`、`generateHardwareKey` 等 MethodChannel 方法）
- [ ] 实现 `_buildTransactionHash` 的 RLP 编码（当前为字符串拼接，签名无法上链）
- [ ] 配置 Android ProGuard/R8 混淆规则
- [ ] 审查 iOS `WalletMethodChannel.swift` 安全检测实现
- [ ] 确认 Crashlytics 等上报工具不会发送含敏感信息的异常堆栈

## 构建

### 前置条件

```bash
# Flutter
flutter --version  # >= 3.16.0, SDK >= 3.0.0

# Rust
rustc --version    # >= 1.70.0
```

### 构建 Rust 核心

```bash
cd rust_core

# 通用构建
cargo build --release

# iOS 专用（生成 universal binary）
./build_ios.sh
```

### 构建 Flutter 应用

> ⚠️ 所有 Flutter 命令**必须指定 `--flavor`**，否则会构建失败。

```bash
# 获取依赖
flutter pub get

# Android (Debug)
flutter build apk --flavor customerA

# Android (Release + 混淆)
flutter build apk --flavor customerA --obfuscate --split-debug-info=build/debug-info/

# iOS (模拟器)
flutter build ios --simulator --flavor customerA

# iOS (真机 Release)
flutter build ios --flavor customerA
```

### 使用构建脚本

```bash
# 单平台单租户
./scripts/build.sh android customerA
./scripts/build.sh ios customerB

# 全平台全租户
./scripts/build.sh all all

# 或使用根目录一键脚本
./build_all.sh
```

## 依赖

### Flutter 依赖

| 分类       | 包名                         | 用途             |
| ---------- | ---------------------------- | ---------------- |
| 状态管理   | `flutter_riverpod`           | 响应式状态管理   |
|            | `riverpod_annotation`        | Riverpod 代码生成 |
| 网络       | `dio`                        | HTTP 客户端      |
|            | `web_socket_channel`         | WebSocket 通信   |
| 加密/安全  | `pointycastle`               | 加密算法库       |
|            | `crypto`                     | 哈希工具         |
|            | `encrypt`                    | 对称加密         |
|            | `asn1lib` / `pem`            | 证书编解码       |
|            | `flutter_secure_storage`     | 安全键值存储     |
| 数据存储   | `hive` / `hive_flutter`      | 本地 NoSQL 存储  |
|            | `path_provider`              | 文件路径         |
| UI 组件    | `flutter_svg`                | SVG 渲染         |
|            | `cached_network_image`       | 图片缓存         |
|            | `shimmer`                    | 骨架屏动效       |
| WebView    | `webview_flutter`            | DApp 浏览器      |
| FFI        | `ffi`                        | Dart-Rust 桥接   |
| 工具       | `uuid` / `intl` / `equatable` / `json_annotation` | 通用工具 |

### Rust 依赖

| 包名       | 用途             |
| ---------- | ---------------- |
| `secp256k1` | 椭圆曲线签名    |
| `bip39`    | 助记词生成/恢复  |
| `bip32`    | HD 钱包密钥派生  |
| `aes-gcm`  | 对称加密        |
| `zeroize`  | 内存安全擦除    |
| `hmac`     | HMAC 签名       |

## 配置

### 多租户配置

编辑 `config/flavors.json`：

```json
{
  "name": "customerA",
  "primaryColor": "#1E88E5",
  "apiBaseUrl": "https://api.customer-a.b2b2c-wallet.com"
}
```

或在 `pubspec.yaml` 的 `flavorizr` 节中添加新租户，然后运行：

```bash
flutter pub run flutter_flavorizr
./scripts/post_flavorizr.sh
```

### 安全配置

编辑 `config/app_config.json`（参考 `config/security_config.example.json`）：

```json
{
  "security": {
    "sslPinning": {
      "enabled": true,
      "certificateHashes": ["sha256/..."]
    },
    "hmac": {
      "enabled": true,
      "timestampValiditySeconds": 60
    }
  }
}
```

## 开发

### 运行

```bash
# 必须指定 flavor
flutter run --flavor customerA
flutter run --flavor customerB
flutter run --flavor customerC
```

### 代码生成

```bash
# Riverpod / JSON Serializable / Hive 代码生成
flutter pub run build_runner build --delete-conflicting-outputs
```

### 分析

```bash
flutter analyze
dart analyze lib/
```

### 测试

```bash
# Flutter
flutter test

# Rust
cd rust_core
cargo test
```

## 许可证

MIT License
