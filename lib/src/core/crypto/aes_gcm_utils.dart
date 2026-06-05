import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// AES-256-GCM 认证加密工具
///
/// 用于加密敏感数据（如助记词）。基于 pointycastle 的经过验证的实现。
///
/// 加密密钥通过 PBKDF2 从用户口令派生，不直接存储密钥。
/// 输出格式：salt(16) + nonce(12) + ciphertext+tag
///
/// ⚠️ 当 Rust 核心库可用时，应优先使用 Rust 的 AES-GCM；
///    此实现作为 Dart 侧的安全基线（非伪实现）。

class AesGcmUtils {
  static const int _saltLength = 16;
  static const int _nonceLength = 12;
  static const int _keyLength = 32; // AES-256
  static const int _pbkdf2Iterations = 100000;

  /// 用口令加密明文
  ///
  /// 返回 hex 编码的 (salt + nonce + ciphertext+tag)
  static String encryptWithPassphrase(String plaintext, String passphrase) {
    final salt = _randomBytes(_saltLength);
    final nonce = _randomBytes(_nonceLength);
    final key = _deriveKey(passphrase, salt);

    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        true,
        AEADParameters(
          KeyParameter(key),
          128, // tag 长度 (bits)
          nonce,
          Uint8List(0), // AAD
        ),
      );

    final plaintextBytes = Uint8List.fromList(utf8.encode(plaintext));
    final ciphertext = cipher.process(plaintextBytes);

    // 组合 salt + nonce + ciphertext
    final result = Uint8List(salt.length + nonce.length + ciphertext.length)
      ..setAll(0, salt)
      ..setAll(salt.length, nonce)
      ..setAll(salt.length + nonce.length, ciphertext);

    return _bytesToHex(result);
  }

  /// 用口令解密
  ///
  /// 输入 hex 编码的 (salt + nonce + ciphertext+tag)
  /// 解密失败（口令错误或数据被篡改）返回 null
  static String? decryptWithPassphrase(String encryptedHex, String passphrase) {
    try {
      final data = _hexToBytes(encryptedHex);
      if (data.length < _saltLength + _nonceLength + 16) return null;

      final salt = data.sublist(0, _saltLength);
      final nonce = data.sublist(_saltLength, _saltLength + _nonceLength);
      final ciphertext = data.sublist(_saltLength + _nonceLength);
      final key = _deriveKey(passphrase, salt);

      final cipher = GCMBlockCipher(AESEngine())
        ..init(
          false,
          AEADParameters(
            KeyParameter(key),
            128,
            nonce,
            Uint8List(0),
          ),
        );

      final decrypted = cipher.process(ciphertext);
      return utf8.decode(decrypted);
    } catch (_) {
      // GCM 认证标签验证失败会抛异常
      return null;
    }
  }

  // ==================== 工具方法 ====================

  /// PBKDF2-HMAC-SHA256 派生密钥
  static Uint8List _deriveKey(String passphrase, Uint8List salt) {
    final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(salt, _pbkdf2Iterations, _keyLength));
    return derivator.process(Uint8List.fromList(utf8.encode(passphrase)));
  }

  static Uint8List _randomBytes(int length) {
    final random = Random.secure();
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = random.nextInt(256);
    }
    return bytes;
  }

  static String _bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static Uint8List _hexToBytes(String hex) {
    final h = hex.startsWith('0x') ? hex.substring(2) : hex;
    final result = Uint8List(h.length ~/ 2);
    for (var i = 0; i < h.length; i += 2) {
      result[i ~/ 2] = int.parse(h.substring(i, i + 2), radix: 16);
    }
    return result;
  }
}
