import 'package:flutter/services.dart';

/// Method Channel 服务
/// 
/// 封装与原生层 (Android/iOS) 的通信

class MethodChannelService {
  static const _channel = MethodChannel('com.b2b2c.wallet/security');
  
  // ==================== 单例 ====================
  
  static final MethodChannelService _instance = MethodChannelService._internal();
  factory MethodChannelService() => _instance;
  MethodChannelService._internal();
  
  // ==================== 生物识别 ====================
  
  /// 检查生物识别是否可用
  Future<BiometricStatus> checkBiometricAvailable() async {
    try {
      final result = await _channel.invokeMethod<Map>('isBiometricAvailable');
      if (result == null) {
        return BiometricStatus(
          available: false,
          biometricType: BiometricType.none,
        );
      }
      
      return BiometricStatus(
        available: result['available'] as bool? ?? false,
        biometricType: _parseBiometricType(result['biometricType'] as String?),
      );
    } on PlatformException catch (e) {
      return BiometricStatus(
        available: false,
        biometricType: BiometricType.none,
        error: e.message,
      );
    }
  }
  
  BiometricType _parseBiometricType(String? type) {
    switch (type) {
      case 'strong':
      case 'faceID':
        return BiometricType.strong;
      case 'weak':
      case 'touchID':
        return BiometricType.weak;
      default:
        return BiometricType.none;
    }
  }
  
  /// 执行生物识别认证
  Future<BiometricResult> authenticate({
    String title = '验证身份',
    String subtitle = '请使用生物识别解锁',
    String reason = '请进行身份验证',
  }) async {
    try {
      final result = await _channel.invokeMethod<Map>('authenticate', {
        'title': title,
        'subtitle': subtitle,
        'reason': reason,
      });
      
      return BiometricResult(
        success: result?['success'] as bool? ?? false,
      );
    } on PlatformException catch (e) {
      return BiometricResult(
        success: false,
        errorCode: e.code,
        errorMessage: e.message,
      );
    }
  }
  
  // ==================== 硬件密钥 ====================
  
  /// 生成硬件密钥
  Future<HardwareKeyResult> generateHardwareKey(String alias) async {
    try {
      final result = await _channel.invokeMethod<Map>('generateHardwareKey', {
        'alias': alias,
      });
      
      return HardwareKeyResult(
        success: result?['success'] as bool? ?? false,
        alias: result?['alias'] as String?,
      );
    } on PlatformException catch (e) {
      return HardwareKeyResult(
        success: false,
        error: e.message,
      );
    }
  }
  
  /// 使用硬件密钥加密
  Future<EncryptionResult> encryptWithHardwareKey({
    required String alias,
    required String plaintext,
  }) async {
    try {
      final result = await _channel.invokeMethod<Map>('encryptWithHardwareKey', {
        'alias': alias,
        'plaintext': plaintext,
      });
      
      return EncryptionResult(
        success: true,
        ciphertext: result?['ciphertext'] as String?,
        iv: result?['iv'] as String?,
      );
    } on PlatformException catch (e) {
      return EncryptionResult(
        success: false,
        error: e.message,
      );
    }
  }
  
  /// 使用硬件密钥解密
  Future<DecryptionResult> decryptWithHardwareKey({
    required String alias,
    required String ciphertext,
    required String iv,
  }) async {
    try {
      final result = await _channel.invokeMethod<Map>('decryptWithHardwareKey', {
        'alias': alias,
        'ciphertext': ciphertext,
        'iv': iv,
      });
      
      return DecryptionResult(
        success: true,
        plaintext: result?['plaintext'] as String?,
      );
    } on PlatformException catch (e) {
      return DecryptionResult(
        success: false,
        error: e.message,
      );
    }
  }
  
  /// 删除硬件密钥
  Future<bool> deleteHardwareKey(String alias) async {
    try {
      final result = await _channel.invokeMethod<Map>('deleteHardwareKey', {
        'alias': alias,
      });
      return result?['success'] as bool? ?? false;
    } on PlatformException {
      return false;
    }
  }
  
  // ==================== 安全检测 ====================
  
  /// 检测 Root/越狱
  Future<RootDetectionResult> checkRooted() async {
    try {
      final result = await _channel.invokeMethod<Map>('checkRooted');
      
      return RootDetectionResult(
        rooted: result?['rooted'] as bool? ?? false,
        reasons: (result?['reasons'] as List?)?.cast<String>() ?? [],
      );
    } on PlatformException catch (e) {
      return RootDetectionResult(
        rooted: false,
        error: e.message,
      );
    }
  }
  
