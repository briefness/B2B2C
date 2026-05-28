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
