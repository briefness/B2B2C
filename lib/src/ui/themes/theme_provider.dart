import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'tenant_theme_service.dart';

/// 主题状态
class ThemeState {
  final ThemeData theme;
  final TenantThemeConfig? config;
  final bool isLoading;
  final String? error;
  
  const ThemeState({
    required this.theme,
    this.config,
    this.isLoading = false,
    this.error,
  });
  
  ThemeState copyWith({
    ThemeData? theme,
    TenantThemeConfig? config,
    bool? isLoading,
    String? error,
  }) {
    return ThemeState(
      theme: theme ?? this.theme,
      config: config ?? this.config,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

/// 主题状态管理器
class ThemeNotifier extends StateNotifier<ThemeState> {
  final TenantThemeService _themeService;
  
  ThemeNotifier(this._themeService) : super(ThemeState(
    theme: _themeService.applyDefaultTheme(),
  ));
  
  /// 加载租户主题
  Future<void> loadTenantTheme({
    required String tenantId,
    required String Function(String) fetchConfig,
    required String Function(String) verifySignature,
  }) async {
    state = state.copyWith(isLoading: true);
    
    try {
      final theme = await _themeService.loadTenantTheme(
        tenantId: tenantId,
        fetchConfig: fetchConfig,
        verifySignature: verifySignature,
      );
      
      state = state.copyWith(
        theme: theme,
        config: _themeService.currentConfig,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }
  
  /// 切换暗色模式
  Future<void> toggleDarkMode() async {
    _themeService.toggleDarkMode();
    
    if (_themeService.currentConfig != null) {
      final theme = await _themeService.applyLocalConfig(_themeService.currentConfig!);
      state = state.copyWith(
        theme: theme,
      );
    }
  }
  
  /// 重置为默认主题
  void resetToDefault() {
    final theme = _themeService.applyDefaultTheme();
    state = state.copyWith(
      theme: theme,
      config: _themeService.currentConfig,
    );
  }
}

/// Provider
final themeProvider = StateNotifierProvider<ThemeNotifier, ThemeState>((ref) {
  return ThemeNotifier(TenantThemeService());
});

/// 当前主题
final currentThemeProvider = Provider<ThemeData>((ref) {
  return ref.watch(themeProvider).theme;
});

/// 租户配置
final tenantConfigProvider = Provider<TenantThemeConfig?>((ref) {
  return ref.watch(themeProvider).config;
});

/// 主题是否加载中
final themeLoadingProvider = Provider<bool>((ref) {
  return ref.watch(themeProvider).isLoading;
});

/// 主题切换动画包装器
class ThemeTransitionWrapper extends StatelessWidget {
  final Widget child;
  final Duration duration;
  
  const ThemeTransitionWrapper({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 300),
  });
  
  @override
  Widget build(BuildContext context) {
    return AnimatedTheme(
      data: Theme.of(context),
      duration: duration,
      child: child,
    );
  }
}

/// 主题感知组件
class ThemeConsumer extends ConsumerWidget {
  final Widget Function(BuildContext context, ThemeData theme) builder;
  
  const ThemeConsumer({
    super.key,
    required this.builder,
  });
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(currentThemeProvider);
    return builder(context, theme);
  }
}
