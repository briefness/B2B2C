import 'package:flutter/foundation.dart';

import '../core/ffi/ffi.dart';
import '../core/security/secure_storage_service.dart';
import '../core/security/security_service.dart';

/// 钱包服务
/// 
/// 负责：
/// 1. 钱包创建/导入
/// 2. 钱包存储
/// 3. 余额查询
/// 4. 交易签名

class WalletService {
  // ==================== 单例 ====================
  
  static final WalletService _instance = WalletService._internal();
  factory WalletService() => _instance;
  WalletService._internal();
  
  // ==================== 依赖 ====================
  
  final _storage = SecureStorageService();
  final _security = SecurityService();
  
  // ==================== 状态 ====================
  
  Wallet? _currentWallet;
  Wallet? get currentWallet => _currentWallet;
  
  // ==================== 钱包创建 ====================
  
  /// 创建新钱包
  Future<WalletCreateResult> createWallet({
    String? name,
    String? passphrase,
  }) async {
    try {
      // 1. 生成助记词
      final mnemonic = generateMnemonic(MnemonicStrength.bits128);
      
      // 2. 验证助记词
      if (!validateMnemonic(mnemonic)) {
        return WalletCreateResult(
          success: false,
          error: 'Failed to validate mnemonic',
        );
      }
      
      // 3. 生成种子
      final seed = mnemonicToSeed(mnemonic, passphrase ?? '');
      
      // 4. 派生地址
      final address = deriveAddress(seed, "m/44'/60'/0'/0/0");
      
      // 5. 创建钱包对象
      final wallet = Wallet(
        id: _generateWalletId(),
        name: name ?? 'Wallet ${DateTime.now().millisecondsSinceEpoch}',
        address: address,
        createdAt: DateTime.now(),
        isImported: false,
      );
      
      // 6. 加密并存储
      await _storeWalletData(wallet, mnemonic, seed, passphrase);
      
      // 7. 设为当前钱包
      _currentWallet = wallet;
      
      return WalletCreateResult(
        success: true,
        wallet: wallet,
        mnemonic: mnemonic, // 仅在创建时返回
      );
    } catch (e) {
      debugPrint('[Wallet] Create wallet error: $e');
      return WalletCreateResult(
        success: false,
        error: e.toString(),
      );
    }
  }
  
  /// 导入钱包
  Future<WalletImportResult> importWallet({
    required String mnemonic,
    String? name,
    String? passphrase,
  }) async {
    try {
      // 1. 验证助记词
      if (!validateMnemonic(mnemonic)) {
        return WalletImportResult(
          success: false,
          error: 'Invalid mnemonic',
        );
      }
      
      // 2. 生成种子
      final seed = mnemonicToSeed(mnemonic, passphrase ?? '');
      
      // 3. 派生地址
      final address = deriveAddress(seed, "m/44'/60'/0'/0/0");
      
      // 4. 检查是否已存在
      final existingWallet = await _findWalletByAddress(address);
      if (existingWallet != null) {
        return WalletImportResult(
          success: false,
          error: 'Wallet already exists',
          existingWallet: existingWallet,
        );
      }
      
      // 5. 创建钱包对象
      final wallet = Wallet(
        id: _generateWalletId(),
        name: name ?? 'Imported Wallet',
        address: address,
        createdAt: DateTime.now(),
        isImported: true,
      );
      
      // 6. 加密并存储
      await _storeWalletData(wallet, mnemonic, seed, passphrase);
      
      // 7. 设为当前钱包
      _currentWallet = wallet;
      
      return WalletImportResult(
        success: true,
        wallet: wallet,
      );
    } catch (e) {
      debugPrint('[Wallet] Import wallet error: $e');
      return WalletImportResult(
        success: false,
        error: e.toString(),
      );
    }
  }
  
  // ==================== 钱包管理 ====================
  
  /// 获取所有钱包
  Future<List<Wallet>> getAllWallets() async {
    final walletIds = await _getWalletIds();
    final wallets = <Wallet>[];
    
    for (final id in walletIds) {
      final wallet = await _loadWallet(id);
      if (wallet != null) {
        wallets.add(wallet);
      }
    }
    
    return wallets;
  }
  
  /// 获取钱包详情
  Future<Wallet?> getWallet(String walletId) async {
    return await _loadWallet(walletId);
  }
  
  /// 删除钱包
  Future<bool> deleteWallet(String walletId) async {
    try {
      await _storage.deleteWallet(walletId);
      
      if (_currentWallet?.id == walletId) {
        _currentWallet = null;
      }
      
      return true;
    } catch (e) {
      debugPrint('[Wallet] Delete wallet error: $e');
      return false;
    }
  }
  
  /// 设置当前钱包
  Future<void> setCurrentWallet(String walletId) async {
    final wallet = await _loadWallet(walletId);
    if (wallet != null) {
      _currentWallet = wallet;
    }
  }
  
  // ==================== 签名 ====================
  
