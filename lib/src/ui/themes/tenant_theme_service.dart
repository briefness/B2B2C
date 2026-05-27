import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';

/// 多租户换肤服务
/// 
/// 负责：
/// 1. 运行时动态加载主题配置
/// 2. 云端配置验签
/// 3. 主题切换动画
/// 4. 本地默认皮肤保底

class TenantThemeService {
  // ==================== 单例 ====================
  
  static final TenantThemeService _instance = TenantThemeService._internal();
  factory TenantThemeService() => _instance;
  TenantThemeService._internal();
  
  // ==================== 状态 ====================
  
  String? _currentTenantId;
  TenantThemeConfig? _currentConfig;
  final _themeController = StreamController<ThemeData>.broadcast();
  
  Stream<ThemeData> get themeStream => _themeController.stream;
  TenantThemeConfig? get currentConfig => _currentConfig;
  String? get currentTenantId => _currentTenantId;
  
  // ==================== 默认配置 ====================
  
  /// 默认主题配置
  static final _defaultConfig = TenantThemeConfig(
    tenantId: 'default',
    tenantName: 'B2B2C Wallet',
    primaryColor: const Color(0xFF1E88E5),
    secondaryColor: const Color(0xFF42A5F5),
    accentColor: const Color(0xFF00BCD4),
    backgroundColor: const Color(0xFFF5F5F5),
    surfaceColor: Colors.white,
    errorColor: const Color(0xFFD32F2F),
    textPrimaryColor: const Color(0xFF212121),
    textSecondaryColor: const Color(0xFF757575),
    borderColor: const Color(0xFFE0E0E0),
    logoUrl: null,
    splashScreenColor: const Color(0xFF1E88E5),
    darkModeConfig: DarkModeConfig.defaultConfig(),
  );
  
  // ==================== 主题加载 ====================
  
  /// 加载租户主题
  /// 
  /// 1. 请求云端配置
  /// 2. 验签配置
  /// 3. 应用主题
  Future<ThemeData> loadTenantTheme({
    required String tenantId,
    required String Function(String path) fetchConfig, // 配置获取函数
    required String Function(String data) verifySignature, // 验签函数
  }) async {
    try {
      // 1. 获取云端配置
      final configJson = await fetchConfig('/config/theme/$tenantId');
      
      // 2. 验签
      if (!_verifyConfigSignature(configJson, verifySignature)) {
        debugPrint('[Theme] Config signature verification failed, using default');
        return _applyConfig(_defaultConfig);
      }
      
      // 3. 解析配置
      final config = TenantThemeConfig.fromJson(
        jsonDecode(configJson) as Map<String, dynamic>,
      );
      
      return _applyConfig(config);
    } catch (e) {
      debugPrint('[Theme] Failed to load theme: $e');
      return _applyConfig(_defaultConfig);
    }
  }
  
  bool _verifyConfigSignature(String configJson, String Function(String) verifySignature) {
    try {
      // 从 JSON 中提取签名部分
      final data = jsonDecode(configJson) as Map<String, dynamic>;
      final signature = data['signature'] as String?;
      final payload = data['payload'] as String?;
      
      if (signature == null || payload == null) {
        return false;
      }
      
      // 验证签名
      final expectedSignature = verifySignature(payload);
      return signature == expectedSignature;
    } catch (e) {
      return false;
    }
  }
  
  ThemeData _applyConfig(TenantThemeConfig config) {
    _currentTenantId = config.tenantId;
    _currentConfig = config;
    
    final theme = _buildThemeData(config);
    _themeController.add(theme);
    
    return theme;
  }
  
