import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/security/method_channel_service.dart';
import '../../core/security/secure_keyboard_service.dart';

/// 安全键盘
/// 
/// 完全自绘的虚拟键盘，键位每次随机打乱。
/// 捕获物理点击事件，防止第三方输入法介入。
/// 
/// 使用方式：
/// ```dart
/// SecureKeyboard(
///   onComplete: (value) => print('输入完成: $value'),
///   maxLength: 6,
///   keyboardType: SecureKeyboardType.pin,
/// )
/// ```

enum SecureKeyboardType {
  /// 数字 PIN 键盘
  pin,
  
  /// 助记词键盘 (24 词)
  mnemonic,
  
  /// 通用数字键盘
  number,
  
  /// 混合键盘 (数字+字母)
  mixed,
}

class SecureKeyboard extends StatefulWidget {
  /// 输入完成回调
  final ValueChanged<String> onComplete;
  
  /// 最大输入长度
  final int? maxLength;
  
  /// 键盘类型
  final SecureKeyboardType keyboardType;
  
  /// 输入框样式
  final TextStyle? inputStyle;
  
  /// 占位符样式
  final TextStyle? placeholderStyle;
  
  /// 键盘背景色
  final Color? keyboardBackgroundColor;
  
  /// 按钮颜色
  final Color? buttonColor;
  
  /// 按下时按钮颜色
  final Color? buttonPressedColor;
  
  /// 是否显示明文
  final bool obscureText;
  
  /// 输入验证
  final String? Function(String)? validator;
  
  /// 错误提示
  final String? errorText;
  
  /// 是否自动获取焦点
  final bool autofocus;
  
  /// 完成按钮文本
  final String? confirmText;
  
  const SecureKeyboard({
    super.key,
    required this.onComplete,
    this.maxLength,
    this.keyboardType = SecureKeyboardType.pin,
    this.inputStyle,
    this.placeholderStyle,
    this.keyboardBackgroundColor,
    this.buttonColor,
    this.buttonPressedColor,
    this.obscureText = true,
    this.validator,
    this.errorText,
    this.autofocus = true,
    this.confirmText,
  });
  
  @override
  State<SecureKeyboard> createState() => _SecureKeyboardState();
}

class _SecureKeyboardState extends State<SecureKeyboard> with SingleTickerProviderStateMixin {
  // ==================== 状态 ====================
  
  final _inputBuffer = <String>[];
  String _displayText = '';
  bool _hasError = false;
  String? _errorMessage;
  
  // 键盘布局
  late SecureKeyboardLayout _layout;
  
  // 动画控制器
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;
  
  // 服务
  final _keyboardService = SecureKeyboardService();
  
  // ==================== 生命周期 ====================
  
  @override
  void initState() {
    super.initState();
    
    // 生成随机键盘布局
    _layout = _keyboardService.generateLocalLayout();
    
    // 初始化抖动动画
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 24)
        .chain(CurveTween(curve: Curves.elasticIn))
        .animate(_shakeController);
    