  /// 签名交易
  Future<TransactionSignResult> signTransaction({
    required String walletId,
    required String to,
    required String value,
    required String data,
    int chainId = 1,
  }) async {
    try {
      // 1. 安全检查
      final canSign = await _security.canPerformSensitiveOperation();
      if (!canSign) {
        return TransactionSignResult(
          success: false,
          error: 'Security check failed',
        );
      }
      
      // 2. 获取私钥
      final privateKey = await _getPrivateKey(walletId);
      if (privateKey == null) {
        return TransactionSignResult(
          success: false,
          error: 'Failed to get private key',
        );
      }
      
      // 3. 构建交易哈希
      final txHash = _buildTransactionHash(
        to: to,
        value: value,
        data: data,
        chainId: chainId,
      );
      
      // 4. 签名
      final signature = signTransactionFFI(
        privateKey,
        txHash,
        chainId: chainId,
      );
      
      return TransactionSignResult(
        success: true,
        signature: signature,
        transactionHash: txHash,
      );
    } catch (e) {
      debugPrint('[Wallet] Sign transaction error: $e');
      return TransactionSignResult(
        success: false,
        error: e.toString(),
      );
    }
  }
  
  // ==================== 私有方法 ====================
  
  Future<void> _storeWalletData(
    Wallet wallet,
    String mnemonic,
    String seed,
    String? passphrase,
  ) async {
    // 1. 存储钱包信息
    await _storage.writeWalletInfo(wallet.id, wallet.toJson());
    
    // 2. 加密并存储助记词
    final encryptedMnemonic = _encryptMnemonic(mnemonic, passphrase ?? '');
    await _storage.writeMnemonic(wallet.id, encryptedMnemonic);
    
    // 3. 添加到钱包列表
    await _addWalletId(wallet.id);
  }
  
  Future<Wallet?> _loadWallet(String walletId) async {
    final info = _storage.readWalletInfo(walletId);
    if (info == null) return null;
    return Wallet.fromJson(info);
  }
  
  Future<String?> _getPrivateKey(String walletId) async {
    // 需要用户验证后才能获取私钥
    // 这里返回 null，实际需要生物识别后解密
    return null;
  }
  
  Future<Wallet?> _findWalletByAddress(String address) async {
    final wallets = await getAllWallets();
    return wallets.cast<Wallet?>().firstWhere(
      (w) => w?.address.toLowerCase() == address.toLowerCase(),
      orElse: () => null,
    );
  }
  
  Future<List<String>> _getWalletIds() async {
    final ids = _storage.read<List<dynamic>>('wallet_ids');
    return ids?.cast<String>() ?? [];
  }
  
  Future<void> _addWalletId(String walletId) async {
    final ids = await _getWalletIds();
    if (!ids.contains(walletId)) {
      ids.add(walletId);
      await _storage.write('wallet_ids', ids);
    }
  }
  
  String _generateWalletId() {
    return 'wallet_${DateTime.now().millisecondsSinceEpoch}_${_generateRandomString(8)}';
  }
  
  String _generateRandomString(int length) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final random = List.generate(length, (index) {
      return chars[DateTime.now().microsecondsSinceEpoch % chars.length];
    }).join();
    return random;
  }
  
  String _encryptMnemonic(String mnemonic, String passphrase) {
    // 生成随机密钥
    final key = SecureCrypto.generateRandomBytesHex(32);
    // 使用 AES-256-CBC 加密
    final encrypted = SecureCrypto.aes256CbcEncrypt(mnemonic, key);
    // 返回 密钥 + 分隔符 + 密文
    return '$key:$encrypted';
  }
  
  String _buildTransactionHash({
    required String to,
    required String value,
    required String data,
    required int chainId,
  }) {
    // 简化实现 - 实际应构建 RLP 编码
    final txData = '$to$value$data$chainId';
    return sha256Hash(_toHex(txData));
  }
  
  String _toHex(String data) {
    return data.codeUnits.map((c) => c.toRadixString(16).padLeft(2, '0')).join();
  }
}

// ==================== 数据模型 ====================

class Wallet {
  final String id;
  final String name;
  final String address;
  final DateTime createdAt;
  final bool isImported;
  final String? avatarUrl;
  
  Wallet({
    required this.id,
    required this.name,
    required this.address,
    required this.createdAt,
    required this.isImported,
    this.avatarUrl,
  });
  
  factory Wallet.fromJson(Map<String, dynamic> json) {
    return Wallet(
      id: json['id'] as String,
      name: json['name'] as String,
      address: json['address'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      isImported: json['isImported'] as bool,
      avatarUrl: json['avatarUrl'] as String?,
    );
  }
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'address': address,
    'createdAt': createdAt.toIso8601String(),
    'isImported': isImported,
    'avatarUrl': avatarUrl,
  };
  
  /// 短地址
  String get shortAddress {
    if (address.length < 10) return address;
    return '${address.substring(0, 6)}...${address.substring(address.length - 4)}';
  }
}

// ==================== 结果模型 ====================

class WalletCreateResult {
  final bool success;
  final Wallet? wallet;
  final String? mnemonic; // 仅创建时返回
  final String? error;
  
  WalletCreateResult({
    required this.success,
    this.wallet,
    this.mnemonic,
    this.error,
  });
}

class WalletImportResult {
  final bool success;
  final Wallet? wallet;
  final Wallet? existingWallet;
  final String? error;
  
  WalletImportResult({
    required this.success,
    this.wallet,
    this.existingWallet,
    this.error,
  });
}

class TransactionSignResult {
  final bool success;
  final String? signature;
  final String? transactionHash;
  final String? error;
  
  TransactionSignResult({
    required this.success,
    this.signature,
    this.transactionHash,
    this.error,
  });
}
