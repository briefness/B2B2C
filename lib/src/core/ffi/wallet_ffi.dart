import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

/// Rust 核心库 FFI 绑定
/// 
/// 本模块提供 Dart 与 Rust 核心库之间的直接内存级别通信，
/// 用于高频密码学计算（如签名），无序列化延迟。

// ==================== 类型定义 ====================

/// 内存分配器
final _allocator = calloc;

// ==================== 动态库加载 ====================

/// 加载 Rust 核心库
DynamicLibrary? _lib;
bool _ffiInitAttempted = false;
bool _ffiAvailable = false;

/// FFI 是否可用
bool get isFfiAvailable => _ffiAvailable;

/// 获取 Rust 核心库
DynamicLibrary get rustLib {
  if (_lib != null) return _lib!;
  
  if (Platform.isAndroid) {
    _lib = DynamicLibrary.open('libb2b2c_wallet_core.so');
  } else if (Platform.isIOS) {
    _lib = DynamicLibrary.process();
  } else if (Platform.isMacOS) {
    _lib = DynamicLibrary.open('libb2b2c_wallet_core.dylib');
  } else if (Platform.isLinux) {
    _lib = DynamicLibrary.open('libb2b2c_wallet_core.so');
  } else if (Platform.isWindows) {
    _lib = DynamicLibrary.open('b2b2c_wallet_core.dll');
  }
  
  return _lib!;
}

// ==================== FFI 函数签名 ====================

typedef _GenerateMnemonicNative = Pointer<Utf8> Function(Int32 strength);
typedef _GenerateMnemonicDart = Pointer<Utf8> Function(int strength);

typedef _FreeMnemonicNative = Void Function(Pointer<Utf8> ptr);
typedef _FreeMnemonicDart = void Function(Pointer<Utf8> ptr);

typedef _MnemonicToSeedNative = Pointer<Utf8> Function(
    Pointer<Utf8> mnemonic, Pointer<Utf8> passphrase);
typedef _MnemonicToSeedDart = Pointer<Utf8> Function(
    Pointer<Utf8> mnemonic, Pointer<Utf8> passphrase);

typedef _ValidateMnemonicNative = Int32 Function(Pointer<Utf8> mnemonic);
typedef _ValidateMnemonicDart = int Function(Pointer<Utf8> mnemonic);

typedef _DeriveKeyNative = Pointer<Utf8> Function(
    Pointer<Utf8> seedHex, Pointer<Utf8> path);
typedef _DeriveKeyDart = Pointer<Utf8> Function(
    Pointer<Utf8> seedHex, Pointer<Utf8> path);

typedef _DeriveAddressNative = Pointer<Utf8> Function(
    Pointer<Utf8> seedHex, Pointer<Utf8> path);
typedef _DeriveAddressDart = Pointer<Utf8> Function(
    Pointer<Utf8> seedHex, Pointer<Utf8> path);

typedef _SignTransactionNative = Pointer<Utf8> Function(
    Pointer<Utf8> privateKeyHex,
    Pointer<Utf8> messageHashHex,
    Uint64 chainId);
typedef _SignTransactionDart = Pointer<Utf8> Function(
    Pointer<Utf8> privateKeyHex,
    Pointer<Utf8> messageHashHex,
    int chainId);

typedef _ComputeHmacNative = Pointer<Utf8> Function(
    Pointer<Utf8> keyHex, Pointer<Utf8> messageHex);
typedef _ComputeHmacDart = Pointer<Utf8> Function(
    Pointer<Utf8> keyHex, Pointer<Utf8> messageHex);

typedef _GenerateRandomBytesNative = Pointer<Utf8> Function(Int32 len);
typedef _GenerateRandomBytesDart = Pointer<Utf8> Function(int len);

typedef _Sha256HashNative = Pointer<Utf8> Function(Pointer<Utf8> dataHex);
typedef _Sha256HashDart = Pointer<Utf8> Function(Pointer<Utf8> dataHex);

typedef _GetVersionNative = Pointer<Utf8> Function();
typedef _GetVersionDart = Pointer<Utf8> Function();

// ==================== 函数引用 ====================

_GenerateMnemonicDart? _generateMnemonic;
_FreeMnemonicDart? _freeMnemonic;
_FreeMnemonicDart? _freeString;
_MnemonicToSeedDart? _mnemonicToSeed;
_ValidateMnemonicDart? _validateMnemonic;
_DeriveKeyDart? _deriveKey;
_DeriveAddressDart? _deriveAddress;
_SignTransactionDart? _signTransaction;
_ComputeHmacDart? _computeHmac;
_GenerateRandomBytesDart? _generateRandomBytes;
_Sha256HashDart? _sha256Hash;
_GetVersionDart? _getVersion;

