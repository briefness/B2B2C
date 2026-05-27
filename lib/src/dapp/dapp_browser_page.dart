import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../ui/widgets/anti_reverse_shield.dart';
import 'dapp_browser_service.dart';
import 'web3_provider.dart';

class DAppBrowserPage extends ConsumerStatefulWidget {
  final String initialUrl;
  final String? title;
  
  const DAppBrowserPage({
    super.key,
    required this.initialUrl,
    this.title,
  });
  
  @override
  ConsumerState<DAppBrowserPage> createState() => _DAppBrowserPageState();
}

class _DAppBrowserPageState extends ConsumerState<DAppBrowserPage> {
  late final WebViewController _controller;
  final DAppBrowserController _dappController = DAppBrowserController();
  
  double _loadingProgress = 0;
  String _currentUrl = '';
  String _currentTitle = '';
  bool _canGoBack = false;
  bool _canGoForward = false;
  
  DAppRequest? _pendingRequest;
  bool _isProviderInjected = false;
  
  // ==================== WebView 安全 ====================
  
  /// 启用 WebView 截屏防护
  Future<void> _enableWebViewSecurity() async {
    // Android: 通过 MethodChannel 设置 FLAG_SECURE
    if (Platform.isAndroid) {
      try {
        const channel = MethodChannel('com.b2b2c.wallet/security');
        await channel.invokeMethod('enableWebViewSecurity');
      } catch (e) {
        debugPrint('[WebView Security] Failed to enable Android security: $e');
      }
    }
    
    // iOS: 通过 WebView 设置阻止截屏
    if (Platform.isIOS) {
      try {
        const channel = MethodChannel('com.b2b2c.wallet/security');
        await channel.invokeMethod('enableWebViewSecurity');
      } catch (e) {
        debugPrint('[WebView Security] Failed to enable iOS security: $e');
      }
    }
  }
  
  @override
  void initState() {
    super.initState();
    _currentUrl = widget.initialUrl;
    _currentTitle = widget.title ?? 'DApp Browser';
    
    // 启用 WebView 截屏防护
    _enableWebViewSecurity();
    
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            setState(() { _currentUrl = url; });
          },
          onPageFinished: (url) async {
            setState(() { _currentUrl = url; });
            
            final title = await _controller.getTitle();
            if (title != null) {
              setState(() { _currentTitle = title; });
            }
            
            if (!_isProviderInjected) {
              await _dappController.injectProvider();
              _isProviderInjected = true;
            }
            
            _updateNavigationState();
          },
          onProgress: (progress) {
            setState(() { _loadingProgress = progress / 100; });
          },
          onNavigationRequest: (request) {
            if (!request.url.startsWith('https://') && !request.url.startsWith('http://')) {
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..addJavaScriptChannel('flutter_inappwebview', onMessageReceived: _handleJavaScriptMessage);
    
    _dappController.onRequest = _handleDAppRequest;
  }
  
  void _handleJavaScriptMessage(JavaScriptMessage message) async {
    try {
      final payload = jsonDecode(message.message) as Map<String, dynamic>;
      
      final request = DAppRequest(
        id: payload['id']?.toString() ?? '',
        method: payload['method'] as String? ?? '',
        params: payload['params'],
        riskLevel: RiskLevel.low,
      );
      
      _handleDAppRequest(request);
      
      final response = await _service.handleRequest(request);
      
      await _controller.runJavaScript('''
        window.postMessage({
          type: 'web3Response',
          id: '${response.id}',
          result: ${response.result ?? 'null'},
          error: ${response.error != null ? '"${response.error}"' : 'null'}
        }, '*');
      ''');
    } catch (e) {
      debugPrint('[DApp] JS message handler error: $e');
    }
  }
  
  DAppBrowserService get _service => DAppBrowserService();
  
  Future<void> _updateNavigationState() async {
    final canGoBack = await _controller.canGoBack();
    final canGoForward = await _controller.canGoForward();
    setState(() {
      _canGoBack = canGoBack;
      _canGoForward = canGoForward;
    });
  }
  
  @override
  void dispose() {
    _dappController.dispose();
    super.dispose();
  }
  
  void _handleDAppRequest(DAppRequest request) {
    setState(() { _pendingRequest = request; });
    _showTransactionConfirmDialog(request);
  }
  
  Future<void> _showTransactionConfirmDialog(DAppRequest request) async {
    final riskAnalysis = _service.analyzeTransactionRisk(
      (request.params as List?)?.first as Map<String, dynamic>? ?? {},
    );
    
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _TransactionConfirmDialog(
        request: request,
        riskAnalysis: riskAnalysis,
      ),
    );
    
    if (result == true) {
      // TODO: 执行签名
    } else {
      await _dappController.evaluateJs('''
        window.postMessage({
          type: 'web3Response',
          id: '${request.id}',
          error: 'User rejected'
        }, '*');
      ''');
    }
    
    setState(() { _pendingRequest = null; });
  }
  
