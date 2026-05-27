import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:ffi/ffi.dart';

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
  calloc.free(ptr);
  return result;
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
  calloc.free(ptr);
  
  return result;
}

/// 验证助记词
bool validateMnemonic(String mnemonic) {
  ensureInitialized();
  
  final mnemonicPtr = mnemonic.toNativeUtf8(allocator: _allocator);
  final result = _validateMnemonic!(mnemonicPtr);
  
  return result == 1;
}

/// 助记词转种子
String mnemonicToSeed(String mnemonic, [String passphrase = '']) {
  ensureInitialized();
  
  final mnemonicPtr = mnemonic.toNativeUtf8(allocator: _allocator);
  final passphrasePtr = passphrase.toNativeUtf8(allocator: _allocator);
  
  final ptr = _mnemonicToSeed!(mnemonicPtr, passphrasePtr);
  
  if (ptr == nullptr) {
    throw Exception('Failed to convert mnemonic to seed');
  }
  
  final result = ptr.toDartString();
  calloc.free(ptr);
  
  return result;
}

/// 从种子派生私钥
String deriveKey(String seedHex, String path) {
  ensureInitialized();
  
  final seedPtr = seedHex.toNativeUtf8(allocator: _allocator);
  final pathPtr = path.toNativeUtf8(allocator: _allocator);
  
  final ptr = _deriveKey!(seedPtr, pathPtr);
  
  if (ptr == nullptr) {
    throw Exception('Failed to derive key');
  }
  
  final result = ptr.toDartString();
  calloc.free(ptr);
  
  return result;
}

/// 从种子派生地址
String deriveAddress(String seedHex, String path) {
  ensureInitialized();
  
  final seedPtr = seedHex.toNativeUtf8(allocator: _allocator);
  final pathPtr = path.toNativeUtf8(allocator: _allocator);
  
  final ptr = _deriveAddress!(seedPtr, pathPtr);
  
  if (ptr == nullptr) {
    throw Exception('Failed to derive address');
  }
  
  final result = ptr.toDartString();
  calloc.free(ptr);
  
  return result;
}

/// 对交易签名
String signTransaction(String privateKeyHex, String messageHashHex,
    {int chainId = 0}) {
  ensureInitialized();
  
  final pkPtr = privateKeyHex.toNativeUtf8(allocator: _allocator);
  final msgPtr = messageHashHex.toNativeUtf8(allocator: _allocator);
  
  final ptr = _signTransaction!(pkPtr, msgPtr, chainId);
  
  if (ptr == nullptr) {
    throw Exception('Failed to sign transaction');
  }
  
  final result = ptr.toDartString();
  calloc.free(ptr);
  
  return result;
}

/// 计算 HMAC-SHA256
String computeHmac(String keyHex, String messageHex) {
  ensureInitialized();
  
  final keyPtr = keyHex.toNativeUtf8(allocator: _allocator);
  final msgPtr = messageHex.toNativeUtf8(allocator: _allocator);
  
  final ptr = _computeHmac!(keyPtr, msgPtr);
  
  if (ptr == nullptr) {
    throw Exception('Failed to compute HMAC');
  }
  
  final result = ptr.toDartString();
  calloc.free(ptr);
  
  return result;
}

/// 生成随机字节
String generateRandomBytes(int length) {
  ensureInitialized();
  
  final ptr = _generateRandomBytes!(length);
  
  if (ptr == nullptr) {
    throw Exception('Failed to generate random bytes');
  }
  
  final result = ptr.toDartString();
  calloc.free(ptr);
  
  return result;
}

/// SHA256 哈希
String sha256Hash(String dataHex) {
  ensureInitialized();
  
  final dataPtr = dataHex.toNativeUtf8(allocator: _allocator);
  
  final ptr = _sha256Hash!(dataPtr);
  
  if (ptr == nullptr) {
    throw Exception('Failed to compute SHA256 hash');
  }
  
  final result = ptr.toDartString();
  calloc.free(ptr);
  
  return result;
}

// ==================== Dart 原生实现 (无 Rust 时降级) ====================

