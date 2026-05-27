import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

/// 安全配置服务
/// 
/// 从配置文件加载安全相关参数：
/// - SSL Pinning 证书哈希
/// - HMAC 密钥
/// - B 端签名公钥

class SecurityConfigService {
  static final SecurityConfigService _instance = SecurityConfigService._internal();
  factory SecurityConfigService() => _instance;
  SecurityConfigService._internal();
  
  // ==================== 证书配置 ====================
  
  /// API 服务器证书哈希
  List<String> get apiCertificateHashes => _config['ssl_pinning']?['api_certificates'] ?? [];
  
  /// WebSocket 服务器证书哈希
  List<String> get wsCertificateHashes => _config['ssl_pinning']?['ws_certificates'] ?? [];
  
  /// 所有证书哈希
  List<String> get allCertificateHashes => [...apiCertificateHashes, ...wsCertificateHashes];
  
  /// 备用证书哈希 (用于证书轮换)
  List<String> get backupCertificateHashes => _config['ssl_pinning']?['backup_certificates'] ?? [];
  
  // ==================== HMAC 配置 ====================
  
  /// HMAC 密钥
  String? get hmacKey => _config['hmac']?['key'];
  
  /// HMAC 签名有效期 (秒)
  int get hmacTimestampTolerance => _config['hmac']?['timestamp_tolerance'] ?? 60;
  
  // ==================== B 端配置签名公钥 ====================
  
  /// B 端配置签名公钥
  String get b2bConfigPublicKey => 
      _config['b2b']?['config_signing']?['public_key'] ?? '';
  
  /// 是否启用 B 端配置签名验证
  bool get enableConfigSignatureVerification => 
      _config['b2b']?['config_signing']?['enabled'] ?? false;
  
  // ==================== 安全开关 ====================
  
  /// 是否启用 SSL Pinning
  bool get enableSSLPinning => _config['ssl_pinning']?['enabled'] ?? true;
  
  /// 是否允许自签名证书
  bool get allowSelfSigned => _config['ssl_pinning']?['allow_self_signed'] ?? false;
  
  /// 是否启用调试检测
  bool get enableDebugDetection => _config['anti_debug']?['enabled'] ?? true;
  
  // ==================== 内部状态 ====================
  
  Map<String, dynamic> _config = {};
  bool _isLoaded = false;
  
  // ==================== 加载配置 ====================
  
  /// 异步加载配置 (含签名验证)
  /// 
  /// 配置 JSON 格式:
  /// ```json
  /// {
  ///   "config": { ... 实际配置 ... },
  ///   "signature": "hex_encoded_hmac_signature"
  /// }
  /// ```
  /// 
  /// 如果启用了签名验证 (enableConfigSignatureVerification = true)，
  /// 则验证 config 字段的 HMAC-SHA256 签名。验签失败时拒绝加载。
  Future<void> loadFromAsset(String assetPath) async {
    try {
      final jsonString = await rootBundle.loadString(assetPath);
      final parsed = jsonDecode(jsonString) as Map<String, dynamic>;
      
      // 检查是否为签名配置格式
      if (parsed.containsKey('config') && parsed.containsKey('signature')) {
        final configData = parsed['config'] as Map<String, dynamic>;
        final signature = parsed['signature'] as String?;
        
        // 先加载配置以获取验证开关
        _config = configData;
        
        // 如果启用了签名验证，则验证配置完整性
        if (enableConfigSignatureVerification && signature != null) {
          final isValid = _verifyConfigSignature(
            configJson: jsonEncode(configData),
            signature: signature,
            publicKey: b2bConfigPublicKey,
          );
          
          if (!isValid) {
            _config = {};
            _isLoaded = false;
            throw SecurityException('配置签名验证失败: 配置可能被篡改');
          }
        }
        
        _isLoaded = true;
      } else {
        // 兼容旧格式 (无签名的直接配置)
        _config = parsed;
        _isLoaded = true;
      }
    } catch (e) {
      if (e is SecurityException) rethrow;
      _config = {};
      _isLoaded = false;
    }
  }
  
  /// 验证配置签名
  /// 
  /// 使用 HMAC-SHA256 验证配置 JSON 的完整性。
  /// 生产环境应替换为 ECDSA/Ed25519 非对称签名验证。
  bool _verifyConfigSignature({
    required String configJson,
    required String signature,
    required String publicKey,
  }) {
    if (publicKey.isEmpty || signature.isEmpty) return false;
    
    // 使用 HMAC-SHA256 验证 (对称签名)
    // TODO: 生产环境替换为 ECDSA 非对称验签 (使用 pointycastle)
    final keyBytes = _hexDecode(publicKey);
    if (keyBytes == null) return false;
    
    final configBytes = utf8.encode(configJson);
    final hmac = Hmac(sha256, keyBytes);
    final digest = hmac.convert(configBytes);
    final expectedSignature = digest.toString();
    
    // 恒定时间比较
    return _constantTimeCompare(expectedSignature, signature);
  }
  
  /// 恒定时间字符串比较
  static bool _constantTimeCompare(String a, String b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return result == 0;
  }
  
  /// 十六进制解码
  static List<int>? _hexDecode(String hex) {
    if (hex.length % 2 != 0) return null;
    try {
      final result = <int>[];
      for (var i = 0; i < hex.length; i += 2) {
        result.add(int.parse(hex.substring(i, i + 2), radix: 16));
      }
      return result;
    } catch (_) {
      return null;
    }
  }
  