/// 初始化 FFI 函数绑定
void _initFFI() {
  final lib = rustLib;
  
  _generateMnemonic =
      lib.lookupFunction<_GenerateMnemonicNative, _GenerateMnemonicDart>(
          'generate_mnemonic');
  
  _freeMnemonic =
      lib.lookupFunction<_FreeMnemonicNative, _FreeMnemonicDart>(
          'free_mnemonic');
  
  // free_string 是 Rust 分配器的正确释放器，用于释放所有 Rust 返回的指针
  _freeString =
      lib.lookupFunction<_FreeMnemonicNative, _FreeMnemonicDart>(
          'free_string');
  
  _mnemonicToSeed =
      lib.lookupFunction<_MnemonicToSeedNative, _MnemonicToSeedDart>(
          'mnemonic_to_seed_hex');
  
  _validateMnemonic =
      lib.lookupFunction<_ValidateMnemonicNative, _ValidateMnemonicDart>(
          'validate_mnemonic');
  
  _deriveKey =
      lib.lookupFunction<_DeriveKeyNative, _DeriveKeyDart>('derive_key');
  
  _deriveAddress =
      lib.lookupFunction<_DeriveAddressNative, _DeriveAddressDart>(
          'derive_address');
  
  _signTransaction =
      lib.lookupFunction<_SignTransactionNative, _SignTransactionDart>(
          'sign_transaction');
  
  _computeHmac =
      lib.lookupFunction<_ComputeHmacNative, _ComputeHmacDart>('compute_hmac');
  
  _generateRandomBytes =
      lib.lookupFunction<_GenerateRandomBytesNative, _GenerateRandomBytesDart>(
          'generate_random_bytes');
  
  _sha256Hash =
      lib.lookupFunction<_Sha256HashNative, _Sha256HashDart>('sha256_hash');
  
  _getVersion =
      lib.lookupFunction<_GetVersionNative, _GetVersionDart>('get_version');
}

/// 确保 FFI 已初始化
void ensureInitialized() {
  if (_ffiInitAttempted) return;
  _ffiInitAttempted = true;
  
  try {
    _initFFI();
    _ffiAvailable = true;
  } catch (e) {
    _ffiAvailable = false;
    // Rust 核心库未编译/未链接，将使用 Dart fallback
  }
}

// ==================== Dart 封装接口 ====================

/// 助记词强度
enum MnemonicStrength {
  bits128(128, 12),
  bits192(192, 18),
  bits256(256, 24);

  const MnemonicStrength(this.value, this.wordCount);
  final int value;
  final int wordCount;
}

/// 核心库版本
String getCoreVersion() {
  ensureInitialized();
  final ptr = _getVersion!();
  final result = ptr.toDartString();
  _freeRustString(ptr);
  return result;
}

/// 释放 Rust 返回的 C 字符串指针
///
/// ⚠️ Rust 通过 CString::into_raw() 分配的内存必须由 Rust 的 free_string 释放，
///    不能用 calloc.free()（分配器不匹配会导致 UB / 崩溃）。
/// Rust 端会在释放前对内存进行 zeroize，确保敏感数据不残留。
void _freeRustString(Pointer<Utf8> ptr) {
  if (ptr == nullptr) return;
  if (_freeString != null) {
    _freeString!(ptr);
  } else if (_freeMnemonic != null) {
    _freeMnemonic!(ptr);
  }
}

/// 生成助记词
String generateMnemonic([MnemonicStrength strength = MnemonicStrength.bits128]) {
  ensureInitialized();
  if (!_ffiAvailable) {
    throw Exception('Rust core library not available. Please build rust_core first.');
  }
  
  final ptr = _generateMnemonic!(strength.value);
  if (ptr == nullptr) {
    throw Exception('Failed to generate mnemonic');
  }
  
  final result = ptr.toDartString();
  _freeRustString(ptr);
  
  return result;
}

/// 验证助记词
bool validateMnemonic(String mnemonic) {
  ensureInitialized();
  
  final mnemonicPtr = mnemonic.toNativeUtf8(allocator: _allocator);
  try {
    final result = _validateMnemonic!(mnemonicPtr);
    return result == 1;
  } finally {
    calloc.free(mnemonicPtr);
  }
}

