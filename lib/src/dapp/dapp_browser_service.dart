import 'dart:async';
import 'dart:convert';

/// DApp 浏览器服务
/// 
/// 负责：
/// 1. Web3 Provider 注入 (EIP-1193)
/// 2. 交易签名拦截
/// 3. 合约ABI解析
/// 4. 危险操作警告

class DAppBrowserService {
  // ==================== 单例 ====================
  
  static final DAppBrowserService _instance = DAppBrowserService._internal();
  factory DAppBrowserService() => _instance;
  DAppBrowserService._internal();
  
  // ==================== 配置 ====================
  
  /// 支持的链
  static const supportedChains = ['ethereum', 'bsc', 'polygon'];
  
  /// 危险方法签名
  static const dangerousMethods = {
    '0x095ea7b3': 'ERC20 Approve - 授权第三方转账代币',
    '0xa22cb465': 'SetApprovalForAll - 授权第三方管理NFT',
    '0x23b872dd': 'TransferFrom - 转账代币',
    '0xb88d4fde': 'SafeTransferFrom - 安全转账NFT',
    '0x42842e0e': 'SafeTransferFrom - 安全转账NFT',
  };
  
  /// 危险合约地址白名单 (需要额外确认)
  static const highRiskAddresses = [
    // 待填充高风险地址
  ];
  
  // ==================== 事件 ====================
  
  final _requestController = StreamController<DAppRequest>.broadcast();
  Stream<DAppRequest> get requestStream => _requestController.stream;
  
  // ==================== 请求处理 ====================
  
  /// 处理 DApp 请求
  Future<DAppResponse> handleRequest(DAppRequest request) async {
    switch (request.method) {
      case 'eth_requestAccounts':
      case 'eth_accounts':
        return _handleAccountsRequest(request);
        
      case 'eth_chainId':
        return _handleChainIdRequest(request);
        
      case 'eth_sendTransaction':
        return _handleSendTransaction(request);
        
      case 'personal_sign':
      case 'eth_sign':
        return _handleSignRequest(request);
        
      case 'eth_signTypedData':
      case 'eth_signTypedData_v4':
        return _handleSignTypedData(request);
        
      default:
        return DAppResponse(
          id: request.id,
          success: false,
          error: 'Method not supported: ${request.method}',
        );
    }
  }
  
  DAppResponse _handleAccountsRequest(DAppRequest request) {
    // TODO: 返回当前钱包地址
    return DAppResponse(
      id: request.id,
      success: true,
      result: jsonEncode(['0x...']),
    );
  }
  
  DAppResponse _handleChainIdRequest(DAppRequest request) {
    // TODO: 返回当前链 ID
    return DAppResponse(
      id: request.id,
      success: true,
      result: jsonEncode('0x1'), // Ethereum Mainnet
    );
  }
  
  DAppResponse _handleSendTransaction(DAppRequest request) {
    // 解析交易参数
    final params = request.params as List?;
    if (params == null || params.isEmpty) {
      return DAppResponse(
        id: request.id,
        success: false,
        error: 'Invalid params',
      );
    }
    
    final txParams = params.first as Map<String, dynamic>?;
    if (txParams == null) {
      return DAppResponse(
        id: request.id,
        success: false,
        error: 'Invalid transaction params',
      );
    }
    
    // 分析交易风险
    final riskAnalysis = analyzeTransactionRisk(txParams);
    
    // 广播请求事件
    _requestController.add(DAppRequest(
      id: request.id,
      method: request.method,
      params: request.params,
      riskLevel: riskAnalysis.level,
      riskDescription: riskAnalysis.description,
    ));
    
    // 返回待确认状态
    return DAppResponse(
      id: request.id,
      success: true,
      result: jsonEncode('pending'),
      status: DAppResponseStatus.pending,
    );
  }
  
  DAppResponse _handleSignRequest(DAppRequest request) {
    // 签名请求也需要确认
    _requestController.add(DAppRequest(
      id: request.id,
      method: request.method,
      params: request.params,
      riskLevel: RiskLevel.medium,
      riskDescription: '签名请求',
    ));
    
    return DAppResponse(
      id: request.id,
      success: true,
      result: jsonEncode('pending'),
      status: DAppResponseStatus.pending,
    );
  }
  
  DAppResponse _handleSignTypedData(DAppRequest request) {
    _requestController.add(DAppRequest(
      id: request.id,
      method: request.method,
      params: request.params,
      riskLevel: RiskLevel.medium,
      riskDescription: '结构化数据签名',
    ));
    
    return DAppResponse(
      id: request.id,
      success: true,
      result: jsonEncode('pending'),
      status: DAppResponseStatus.pending,
    );
  }
  
