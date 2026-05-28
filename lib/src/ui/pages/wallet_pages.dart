import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/security/secure_storage_service.dart';
import '../../core/security/security_service.dart';
import '../../services/wallet_service.dart';
import '../widgets/anti_reverse_shield.dart';
import '../widgets/secure_keyboard.dart';

/// 钱包服务 Provider
final walletServiceProvider = Provider<WalletService>((ref) {
  return WalletService();
});

/// 当前钱包 Provider
final currentWalletProvider = StateProvider<Wallet?>((ref) {
  return null;
});

/// 钱包列表 Provider
final walletListProvider = FutureProvider<List<Wallet>>((ref) async {
  final service = ref.watch(walletServiceProvider);
  return await service.getAllWallets();
});

/// 主页
class HomePage extends ConsumerWidget {
  const HomePage({super.key});
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallet = ref.watch(currentWalletProvider);
    
    return AntiReverseShield(
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              // 头部
              _buildHeader(context, wallet),
              
              // 余额卡片
              _buildBalanceCard(context, wallet),
              
              // 功能区
              Expanded(
                child: _buildFunctionGrid(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildHeader(BuildContext context, Wallet? wallet) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          // Logo
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.account_balance_wallet,
              color: Colors.white,
            ),
          ),
          
          const SizedBox(width: 12),
          
          // 钱包名称
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  wallet?.name ?? 'B2B2C Wallet',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (wallet != null)
                  Text(
                    wallet.shortAddress,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          
          // 设置按钮
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.of(context).pushNamed('/settings');
            },
          ),
        ],
      ),
    );
  }
  
  Widget _buildBalanceCard(BuildContext context, Wallet? wallet) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Theme.of(context).colorScheme.primary,
            Theme.of(context).colorScheme.secondary,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '总资产',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '\$0.00',
            style: TextStyle(
              color: Colors.white,
              fontSize: 36,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.account_balance, color: Colors.white70, size: 16),
              const SizedBox(width: 4),
              const Text(
                '0.00 ETH',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  '+0.00%',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildFunctionGrid(BuildContext context) {
    final functions = [
      _FunctionItem(
        icon: Icons.swap_horiz,
        label: '转账',
        onTap: () => Navigator.of(context).pushNamed('/transfer'),
      ),
      _FunctionItem(
        icon: Icons.qr_code,
        label: '收款',
        onTap: () => Navigator.of(context).pushNamed('/receive'),
      ),
      _FunctionItem(
        icon: Icons.explore,
        label: 'DApp',
        onTap: () => Navigator.of(context).pushNamed('/dapp'),
      ),
      _FunctionItem(
        icon: Icons.history,
        label: '记录',
        onTap: () => Navigator.of(context).pushNamed('/history'),
      ),
      _FunctionItem(
        icon: Icons.security,
        label: '安全中心',
        onTap: () => Navigator.of(context).pushNamed('/security'),
      ),
      _FunctionItem(
        icon: Icons.language,
        label: '浏览器',
        onTap: () => Navigator.of(context).pushNamed('/browser'),
      ),
    ];
    
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 1,
      ),
      itemCount: functions.length,
      itemBuilder: (context, index) {
        final item = functions[index];
        return _buildFunctionCard(context, item);
      },
    );
  }
  
  Widget _buildFunctionCard(BuildContext context, _FunctionItem item) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(12),
      elevation: 2,
      child: InkWell(
        onTap: item.onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              item.icon,
              size: 32,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 8),
            Text(
              item.label,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _FunctionItem {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  
  _FunctionItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });
}

/// 创建钱包页面
class CreateWalletPage extends ConsumerStatefulWidget {
  const CreateWalletPage({super.key});
  
  @override
  ConsumerState<CreateWalletPage> createState() => _CreateWalletPageState();
}

class _CreateWalletPageState extends ConsumerState<CreateWalletPage> {
  final _walletService = WalletService();
  String? _mnemonic;
  Wallet? _wallet;
  bool _isCreating = false;
  bool _showMnemonic = false;
  int _currentStep = 0; // 0=创建, 1=助记词, 2=设置PIN, 3=确认PIN
  
  String? _firstPin;
  String? _pinError;
  
  Future<void> _createWallet() async {
    setState(() => _isCreating = true);
    
    final result = await _walletService.createWallet();
    
    setState(() {
      _isCreating = false;
      if (result.success) {
        _wallet = result.wallet;
        _mnemonic = result.mnemonic;
        _currentStep = 1;
      }
    });
  }
  
  void _onPinSet(String pin) {
    setState(() {
      _firstPin = pin;
      _pinError = null;
      _currentStep = 3;
    });
  }
  