/// 助记词转种子
String mnemonicToSeed(String mnemonic, [String passphrase = '']) {
  ensureInitialized();
  
  final mnemonicPtr = mnemonic.toNativeUtf8(allocator: _allocator);
  final passphrasePtr = passphrase.toNativeUtf8(allocator: _allocator);
  
  try {
    final ptr = _mnemonicToSeed!(mnemonicPtr, passphrasePtr);
    if (ptr == nullptr) {
      throw Exception('Failed to convert mnemonic to seed');
    }
    final result = ptr.toDartString();
    _freeRustString(ptr);
    return result;
  } finally {
    calloc.free(mnemonicPtr);
    calloc.free(passphrasePtr);
  }
}

/// 从种子派生私钥
String deriveKey(String seedHex, String path) {
  ensureInitialized();
  
  final seedPtr = seedHex.toNativeUtf8(allocator: _allocator);
  final pathPtr = path.toNativeUtf8(allocator: _allocator);
  
  try {
    final ptr = _deriveKey!(seedPtr, pathPtr);
    if (ptr == nullptr) {
      throw Exception('Failed to derive key');
    }
    final result = ptr.toDartString();
    _freeRustString(ptr);
    return result;
  } finally {
    calloc.free(seedPtr);
    calloc.free(pathPtr);
  }
}

/// 从种子派生地址
String deriveAddress(String seedHex, String path) {
  ensureInitialized();
  
  final seedPtr = seedHex.toNativeUtf8(allocator: _allocator);
  final pathPtr = path.toNativeUtf8(allocator: _allocator);
  
  try {
    final ptr = _deriveAddress!(seedPtr, pathPtr);
    if (ptr == nullptr) {
      throw Exception('Failed to derive address');
    }
    final result = ptr.toDartString();
    _freeRustString(ptr);
    return result;
  } finally {
    calloc.free(seedPtr);
    calloc.free(pathPtr);
  }
}

/// 对交易签名
String signTransaction(String privateKeyHex, String messageHashHex,
    {int chainId = 0}) {
  ensureInitialized();
  
  final pkPtr = privateKeyHex.toNativeUtf8(allocator: _allocator);
  final msgPtr = messageHashHex.toNativeUtf8(allocator: _allocator);
  
  try {
    final ptr = _signTransaction!(pkPtr, msgPtr, chainId);
    if (ptr == nullptr) {
      throw Exception('Failed to sign transaction');
    }
    final result = ptr.toDartString();
    _freeRustString(ptr);
    return result;
  } finally {
    // 私钥参数指针含敏感数据，释放前先置零
    _zeroNativeUtf8(pkPtr);
    calloc.free(pkPtr);
    calloc.free(msgPtr);
  }
}

/// 计算 HMAC-SHA256
String computeHmac(String keyHex, String messageHex) {
  ensureInitialized();
  
  final keyPtr = keyHex.toNativeUtf8(allocator: _allocator);
  final msgPtr = messageHex.toNativeUtf8(allocator: _allocator);
  
  try {
    final ptr = _computeHmac!(keyPtr, msgPtr);
    if (ptr == nullptr) {
      throw Exception('Failed to compute HMAC');
    }
    final result = ptr.toDartString();
    _freeRustString(ptr);
    return result;
  } finally {
    // HMAC 密钥含敏感数据，释放前先置零
    _zeroNativeUtf8(keyPtr);
    calloc.free(keyPtr);
    calloc.free(msgPtr);
  }
}

/// 生成随机字节
String generateRandomBytes(int length) {
  ensureInitialized();
  
  final ptr = _generateRandomBytes!(length);
  
  if (ptr == nullptr) {
    throw Exception('Failed to generate random bytes');
  }
  
  final result = ptr.toDartString();
  _freeRustString(ptr);
  
  return result;
}

/// SHA256 哈希
String sha256Hash(String dataHex) {
  ensureInitialized();
  
  final dataPtr = dataHex.toNativeUtf8(allocator: _allocator);
  
  try {
    final ptr = _sha256Hash!(dataPtr);
    if (ptr == nullptr) {
      throw Exception('Failed to compute SHA256 hash');
    }
    final result = ptr.toDartString();
    _freeRustString(ptr);
    return result;
  } finally {
    calloc.free(dataPtr);
  }
}