  // ==================== 风险分析 ====================
  
  RiskAnalysis analyzeTransactionRisk(Map<String, dynamic> txParams) {
    final data = txParams['data'] as String? ?? '';
    final to = txParams['to'] as String? ?? '';
    final value = txParams['value'] as String? ?? '0x0';
    
    // 检查数据字段
    if (data.isNotEmpty && data.length > 10) {
      final methodSignature = data.substring(0, 10).toLowerCase();
      
      // 检查是否是高危方法
      if (dangerousMethods.containsKey(methodSignature)) {
        final description = dangerousMethods[methodSignature]!;
        
        // Approve 方法风险最高
        if (methodSignature == '0x095ea7b3') {
          return RiskAnalysis(
            level: RiskLevel.critical,
            description: '⚠️ 高危操作：$description\n\n此操作将授权第三方无限额度转走您的代币，请确认您信任此 DApp！',
            recommendations: [
              '仅在绝对必要时授权',
              '授权后建议使用 setAllowance 限制额度',
              '避免长期授权不使用的合约',
            ],
          );
        }
        
        // SetApprovalForAll
        if (methodSignature == '0xa22cb465') {
          return RiskAnalysis(
            level: RiskLevel.critical,
            description: '⚠️ 高危操作：$description\n\n此操作将授权第三方买卖您的NFT，请确认您信任此 DApp！',
            recommendations: [
              '确保此 DApp 来自可信来源',
              '考虑授权后立即撤销不使用的授权',
            ],
          );
        }
        
        return RiskAnalysis(
          level: RiskLevel.high,
          description: '⚠️ 注意：$description',
          recommendations: ['仔细确认接收地址和金额'],
        );
      }
    }
    
    // 检查目标地址风险
    if (highRiskAddresses.contains(to.toLowerCase())) {
      return RiskAnalysis(
        level: RiskLevel.high,
        description: '⚠️ 目标地址在风险名单中',
        recommendations: ['谨慎操作'],
      );
    }
    
    // 检查金额
    final weiValue = int.tryParse(value.replaceFirst('0x', ''), radix: 16) ?? 0;
    if (weiValue > 0) {
      return RiskAnalysis(
        level: RiskLevel.low,
        description: '转账 ${_formatWei(weiValue)} ETH',
        recommendations: ['确认转账金额和目标地址'],
      );
    }
    
    return RiskAnalysis(
      level: RiskLevel.low,
      description: '合约交互',
      recommendations: ['确认合约地址'],
    );
  }
  
  /// 解析合约数据
  Map<String, dynamic>? parseContractData(String data) {
    if (data.isEmpty || data.length < 10) return null;
    
    try {
      final methodSignature = data.substring(0, 10).toLowerCase();
      final methodName = dangerousMethods[methodSignature] ?? 'Unknown';
      
      return {
        'methodSignature': methodSignature,
        'methodName': methodName,
        'isDangerous': dangerousMethods.containsKey(methodSignature),
      };
    } catch (e) {
      return null;
    }
  }
  
  String _formatWei(int wei) {
    const ether = 1000000000000000000;
    final eth = wei / ether;
    return eth.toStringAsFixed(6);
  }
  
  // ==================== 清理 ====================
  
  void dispose() {
    _requestController.close();
  }
}

// ==================== 数据模型 ====================

enum RiskLevel {
  low,
  medium,
  high,
  critical,
}

class DAppRequest {
  final String id;
  final String method;
  final dynamic params;
  final RiskLevel riskLevel;
  final String? riskDescription;
  final List<String>? recommendations;
  
  DAppRequest({
    required this.id,
    required this.method,
    required this.params,
    required this.riskLevel,
    this.riskDescription,
    this.recommendations,
  });
}

class DAppResponse {
  final String id;
  final bool success;
  final String? result;
  final String? error;
  final DAppResponseStatus status;
  
  DAppResponse({
    required this.id,
    required this.success,
    this.result,
    this.error,
    this.status = DAppResponseStatus.completed,
  });
}

enum DAppResponseStatus {
  completed,
  pending,
  rejected,
}

class RiskAnalysis {
  final RiskLevel level;
  final String description;
  final List<String> recommendations;
  
  RiskAnalysis({
    required this.level,
    required this.description,
    this.recommendations = const [],
  });
}
