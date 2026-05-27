import 'dart:async';
import 'dart:convert';

/// DApp 浏览器沙箱服务
/// 
/// 负责：
/// 1. Web3 Provider 注入 (EIP-1193)
/// 2. 交易请求拦截与签名
/// 3. 恶意合约检测与警告
/// 4. 链交互隔离

class DAppSandboxService {
  // ==================== 单例 ====================
  
  static final DAppSandboxService _instance = DAppSandboxService._internal();
  factory DAppSandboxService() => _instance;
  DAppSandboxService._internal();
  
  // ==================== 事件流 ====================
  
  final _requestController = StreamController<DAppRequest>.broadcast();
  Stream<DAppRequest> get requestStream => _requestController.stream;
  
  // ==================== 危险合约方法签名 ====================
  
  /// 高危方法签名 (需要红色警告)
  static const highRiskMethods = {
    // ERC20 Approve (授权第三方转账)
    '0x095ea7b3': DAppMethodInfo(
      name: 'approve',
      description: '授权代币',
      risk: RiskLevel.high,
      warning: '此操作将授权第三方在未来可以转走您的代币，请确认您了解此操作的风险！',
    ),
    
    // ERC721 SetApprovalForAll (授权所有 NFT)
    '0xa22cb465': DAppMethodInfo(
      name: 'setApprovalForAll',
      description: '授权所有 NFT',
      risk: RiskLevel.critical,
      warning: '此操作将授权第三方可以转走您所有的 NFT，请务必谨慎！',
    ),
    
    // ERC1155 SetApprovalForAll
    '0xf242432a': DAppMethodInfo(
      name: 'setApprovalForAll',
      description: '授权所有 ERC1155 代币',
      risk: RiskLevel.critical,
      warning: '此操作将授权第三方可以转走您所有的 ERC1155 代币，请务必谨慎！',
    ),
    
    // increaseAllowance (增加授权额度)
    '0xa1657219': DAppMethodInfo(
      name: 'increaseAllowance',
      description: '增加授权额度',
      risk: RiskLevel.high,
      warning: '此操作将增加第三方可以转走您代币的额度！',
    ),
    
    // permit (无交易签名)
    '0xd505accf': DAppMethodInfo(
      name: 'permit',
      description: '离线授权签名',
      risk: RiskLevel.high,
      warning: '此操作需要您签署一个离线授权，请确认签名内容！',
    ),
  };
  
  /// 中危方法签名
  static const mediumRiskMethods = {
    // TransferFrom (转账)
    '0x23b872dd': DAppMethodInfo(
      name: 'transferFrom',
      description: '转账代币',
      risk: RiskLevel.medium,
      warning: '此操作将转账您的代币，请确认收款地址正确。',
    ),
    
    // safeTransferFrom
    '0xb88d4fde': DAppMethodInfo(
      name: 'safeTransferFrom',
      description: '安全转账 NFT',
      risk: RiskLevel.medium,
      warning: '此操作将转账您的 NFT，请确认收款地址正确。',
    ),
    
    // transfer
    '0xa9059cbb': DAppMethodInfo(
      name: 'transfer',
      description: '转账 ERC20',
      risk: RiskLevel.medium,
      warning: '此操作将转账您的代币，请确认收款地址正确。',
    ),
  };
  
  // ==================== Web3 Provider JS 代码 ====================
  
