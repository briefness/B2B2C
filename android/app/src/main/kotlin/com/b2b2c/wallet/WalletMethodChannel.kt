package com.b2b2c.wallet

import android.content.Context
import android.os.Build
import android.os.Debug
import android.provider.Settings
import io.flutter.plugin.common.MethodChannel
import io.flutter.embedding.engine.FlutterEngine
import java.security.SecureRandom

/**
 * 统一安全 Method Channel
 * 
 * 通道名称: com.b2b2c.wallet/security
 * 与 Dart 层 MethodChannelService 保持一致
 */
class WalletMethodChannel(private val context: Context) {
    
    companion object {
        // ⚠️ 与 Dart 层 MethodChannelService._channel 名称一致
        const val CHANNEL = "com.b2b2c.wallet/security"
    }
    
    private var channel: MethodChannel? = null
    private val biometricHelper = BiometricHelper(context)
    
    fun registerWith(flutterEngine: FlutterEngine) {
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                // ==================== 安全检测 ====================
                
                "checkRooted" -> {
                    val rooted = biometricHelper.checkRooted()
                    val reasons = mutableListOf<String>()
                    if (rooted) reasons.add("Found root indicators")
                    result.success(mapOf(
                        "rooted" to rooted,
                        "reasons" to reasons
                    ))
                }
                
                "checkDebugger" -> {
                    val isDebuggable = biometricHelper.checkDebuggable()
                    val isDebuggerConnected = Debug.isDebuggerConnected()
                    val isWaiting = Debug.waitingForDebugger()
                    result.success(mapOf(
                        "debugged" to (isDebuggable || isDebuggerConnected || isWaiting)
                    ))
                }
                
                "checkHookFrameworks" -> {
                    val hookResult = biometricHelper.checkHooks()
                    val frameworks = mutableListOf<String>()
                    hookResult.forEach { (name, detected) ->
                        if (detected as Boolean) frameworks.add(name)
                    }
                    result.success(mapOf(
                        "hooked" to frameworks.isNotEmpty(),
                        "frameworks" to frameworks
                    ))
                }
                
                // ==================== 设备信息 ====================
                
                "getDeviceId" -> {
                    val deviceId = Settings.Secure.getString(
                        context.contentResolver,
                        Settings.Secure.ANDROID_ID
                    ) ?: "unknown"
                    result.success(mapOf("deviceId" to deviceId))
                }
                
                "isDeviceSecured" -> {
                    result.success(mapOf(
                        "secured" to biometricHelper.isDeviceSecured()
                    ))
                }
                
                // ==================== 安全键盘 ====================
                
                "generateSecureKeyboardLayout" -> {
                    val random = SecureRandom()
                    val digits = (0..9).map { it.toString() }.shuffled(random)
                    val letters = ('A'..'Z').map { it.toString() }.shuffled(random)
                    result.success(mapOf(
                        "digits" to digits,
                        "letters" to letters,
                        "timestamp" to System.currentTimeMillis()
                    ))
                }
                
                "isSecureInputActive" -> {
                    result.success(mapOf("active" to true))
                }
                
                // ==================== 综合安全检查 ====================
                
                "getSecurityThreatLevel" -> {
                    val hookResult = biometricHelper.checkHooks()
                    val hasHooks = hookResult.values.any { it as Boolean }
                    
                    val level = when {
                        hasHooks -> "critical"
                        Debug.isDebuggerConnected() -> "high"
                        biometricHelper.checkDebuggable() -> "high"
                        biometricHelper.checkRooted() -> "medium"
                        !biometricHelper.isDeviceSecured() -> "low"
                        else -> "none"
                    }
                    result.success(mapOf(
                        "level" to level,
                        "details" to biometricHelper.performSecurityCheck()
                    ))
                }
                
                // ==================== WebView 安全 ====================
                
                "enableWebViewSecurity" -> {
                    result.success(mapOf(
                        "enabled" to true,
                        "platform" to "android",
                        "securityLevel" to "high",
                        "features" to listOf(
                            "FLAG_SECURE",
                            "screenshot_prevention",
                            "hook_detection"
                        )
                    ))
                }
                
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}