  /// 检测调试器
  Future<bool> checkDebugger() async {
    try {
      final result = await _channel.invokeMethod<Map>('checkDebugger');
      return result?['debugged'] as bool? ?? false;
    } on PlatformException {
      return false;
    }
  }
  
  /// 检测 Hook 框架
  Future<HookDetectionResult> checkHookFrameworks() async {
    try {
      final result = await _channel.invokeMethod<Map>('checkHookFrameworks');
      
      return HookDetectionResult(
        hooked: result?['hooked'] as bool? ?? false,
        frameworks: (result?['frameworks'] as List?)?.cast<String>() ?? [],
      );
    } on PlatformException catch (e) {
      return HookDetectionResult(
        hooked: false,
        error: e.message,
      );
    }
  }
  
  /// 获取设备 ID
  Future<String?> getDeviceId() async {
    try {
      final result = await _channel.invokeMethod<Map>('getDeviceId');
      return result?['deviceId'] as String?;
    } on PlatformException {
      return null;
    }
  }
  
  // ==================== 安全键盘 ====================
  
  /// 生成随机键盘布局
  Future<SecureKeyboardLayout> generateSecureKeyboardLayout() async {
    try {
      final result = await _channel.invokeMethod<Map>('generateSecureKeyboardLayout');
      
      if (result == null) {
        return SecureKeyboardLayout.defaultLayout();
      }
      
      return SecureKeyboardLayout(
        digits: (result['digits'] as List?)?.cast<String>() ?? ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'],
        letters: (result['letters'] as List?)?.cast<String>() ?? List.generate(26, (i) => String.fromCharCode(65 + i)),
        timestamp: result['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      );
    } on PlatformException {
      return SecureKeyboardLayout.defaultLayout();
    }
  }
  
  /// 检查安全输入是否激活
  Future<bool> isSecureInputActive() async {
    try {
      final result = await _channel.invokeMethod<Map>('isSecureInputActive');
      return result?['active'] as bool? ?? true;
    } on PlatformException {
      return true;
    }
  }
}

// ==================== 数据模型 ====================

enum BiometricType {
  none,
  weak,     // 弱生物识别 (旧版指纹)
  strong,   // 强生物识别 (Face ID, 强指纹)
}

class BiometricStatus {
  final bool available;
  final BiometricType biometricType;
  final String? error;
  
  BiometricStatus({
    required this.available,
    required this.biometricType,
    this.error,
  });
}

class BiometricResult {
  final bool success;
  final String? errorCode;
  final String? errorMessage;
  
  BiometricResult({
    required this.success,
    this.errorCode,
    this.errorMessage,
  });
}

class HardwareKeyResult {
  final bool success;
  final String? alias;
  final String? error;
  
  HardwareKeyResult({
    required this.success,
    this.alias,
    this.error,
  });
}

class EncryptionResult {
  final bool success;
  final String? ciphertext;
  final String? iv;
  final String? error;
  
  EncryptionResult({
    required this.success,
    this.ciphertext,
    this.iv,
    this.error,
  });
}

class DecryptionResult {
  final bool success;
  final String? plaintext;
  final String? error;
  
  DecryptionResult({
    required this.success,
    this.plaintext,
    this.error,
  });
}

class RootDetectionResult {
  final bool rooted;
  final List<String> reasons;
  final String? error;
  
  RootDetectionResult({
    required this.rooted,
    this.reasons = const [],
    this.error,
  });
}

class HookDetectionResult {
  final bool hooked;
  final List<String> frameworks;
  final String? error;
  
  HookDetectionResult({
    required this.hooked,
    this.frameworks = const [],
    this.error,
  });
}

class SecureKeyboardLayout {
  final List<String> digits;
  final List<String> letters;
  final int timestamp;
  
  SecureKeyboardLayout({
    required this.digits,
    required this.letters,
    required this.timestamp,
  });
  
  factory SecureKeyboardLayout.defaultLayout() {
    return SecureKeyboardLayout(
      digits: List.generate(10, (i) => '$i'),
      letters: List.generate(26, (i) => String.fromCharCode(65 + i)),
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
  }
}
