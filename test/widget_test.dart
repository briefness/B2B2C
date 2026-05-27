// B2B2C Wallet 基础冒烟测试
//
// 验证应用可以正常启动且不报错。

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:b2b2c_wallet/main.dart';

void main() {
  testWidgets('App smoke test - launches without crash', (WidgetTester tester) async {
    // 构建应用并触发一帧
    await tester.pumpWidget(
      const ProviderScope(
        child: B2B2CWalletApp(),
      ),
    );

    // 验证应用正常启动
    expect(find.byType(B2B2CWalletApp), findsOneWidget);
  });
}
