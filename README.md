# B2B2C 虚拟币钱包 App

基于白皮书设计的工业级 B2B2C 加密货币钱包应用，采用 Rust 核心 + Flutter UI 的沙箱混合原生架构。

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
│   │   ├── lib.rs           # 库入口
│   │   ├── error.rs         # 错误类型
│   │   ├── memory.rs        # 内存安全
│   │   ├── mnemonic.rs       # BIP39 助记词
│   │   ├── key_derivation.rs # BIP32/44 HD 钱包
│   │   ├── signing.rs        # 交易签名
│   │   ├── crypto_utils.rs   # 加密工具
│   │   └── ffi.rs           # FFI 接口
│   └── words/               # BIP39 词表
│
├── lib/                      # Flutter 应用
│   ├── main.dart            # 入口
│   └── src/
│       ├── core/
│       │   ├── ffi/         # Dart FFI 绑定
│       │   ├── security/    # 安全服务
│       │   └── network/     # 网络服务
│       ├── services/        # 业务服务
│       ├── dapp/            # DApp 浏览器
│       └── ui/
│           ├── pages/       # 页面
│           ├── widgets/     # 组件
│           └── themes/      # 主题
│
├── android/                  # Android 原生
│   └── app/src/main/kotlin/
│       └── com/b2b2c/wallet/
│
├── ios/                      # iOS 原生
│   └── Runner/
│
├── config/                   # 配置文件
│   ├── app_config.json
│   ├── flavors.json
│   └── app.yaml
│
├── scripts/                  # 构建脚本
│   └── build.sh
│
└── .github/workflows/        # CI/CD
    └── build.yml
```

## 安全特性

### 1. 核心层安全
- **Rust 内存安全**: 使用 `zeroize` 宏，私钥使用后自动物理擦除
- **BIP39/44 标准**: 遵循行业标准助记词和 HD 钱包规范
- **Secp256k1 签名**: 椭圆曲线签名，支持 EIP-155 重放保护

### 2. 传输层安全
- **双向 SSL Pinning**: 硬编码证书哈希，禁用代理
- **HMAC 验签**: 请求头包含 Nonce + Timestamp + 签名
- **防重放**: 60 秒时间窗口 + Nonce 去重

### 3. 应用层安全
- **反调试**: 检测 Frida/xposed 等 Hook 框架
- **安全键盘**: 每次随机打乱键位，防止输入录制
- **FLAG_SECURE**: 防止截屏和屏幕录制

### 4. DApp 交互安全
- **ABI 解析**: 解析合约方法签名
- **风险警告**: 对 Approve/SetApprovalForAll 弹出红色警告
- **Web3 沙箱**: 私钥永远不离开安全区域

## 构建

### 前置条件

```bash
# Flutter
flutter --version >= 3.16.0

# Rust
rustc --version >= 1.70.0
```

### 构建 Rust 核心

```bash
cd rust_core
cargo build --release
```

### 构建 Flutter 应用

```bash
# 获取依赖
flutter pub get

# Android
flutter build apk --flavor customerA --obfuscate

# iOS
flutter build ios --simulator --flavor customerA
```

### 使用构建脚本

```bash
# 单平台单租户
./scripts/build.sh android customerA
./scripts/build.sh ios customerB

# 全平台全租户
./scripts/build.sh all all
```

## 依赖

### Flutter 依赖
- flutter_riverpod: 状态管理
- dio: HTTP 客户端
- hive_flutter: 本地存储
- flutter_secure_storage: 安全存储
- flutter_inappwebview: WebView (DApp 浏览器)
- pointycastle: 加密库

### Rust 依赖
- secp256k1: 椭圆曲线
- bip39: 助记词
- bip32: HD 钱包
- aes-gcm: 对称加密
- zeroize: 内存擦除
- hmac: HMAC

## 配置

### 多租户配置

编辑 `config/flavors.json`:

```json
{
  "name": "customerA",
  "primaryColor": "#1E88E5",
  "apiBaseUrl": "https://api.customer-a.b2b2c-wallet.com"
}
```

### 安全配置

编辑 `config/app_config.json`:

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
flutter run
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
