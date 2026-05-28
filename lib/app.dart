import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'flavors.dart';
import 'src/core/security/security_service.dart';
import 'src/services/wallet_service.dart';
import 'src/ui/pages/wallet_pages.dart';

class App extends StatelessWidget {
  final SecurityService securityService;

  const App({super.key, required this.securityService});

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      child: MaterialApp(
        title: F.title,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
          useMaterial3: true,
        ),
        debugShowCheckedModeBanner: false,
        home: _flavorBanner(
          child: SecurityGuard(
            securityService: securityService,
            child: const WalletEntryPage(),
          ),
          show: kDebugMode,
        ),
        routes: {
          '/home': (context) => const HomePage(),
          '/create': (context) => const CreateWalletPage(),
          '/import': (context) => const ImportWalletPage(),
        },
      ),
    );
  }

  Widget _flavorBanner({required Widget child, bool show = true}) => show
      ? Banner(
          location: BannerLocation.topStart,
          message: F.name,
          color: Colors.green.withAlpha(150),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 12.0,
            letterSpacing: 1.0,
          ),
          textDirection: TextDirection.ltr,
          child: child,
        )
      : child;
}

/// 安全守卫 Widget
/// 
/// 监听 SecurityService 的安全状态流，
/// 检测到威胁时显示安全警告遮罩层。
class SecurityGuard extends StatefulWidget {
  final SecurityService securityService;
  final Widget child;

  const SecurityGuard({
    super.key,
    required this.securityService,
    required this.child,
  });

  @override
  State<SecurityGuard> createState() => _SecurityGuardState();
}

class _SecurityGuardState extends State<SecurityGuard> with WidgetsBindingObserver {
  late StreamSubscription<SecurityState> _securitySubscription;
  SecurityState _currentState = SecurityState.unknown;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // 监听安全状态变化
    _securitySubscription = widget.securityService.securityState.listen((state) {
      setState(() => _currentState = state);

      if (state == SecurityState.threat && kReleaseMode) {
        _showSecurityAlert();
      }
    });

    _currentState = widget.securityService.currentState;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _securitySubscription.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 从后台恢复时重新检测安全环境
    if (state == AppLifecycleState.resumed) {
      widget.securityService.performSecurityCheck();
    }
  }

  void _showSecurityAlert() {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.shield, color: Colors.red, size: 48),
        title: const Text('安全警告'),
        content: const Text(
          '检测到您的设备存在安全风险（越狱/Root、调试器或 Hook 框架）。\n\n'
          '为保护您的资产安全，部分功能可能受到限制。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('我已知晓风险'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,

        // 安全状态指示器（仅在开发模式显示）
        if (kDebugMode && _currentState != SecurityState.unknown)
          Positioned(
            top: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                margin: const EdgeInsets.only(top: 4, right: 4),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _currentState == SecurityState.secure
                      ? Colors.green.withOpacity(0.8)
                      : Colors.red.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _currentState == SecurityState.secure ? '🔒 安全' : '⚠️ 风险',
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 入口判断页：有钱包进首页，没钱包进引导页
class WalletEntryPage extends ConsumerWidget {
  const WalletEntryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallet = ref.watch(currentWalletProvider);

    if (wallet != null) {
      return const HomePage();
    }

    return const WelcomePage();
  }
}

/// 欢迎引导页
class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const Spacer(flex: 2),

              // Logo
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      theme.colorScheme.primary,
                      theme.colorScheme.secondary,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: theme.colorScheme.primary.withOpacity(0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.account_balance_wallet,
                  size: 48,
                  color: Colors.white,
                ),
              ),

              const SizedBox(height: 32),

              Text(
                F.title,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 12),

              Text(
                '安全、便捷的加密货币钱包',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),

              const Spacer(flex: 3),

              // 创建钱包
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: () => _createWallet(context),
                  icon: const Icon(Icons.add),
                  label: const Text('创建钱包', style: TextStyle(fontSize: 16)),
                ),
              ),

              const SizedBox(height: 16),

              // 导入钱包
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: () => _importWallet(context),
                  icon: const Icon(Icons.download),
                  label: const Text('导入钱包', style: TextStyle(fontSize: 16)),
                ),
              ),

              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }

  void _createWallet(BuildContext context) async {
    final wallet = await Navigator.of(context).push<Wallet>(
      MaterialPageRoute(builder: (_) => const CreateWalletPage()),
    );
    if (wallet != null && context.mounted) {
      Navigator.of(context).pushReplacementNamed('/home');
    }
  }

  void _importWallet(BuildContext context) async {
    final wallet = await Navigator.of(context).push<Wallet>(
      MaterialPageRoute(builder: (_) => const ImportWalletPage()),
    );
    if (wallet != null && context.mounted) {
      Navigator.of(context).pushReplacementNamed('/home');
    }
  }
}