    // 监听错误文本变化
    if (widget.errorText != null) {
      _errorMessage = widget.errorText;
      _hasError = true;
    }
  }
  
  @override
  void dispose() {
    _shakeController.dispose();
    _keyboardService.dispose();
    super.dispose();
  }
  
  // ==================== 输入处理 ====================
  
  void _onKeyPressed(String key) {
    HapticFeedback.lightImpact();
    
    setState(() {
      if (key == 'delete') {
        if (_inputBuffer.isNotEmpty) {
          _inputBuffer.removeLast();
          _updateDisplayText();
        }
      } else if (key == 'confirm') {
        _onComplete();
      } else if (widget.maxLength == null || _inputBuffer.length < widget.maxLength!) {
        _inputBuffer.add(key);
        _updateDisplayText();
        
        // 触发抖动动画
        if (_hasError) {
          _shakeController.forward(from: 0);
        }
        _hasError = false;
        _errorMessage = null;
        
        // 自动完成
        if (widget.maxLength != null && _inputBuffer.length >= widget.maxLength!) {
          _onComplete();
        }
      }
    });
  }
  
  void _updateDisplayText() {
    if (widget.obscureText) {
      _displayText = '●' * _inputBuffer.length;
    } else {
      _displayText = _inputBuffer.join();
    }
  }
  
  void _onComplete() {
    final value = _inputBuffer.join();
    
    // 验证
    if (widget.validator != null) {
      final error = widget.validator!(value);
      if (error != null) {
        setState(() {
          _hasError = true;
          _errorMessage = error;
        });
        _shakeController.forward(from: 0);
        return;
      }
    }
    
    widget.onComplete(value);
  }
  
  void _refreshLayout() {
    setState(() {
      _layout = _keyboardService.generateLocalLayout();
    });
  }
  
  // ==================== 构建 ====================
  
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 输入显示区
        _buildInputDisplay(),
        
        const SizedBox(height: 16),
        
        // 键盘区
        _buildKeyboard(),
      ],
    );
  }
  
  Widget _buildInputDisplay() {
    return AnimatedBuilder(
      animation: _shakeAnimation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(
            sin(_shakeAnimation.value * pi / 12) * 8,
            0,
          ),
          child: child,
        );
      },
      child: Column(
        children: [
          // 密码点显示
          _buildDots(),
          
          // 错误信息
          if (_errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }
  
  Widget _buildDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        widget.maxLength ?? 6,
        (index) {
          final isFilled = index < _inputBuffer.length;
          return Container(
            width: 12,
            height: 12,
            margin: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _hasError
                  ? Theme.of(context).colorScheme.error
                  : isFilled
                      ? Theme.of(context).colorScheme.primary
                      : Colors.transparent,
              border: Border.all(
                color: _hasError
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.primary,
                width: 1.5,
              ),
            ),
          );
        },
      ),
    );
  }
  
  Widget _buildKeyboard() {
    final bgColor = widget.keyboardBackgroundColor ?? const Color(0xFFF5F5F5);
    final btnColor = widget.buttonColor ?? Colors.white;
    final pressedColor = widget.buttonPressedColor ?? const Color(0xFFE0E0E0);
    
    return Container(
      color: bgColor,
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          // 刷新按钮
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              icon: const Icon(Icons.refresh, size: 20),
              onPressed: _refreshLayout,
              tooltip: '刷新键盘',
            ),
          ),
          
          // 根据键盘类型构建
          _buildKeyboardGrid(btnColor, pressedColor),
        ],
      ),
    );
  }
  
  Widget _buildKeyboardGrid(Color btnColor, Color pressedColor) {
    switch (widget.keyboardType) {
      case SecureKeyboardType.pin:
      case SecureKeyboardType.number:
        return _buildNumberKeyboard(btnColor, pressedColor);
        
      case SecureKeyboardType.mnemonic:
        return _buildMnemonicKeyboard(btnColor, pressedColor);
        
      case SecureKeyboardType.mixed:
        return _buildMixedKeyboard(btnColor, pressedColor);
    }
  }
  
  Widget _buildNumberKeyboard(Color btnColor, Color pressedColor) {
    final digits = _layout.digits;
    final rows = <List<String>>[];
    
    for (var i = 0; i < digits.length; i += 3) {
      final end = (i + 3 > digits.length) ? digits.length : i + 3;
      rows.add(digits.sublist(i, end));
    }
    
    return Column(
      children: [
        // 数字行
        ...rows.map((row) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: row.map((digit) {
                return _buildKey(digit, btnColor, pressedColor);
              }).toList(),
            ),
          );
        }),
        
        // 底部行: 删除 + 0 + 确认
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildKey('delete', btnColor, pressedColor, isIcon: true, icon: Icons.backspace_outlined),
              _buildKey(digits[0], btnColor, pressedColor),
              _buildConfirmKey(btnColor, pressedColor),
            ],
          ),
        ),
      ],
    );
  }
  
  Widget _buildMnemonicKeyboard(Color btnColor, Color pressedColor) {
    final letters = _layout.letters;
    final rows = <List<String>>[];
    
    for (var i = 0; i < letters.length; i += 7) {
      final end = (i + 7 > letters.length) ? letters.length : i + 7;
      rows.add(letters.sublist(i, end));
    }
    
    return Column(
      children: [
        ...rows.map((row) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: row.map((letter) {
                return _buildKey(letter, btnColor, pressedColor, width: 36, height: 40);
              }).toList(),
            ),
          );
        }),
        
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildKey('delete', btnColor, pressedColor, isIcon: true, icon: Icons.backspace_outlined),
              const Spacer(),
              _buildConfirmKey(btnColor, pressedColor),
            ],
          ),
        ),
      ],
    );
  }
  
  Widget _buildMixedKeyboard(Color btnColor, Color pressedColor) {
    // 混合键盘: 数字 + 字母 + 特殊符号
    return Column(
      children: [
        // 数字行
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: _layout.digits.take(5).map((d) {
              return _buildKey(d, btnColor, pressedColor);
            }).toList(),
          ),
        ),
        
        // 字母前 9 个
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: _layout.letters.take(9).map((l) {
              return _buildKey(l, btnColor, pressedColor, width: 32, height: 40);
            }).toList(),
          ),
        ),
        
        // 字母 9-18 个
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: _layout.letters.skip(9).take(9).map((l) {
              return _buildKey(l, btnColor, pressedColor, width: 32, height: 40);
            }).toList(),
          ),
        ),
        
        // 字母 18-26 + 删除 + 确认
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildKey('delete', btnColor, pressedColor, isIcon: true, icon: Icons.backspace_outlined),
              ..._layout.letters.skip(18).take(8).map((l) {
                return _buildKey(l, btnColor, pressedColor, width: 32, height: 40);
              }),
              _buildConfirmKey(btnColor, pressedColor),
            ],
          ),
        ),
      ],
    );
  }
  
  Widget _buildKey(
    String key,
    Color btnColor,
    Color pressedColor, {
    bool isIcon = false,
    IconData? icon,
    double width = 72,
    double height = 56,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Material(
        color: btnColor,
        borderRadius: BorderRadius.circular(8),
        elevation: 1,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          splashColor: pressedColor,
          highlightColor: pressedColor,
          onTap: () => _onKeyPressed(key),
          child: Container(
            width: width,
            height: height,
            alignment: Alignment.center,
            child: isIcon && icon != null
                ? Icon(icon, size: 24, color: Colors.black87)
                : Text(
                    key,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildConfirmKey(Color btnColor, Color pressedColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Material(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(8),
        elevation: 1,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          splashColor: pressedColor,
          onTap: () => _onKeyPressed('confirm'),
          child: Container(
            width: 72,
            height: 56,
            alignment: Alignment.center,
            child: Text(
              widget.confirmText ?? '确认',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 安全文本字段
/// 
/// 使用安全键盘的文本输入框
class SecureTextField extends StatefulWidget {
  final SecureKeyboardType keyboardType;
  final int? maxLength;
  final ValueChanged<String> onChanged;
  final bool autofocus;
  
  const SecureTextField({
    super.key,
    this.keyboardType = SecureKeyboardType.pin,
    this.maxLength,
    required this.onChanged,
    this.autofocus = true,
  });
  
  @override
  State<SecureTextField> createState() => _SecureTextFieldState();
}

class _SecureTextFieldState extends State<SecureTextField> {
  String _value = '';
  
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 占位显示
        Container(
          height: 56,
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).colorScheme.outline),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              '●' * _value.length,
              style: const TextStyle(fontSize: 24, letterSpacing: 8),
            ),
          ),
        ),
        
        const SizedBox(height: 16),
        
        // 安全键盘
        SecureKeyboard(
          keyboardType: widget.keyboardType,
          maxLength: widget.maxLength,
          onComplete: (value) {
            setState(() => _value = value);
            widget.onChanged(value);
          },
        ),
      ],
    );
  }
}