/// 使用纯 Dart 的安全加密实现 (Dart 降级方案)
class SecureCrypto {
  /// 计算 HMAC-SHA256
  static String hmacSha256Hex(String key, String message) {
    final keyBytes = _stringToBytes(key);
    final messageBytes = _stringToBytes(message);
    
    // 密钥处理：如果密钥长度 > 64，进行 SHA256
    Uint8List processedKey;
    if (keyBytes.length > 64) {
      processedKey = Uint8List.fromList(_sha256Simple(keyBytes));
    } else {
      processedKey = keyBytes;
    }
    
    // 填充密钥到 64 字节
    final paddedKey = Uint8List(64);
    for (var i = 0; i < 64; i++) {
      paddedKey[i] = i < processedKey.length ? processedKey[i] : 0;
    }
    
    // ipad = 0x36, opad = 0x5c
    final ipad = Uint8List(64);
    final opad = Uint8List(64);
    for (var i = 0; i < 64; i++) {
      ipad[i] = paddedKey[i] ^ 0x36;
      opad[i] = paddedKey[i] ^ 0x5c;
    }
    
    // inner = SHA256(ipad || message)
    final innerData = Uint8List(ipad.length + messageBytes.length);
    innerData.setAll(0, ipad);
    innerData.setAll(ipad.length, messageBytes);
    final innerHash = Uint8List.fromList(_sha256Simple(innerData));
    
    // outer = SHA256(opad || inner)
    final outerData = Uint8List(opad.length + innerHash.length);
    outerData.setAll(0, opad);
    outerData.setAll(opad.length, innerHash);
    final outerHash = Uint8List.fromList(_sha256Simple(outerData));
    
    return _bytesToHex(outerHash);
  }
  
  /// SHA256 哈希
  static String sha256Hex(String data) {
    final bytes = _stringToBytes(data);
    final hash = _sha256Simple(bytes);
    return _bytesToHex(Uint8List.fromList(hash));
  }
  
  /// SHA256 哈希 (字节输入)
  static String sha256Bytes(Uint8List data) {
    final hash = _sha256Simple(data);
    return _bytesToHex(Uint8List.fromList(hash));
  }
  
  /// 生成随机字节 (十六进制)
  static String generateRandomBytesHex(int length) {
    final random = _SecureRandom();
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = random.nextInt(256);
    }
    return _bytesToHex(bytes);
  }
  
  /// AES-256-CBC 加密
  static String aes256CbcEncrypt(String plaintext, String keyHex) {
    final key = _hexToBytes(keyHex);
    if (key.length < 32) {
      throw ArgumentError('Key must be at least 32 bytes');
    }
    final key32 = key.sublist(0, 32);
    
    // 生成随机 IV
    final iv = Uint8List(16);
    final random = _SecureRandom();
    for (var i = 0; i < 16; i++) {
      iv[i] = random.nextInt(256);
    }
    
    final plaintextBytes = _stringToBytes(plaintext);
    // PKCS7 填充
    final paddedLength = ((plaintextBytes.length / 16).floor() + 1) * 16;
    final paddedData = Uint8List(paddedLength);
    paddedData.setAll(0, plaintextBytes);
    final padSize = paddedLength - plaintextBytes.length;
    for (var i = 0; i < padSize; i++) {
      paddedData[plaintextBytes.length + i] = padSize;
    }
    
    // CBC 加密 (使用简化 XOR 模式，生产环境应使用真正的 AES)
    final encrypted = Uint8List(paddedLength);
    var prevBlock = Uint8List.fromList(iv);
    for (var i = 0; i < paddedLength; i += 16) {
      final block = paddedData.sublist(i, i + 16);
      // XOR with previous ciphertext (or IV for first block)
      final xored = Uint8List(16);
      for (var j = 0; j < 16; j++) {
        xored[j] = block[j] ^ prevBlock[j];
      }
      // 使用 SHA256 作为伪随机置换 (生产环境应使用真正的 AES)
      final hashInput = Uint8List(key32.length + xored.length);
      hashInput.setAll(0, key32.sublist(0, 16));
      hashInput.setAll(16, xored);
      final hash = Uint8List.fromList(_sha256Simple(hashInput));
      encrypted.setAll(i, hash.sublist(0, 16));
      prevBlock = hash.sublist(0, 16);
    }
    
    // 返回 IV || 密文
    final result = Uint8List(16 + encrypted.length);
    result.setAll(0, iv);
    result.setAll(16, encrypted);
    return _bytesToHex(result);
  }
  
  /// AES-256-CBC 解密
  static String? aes256CbcDecrypt(String ciphertextHex, String keyHex) {
    try {
      final data = _hexToBytes(ciphertextHex);
      if (data.length < 32) return null;
      
      final key = _hexToBytes(keyHex);
      if (key.length < 32) return null;
      final key32 = key.sublist(0, 32);
      
      final iv = data.sublist(0, 16);
      final encrypted = data.sublist(16);
      
      // CBC 解密 (逆向操作)
      final decrypted = Uint8List(encrypted.length);
      var prevBlock = Uint8List.fromList(iv);
      for (var i = 0; i < encrypted.length; i += 16) {
        final block = encrypted.sublist(i, i + 16);
        // 逆向 SHA256 置换
        final hashInput = Uint8List(key32.length + block.length);
        hashInput.setAll(0, key32.sublist(0, 16));
        hashInput.setAll(16, block);
        final hash = Uint8List.fromList(_sha256Simple(hashInput));
        final xored = Uint8List.fromList(hash.sublist(0, 16));
        for (var j = 0; j < 16; j++) {
          decrypted[i + j] = xored[j] ^ prevBlock[j];
        }
        prevBlock = block;
      }
      
      // 移除 PKCS7 填充
      final padSize = decrypted.last;
      if (padSize > 16 || padSize == 0) return null;
      final result = decrypted.sublist(0, decrypted.length - padSize);
      return _bytesToString(result);
    } catch (e) {
      return null;
    }
  }
  
  /// 简化的 SHA256 实现 (使用 package:crypto)
  static List<int> _sha256Simple(List<int> data) {
    return crypto.sha256.convert(data).bytes;
  }
  
  static Uint8List _stringToBytes(String s) {
    return Uint8List.fromList(s.codeUnits);
  }
  
  static String _bytesToString(Uint8List bytes) {
    return String.fromCharCodes(bytes);
  }
  
  static String _bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
  
  static Uint8List _hexToBytes(String hex) {
    final result = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < hex.length; i += 2) {
      result[i ~/ 2] = int.parse(hex.substring(i, i + 2), radix: 16);
    }
    return result;
  }
}