  /// 注入的 Web3 Provider JavaScript 代码
  static String get providerInjectionScript {
    return '''
(function() {
  // 防止重复注入
  if (window.ethereum) {
    return;
  }
  
  const originalProvider = window.ethereum || {};
  
  // EIP-1193 Provider 接口
  const provider = {
    isMetaMask: true,
    isB2B2C: true,
    chainId: '0x1', // Ethereum Mainnet
    networkVersion: '1',
    
    // 请求方法
    async request(args) {
      const method = args.method || args;
      const params = args.params || [];
      
      // 通过 Flutter 通道发送请求
      return new Promise((resolve, reject) => {
        window.FlutterChannel.postMessage(JSON.stringify({
          type: 'dapp_request',
          method: method,
          params: params
        }));
        
        // 监听响应
        window._b2b2c_response_callback = (event) => {
          const data = JSON.parse(event.data);
          if (data.success) {
            resolve(data.result);
          } else {
            reject(new Error(data.error));
          }
        };
      });
    },
    
    // 监听链变化
    on(event, callback) {
      window.addEventListener('b2b2c_' + event, (e) => callback(e.detail));
    },
    
    removeListener(event, callback) {
      window.removeEventListener('b2b2c_' + event, callback);
    },
    
    // 断开连接
    disconnect() {
      window.FlutterChannel.postMessage(JSON.stringify({
        type: 'dapp_disconnect'
      }));
    }
  };
  
  // eth_accounts
  function getAccounts() {
    return window.FlutterChannel.request({ method: 'eth_accounts' });
  }
  
  // eth_chainId
  function getChainId() {
    return Promise.resolve(provider.chainId);
  }
  
  // eth_requestAccounts
  async function requestAccounts() {
    const accounts = await provider.request({ method: 'eth_requestAccounts' });
    return accounts;
  }
  
  // eth_sendTransaction
  async function sendTransaction(txParams) {
    return await provider.request({
      method: 'eth_sendTransaction',
      params: [txParams]
    });
  }
  
  // eth_sign
  async function sign(message) {
    return await provider.request({
      method: 'eth_sign',
      params: [message]
    });
  }
  
  // personal_sign
  async function personalSign(message, account) {
    return await provider.request({
      method: 'personal_sign',
      params: [message, account]
    });
  }
  
  // eth_signTypedData_v4
  async function signTypedData(typedData, account) {
    return await provider.request({
      method: 'eth_signTypedData_v4',
      params: [account, typedData]
    });
  }
  
  // 添加到 window
  Object.defineProperty(provider, 'selectedAddress', {
    get: () => window._b2b2c_selected_address,
    set: (value) => { window._b2b2c_selected_address = value; }
  });
  
  window.ethereum = provider;
  window.web3 = { currentProvider: provider };
  
  console.log('B2B2C Wallet Web3 Provider injected');
})();
''';
  }
  
  // ==================== 请求处理 ====================
  
  /// 解析 DApp 请求
  DAppRequest parseRequest(Map<String, dynamic> data) {
    final type = data['type'] as String?;
    final method = data['method'] as String?;
    final params = data['params'] as List?;
    
    if (type == 'dapp_request') {
      return _parseWeb3Request(method ?? '', params ?? []);
    }
    
    return DAppRequest(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      method: method ?? '',
      params: params ?? [],
      type: DAppRequestType.unknown,
      description: '未知请求',
    );
  }
  
  DAppRequest _parseWeb3Request(String method, List params) {
    switch (method) {
      case 'eth_requestAccounts':
      case 'eth_accounts':
        return DAppRequest(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          method: method,
          params: params,
          type: DAppRequestType.connect,
          description: '连接钱包',
        );
        
      case 'eth_chainId':
        return DAppRequest(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          method: method,
          params: params,
          type: DAppRequestType.chainId,
          description: '获取链 ID',
        );
        
      case 'eth_sendTransaction':
        return _parseTransactionRequest(method, params);
        
      case 'personal_sign':
        return DAppRequest(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          method: method,
          params: params,
          type: DAppRequestType.sign,
          description: '签名消息',
          decodedParams: _decodeSignParams(params),
        );
        
      case 'eth_sign':
        return DAppRequest(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          method: method,
          params: params,
          type: DAppRequestType.sign,
          description: '签名数据',
        );
        
      case 'eth_signTypedData_v4':
        return DAppRequest(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          method: method,
          params: params,
          type: DAppRequestType.sign,
          description: '签名结构化数据',
        );
        
      default:
        return DAppRequest(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          method: method,
          params: params,
          type: DAppRequestType.unknown,
          description: '未知请求',
        );
    }
  }
  
