import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// secp256k1 ECDSA 签名/验签工具
///
/// 用于配置签名验证和 M-of-N 多签审批。
/// 基于 pointycastle 实现真正的非对称签名。
///
/// 注意：客户端仅需 verify，sign 仅用于测试和 B 端管理工具。

class Secp256k1Utils {
  static final ECDomainParameters _domainParams =
      ECDomainParameters('secp256k1');

  // ==================== 验签 ====================

  /// 验证 ECDSA 签名
  ///
  /// [messageHash] - SHA-256 消息哈希 (32 字节)
  /// [signatureHex] - DER 编码的签名 (hex)
  /// [publicKeyHex] - 非压缩公钥 (04 + 64 字节 hex) 或压缩公钥 (02/03 + 32 字节 hex)
  ///
  /// 返回 true 表示签名有效
  static bool verify({
    required Uint8List messageHash,
    required String signatureHex,
    required String publicKeyHex,
  }) {
    try {
      // 解析公钥
      final pubKeyBytes = _hexToBytes(publicKeyHex);
      final ecPoint = _domainParams.curve.decodePoint(pubKeyBytes);
      if (ecPoint == null) return false;
      final publicKey =
          ECPublicKey(ecPoint, _domainParams);

      // 解析 DER 签名
      final sigBytes = _hexToBytes(signatureHex);
      final ecSignature = _decodeDerSignature(sigBytes);
      if (ecSignature == null) return false;

      // 验签
      final signer = ECDSASigner(null); // 消息已是哈希，不需要再次哈希
      signer.init(false, PublicKeyParameter<ECPublicKey>(publicKey));
      return signer.verifySignature(messageHash, ecSignature);
    } catch (_) {
      return false;
    }
  }

  /// 验证消息签名（自动做 SHA-256 哈希）
  ///
  /// [message] - 原始消息字符串
  /// [signatureHex] - DER 编码的签名 (hex)
  /// [publicKeyHex] - 公钥 (hex)
  static bool verifyMessage({
    required String message,
    required String signatureHex,
    required String publicKeyHex,
  }) {
    final messageBytes = utf8.encode(message);
    final hash = SHA256Digest().process(Uint8List.fromList(messageBytes));
    return verify(
      messageHash: hash,
      signatureHex: signatureHex,
      publicKeyHex: publicKeyHex,
    );
  }

  // ==================== 签名 ====================

  /// ECDSA 签名
  ///
  /// ⚠️ 仅用于测试和 B 端管理工具，客户端不应持有签名私钥。
  ///
  /// [messageHash] - SHA-256 消息哈希 (32 字节)
  /// [privateKeyHex] - 私钥 (32 字节 hex)
  ///
  /// 返回 DER 编码的签名 (hex)
  static String sign({
    required Uint8List messageHash,
    required String privateKeyHex,
  }) {
    final privKeyBytes = _hexToBytes(privateKeyHex);
    final privateKey = ECPrivateKey(
      _bytesToBigInt(privKeyBytes),
      _domainParams,
    );

    final signer = ECDSASigner(null);
    signer.init(
      true,
      ParametersWithRandom(
        PrivateKeyParameter<ECPrivateKey>(privateKey),
        _secureRandom(),
      ),
    );

    final ecSignature =
        signer.generateSignature(messageHash) as ECSignature;

    // 规范化 S 值 (low-S，防止签名可锻性)
    final normalizedSig = _normalizeSignature(ecSignature);

    return _bytesToHex(_encodeDerSignature(normalizedSig));
  }

  /// 签名消息（自动做 SHA-256 哈希）
  static String signMessage({
    required String message,
    required String privateKeyHex,
  }) {
    final messageBytes = utf8.encode(message);
    final hash = SHA256Digest().process(Uint8List.fromList(messageBytes));
    return sign(messageHash: hash, privateKeyHex: privateKeyHex);
  }

  // ==================== 密钥生成 ====================

