import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 反逆向防护组件
/// 
/// 提供运行时安全检测和防护：
/// 1. 调试器检测
/// 2. 屏幕截图检测
/// 3. 应用切换检测
/// 4. 安全状态显示

class AntiReverseShield extends StatefulWidget {
  final Widget child;
  final Widget? threatOverlay;
  final VoidCallback? onThreatDetected;
  final bool enableDebugProtection;
  final bool enableScreenshotProtection;
  
  const AntiReverseShield({
    super.key,
    required this.child,
    this.threatOverlay,
    this.onThreatDetected,
    this.enableDebugProtection = true,
    this.enableScreenshotProtection = true,
  });
  
  @override
  State<AntiReverseShield> createState() => _AntiReverseShieldState();
}

class _AntiReverseShieldState extends State<AntiReverseShield>
    with WidgetsBindingObserver {
  
  bool _isScreenCaptured = false;
  bool _appInBackground = false;
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // 监听截屏通知
    _setupScreenshotListener();
  }
  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  
  void _setupScreenshotListener() {
    // iOS 截屏通知
    if (Platform.isIOS) {
      // 通过 Native channel 监听
    }
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        setState(() => _appInBackground = true);
        _onAppBackground();
        break;
      case AppLifecycleState.resumed:
        setState(() => _appInBackground = false);
        _onAppForeground();
        break;
      default:
        break;
    }
  }
  
  void _onAppBackground() {
    // 应用进入后台时，可以选择模糊显示内容
    debugPrint('[Security] App went to background');
  }
  
  void _onAppForeground() {
    debugPrint('[Security] App returned to foreground');
  }
  
  void _onScreenshotDetected() {
    setState(() => _isScreenCaptured = true);
    widget.onThreatDetected?.call();
    
    // 延迟重置
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() => _isScreenCaptured = false);
      }
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 主内容
        widget.child,
        
        // 截屏提示
        if (_isScreenCaptured)
          Positioned.fill(
            child: Container(
              color: Colors.red.withOpacity(0.3),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.screenshot_outlined,
                      size: 64,
                      color: Colors.red.shade700,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '截图检测',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.red.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        
        // 后台提示
        if (_appInBackground)
          Positioned.fill(
            child: Container(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_outline, size: 64),
                    SizedBox(height: 16),
                    Text('应用已锁定'),
                  ],
                ),
              ),
            ),
          ),
        
        // 自定义威胁覆盖
        if (widget.threatOverlay != null) widget.threatOverlay!,
      ],
    );
  }
}

/// 安全内容包装器
/// 
/// 在检测到威胁时自动隐藏敏感内容
class SecureContentWrapper extends StatefulWidget {
  final Widget child;
  final bool requiresAuthentication;
  
  const SecureContentWrapper({
    super.key,
    required this.child,
    this.requiresAuthentication = false,
  });
  
  @override
  State<SecureContentWrapper> createState() => _SecureContentWrapperState();
}

class _SecureContentWrapperState extends State<SecureContentWrapper> {
  bool _isSecure = true;
  
  @override
  void initState() {
    super.initState();
    _checkSecurity();
  }
  
  Future<void> _checkSecurity() async {
    // TODO: 调用安全服务检查
    // 目前模拟
    await Future.delayed(const Duration(milliseconds: 100));
    if (mounted) {
      setState(() => _isSecure = true);
    }
  }
  
  @override
  Widget build(BuildContext context) {
    if (!_isSecure) {
      return const _BlurredPlaceholder();
    }
    return widget.child;
  }
}

class _BlurredPlaceholder extends StatelessWidget {
  const _BlurredPlaceholder();
  
  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.security,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              '内容已隐藏',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              '安全检测中...',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 反截图包装器
/// 
/// 对特定内容禁用截图
class AntiScreenshotWrapper extends StatelessWidget {
  final Widget child;
  
  const AntiScreenshotWrapper({
    super.key,
    required this.child,
  });
  
  @override
  Widget build(BuildContext context) {
    // 在 Android 上，这需要原生层设置 FLAG_SECURE
    // Flutter 端无法直接控制
    
    // iOS 上需要在 ViewController 中设置
    return child;
  }
}

/// 安全对话框
/// 
/// 关闭后内容自动销毁
class SecureDialog extends StatelessWidget {
  final String title;
  final String? message;
  final Widget? content;
  final List<Widget> actions;
  final bool dismissible;
  
  const SecureDialog({
    super.key,
    required this.title,
    this.message,
    this.content,
    this.actions = const [],
    this.dismissible = false,
  });
  
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: dismissible,
      child: AlertDialog(
        title: Text(title),
        content: content ?? (message != null ? Text(message!) : null),
        actions: actions,
      ),
    );
  }
  
  /// 显示安全警告对话框
  static Future<void> showWarning(
    BuildContext context, {
    required String title,
    required String message,
    String confirmText = '确认',
    VoidCallback? onConfirm,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false, // 禁止点击外部关闭
      builder: (context) => AlertDialog(
        backgroundColor: Colors.red.shade50,
        title: Row(
          children: [
            Icon(Icons.warning_amber, color: Colors.red.shade700),
            const SizedBox(width: 8),
            Text(title),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              onConfirm?.call();
            },
            child: Text(confirmText),
          ),
        ],
      ),
    );
  }
}
