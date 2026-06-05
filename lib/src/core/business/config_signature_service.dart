import 'dart:convert';

import '../crypto/ecdsa_utils.dart';

// ==================== 独立类型定义 ====================

/// 配置载荷
class ConfigPayload {
  final String id;
  final String type;
  final Map<String, dynamic> data;
  final String version;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final String signature;
  
  ConfigPayload({
    required this.id,
    required this.type,
    required this.data,
    required this.version,
    required this.createdAt,
    this.expiresAt,
    required this.signature,
  });
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'data': data,
    'version': version,
    'createdAt': createdAt.toIso8601String(),
    'expiresAt': expiresAt?.toIso8601String(),
  };
  
  String toSignString() {
    return jsonEncode(toJson());
  }
}

/// 验签结果
class ConfigVerificationResult {
  final bool isValid;
  final String? error;
  final ConfigPayload? payload;
  
  ConfigVerificationResult({
    required this.isValid,
    this.error,
    this.payload,
  });
}

/// 签名结果
class ConfigSignResult {
  final bool success;
  final String? signature;
  final String? error;
  
  ConfigSignResult({required this.success, this.signature, this.error});
}

// ==================== 配置签名验签服务 ====================

/// 配置签名验签服务
/// 
/// 用于 B 端动态配置的完整性验证
/// 确保配置文件在传输过程中未被篡改

class ConfigSignatureService {
  // ==================== 单例 ====================
  
  static final ConfigSignatureService _instance = ConfigSignatureService._internal();
  factory ConfigSignatureService() => _instance;
  ConfigSignatureService._internal();
  
  // ==================== 配置 ====================
  
  /// 内置的 secp256k1 公钥 (用于验证配置签名)
  ///
  /// 格式：非压缩公钥 (04 + X(32字节) + Y(32字节))，共 130 个 hex 字符。
  /// ⚠️ 生产环境必须替换为真实的 B 端配置签名公钥，并优先通过
  ///    SecurityConfigService 动态加载 + 公钥 pinning。
  /// ⚠️ 签名私钥仅存在于 B 端签发服务，绝不内置于客户端。
  static const String builtinPublicKey =
      '04PLACEHOLDER_REPLACE_WITH_REAL_SECP256K1_PUBLIC_KEY_0000000000000000000000000000000000000000000000000000000000000000';
  
  /// 可配置的公钥 (从 SecurityConfigService 加载)
  String? _configurablePublicKey;
  
  /// 设置可配置的公钥
  void setPublicKey(String publicKey) {
    _configurablePublicKey = publicKey;
  }
  
  /// 获取当前使用的公钥
  String get _activePublicKey => _configurablePublicKey ?? builtinPublicKey;
  
  // ==================== 服务方法 ====================
  
  /// 验签配置
  ConfigVerificationResult verifyConfig(String signedConfigJson) {
    try {
      final json = jsonDecode(signedConfigJson) as Map<String, dynamic>;
      
      // 提取签名
      final signature = json['signature'] as String?;
      if (signature == null || signature.isEmpty) {
        return ConfigVerificationResult(
          isValid: false,
          error: 'Missing signature',
        );
      }
      
      // 提取配置数据
      final configData = Map<String, dynamic>.from(json);
      configData.remove('signature');
      
      // 重建配置字符串
      final sortedJson = _sortJsonKeys(configData);
      final signString = jsonEncode(sortedJson);
      
      // 验证签名
      final isValid = _verifySignature(signString, signature, _activePublicKey);
      
      if (!isValid) {
        return ConfigVerificationResult(
          isValid: false,
          error: 'Invalid signature - config may have been tampered',
        );
      }
      
      // 解析配置载荷
      final payload = ConfigPayload(
        id: json['id'] ?? '',
        type: json['type'] ?? '',
        data: json['data'] ?? {},
        version: json['version'] ?? '',
        createdAt: json['createdAt'] != null 
            ? DateTime.parse(json['createdAt']) 
            : DateTime.now(),
        expiresAt: json['expiresAt'] != null 
            ? DateTime.parse(json['expiresAt']) 
            : null,
        signature: signature,
      );
      
      // 检查过期
      if (payload.expiresAt != null && DateTime.now().isAfter(payload.expiresAt!)) {
        return ConfigVerificationResult(
          isValid: false,
          error: 'Config has expired',
          payload: payload,
        );
      }
      
      return ConfigVerificationResult(
        isValid: true,
        payload: payload,
      );
    } catch (e) {
      return ConfigVerificationResult(
        isValid: false,
        error: 'Parse error: $e',
      );
    }
  }
  
  /// 签名配置 (B 端管理员使用)
  ConfigSignResult signConfig({
    required String id,
    required String type,
    required Map<String, dynamic> data,
    required String version,
    String? privateKey,
    Duration? validity,
  }) {
    try {
      // 验证私钥
      if (privateKey == null || privateKey.isEmpty) {
        return ConfigSignResult(
          success: false,
          error: 'Private key required for signing',
        );
      }
      
      final now = DateTime.now();
      final payload = {
        'id': id,
        'type': type,
        'data': data,
        'version': version,
        'createdAt': now.toIso8601String(),
        'expiresAt': validity != null 
            ? now.add(validity).toIso8601String() 
            : null,
      };
      
      // 排序键并生成签名字符串
      final sortedJson = _sortJsonKeys(payload);
      final signString = jsonEncode(sortedJson);
      
      // 生成签名
      final signature = _sign(signString, privateKey);
      
      // 构建带签名的配置
      final signedConfig = Map<String, dynamic>.from(sortedJson);
      signedConfig['signature'] = signature;
      
      return ConfigSignResult(
        success: true,
        signature: jsonEncode(signedConfig),
      );
    } catch (e) {
      return ConfigSignResult(
        success: false,
        error: 'Sign error: $e',
      );
    }
  }
  
  /// 解析并验证配置
  ConfigVerificationResult parseAndVerify(String signedConfigJson) {
    return verifyConfig(signedConfigJson);
  }
  
  // ==================== 私有方法 ====================
  
  /// 排序 JSON 键 (确保签名一致性)
  Map<String, dynamic> _sortJsonKeys(Map<String, dynamic> json) {
    final sorted = <String, dynamic>{};
    final keys = json.keys.toList()..sort();
    
    for (final key in keys) {
      final value = json[key];
      if (value is Map<String, dynamic>) {
        sorted[key] = _sortJsonKeys(value);
      } else if (value is List) {
        sorted[key] = value.map((item) {
          if (item is Map<String, dynamic>) {
            return _sortJsonKeys(item);
          }
          return item;
        }).toList();
      } else {
        sorted[key] = value;
      }
    }
    
    return sorted;
  }
  
  /// 生成签名 (secp256k1 ECDSA)
  ///
  /// ⚠️ 仅用于测试和 B 端管理工具。客户端不应持有签名私钥。
  /// 返回 DER 编码的签名 (hex)。
  String _sign(String message, String privateKeyHex) {
    return Secp256k1Utils.signMessage(
      message: message,
      privateKeyHex: privateKeyHex,
    );
  }

  /// 验证签名 (secp256k1 ECDSA)
  ///
  /// 使用内置/动态加载的公钥验证 DER 编码的 ECDSA 签名。
  /// pointycastle 的验签内部已是恒定时间，无需手动比较。
  bool _verifySignature(String message, String signature, String publicKeyHex) {
    return Secp256k1Utils.verifyMessage(
      message: message,
      signatureHex: signature,
      publicKeyHex: publicKeyHex,
    );
  }
}