  /// 生成 secp256k1 密钥对（仅用于测试）
  ///
  /// 返回 (privateKeyHex, publicKeyHex)
  /// publicKeyHex 为非压缩格式 (04 + X + Y)
  static (String privateKey, String publicKey) generateKeyPair() {
    final keyGen = ECKeyGenerator();
    keyGen.init(ParametersWithRandom(
      ECKeyGeneratorParameters(_domainParams),
      _secureRandom(),
    ));

    final keyPair = keyGen.generateKeyPair();
    final privateKey = keyPair.privateKey as ECPrivateKey;
    final publicKey = keyPair.publicKey as ECPublicKey;

    final privKeyHex = _bigIntToHex(privateKey.d!, 32);
    final pubKeyHex = _bytesToHex(publicKey.Q!.getEncoded(false));

    return (privKeyHex, pubKeyHex);
  }

  // ==================== DER 编解码 ====================

  /// 解码 DER 格式的 ECDSA 签名
  static ECSignature? _decodeDerSignature(Uint8List derBytes) {
    try {
      if (derBytes.length < 8) return null;
      if (derBytes[0] != 0x30) return null;

      var offset = 2;

      // 解析 R
      if (derBytes[offset] != 0x02) return null;
      offset++;
      final rLength = derBytes[offset];
      offset++;
      final rBytes = derBytes.sublist(offset, offset + rLength);
      offset += rLength;

      // 解析 S
      if (derBytes[offset] != 0x02) return null;
      offset++;
      final sLength = derBytes[offset];
      offset++;
      final sBytes = derBytes.sublist(offset, offset + sLength);

      final r = _bytesToBigInt(rBytes);
      final s = _bytesToBigInt(sBytes);

      return ECSignature(r, s);
    } catch (_) {
      return null;
    }
  }

  /// 编码 ECDSA 签名为 DER 格式
  static Uint8List _encodeDerSignature(ECSignature sig) {
    final rBytes = _bigIntToUnsignedBytes(sig.r);
    final sBytes = _bigIntToUnsignedBytes(sig.s);

    // DER: 0x30 [total_length] 0x02 [r_length] [r] 0x02 [s_length] [s]
    final totalLength = 2 + rBytes.length + 2 + sBytes.length;
    final result = Uint8List(2 + totalLength);

    var offset = 0;
    result[offset++] = 0x30; // SEQUENCE
    result[offset++] = totalLength;
    result[offset++] = 0x02; // INTEGER
    result[offset++] = rBytes.length;
    result.setAll(offset, rBytes);
    offset += rBytes.length;
    result[offset++] = 0x02; // INTEGER
    result[offset++] = sBytes.length;
    result.setAll(offset, sBytes);

    return result;
  }

  /// 规范化签名 S 值 (BIP-62 low-S)
  static ECSignature _normalizeSignature(ECSignature sig) {
    final halfN = _domainParams.n >> 1;
    if (sig.s.compareTo(halfN) > 0) {
      return ECSignature(sig.r, _domainParams.n - sig.s);
    }
    return sig;
  }

  // ==================== 工具方法 ====================

  static SecureRandom _secureRandom() {
    final secureRandom = FortunaRandom();
    final random = Random.secure();
    final seeds = List<int>.generate(32, (_) => random.nextInt(256));
    secureRandom.seed(KeyParameter(Uint8List.fromList(seeds)));
    return secureRandom;
  }

  static Uint8List _hexToBytes(String hex) {
    final h = hex.startsWith('0x') ? hex.substring(2) : hex;
    final result = Uint8List(h.length ~/ 2);
    for (var i = 0; i < h.length; i += 2) {
      result[i ~/ 2] = int.parse(h.substring(i, i + 2), radix: 16);
    }
    return result;
  }

  static String _bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static BigInt _bytesToBigInt(List<int> bytes) {
    var result = BigInt.zero;
    for (final byte in bytes) {
      result = (result << 8) | BigInt.from(byte);
    }
    return result;
  }

  static String _bigIntToHex(BigInt value, int length) {
    return value.toRadixString(16).padLeft(length * 2, '0');
  }

  /// BigInt 转无符号字节（DER 编码需要前导 0x00 表示正数）
  static Uint8List _bigIntToUnsignedBytes(BigInt value) {
    var hex = value.toRadixString(16);
    if (hex.length.isOdd) hex = '0$hex';
    final bytes = _hexToBytes(hex);
    // 如果最高位为 1，DER 编码需要前导 0x00 表示正数
    if (bytes[0] & 0x80 != 0) {
      final padded = Uint8List(bytes.length + 1);
      padded[0] = 0x00;
      padded.setAll(1, bytes);
      return padded;
    }
    return bytes;
  }
}
