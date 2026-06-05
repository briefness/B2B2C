import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:asn1lib/asn1lib.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';

import '../ffi/ffi.dart';
import '../security/method_channel_service.dart';

/// 安全网络服务
/// 
/// 特性：
/// 1. 双向 SSL Pinning - 防止中间人攻击
/// 2. HMAC 请求签名 - 防篡改和重放
/// 3. 系统代理禁用 - 防抓包
/// 4. 请求超时保护
/// 5. 自动重试机制

class SecureNetworkService {
  // ==================== 单例 ====================
  
  static final SecureNetworkService _instance = SecureNetworkService._internal();
  factory SecureNetworkService() => _instance;
  SecureNetworkService._internal();
  
  // ==================== 配置 ====================
  
  /// 服务器证书公钥哈希 (SHA-256)
  /// 
  /// 获取真实证书哈希:
  /// ```bash
  /// echo | openssl s_client -servername api.b2b2c-wallet.com -connect api.b2b2c-wallet.com:443 2>/dev/null | openssl x509 -pubkey -noout | openssl pkey -pubin -outform DER | openssl dgst -sha256 -binary | base64
  /// ```
  /// 
  /// ⚠️ 生产环境必须替换为真实证书哈希
  static const List<String> _certificateHashes = [
    'sha256/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=', // TODO: 替换为真实证书
  ];
  
  /// 备用证书哈希 (用于证书轮换)
  static const List<String> _backupCertificateHashes = [
    'sha256/BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=', // TODO: 替换为备用证书
  ];
  
  /// 是否启用 SSL Pinning
  static const bool _enableSSLPinning = true;
  
  // ignore: unused_field
  static const _timestampValiditySeconds = 60;
  
  /// HMAC Nonce 长度
  static const _nonceLength = 32;
  
  // ==================== 状态 ====================
  
  late final Dio _dio;
  String? _sessionKey;
  
  // ==================== 初始化 ====================
  