/// 将原生 UTF8 缓冲区置零（用于释放含敏感数据的 Dart 分配指针）
void _zeroNativeUtf8(Pointer<Utf8> ptr) {
  if (ptr == nullptr) return;
  final bytes = ptr.cast<Uint8>();
  var i = 0;
  // 逐字节置零直到 null 终止符
  while (bytes[i] != 0) {
    bytes[i] = 0;
    i++;
  }
}

// ==================== Dart 安全加密工具 ====================

/// 使用 package:crypto 的安全加密实现
///
/// 当 Rust 核心不可用时作为降级方案（仅限 HMAC/SHA256/随机数，
/// AES 等高级操作必须使用 Rust 或 pointycastle）。
class SecureCrypto {
  /// 计算 HMAC-SHA256（使用 package:crypto 的经过验证的实现）
  static String hmacSha256Hex(String key, String message) {
    final keyBytes = utf8.encode(key);
    final messageBytes = utf8.encode(message);
    final hmac = crypto.Hmac(crypto.sha256, keyBytes);
    final digest = hmac.convert(messageBytes);
    return digest.toString();
  }

  /// SHA256 哈希
  static String sha256Hex(String data) {
    final bytes = utf8.encode(data);
    final digest = crypto.sha256.convert(bytes);
    return digest.toString();
  }

  /// SHA256 哈希 (字节输入)
  static String sha256Bytes(Uint8List data) {
    final digest = crypto.sha256.convert(data);
    return digest.toString();
  }

  /// 生成随机字节 (十六进制)
  ///
  /// 使用 dart:math 的 Random.secure() 生成密码学安全的随机数。
  static String generateRandomBytesHex(int length) {
    final random = Random.secure();
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = random.nextInt(256);
    }
    return _bytesToHex(bytes);
  }

  static String _bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}

/// 异常：Rust 核心库不可用
class RustCoreUnavailableException implements Exception {
  final String message;
  RustCoreUnavailableException([this.message = 'Rust 核心库未加载，将无法使用加密功能']);
  @override
  String toString() => 'RustCoreUnavailableException: $message';
}

/// 钱包 FFI 服务
class WalletFFIService {
  bool _rustAvailable = false;
  
  bool get isRustAvailable => _rustAvailable;
  
  Future<void> initialize() async {
    try {
      ensureInitialized();
      final version = getCoreVersion();
      _rustAvailable = version.isNotEmpty;
      debugPrint('[WalletFFI] Rust core v$version initialized');
    } catch (e) {
      _rustAvailable = false;
      if (kReleaseMode) {
        // Release 模式下 Rust 核心库不可用是致命错误，必须阻断启动
        throw RustCoreUnavailableException(
          'Rust 核心库加载失败: $e。此错误在 Release 模式下不可恢复。',
        );
      }
      // Debug 模式允许继续，但记录警告
      debugPrint('[WalletFFI] ⚠️ WARNING: Rust core unavailable, using Dart crypto fallback (debug only)');
    }
  }

  String generateRandomBytes(int length) {
    if (_rustAvailable) {
      ensureInitialized();
      if (!isFfiAvailable || _generateRandomBytes == null) {
        return SecureCrypto.generateRandomBytesHex(length);
      }
      final ptr = _generateRandomBytes!(length);
      if (ptr == nullptr) {
        return SecureCrypto.generateRandomBytesHex(length);
      }
      final result = ptr.toDartString();
      _freeRustString(ptr);
      return result;
    }
    // Dart fallback 使用 Random.secure()
    return SecureCrypto.generateRandomBytesHex(length);
  }

  String sha256(String data) {
    if (_rustAvailable) {
      final hex = _toHex(data);
      return sha256Hash(hex);
    }
    return SecureCrypto.sha256Hex(data);
  }

  String hmacSha256(String key, String message) {
    if (_rustAvailable) {
      final keyHex = _toHex(key);
      final msgHex = _toHex(message);
      return computeHmac(keyHex, msgHex);
    }
    return SecureCrypto.hmacSha256Hex(key, message);
  }
  
  String _toHex(String data) {
    return data.codeUnits.map((c) => c.toRadixString(16).padLeft(2, '0')).join();
  }
  
  String generateRandomBytesFFI(int length) => generateRandomBytes(length);
}

/// FFI 函数别名 (避免与 wallet_service 中的方法名冲突)
String signTransactionFFI(String privateKeyHex, String messageHashHex,
    {int chainId = 0}) => signTransaction(privateKeyHex, messageHashHex, chainId: chainId);