  DAppRequest _parseTransactionRequest(String method, List params) {
    if (params.isEmpty) {
      return DAppRequest(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        method: method,
        params: params,
        type: DAppRequestType.transaction,
        description: '发送交易',
      );
    }
    
    final txParams = params[0] as Map<String, dynamic>?;
    if (txParams == null) {
      return DAppRequest(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        method: method,
        params: params,
        type: DAppRequestType.transaction,
        description: '发送交易',
      );
    }
    
    // 解析交易数据
    final data = txParams['data'] as String?;
    final to = txParams['to'] as String?;
    final value = txParams['value'] as String?;
    
    // 解析方法签名
    DAppMethodInfo? methodInfo;
    RiskLevel riskLevel = RiskLevel.low;
    String? warning;
    
    if (data != null && data.length >= 10) {
      final methodSignature = data.substring(0, 10);
      methodInfo = _detectMethod(methodSignature);
      if (methodInfo != null) {
        riskLevel = methodInfo.risk;
        warning = methodInfo.warning;
      }
    }
    
    return DAppRequest(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      method: method,
      params: params,
      type: DAppRequestType.transaction,
      description: methodInfo?.description ?? '发送交易',
      decodedParams: txParams,
      riskLevel: riskLevel,
      warning: warning,
      to: to,
      value: value,
    );
  }
  
  /// 检测危险方法
  DAppMethodInfo? _detectMethod(String signature) {
    // 首先检查高危方法
    if (highRiskMethods.containsKey(signature)) {
      return highRiskMethods[signature];
    }
    
    // 然后检查中危方法
    if (mediumRiskMethods.containsKey(signature)) {
      return mediumRiskMethods[signature];
    }
    
    return null;
  }
  
  /// 解码签名参数
  Map<String, dynamic>? _decodeSignParams(List params) {
    if (params.isEmpty) return null;
    
    final firstParam = params[0] as String;
    
    // 尝试解析为 JSON (TypedData)
    try {
      return jsonDecode(firstParam) as Map<String, dynamic>;
    } catch (_) {
      // 不是 JSON，可能是普通消息
      return {'message': firstParam};
    }
  }
  
  // ==================== 请求响应 ====================
  
  /// 发送请求到 UI
  Future<DAppResponse> sendRequestToUI(DAppRequest request) async {
    final completer = Completer<DAppResponse>();
    
    // 添加到流
    _requestController.add(request);
    
    // 设置超时
    Timer(const Duration(seconds: 120), () {
      if (!completer.isCompleted) {
        completer.complete(DAppResponse(
          id: request.id,
          success: false,
          error: '请求超时',
        ));
      }
    });
    
    return completer.future;
  }
  
  /// 处理 UI 响应
  void handleResponse(String requestId, DAppResponse response) {
    // TODO: 完成对应的 Promise
  }
  
  // ==================== 地址白名单 ====================
  
  bool _isWhiteListed(String address) {
    // TODO: 检查地址白名单
    return false;
  }
  
  /// 验证合约地址
  Future<bool> verifyContract(String address) async {
    // TODO: 调用云端验证合约安全性
    return true;
  }
  
  // ==================== 清理 ====================
  
  void dispose() {
    _requestController.close();
  }
}

// ==================== 数据模型 ====================

enum DAppRequestType {
  connect,
  chainId,
  transaction,
  sign,
  unknown,
}

enum RiskLevel {
  low,
  medium,
  high,
  critical,
}

class DAppMethodInfo {
  final String name;
  final String description;
  final RiskLevel risk;
  final String? warning;
  
  const DAppMethodInfo({
    required this.name,
    required this.description,
    required this.risk,
    this.warning,
  });
}

class DAppRequest {
  final String id;
  final String method;
  final List params;
  final DAppRequestType type;
  final String description;
  final Map<String, dynamic>? decodedParams;
  final RiskLevel riskLevel;
  final String? warning;
  final String? to;
  final String? value;
  
  DAppRequest({
    required this.id,
    required this.method,
    required this.params,
    required this.type,
    required this.description,
    this.decodedParams,
    this.riskLevel = RiskLevel.low,
    this.warning,
    this.to,
    this.value,
  });
  
  bool get isHighRisk => riskLevel == RiskLevel.high || riskLevel == RiskLevel.critical;
}

class DAppResponse {
  final String id;
  final bool success;
  final String? result;
  final String? error;
  
  DAppResponse({
    required this.id,
    required this.success,
    this.result,
    this.error,
  });
  
  factory DAppResponse.success(String id, String result) {
    return DAppResponse(
      id: id,
      success: true,
      result: result,
    );
  }
  
  factory DAppResponse.error(String id, String error) {
    return DAppResponse(
      id: id,
      success: false,
      error: error,
    );
  }
}