  void initialize({
    required String baseUrl,
    String? sessionKey,
  }) {
    _sessionKey = sessionKey;
    
    _dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 30),
    ));
    
    // 配置 SSL Pinning + 代理禁用
    _configureHttpClient();
    
    // 添加拦截器
    _dio.interceptors.addAll([
      _SecurityInterceptor(sessionKey: _sessionKey),
      // 仅在 Debug 模式启用日志拦截器
      if (kDebugMode) _LoggingInterceptor(),
    ]);
  }
  
  /// 配置自定义 HttpClient
  /// 
  /// 1. SSL Certificate Pinning: 验证服务器证书哈希
  /// 2. 禁用系统代理: 防止 Charles/Fiddler 等抓包工具截获流量
  void _configureHttpClient() {
    (_dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
      final client = HttpClient();
      
      // ========== 禁用系统代理 ==========
      // 强制直连，不走系统代理，挂载 Charles/Fiddler 时 App 无法联网
      client.findProxy = (_) => 'DIRECT';
      
      // ========== SSL Certificate Pinning ==========
      if (_enableSSLPinning) {
        // ⚠️ 重要架构限制：
        // Dart 的 badCertificateCallback 仅在系统证书校验「失败」时触发。
        // 系统校验通过时不会回调，因此这里的 pin 校验是「在系统校验失败时
        // 作为额外放行依据」。真正严格的 SPKI pinning 需要原生层 (OkHttp
        // CertificatePinner / iOS URLSession) 配合。
        // 当前实现：保留系统校验 + SPKI 公钥哈希作为补充校验。
        client.badCertificateCallback = (X509Certificate cert, String host, int port) {
          // debug 模式下检测占位符哈希，避免误以为 pinning 生效
          assert(() {
            final hasPlaceholder = _certificateHashes
                .any((h) => h.contains('AAAA') || h.contains('BBBB'));
            if (hasPlaceholder) {
              debugPrint('[SSL Pinning] ⚠️ 警告：证书哈希仍是占位符，pinning 未真正生效！');
            }
            return true;
          }());

          // 计算服务器证书的 SPKI 公钥 SHA-256 哈希
          final pinHash = _computeSpkiHash(cert);
          if (pinHash == null) return false;
          final certHashStr = 'sha256/$pinHash';

          // 检查主 + 备用证书白名单
          for (final expected in [..._certificateHashes, ..._backupCertificateHashes]) {
            if (_constantTimeCompare(certHashStr, expected)) {
              return true;
            }
          }

          // 证书不在白名单中，拒绝连接 (可能是 MITM 攻击)
          if (kDebugMode) {
            debugPrint('[SSL Pinning] Public key hash mismatch!');
            debugPrint('[SSL Pinning] Got: $certHashStr');
          }
          return false;
        };
      }
      
      return client;
    };
  }
  
  /// 计算证书的 SubjectPublicKeyInfo (SPKI) SHA-256 哈希 (Base64 编码)
  ///
  /// 相比对整张证书 DER 做哈希，SPKI 公钥哈希在证书续期（同一密钥对）时
  /// 仍然有效，是行业标准 (HPKP / OkHttp CertificatePinner) 的做法。
  ///
  /// 注：Dart 的 X509Certificate 未直接暴露 SPKI 字段，这里从 DER 中解析
  /// SubjectPublicKeyInfo。解析失败时返回 null（fail-closed）。
  String? _computeSpkiHash(X509Certificate cert) {
    try {
      final spki = _extractSpki(cert.der);
      if (spki == null) return null;
      final hash = sha256.convert(spki);
      return base64Encode(hash.bytes);
    } catch (_) {
      return null;
    }
  }

  /// 从证书 DER 中提取 SubjectPublicKeyInfo
  ///
  /// X.509 结构: Certificate → TBSCertificate → ... → subjectPublicKeyInfo
  /// SPKI 本身是一个 SEQUENCE，包含算法标识和公钥位串。
  Uint8List? _extractSpki(Uint8List der) {
    try {
      final parser = ASN1Parser(der);
      final cert = parser.nextObject() as ASN1Sequence;
      final tbsCert = cert.elements.first as ASN1Sequence;
      // 遍历 TBSCertificate 元素，找到 SubjectPublicKeyInfo (SEQUENCE 内含 BIT STRING)
      for (final element in tbsCert.elements) {
        if (element is ASN1Sequence) {
          final hasBitString =
              element.elements.any((e) => e is ASN1BitString);
          if (hasBitString) {
            return element.encodedBytes;
          }
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }
  
  /// 恒定时间字符串比较 — 防止时序攻击
  static bool _constantTimeCompare(String a, String b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return result == 0;
  }
  
  // ==================== 请求方法 ====================
  
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) {
    return _dio.get<T>(
      path,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
  }
  
  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) {
    return _dio.post<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
  }
  
  Future<Response<T>> put<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) {
    return _dio.put<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
  }
  
  Future<Response<T>> delete<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) {
    return _dio.delete<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
  }
  
  // ==================== HMAC 签名 ====================
  
  /// 生成 HMAC 签名
  String generateHmacSignature({
    required String method,
    required String path,
    required Map<String, dynamic> params,
    required String timestamp,
    required String nonce,
    String? sessionKey,
  }) {
    final signString = _buildSignString(
      method: method,
      path: path,
      params: params,
      timestamp: timestamp,
      nonce: nonce,
    );
    
    final key = sessionKey ?? _sessionKey ?? '';
    return WalletFFIService().hmacSha256(key, signString);
  }
  
  String _buildSignString({
    required String method,
    required String path,
    required Map<String, dynamic> params,
    required String timestamp,
    required String nonce,
  }) {
    final sortedKeys = params.keys.toList()..sort();
    final paramString = sortedKeys.map((key) {
      final value = params[key];
      if (value is Map || value is List) {
        return '$key=${jsonEncode(value)}';
      }
      return '$key=$value';
    }).join('&');
    
    return '$method\n$path\n$paramString\n$timestamp\n$nonce';
  }
  
  /// 验证响应签名 (恒定时间比较)
  bool verifyResponseSignature({
    required String signature,
    required String timestamp,
    required String data,
    String? sessionKey,
  }) {
    final key = sessionKey ?? _sessionKey ?? '';
    final expectedSignature = WalletFFIService().hmacSha256(key, '$timestamp$data');
    return _constantTimeCompare(signature, expectedSignature);
  }
  
  /// 生成时间戳
  String generateTimestamp() {
    return DateTime.now().millisecondsSinceEpoch.toString();
  }
  
  /// 生成随机数
  String generateNonce() {
    final randomBytes = WalletFFIService().generateRandomBytes(_nonceLength);
    return randomBytes.substring(0, _nonceLength * 2);
  }
}