  ThemeData _buildThemeData(TenantThemeConfig config) {
    final brightness = config.darkModeConfig?.enabled == true
        ? Brightness.dark
        : Brightness.light;
    
    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: config.primaryColor,
      onPrimary: _getContrastingColor(config.primaryColor),
      secondary: config.secondaryColor,
      onSecondary: _getContrastingColor(config.secondaryColor),
      error: config.errorColor,
      onError: Colors.white,
      surface: config.surfaceColor,
      onSurface: config.textPrimaryColor,
    );
    
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: config.backgroundColor,
      primaryColor: config.primaryColor,
      appBarTheme: AppBarTheme(
        backgroundColor: config.primaryColor,
        foregroundColor: _getContrastingColor(config.primaryColor),
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: config.surfaceColor,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: config.primaryColor,
          foregroundColor: _getContrastingColor(config.primaryColor),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: config.surfaceColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: config.borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: config.borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: config.primaryColor, width: 2),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: config.borderColor,
        thickness: 1,
      ),
      textTheme: TextTheme(
        displayLarge: TextStyle(color: config.textPrimaryColor),
        displayMedium: TextStyle(color: config.textPrimaryColor),
        displaySmall: TextStyle(color: config.textPrimaryColor),
        headlineLarge: TextStyle(color: config.textPrimaryColor),
        headlineMedium: TextStyle(color: config.textPrimaryColor),
        headlineSmall: TextStyle(color: config.textPrimaryColor),
        titleLarge: TextStyle(color: config.textPrimaryColor),
        titleMedium: TextStyle(color: config.textPrimaryColor),
        titleSmall: TextStyle(color: config.textPrimaryColor),
        bodyLarge: TextStyle(color: config.textPrimaryColor),
        bodyMedium: TextStyle(color: config.textPrimaryColor),
        bodySmall: TextStyle(color: config.textSecondaryColor),
        labelLarge: TextStyle(color: config.textPrimaryColor),
        labelMedium: TextStyle(color: config.textPrimaryColor),
        labelSmall: TextStyle(color: config.textSecondaryColor),
      ),
    );
  }
  
  Color _getContrastingColor(Color color) {
    // 计算对比度
    final luminance = color.computeLuminance();
    return luminance > 0.5 ? Colors.black : Colors.white;
  }
  
  // ==================== 主题切换 ====================
  
  /// 应用默认主题
  ThemeData applyDefaultTheme() {
    return _applyConfig(_defaultConfig);
  }
  
  /// 应用本地配置
  Future<ThemeData> applyLocalConfig(TenantThemeConfig config) async {
    return _applyConfig(config);
  }
  
  /// 切换暗色模式
  void toggleDarkMode() {
    if (_currentConfig == null) return;
    
    final newConfig = _currentConfig!.copyWith(
      darkModeConfig: DarkModeConfig(
        enabled: !(_currentConfig!.darkModeConfig?.enabled ?? false),
        darkPrimaryColor: _currentConfig!.darkModeConfig?.darkPrimaryColor,
        darkBackgroundColor: _currentConfig!.darkModeConfig?.darkBackgroundColor,
      ),
    );
    
    _applyConfig(newConfig);
  }
  
  // ==================== 清理 ====================
  
  void dispose() {
    _themeController.close();
  }
}

// ==================== 数据模型 ====================

class TenantThemeConfig {
  final String tenantId;
  final String tenantName;
  final Color primaryColor;
  final Color secondaryColor;
  final Color accentColor;
  final Color backgroundColor;
  final Color surfaceColor;
  final Color errorColor;
  final Color textPrimaryColor;
  final Color textSecondaryColor;
  final Color borderColor;
  final String? logoUrl;
  final Color splashScreenColor;
  final DarkModeConfig? darkModeConfig;
  
  const TenantThemeConfig({
    required this.tenantId,
    required this.tenantName,
    required this.primaryColor,
    required this.secondaryColor,
    required this.accentColor,
    required this.backgroundColor,
    required this.surfaceColor,
    required this.errorColor,
    required this.textPrimaryColor,
    required this.textSecondaryColor,
    required this.borderColor,
    this.logoUrl,
    required this.splashScreenColor,
    this.darkModeConfig,
  });
  
  factory TenantThemeConfig.fromJson(Map<String, dynamic> json) {
    return TenantThemeConfig(
      tenantId: json['tenantId'] as String? ?? 'default',
      tenantName: json['tenantName'] as String? ?? 'B2B2C Wallet',
      primaryColor: _parseColor(json['primaryColor']),
      secondaryColor: _parseColor(json['secondaryColor']),
      accentColor: _parseColor(json['accentColor']),
      backgroundColor: _parseColor(json['backgroundColor']),
      surfaceColor: _parseColor(json['surfaceColor']),
      errorColor: _parseColor(json['errorColor']),
      textPrimaryColor: _parseColor(json['textPrimaryColor']),
      textSecondaryColor: _parseColor(json['textSecondaryColor']),
      borderColor: _parseColor(json['borderColor']),
      logoUrl: json['logoUrl'] as String?,
      splashScreenColor: _parseColor(json['splashScreenColor']),
      darkModeConfig: json['darkModeConfig'] != null
          ? DarkModeConfig.fromJson(json['darkModeConfig'] as Map<String, dynamic>)
          : null,
    );
  }
  
