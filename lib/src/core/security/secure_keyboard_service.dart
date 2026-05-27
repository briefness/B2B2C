import 'dart:async';
import 'dart:math';

import 'method_channel_service.dart';

export 'method_channel_service.dart' show SecureKeyboardLayout;
export 'secure_keyboard_service.dart' show SecureKeyboardService;

/// 安全键盘服务
/// 
/// 特性：
/// 1. 每次打开随机打乱键位
/// 2. 捕获物理点击事件，无第三方输入法介入
/// 3. 自动清理输入内容
/// 4. 防截屏、录屏

class SecureKeyboardService {
  // ==================== 单例 ====================
  
  static final SecureKeyboardService _instance = SecureKeyboardService._internal();
  factory SecureKeyboardService() => _instance;
  SecureKeyboardService._internal();
  
  // ==================== 依赖 ====================
  
  final _methodChannel = MethodChannelService();
  
  // ==================== 状态 ====================
  
  SecureKeyboardLayout? _currentLayout;
  final List<String> _inputBuffer = [];
  final _inputController = StreamController<String>.broadcast();
  
  Stream<String> get inputStream => _inputController.stream;
  String get currentInput => _inputBuffer.join();
  int get inputLength => _inputBuffer.length;
  
  // ==================== 键盘布局 ====================
  
  /// 获取当前键盘布局
  SecureKeyboardLayout get currentLayout {
    _currentLayout ??= SecureKeyboardLayout.defaultLayout();
    return _currentLayout!;
  }
  
  /// 刷新键盘布局 (生成新的随机布局)
  Future<void> refreshLayout() async {
    _currentLayout = await _methodChannel.generateSecureKeyboardLayout();
  }
  
  /// 生成随机键盘布局 (本地)
  SecureKeyboardLayout generateLocalLayout() {
    final random = Random.secure();
    final digits = List.generate(10, (i) => '$i')..shuffle(random);
    final letters = List.generate(26, (i) => String.fromCharCode(65 + i))..shuffle(random);
    
    return SecureKeyboardLayout(
      digits: digits,
      letters: letters,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
  }
  
  // ==================== 输入处理 ====================
  
  /// 添加字符
  void addChar(String char) {
    _inputBuffer.add(char);
    _inputController.add(currentInput);
  }
  
  /// 删除最后一个字符
  void deleteChar() {
    if (_inputBuffer.isNotEmpty) {
      _inputBuffer.removeLast();
      _inputController.add(currentInput);
    }
  }
  
  /// 清空输入
  void clear() {
    _inputBuffer.clear();
    _inputController.add('');
  }
  
  /// 清空并返回输入内容
  String consumeAndClear() {
    final result = currentInput;
    clear();
    return result;
  }
  
  // ==================== 释放 ====================
  
  void dispose() {
    _inputController.close();
  }
}