  /// 同步加载配置 (从内存)
  void loadFromMap(Map<String, dynamic> config) {
    _config = config;
    _isLoaded = true;
  }
  
  /// 检查配置是否已加载
  bool get isLoaded => _isLoaded;
  
  /// 获取配置值
  T? getValue<T>(String path) {
    final parts = path.split('.');
    dynamic current = _config;
    
    for (final part in parts) {
      if (current is Map<String, dynamic>) {
        current = current[part];
      } else {
        return null;
      }
    }
    
    return current as T?;
  }
  
  /// 清除配置
  void clear() {
    _config = {};
    _isLoaded = false;
  }
}

/// 环境变量配置
class EnvironmentConfig {
  /// 开发环境
  static const development = EnvironmentConfig._(
    name: 'development',
    apiBaseUrl: 'https://dev-api.b2b2c-wallet.com',
    wsUrl: 'wss://dev-ws.b2b2c-wallet.com',
    ethRpcUrl: 'https://ethereum-dev-rpc.example.com',
    bscRpcUrl: 'https://bsc-dev-rpc.example.com',
    polygonRpcUrl: 'https://polygon-dev-rpc.example.com',
    // 示例开发证书 (请替换为真实开发环境证书)
    apiCertHash: 'sha256/DEVELOPMENT_API_CERT_HASH_PLACEHOLDER',
    wsCertHash: 'sha256/DEVELOPMENT_WS_CERT_HASH_PLACEHOLDER',
    // 示例 HMAC 密钥
    hmacKey: 'dev_hmac_key_placeholder',
    // 示例 B2B 配置签名公钥
    b2bPublicKey: '04DEV00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000',
  );
  
  /// 预发布环境
  static const staging = EnvironmentConfig._(
    name: 'staging',
    apiBaseUrl: 'https://staging-api.b2b2c-wallet.com',
    wsUrl: 'wss://staging-ws.b2b2c-wallet.com',
    ethRpcUrl: 'https://ethereum-staging-rpc.example.com',
    bscRpcUrl: 'https://bsc-staging-rpc.example.com',
    polygonRpcUrl: 'https://polygon-staging-rpc.example.com',
    apiCertHash: 'sha256/STAGING_API_CERT_HASH_PLACEHOLDER',
    wsCertHash: 'sha256/STAGING_WS_CERT_HASH_PLACEHOLDER',
    hmacKey: 'staging_hmac_key_placeholder',
    b2bPublicKey: '04STAG0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000',
  );
  
  /// 生产环境
  static const production = EnvironmentConfig._(
    name: 'production',
    apiBaseUrl: 'https://api.b2b2c-wallet.com',
    wsUrl: 'wss://ws.b2b2c-wallet.com',
    ethRpcUrl: 'https://ethereum-rpc.example.com',
    bscRpcUrl: 'https://bsc-rpc.example.com',
    polygonRpcUrl: 'https://polygon-rpc.example.com',
    // ⚠️ 必须替换为真实生产证书哈希
    apiCertHash: 'sha256/PRODUCTION_API_CERT_HASH_PLACEHOLDER',
    wsCertHash: 'sha256/PRODUCTION_WS_CERT_HASH_PLACEHOLDER',
    // ⚠️ 必须替换为真实 HMAC 密钥
    hmacKey: 'prod_hmac_key_placeholder',
    // ⚠️ 必须替换为真实 B2B 配置签名公钥
    b2bPublicKey: '04PROD00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000',
  );
  
  const EnvironmentConfig._({
    required this.name,
    required this.apiBaseUrl,
    required this.wsUrl,
    required this.ethRpcUrl,
    required this.bscRpcUrl,
    required this.polygonRpcUrl,
    required this.apiCertHash,
    required this.wsCertHash,
    required this.hmacKey,
    required this.b2bPublicKey,
  });
  
  final String name;
  final String apiBaseUrl;
  final String wsUrl;
  final String ethRpcUrl;
  final String bscRpcUrl;
  final String polygonRpcUrl;
  final String apiCertHash;
  final String wsCertHash;
  final String hmacKey;
  final String b2bPublicKey;
  
  /// 根据环境名称获取配置
  static EnvironmentConfig fromName(String name) {
    switch (name.toLowerCase()) {
      case 'dev':
      case 'development':
        return development;
      case 'staging':
      case 'pre':
      case 'preprod':
        return staging;
      case 'prod':
      case 'production':
        return production;
      default:
        return development;
    }
  }
  
  /// 转换为配置 Map (用于加载到 SecurityConfigService)
  Map<String, dynamic> toConfigMap() => {
    'ssl_pinning': {
      'enabled': true,
      'allow_self_signed': false,
      'api_certificates': [apiCertHash],
      'ws_certificates': [wsCertHash],
      'backup_certificates': [], // 生产前由运维提供
    },
    'hmac': {
      'enabled': true,
      'key': hmacKey,
      'timestamp_tolerance': 60,
    },
    'b2b': {
      'config_signing': {
        'enabled': true,
        'public_key': b2bPublicKey,
      },
    },
    'anti_debug': {
      'enabled': true,
    },
  };
}

/// 安全异常
class SecurityException implements Exception {
  final String message;
  SecurityException(this.message);
  
  @override
  String toString() => 'SecurityException: $message';
}