  Map<String, dynamic> toJson() => {
    'tenantId': tenantId,
    'tenantName': tenantName,
    'primaryColor': '#${primaryColor.toARGB32().toRadixString(16).substring(2)}',
    'secondaryColor': '#${secondaryColor.toARGB32().toRadixString(16).substring(2)}',
    'accentColor': '#${accentColor.toARGB32().toRadixString(16).substring(2)}',
    'backgroundColor': '#${backgroundColor.toARGB32().toRadixString(16).substring(2)}',
    'surfaceColor': '#${surfaceColor.toARGB32().toRadixString(16).substring(2)}',
    'errorColor': '#${errorColor.toARGB32().toRadixString(16).substring(2)}',
    'textPrimaryColor': '#${textPrimaryColor.toARGB32().toRadixString(16).substring(2)}',
    'textSecondaryColor': '#${textSecondaryColor.toARGB32().toRadixString(16).substring(2)}',
    'borderColor': '#${borderColor.toARGB32().toRadixString(16).substring(2)}',
    'logoUrl': logoUrl,
    'splashScreenColor': '#${splashScreenColor.toARGB32().toRadixString(16).substring(2)}',
    'darkModeConfig': darkModeConfig?.toJson(),
  };
  
  TenantThemeConfig copyWith({
    String? tenantId,
    String? tenantName,
    Color? primaryColor,
    Color? secondaryColor,
    Color? accentColor,
    Color? backgroundColor,
    Color? surfaceColor,
    Color? errorColor,
    Color? textPrimaryColor,
    Color? textSecondaryColor,
    Color? borderColor,
    String? logoUrl,
    Color? splashScreenColor,
    DarkModeConfig? darkModeConfig,
  }) {
    return TenantThemeConfig(
      tenantId: tenantId ?? this.tenantId,
      tenantName: tenantName ?? this.tenantName,
      primaryColor: primaryColor ?? this.primaryColor,
      secondaryColor: secondaryColor ?? this.secondaryColor,
      accentColor: accentColor ?? this.accentColor,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      surfaceColor: surfaceColor ?? this.surfaceColor,
      errorColor: errorColor ?? this.errorColor,
      textPrimaryColor: textPrimaryColor ?? this.textPrimaryColor,
      textSecondaryColor: textSecondaryColor ?? this.textSecondaryColor,
      borderColor: borderColor ?? this.borderColor,
      logoUrl: logoUrl ?? this.logoUrl,
      splashScreenColor: splashScreenColor ?? this.splashScreenColor,
      darkModeConfig: darkModeConfig ?? this.darkModeConfig,
    );
  }
  
  static Color _parseColor(dynamic value) {
    if (value == null) return Colors.grey;
    if (value is Color) return value;
    if (value is String) {
      final hex = value.replaceFirst('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    }
    return Colors.grey;
  }
}

class DarkModeConfig {
  final bool enabled;
  final Color? darkPrimaryColor;
  final Color? darkBackgroundColor;
  
  const DarkModeConfig({
    required this.enabled,
    this.darkPrimaryColor,
    this.darkBackgroundColor,
  });
  
  factory DarkModeConfig.fromJson(Map<String, dynamic> json) {
    return DarkModeConfig(
      enabled: json['enabled'] as bool? ?? false,
      darkPrimaryColor: TenantThemeConfig._parseColor(json['darkPrimaryColor']),
      darkBackgroundColor: TenantThemeConfig._parseColor(json['darkBackgroundColor']),
    );
  }
  
  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'darkPrimaryColor': darkPrimaryColor != null
        ? '#${darkPrimaryColor!.toARGB32().toRadixString(16).substring(2)}'
        : null,
    'darkBackgroundColor': darkBackgroundColor != null
        ? '#${darkBackgroundColor!.toARGB32().toRadixString(16).substring(2)}'
        : null,
  };
  
  factory DarkModeConfig.defaultConfig() {
    return const DarkModeConfig(
      enabled: false,
      darkPrimaryColor: Color(0xFF121212),
      darkBackgroundColor: Color(0xFF1E1E1E),
    );
  }
}
