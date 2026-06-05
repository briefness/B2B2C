import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'flavors.dart';
import 'src/core/security/secure_storage_service.dart';
import 'src/core/security/security_service.dart';
import 'src/core/security/security_config_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Flavor 初始化
  const flavor = String.fromEnvironment('FLUTTER_APP_FLAVOR');
  F.appFlavor = Flavor.values.firstWhere(
    (element) => element.name.toLowerCase() == flavor.toLowerCase(),
    orElse: () => Flavor.values.first,
  );

  // 2. 初始化安全存储 (Hive + SecureStorage)
  await SecureStorageService().initialize();

  // 3. 加载安全配置
  final securityConfig = SecurityConfigService();
  // 根据环境加载配置 (开发环境使用内存配置)
  final envConfig = kReleaseMode
      ? EnvironmentConfig.production
      : EnvironmentConfig.development;
  securityConfig.loadFromMap(envConfig.toConfigMap());

  // 3.1 Release 模式占位符检测 — 阻断携带占位符的发布包启动
  if (kReleaseMode) {
    _assertNoPlaceholders(envConfig);
  }

  // 4. 安全环境检测 (越狱/Root、调试器、Hook 框架)
  final securityService = SecurityService();
  await securityService.initialize();

  // 5. 启动定时安全检测 (每 30 秒)
  if (kReleaseMode) {
    securityService.startPeriodicCheck();
  }

  // 6. 锁定竖屏
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(App(securityService: securityService));
}

/// Release 模式占位符检测
///
/// 检查 SSL 证书哈希、HMAC 密钥、B2B 签名公钥等关键安全配置
/// 是否仍为开发占位符。如果是，则抛出异常阻止应用启动，
/// 避免携带空白安全配置的包被发布到生产环境。
void _assertNoPlaceholders(EnvironmentConfig config) {
  const placeholderPatterns = [
    'AAAAAAA',
    'placeholder',
    'PLACEHOLDER',
    'REPLACE_WITH',
    'TODO',
    'dev_hmac',
    'staging_hmac',
    'prod_hmac',
  ];

  final configMap = config.toConfigMap();
  final violations = <String>[];

  void check(String label, String? value) {
    if (value == null || value.isEmpty) {
      violations.add('$label: 值为空');
      return;
    }
    for (final pattern in placeholderPatterns) {
      if (value.contains(pattern)) {
        violations.add('$label: 包含占位符 "$pattern"');
        break;
      }
    }
  }

  // 检查 SSL 证书哈希
  final sslHashes = configMap['sslPinningHashes'] as List<String>? ?? [];
  for (var i = 0; i < sslHashes.length; i++) {
    check('SSL 证书哈希[$i]', sslHashes[i]);
  }

  // 检查 HMAC 密钥
  check('HMAC 密钥', configMap['hmacKey'] as String?);

  // 检查 B2B 签名公钥
  check('B2B 签名公钥', configMap['b2bPublicKey'] as String?);

  if (violations.isNotEmpty) {
    throw StateError(
      '[安全阻断] Release 模式检测到占位符配置，禁止启动：\n'
      '${violations.join('\n')}\n'
      '请在 CI/CD 流程中替换为真实值。',
    );
  }
}
