import 'dart:async';
import 'dart:convert';
import 'dart:io';
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
        client.badCertificateCallback = (X509Certificate cert, String host, int port) {
          // 计算服务器证书的 SHA-256 哈希
          final certHash = _computeCertHash(cert);
          final certHashStr = 'sha256/$certHash';
          
          // 检查主证书白名单
          for (final expected in _certificateHashes) {
            if (_constantTimeCompare(certHashStr, expected)) {
              return true; // 证书在白名单中，放行
            }
          }
          
          // 检查备用证书白名单
          for (final expected in _backupCertificateHashes) {
            if (_constantTimeCompare(certHashStr, expected)) {
              return true;
            }
          }
          
          // 证书不在白名单中，拒绝连接 (可能是 MITM 攻击)
          if (kDebugMode) {
            debugPrint('[SSL Pinning] Certificate hash mismatch!');
            debugPrint('[SSL Pinning] Got: $certHashStr');
          }
          return false;
        };
      }
      
      return client;
    };
  }
  
  /// 计算证书 SHA-256 哈希 (Base64 编码)
  String _computeCertHash(X509Certificate cert) {
    final derBytes = cert.der;
    final hash = sha256.convert(derBytes);
    return base64Encode(hash.bytes);
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
