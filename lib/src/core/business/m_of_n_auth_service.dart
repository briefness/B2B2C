import 'dart:async';
import 'dart:convert';
import '../ffi/ffi.dart';

/// M-of-N 多签审批服务
/// 
/// 用于 B 端高敏感操作的 M-of-N 多人审批机制
/// 例如：B 端管理员修改重要配置、发布活动等

class MofNAuthService {
  static final MofNAuthService _instance = MofNAuthService._internal();
  factory MofNAuthService() => _instance;
  MofNAuthService._internal();

  final _pendingRequests = <String, MofNRequest>{};
  final _approvedSignatures = <String, List<ApprovalSignature>>{};
  
  /// 创建多签请求
  /// 
  /// [threshold] - 需要多少个审批人同意 (M)
  /// [approvers] - 审批人列表 (N)
  /// [operationType] - 操作类型
  /// [payload] - 操作内容
  /// [ttl] - 请求有效期 (默认 24 小时)
  Future<MofNRequest> createRequest({
    required int threshold,
    required List<String> approvers,
    required OperationType operationType,
    required Map<String, dynamic> payload,
    Duration ttl = const Duration(hours: 24),
  }) async {
    final requestId = _generateRequestId();
    final request = MofNRequest(
      id: requestId,
      threshold: threshold,
      approvers: approvers,
      operationType: operationType,
      payload: payload,
      status: RequestStatus.pending,
      createdAt: DateTime.now(),
      expiresAt: DateTime.now().add(ttl),
      creatorId: await _getCurrentUserId(),
    );
    
    _pendingRequests[requestId] = request;
    _approvedSignatures[requestId] = [];
    
    // 发送到服务器 (TODO: 实际 API 调用)
    await _syncRequestToServer(request);
    
    return request;
  }
  
  /// 提交审批
  /// 
  /// [requestId] - 请求 ID
  /// [approverId] - 审批人 ID
  /// [signature] - 审批签名 (使用审批人私钥签名)
  Future<ApprovalResult> submitApproval({
    required String requestId,
    required String approverId,
    required String signature,
    String? comment,
  }) async {
    final request = _pendingRequests[requestId];
    if (request == null) {
      return ApprovalResult(
        success: false,
        error: 'Request not found',
      );
    }
    
    // 检查过期
    if (DateTime.now().isAfter(request.expiresAt)) {
      request.status = RequestStatus.expired;
      return ApprovalResult(
        success: false,
        error: 'Request has expired',
      );
    }
    
    // 检查是否已审批
    final signatures = _approvedSignatures[requestId] ?? [];
    if (signatures.any((s) => s.approverId == approverId)) {
      return ApprovalResult(
        success: false,
        error: 'Already approved',
      );
    }
    
    // 验证签名
    final isValid = await _verifyApprovalSignature(
      requestId: requestId,
      approverId: approverId,
      signature: signature,
    );
    
    if (!isValid) {
      return ApprovalResult(
        success: false,
        error: 'Invalid signature',
      );
    }
    
    // 添加签名
    signatures.add(ApprovalSignature(
      approverId: approverId,
      signature: signature,
      timestamp: DateTime.now(),
      comment: comment,
    ));
    
    _approvedSignatures[requestId] = signatures;
    
    // 检查是否达到阈值
    if (signatures.length >= request.threshold) {
      request.status = RequestStatus.approved;
      
      // 执行操作
      await _executeApprovedOperation(request, signatures);
      
      return ApprovalResult(
        success: true,
        approved: true,
        thresholdReached: true,
        signatureCount: signatures.length,
      );
    }
    
    return ApprovalResult(
      success: true,
      approved: false,
      thresholdReached: false,
      signatureCount: signatures.length,
      requiredSignatures: request.threshold - signatures.length,
    );
  }
  
  /// 拒绝请求
  Future<bool> rejectRequest({
    required String requestId,
    required String approverId,
    String? reason,
  }) async {
    final request = _pendingRequests[requestId];
    if (request == null) return false;
    
    request.status = RequestStatus.rejected;
    request.rejectReason = reason;
    request.rejectedBy = approverId;
    request.rejectedAt = DateTime.now();
    
    return true;
  }
  