  @override
  Widget build(BuildContext context) {
    return AntiReverseShield(
      child: Scaffold(
        appBar: _buildAppBar(),
        body: Column(
          children: [
            if (_pendingRequest != null) _buildRiskAlert(),
            Expanded(child: _buildWebView()),
          ],
        ),
        bottomNavigationBar: _buildBottomBar(),
      ),
    );
  }
  
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_currentTitle, style: const TextStyle(fontSize: 16), overflow: TextOverflow.ellipsis),
          Text(
            _currentUrl,
            style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onPrimary.withOpacity(0.7)),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.of(context).pop()),
      actions: [
        IconButton(icon: const Icon(Icons.refresh), onPressed: () => _controller.reload()),
        PopupMenuButton<String>(
          onSelected: (value) {
            switch (value) {
              case 'home':
                _controller.loadRequest(Uri.parse('https://app.uniswap.org'));
                break;
              case 'share':
                break;
              case 'security':
                _showSecurityInfo();
                break;
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'home', child: Text('Go to Uniswap')),
            const PopupMenuItem(value: 'share', child: Text('Share')),
            const PopupMenuItem(value: 'security', child: Text('Security Info')),
          ],
        ),
      ],
    );
  }
  
  Widget _buildRiskAlert() {
    final risk = _pendingRequest?.riskLevel ?? RiskLevel.low;
    final color = _getRiskColor(risk);
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: color.withOpacity(0.1),
      child: Row(
        children: [
          Icon(_getRiskIcon(risk), color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _pendingRequest?.riskDescription ?? '',
              style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildWebView() {
    return Stack(
      children: [
        WebViewWidget(controller: _controller),
        if (_loadingProgress < 1.0)
          LinearProgressIndicator(value: _loadingProgress),
      ],
    );
  }
  
  Widget _buildBottomBar() {
    return SafeArea(
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            IconButton(icon: const Icon(Icons.arrow_back_ios), onPressed: _canGoBack ? () => _controller.goBack() : null),
            IconButton(icon: const Icon(Icons.arrow_forward_ios), onPressed: _canGoForward ? () => _controller.goForward() : null),
            IconButton(icon: const Icon(Icons.home), onPressed: () => _controller.loadRequest(Uri.parse('https://app.uniswap.org'))),
            IconButton(icon: const Icon(Icons.refresh), onPressed: () => _controller.reload()),
            IconButton(icon: const Icon(Icons.settings), onPressed: () => _showSecurityInfo()),
          ],
        ),
      ),
    );
  }
  
  void _showSecurityInfo() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('安全信息', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            const _SecurityInfoRow(icon: Icons.lock, title: '连接安全', description: 'SSL 加密连接'),
            const _SecurityInfoRow(icon: Icons.shield, title: '私钥保护', description: '私钥永不离开安全区域'),
            const _SecurityInfoRow(icon: Icons.warning, title: '交易风险', description: '所有交易需要您确认'),
            const SizedBox(height: 16),
            Text('当前 URL: $_currentUrl', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
  
  Color _getRiskColor(RiskLevel level) {
    switch (level) {
      case RiskLevel.low: return Colors.green;
      case RiskLevel.medium: return Colors.orange;
      case RiskLevel.high: return Colors.deepOrange;
      case RiskLevel.critical: return Colors.red;
    }
  }
  
  IconData _getRiskIcon(RiskLevel level) {
    switch (level) {
      case RiskLevel.low: return Icons.check_circle;
      case RiskLevel.medium: return Icons.warning;
      case RiskLevel.high: return Icons.error;
      case RiskLevel.critical: return Icons.dangerous;
    }
  }
}

class _SecurityInfoRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  
  const _SecurityInfoRow({required this.icon, required this.title, required this.description});
  
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(description, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TransactionConfirmDialog extends StatelessWidget {
  final DAppRequest request;
  final RiskAnalysis riskAnalysis;
  
  const _TransactionConfirmDialog({required this.request, required this.riskAnalysis});
  
  @override
  Widget build(BuildContext context) {
    final isHighRisk = riskAnalysis.level == RiskLevel.high || riskAnalysis.level == RiskLevel.critical;
    
    return AlertDialog(
      title: Row(
        children: [
          Icon(isHighRisk ? Icons.warning : Icons.swap_horiz, color: isHighRisk ? Colors.red : null),
          const SizedBox(width: 8),
          const Text('交易确认'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _getRiskColor(riskAnalysis.level).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _getRiskColor(riskAnalysis.level)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(_getRiskIcon(riskAnalysis.level), color: _getRiskColor(riskAnalysis.level), size: 20),
                      const SizedBox(width: 8),
                      Text(
                        _getRiskLevelText(riskAnalysis.level),
                        style: TextStyle(fontWeight: FontWeight.bold, color: _getRiskColor(riskAnalysis.level)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(riskAnalysis.description),
                  if (riskAnalysis.recommendations.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text('建议:', style: TextStyle(fontWeight: FontWeight.w600)),
                    ...riskAnalysis.recommendations.map((r) => Padding(
                      padding: const EdgeInsets.only(left: 8, top: 4),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('• '),
                        Expanded(child: Text(r)),
                      ]),
                    )),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text('方法: ${request.method}', style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('取消')),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: isHighRisk ? ElevatedButton.styleFrom(backgroundColor: Colors.red) : null,
          child: Text(isHighRisk ? '确认继续' : '确认'),
        ),
      ],
    );
  }
  
  Color _getRiskColor(RiskLevel level) {
    switch (level) {
      case RiskLevel.low: return Colors.green;
      case RiskLevel.medium: return Colors.orange;
      case RiskLevel.high: return Colors.deepOrange;
      case RiskLevel.critical: return Colors.red;
    }
  }
  
  IconData _getRiskIcon(RiskLevel level) {
    switch (level) {
      case RiskLevel.low: return Icons.check_circle;
      case RiskLevel.medium: return Icons.warning;
      case RiskLevel.high: return Icons.error;
      case RiskLevel.critical: return Icons.dangerous;
    }
  }
  
  String _getRiskLevelText(RiskLevel level) {
    switch (level) {
      case RiskLevel.low: return '低风险';
      case RiskLevel.medium: return '中等风险';
      case RiskLevel.high: return '高风险';
      case RiskLevel.critical: return '极高风险';
    }
  }
}
