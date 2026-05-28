import 'package:flutter_test/flutter_test.dart';
import 'package:b2b2c_wallet/app.dart';
import 'package:b2b2c_wallet/src/core/security/security_service.dart';

void main() {
  testWidgets('App renders without crash', (WidgetTester tester) async {
    final securityService = SecurityService();
    await tester.pumpWidget(App(securityService: securityService));
    expect(find.byType(App), findsOneWidget);
  });
}