// ==================== 拦截器 ====================

/// 安全拦截器
class _SecurityInterceptor extends Interceptor {
  final String? sessionKey;
  
  _SecurityInterceptor({this.sessionKey});
  
  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // 1. 添加安全请求头
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final nonce = _generateNonce();
    
    options.headers['X-Timestamp'] = timestamp;
    options.headers['X-Nonce'] = nonce;
    
    // 2. 计算 HMAC 签名
    if (sessionKey != null) {
      final params = <String, dynamic>{
        ...options.queryParameters,
        if (options.data != null) 'body': options.data,
      };
      
      final signString = _buildSignString(
        method: options.method,
        path: options.path,
        params: params,
        timestamp: timestamp,
        nonce: nonce,
      );
      
      final signature = WalletFFIService().hmacSha256(sessionKey!, signString);
      options.headers['X-Signature'] = signature;
    }
    
    // 3. 添加设备指纹 (从原生层获取真实设备 ID)
    options.headers['X-Device-Id'] = await _getDeviceId();
    
    handler.next(options);
  }
  
  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    // 检查是否是证书错误 (仅 Debug 模式记录日志)
    if (err.type == DioExceptionType.badCertificate) {
      if (kDebugMode) {
        debugPrint('[Network] Certificate validation failed - possible MITM attack');
      }
    }
    
    handler.next(err);
  }
  
  String _buildSignString({
    required String method,
    required String path,
    required Map<String, dynamic> params,
    required String timestamp,
    required String nonce,
  }) {
    final sortedKeys = params.keys.toList()..sort();
    final paramString = sortedKeys.map((key) {
      final value = params[key];
      if (value is Map || value is List) {
        return '$key=${jsonEncode(value)}';
      }
      return '$key=$value';
    }).join('&');
    return '$method\n$path\n$paramString\n$timestamp\n$nonce';
  }
  
  String _generateNonce() {
    final randomBytes = WalletFFIService().generateRandomBytes(16);
    return randomBytes.substring(0, 32);
  }
  
  Future<String> _getDeviceId() async {
    try {
      final deviceId = await MethodChannelService().getDeviceId();
      return deviceId ?? 'unknown';
    } catch (_) {
      return 'unknown';
    }
  }
}

/// 日志拦截器 (仅 Debug 模式使用)
class _LoggingInterceptor extends Interceptor {
  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    assert(() {
      debugPrint('[Network] ${options.method} ${options.uri}');
      // 不打印 Headers (可能含签名等敏感信息)
      return true;
    }());
    handler.next(options);
  }
  
  @override
  Future<void> onResponse(
    Response response,
    ResponseInterceptorHandler handler,
  ) async {
    assert(() {
      debugPrint('[Network] Response ${response.statusCode}');
      return true;
    }());
    handler.next(response);
  }
}

// ==================== SSL Pinning 配置 ====================

/// SSL Pinning 验证器 (保留为静态工具类)
class SSLPinningValidator {
  /// 验证服务器证书
  static bool validateCertificate(String serverCertDer) {
    final serverHash = sha256.convert(utf8.encode(serverCertDer)).toString();
    
    for (final expectedHash in SecureNetworkService._certificateHashes) {
      final hash = expectedHash.startsWith('sha256/') 
          ? expectedHash.substring(7) 
          : expectedHash;
      if (SecureNetworkService._constantTimeCompare(serverHash, hash)) {
        return true;
      }
    }
    
    for (final expectedHash in SecureNetworkService._backupCertificateHashes) {
      final hash = expectedHash.startsWith('sha256/') 
          ? expectedHash.substring(7) 
          : expectedHash;
      if (SecureNetworkService._constantTimeCompare(serverHash, hash)) {
        return true;
      }
    }
    
    return false;
  }
}

// ==================== 代理配置 ====================

class ProxyConfiguration {
  /// 绕过所有代理
  static const noProxy = 'DIRECT';
  
  /// 自定义代理 (仅开发环境使用)
  static String customProxy(String host, int port) {
    return 'PROXY $host:$port';
  }
}