  Future<void> _onPinConfirm(String pin) async {
    if (pin == _firstPin) {
      // PIN 一致，执行安全存储
      final storage = SecureStorageService();
      final security = SecurityService();
      
      // 安全环境检查（Release 模式下阻止不安全环境）
      final canProceed = await security.canPerformSensitiveOperation();
      if (!canProceed && !kDebugMode) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('检测到不安全环境，无法完成操作')),
          );
        }
        return;
      }
      
      // 存储 PIN 哈希到安全存储
      await storage.writeSecure('wallet_pin', pin);
      
      // 存储助记词到安全存储
      if (_wallet != null && _mnemonic != null) {
        await storage.writeMnemonic(_wallet!.id, _mnemonic!);
      }
      
      if (mounted) {
        Navigator.of(context).pop(_wallet);
      }
    } else {
      setState(() {
        _pinError = 'PIN 不一致，请重新输入';
        _currentStep = 2;
        _firstPin = null;
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_getStepTitle()),
        leading: _currentStep > 0
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  if (_currentStep == 1) {
                    Navigator.of(context).pop();
                  } else {
                    setState(() => _currentStep = _currentStep - 1);
                  }
                },
              )
            : null,
      ),
      body: _buildCurrentStep(),
    );
  }
  
  String _getStepTitle() {
    switch (_currentStep) {
      case 0: return '创建钱包';
      case 1: return '备份助记词';
      case 2: return '设置 PIN';
      case 3: return '确认 PIN';
      default: return '创建钱包';
    }
  }
  
  Widget _buildCurrentStep() {
    switch (_currentStep) {
      case 0: return _buildCreateForm();
      case 1: return _buildShowMnemonic();
      case 2: return _buildSetPin();
      case 3: return _buildConfirmPin();
      default: return _buildCreateForm();
    }
  }
  
  Widget _buildCreateForm() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.account_balance_wallet,
            size: 80,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 24),
          Text(
            '创建新钱包',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          Text(
            '我们将为您生成一个安全的加密货币钱包',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 48),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isCreating ? null : _createWallet,
              child: _isCreating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('创建钱包'),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildShowMnemonic() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 警告
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.warning, color: Colors.orange.shade700),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '请妥善保管您的助记词！\n丢失将无法恢复钱包资产。',
                    style: TextStyle(color: Colors.orange.shade900),
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 24),
          
          Text(
            '您的助记词',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          
          // 助记词显示
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                if (_showMnemonic && _mnemonic != null)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _mnemonic!.split(' ').asMap().entries.map((entry) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Text(
                          '${entry.key + 1}. ${entry.value}',
                          style: const TextStyle(fontSize: 14),
                        ),
                      );
                    }).toList(),
                  )
                else
                  Center(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        setState(() => _showMnemonic = true);
                      },
                      icon: const Icon(Icons.visibility),
                      label: const Text('显示助记词'),
                    ),
                  ),
              ],
            ),
          ),
          
          const SizedBox(height: 24),
          
          // 下一步按钮
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _showMnemonic
                  ? () {
                      setState(() => _currentStep = 2);
                    }
                  : null,
              child: const Text('我已备份，下一步'),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildSetPin() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 32),
          
          Icon(
            Icons.lock_outline,
            size: 48,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          
          Text(
            '设置 6 位 PIN 码',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            '用于保护您的钱包安全',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          
          if (_pinError != null) ...[
            const SizedBox(height: 12),
            Text(
              _pinError!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 14,
              ),
            ),
          ],
          
          const SizedBox(height: 32),
          
          Expanded(
            child: SecureKeyboard(
              keyboardType: SecureKeyboardType.pin,
              maxLength: 6,
              obscureText: true,
              onComplete: _onPinSet,
              errorText: _pinError,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildConfirmPin() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 32),
          
          Icon(
            Icons.lock_outline,
            size: 48,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          
          Text(
            '再次输入 PIN 码',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            '请确认您的 PIN 码',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          
          const SizedBox(height: 32),
          
          Expanded(
            child: SecureKeyboard(
              keyboardType: SecureKeyboardType.pin,
              maxLength: 6,
              obscureText: true,
              onComplete: _onPinConfirm,
            ),
          ),
        ],
      ),
    );
  }
}


/// 导入钱包页面
class ImportWalletPage extends ConsumerStatefulWidget {
  const ImportWalletPage({super.key});
  
  @override
  ConsumerState<ImportWalletPage> createState() => _ImportWalletPageState();
}

class _ImportWalletPageState extends ConsumerState<ImportWalletPage> {
  final _walletService = WalletService();
  final _mnemonicController = TextEditingController();
  bool _isImporting = false;
  String? _error;
  
  @override
  void dispose() {
    _mnemonicController.dispose();
    super.dispose();
  }
  
  Future<void> _importWallet() async {
    final mnemonic = _mnemonicController.text.trim();
    if (mnemonic.isEmpty) {
      setState(() => _error = '请输入助记词');
      return;
    }
    
    setState(() {
      _isImporting = true;
      _error = null;
    });
    
    final result = await _walletService.importWallet(mnemonic: mnemonic);
    
    setState(() {
      _isImporting = false;
      if (result.success) {
        Navigator.of(context).pop(result.wallet);
      } else {
        _error = result.error;
      }
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('导入钱包'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '输入助记词',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Text(
              '请输入您钱包的 12 或 24 个助记词，用空格分隔',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            
            // 助记词输入框
            TextField(
              controller: _mnemonicController,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'word1 word2 word3 ...',
                errorText: _error,
                border: const OutlineInputBorder(),
              ),
            ),
            
            const SizedBox(height: 24),
            
            // 导入按钮
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isImporting ? null : _importWallet,
                child: _isImporting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('导入钱包'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
