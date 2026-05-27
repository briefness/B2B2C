import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/wallet_service.dart';
import '../widgets/anti_reverse_shield.dart';

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
  int _currentStep = 0;
  
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
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('创建钱包'),
      ),
      body: _currentStep == 0 ? _buildCreateForm() : _buildShowMnemonic(),
    );
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
                      // 确认已备份
                      Navigator.of(context).pop(_wallet);
                    }
                  : null,
              child: const Text('我已备份，继续'),
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
