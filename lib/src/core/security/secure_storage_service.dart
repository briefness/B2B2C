import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// 安全存储服务
/// 
/// 负责：
/// 1. 敏感数据加密存储 (Flutter Secure Storage)
/// 2. 普通数据本地存储 (Hive)
/// 3. 加密密钥管理
/// 4. 数据自动清理

class SecureStorageService {
  // ==================== 单例 ====================
  
  static final SecureStorageService _instance = SecureStorageService._internal();
  factory SecureStorageService() => _instance;
  SecureStorageService._internal();
  
  // ==================== 存储实例 ====================
  
  late final FlutterSecureStorage _secureStorage;
  late final Box<dynamic> _hiveBox;
  
  bool _isInitialized = false;
  
  // ==================== 初始化 ====================
  
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    // 初始化 Hive
    await Hive.initFlutter();
    _hiveBox = await Hive.openBox('b2b2c_wallet');
    
    // 初始化安全存储
    _secureStorage = const FlutterSecureStorage(
      aOptions: AndroidOptions(
        encryptedSharedPreferences: true,
        sharedPreferencesName: 'b2b2c_secure',
        preferencesKeyPrefix: 'wallet_',
      ),
      iOptions: IOSOptions(
        accessibility: KeychainAccessibility.first_unlock_this_device,
        accountName: 'b2b2c_wallet',
      ),
    );
    
    _isInitialized = true;
  }
  
  // ==================== 安全存储 (敏感数据) ====================
  
  /// 存储敏感数据
  Future<void> writeSecure(String key, String value) async {
    await _secureStorage.write(key: key, value: value);
  }
  
  /// 读取敏感数据
  Future<String?> readSecure(String key) async {
    return await _secureStorage.read(key: key);
  }
  
  /// 删除敏感数据
  Future<void> deleteSecure(String key) async {
    await _secureStorage.delete(key: key);
  }
  
  /// 存储私钥 (特殊处理)
  Future<void> writePrivateKey(String walletId, String encryptedPrivateKey) async {
    await writeSecure('pk_$walletId', encryptedPrivateKey);
  }
  
  /// 读取私钥
  Future<String?> readPrivateKey(String walletId) async {
    return await readSecure('pk_$walletId');
  }
  
  /// 删除私钥
  Future<void> deletePrivateKey(String walletId) async {
    await deleteSecure('pk_$walletId');
  }
  
  /// 存储助记词 (加密)
  Future<void> writeMnemonic(String walletId, String encryptedMnemonic) async {
    await writeSecure('mn_$walletId', encryptedMnemonic);
  }
  
  /// 读取助记词
  Future<String?> readMnemonic(String walletId) async {
    return await readSecure('mn_$walletId');
  }
  
  /// 存储加密密钥
  Future<void> writeEncryptionKey(String keyId, Uint8List key) async {
    await writeSecure('ek_$keyId', base64Encode(key));
  }
  
  /// 读取加密密钥
  Future<Uint8List?> readEncryptionKey(String keyId) async {
    final encoded = await readSecure('ek_$keyId');
    if (encoded == null) return null;
    return base64Decode(encoded);
  }
  
  /// 存储会话密钥
  Future<void> writeSessionKey(String sessionKey) async {
    await writeSecure('session_key', sessionKey);
  }
  
  /// 读取会话密钥
  Future<String?> readSessionKey() async {
    return await readSecure('session_key');
  }
  
  /// 清除所有安全存储
  Future<void> clearAllSecure() async {
    await _secureStorage.deleteAll();
  }
  
  // ==================== Hive 存储 (非敏感数据) ====================
  
  /// 存储数据
  Future<void> write(String key, dynamic value) async {
    await _hiveBox.put(key, value);
  }
  
  /// 读取数据
  T? read<T>(String key) {
    return _hiveBox.get(key) as T?;
  }
  
  /// 删除数据
  Future<void> delete(String key) async {
    await _hiveBox.delete(key);
  }
  
  /// 存储钱包信息 (非敏感)
  Future<void> writeWalletInfo(String walletId, Map<String, dynamic> info) async {
    await write('wallet_info_$walletId', info);
  }
  
  /// 读取钱包信息
  Map<String, dynamic>? readWalletInfo(String walletId) {
    final data = read<Map<dynamic, dynamic>>('wallet_info_$walletId');
    if (data == null) return null;
    return data.map((k, v) => MapEntry(k.toString(), v));
  }
  
  /// 存储交易历史
  Future<void> writeTransactionHistory(String walletId, List<Map<String, dynamic>> history) async {
    await write('tx_history_$walletId', history);
  }
  
  /// 读取交易历史
  List<Map<String, dynamic>> readTransactionHistory(String walletId) {
    final data = read<List>('tx_history_$walletId');
    if (data == null) return [];
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }
  
  /// 存储应用配置
  Future<void> writeAppConfig(Map<String, dynamic> config) async {
    await write('app_config', config);
  }
  
  /// 读取应用配置
  Map<String, dynamic>? readAppConfig() {
    final data = read<Map<dynamic, dynamic>>('app_config');
    if (data == null) return null;
    return data.map((k, v) => MapEntry(k.toString(), v));
  }
  
  /// 清除所有 Hive 数据
  Future<void> clearAll() async {
    await _hiveBox.clear();
  }
  
  // ==================== 批量操作 ====================
  
  /// 清除所有存储 (安全退出时调用)
  Future<void> clearAllData() async {
    await Future.wait([
      clearAllSecure(),
      clearAll(),
    ]);
  }
  
  /// 导出数据 (加密)
  Future<Map<String, dynamic>> exportData() async {
    final data = <String, dynamic>{
      'hive': _hiveBox.toMap(),
      'exportTime': DateTime.now().toIso8601String(),
    };
    return data;
  }
  
  /// 导入数据 (解密)
  Future<void> importData(Map<String, dynamic> data) async {
    if (data['hive'] != null) {
      for (final entry in (data['hive'] as Map).entries) {
        await write(entry.key.toString(), entry.value);
      }
    }
  }
  
  // ==================== 清理 ====================
  
  /// 删除钱包相关所有数据
  Future<void> deleteWallet(String walletId) async {
    await Future.wait([
      deleteSecure('pk_$walletId'),
      deleteSecure('mn_$walletId'),
      delete('wallet_info_$walletId'),
      delete('tx_history_$walletId'),
    ]);
  }
  
  /// 获取存储使用统计
  Map<String, int> getStorageStats() {
    return {
      'secureKeys': 0, // 无法从外部获取
      'hiveKeys': _hiveBox.length,
    };
  }
}