  /// 获取请求状态
  MofNRequest? getRequest(String requestId) {
    return _pendingRequests[requestId];
  }
  
  /// 获取待审批请求列表
  List<MofNRequest> getPendingRequests(String approverId) {
    return _pendingRequests.values
        .where((r) => 
            r.status == RequestStatus.pending &&
            r.approvers.contains(approverId) &&
            !(_approvedSignatures[r.id]?.any((s) => s.approverId == approverId) ?? false))
        .toList();
  }
  
  /// 签名请求内容
  String signRequest(String requestId, String privateKeyHex) {
    final request = _pendingRequests[requestId];
    if (request == null) return '';
    
    final signData = _buildSignData(request);
    return WalletFFIService().hmacSha256(privateKeyHex, signData);
  }
  
  Future<bool> _verifyApprovalSignature({
    required String requestId,
    required String approverId,
    required String signature,
  }) async {
    final request = _pendingRequests[requestId];
    if (request == null) return false;
    
    // TODO: 从服务器验证公钥
    final signData = _buildSignData(request);
    final expectedSignature = WalletFFIService().hmacSha256(approverId, signData);
    
    return signature == expectedSignature;
  }
  
  String _buildSignData(MofNRequest request) {
    final payloadStr = jsonEncode(request.payload);
    return '${request.id}:${request.threshold}:${request.operationType.name}:$payloadStr:${request.createdAt.millisecondsSinceEpoch}';
  }
  
  Future<void> _syncRequestToServer(MofNRequest request) async {
    // TODO: 实现服务器同步
  }
  
  Future<void> _executeApprovedOperation(MofNRequest request, List<ApprovalSignature> signatures) async {
    // TODO: 执行已批准的操作
    // 例如：发布配置、调整活动等
  }
  
  Future<String> _getCurrentUserId() async {
    // TODO: 从认证服务获取当前用户 ID
    return 'current_user';
  }
  
  String _generateRequestId() {
    return 'mofn_${DateTime.now().millisecondsSinceEpoch}_${SecureCrypto.generateRandomBytesHex(8)}';
  }
}

/// 多签请求
class MofNRequest {
  final String id;
  final int threshold;
  final List<String> approvers;
  final OperationType operationType;
  final Map<String, dynamic> payload;
  RequestStatus status;
  final DateTime createdAt;
  final DateTime expiresAt;
  final String creatorId;
  String? rejectReason;
  String? rejectedBy;
  DateTime? rejectedAt;
  
  MofNRequest({
    required this.id,
    required this.threshold,
    required this.approvers,
    required this.operationType,
    required this.payload,
    required this.status,
    required this.createdAt,
    required this.expiresAt,
    required this.creatorId,
    this.rejectReason,
    this.rejectedBy,
    this.rejectedAt,
  });
  
  int get currentSignatures => 0; // TODO: 从服务获取
  bool get isExpired => DateTime.now().isAfter(expiresAt);
  bool get isPending => status == RequestStatus.pending;
}

/// 审批签名
class ApprovalSignature {
  final String approverId;
  final String signature;
  final DateTime timestamp;
  final String? comment;
  
  ApprovalSignature({
    required this.approverId,
    required this.signature,
    required this.timestamp,
    this.comment,
  });
}

/// 审批结果
class ApprovalResult {
  final bool success;
  final bool approved;
  final bool thresholdReached;
  final int signatureCount;
  final int? requiredSignatures;
  final String? error;
  
  ApprovalResult({
    required this.success,
    this.approved = false,
    this.thresholdReached = false,
    this.signatureCount = 0,
    this.requiredSignatures,
    this.error,
  });
}

/// 操作类型
enum OperationType {
  configUpdate,
  activityPublish,
  userManagement,
  withdrawalApproval,
  emergencyFreeze,
  systemSetting,
}

/// 请求状态
enum RequestStatus {
  pending,
  approved,
  rejected,
  expired,
  cancelled,
}
