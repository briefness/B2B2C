import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'flavors.dart';
import 'src/core/security/secure_storage_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Flavor 初始化
  const flavor = String.fromEnvironment('FLUTTER_APP_FLAVOR');
  F.appFlavor = Flavor.values.firstWhere(
    (element) => element.name.toLowerCase() == flavor.toLowerCase(),
    orElse: () => Flavor.values.first,
  );

  // 初始化安全存储 (Hive + SecureStorage)
  await SecureStorageService().initialize();

  // 锁定竖屏
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(const App());
}