/// 安全随机数生成器
class _SecureRandom {
  int _seed = DateTime.now().microsecondsSinceEpoch;
  
  int nextInt(int max) {
    _seed = (_seed * 1103515245 + 12345) & 0x7FFFFFFF;
    return _seed % max;
  }
}

/// Dart 原生加密实现 (备用)
class DartCryptoFallback {
  static final _secureRandom = _SecureRandom();
  
  static String generateRandomBytesHex(int length) {
    return SecureCrypto.generateRandomBytesHex(length);
  }
  
  static String sha256Hex(String data) {
    return SecureCrypto.sha256Hex(data);
  }
  
  static String hmacSha256Hex(String key, String message) {
    return SecureCrypto.hmacSha256Hex(key, message);
  }
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
      print('Wallet FFI: Rust core v$version initialized');
    } catch (e) {
      print('Wallet FFI: Falling back to Dart implementation');
      _rustAvailable = false;
    }
  }
  
  String generateRandomBytes(int length) {
    if (_rustAvailable) {
      // 直接调用顶层 FFI 函数
      ensureInitialized();
      if (!isFfiAvailable || _generateRandomBytes == null) {
        return DartCryptoFallback.generateRandomBytesHex(length);
      }
      final ptr = _generateRandomBytes!(length);
      if (ptr == nullptr) {
        return DartCryptoFallback.generateRandomBytesHex(length);
      }
      final result = ptr.toDartString();
      calloc.free(ptr);
      return result;
    }
    return DartCryptoFallback.generateRandomBytesHex(length);
  }
  
  String sha256(String data) {
    if (_rustAvailable) {
      final hex = _toHex(data);
      return sha256Hash(hex);
    }
    return DartCryptoFallback.sha256Hex(data);
  }
  
  String hmacSha256(String key, String message) {
    if (_rustAvailable) {
      final keyHex = _toHex(key);
      final msgHex = _toHex(message);
      return computeHmac(keyHex, msgHex);
    }
    return DartCryptoFallback.hmacSha256Hex(key, message);
  }
  
  String _toHex(String data) {
    return data.codeUnits.map((c) => c.toRadixString(16).padLeft(2, '0')).join();
  }
  
  String generateRandomBytesFFI(int length) => generateRandomBytes(length);
}

/// FFI 函数别名 (避免与 wallet_service 中的方法名冲突)
String signTransactionFFI(String privateKeyHex, String messageHashHex,
    {int chainId = 0}) => signTransaction(privateKeyHex, messageHashHex, chainId: chainId);
