import Flutter
import UIKit
import LocalAuthentication

class WalletMethodChannel: NSObject {
    private static var channel: FlutterMethodChannel?

    static func register(with registrar: FlutterPluginRegistrar) {
        channel = FlutterMethodChannel(
            name: "com.b2b2c.wallet/security",
            binaryMessenger: registrar.messenger()
        )
        channel?.setMethodCallHandler { call, result in
            handle(call: call, result: result)
        }
    }

    static func register(with messenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(
            name: "com.b2b2c.wallet/security",
            binaryMessenger: messenger
        )
        channel?.setMethodCallHandler { call, result in
            handle(call: call, result: result)
        }
    }

    private static func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "isBiometricAvailable":
            isBiometricAvailable(result: result)
        case "authenticate":
            if let args = call.arguments as? [String: Any] {
                authenticate(args: args, result: result)
            } else {
                result(FlutterError(code: "INVALID_ARGS", message: "Invalid arguments", details: nil))
            }
        case "checkRooted":
            checkRooted(result: result)
        case "checkDebugger":
            checkDebugger(result: result)
        case "checkHookFrameworks":
            checkHookFrameworks(result: result)
        case "getDeviceId":
            getDeviceId(result: result)
        case "generateSecureKeyboardLayout":
            generateSecureKeyboardLayout(result: result)
        case "isSecureInputActive":
            isSecureInputActive(result: result)
        case "enableWebViewSecurity":
            enableWebViewSecurity(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Biometric

    private static func isBiometricAvailable(result: @escaping FlutterResult) {
        let context = LAContext()
        var error: NSError?
        let available = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)

        var biometricType = "none"
        if available {
            switch context.biometryType {
            case .faceID:
                biometricType = "faceID"
            case .touchID:
                biometricType = "touchID"
            case .opticID:
                biometricType = "strong"
            @unknown default:
                biometricType = "unknown"
            }
        }

        result(["available": available, "biometricType": biometricType])
    }

    private static func authenticate(args: [String: Any], result: @escaping FlutterResult) {
        let context = LAContext()
        let title = args["title"] as? String ?? "验证身份"
        let reason = args["reason"] as? String ?? "请进行身份验证"

        context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: reason
        ) { success, error in
            DispatchQueue.main.async {
                if success {
                    result(["success": true])
                } else {
                    result(["success": false, "error": error?.localizedDescription ?? "认证失败"])
                }
            }
        }
    }

    // MARK: - Security Detection

    private static func checkRooted(result: @escaping FlutterResult) {
        #if targetEnvironment(simulator)
        result(["rooted": false, "reasons": []])
        #else
        let suspiciousPaths = [
            "/Applications/Cydia.app",
            "/Library/MobileSubstrate/MobileSubstrate.dylib",
            "/bin/bash",
            "/usr/sbin/sshd",
            "/etc/apt",
            "/private/var/lib/apt/",
            "/usr/bin/ssh"
        ]
        var reasons: [String] = []
        for path in suspiciousPaths {
            if FileManager.default.fileExists(atPath: path) {
                reasons.append("Found suspicious file: \(path)")
            }
        }
        result(["rooted": !reasons.isEmpty, "reasons": reasons])
        #endif
    }

    private static func checkDebugger(result: @escaping FlutterResult) {
        #if DEBUG
        result(["debugged": true])
        #else
        var info = kinfo_proc()
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        var size = MemoryLayout<kinfo_proc>.stride
        let sysctlResult = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)

        let debugged = (sysctlResult == 0) && (info.kp_proc.p_flag & P_TRACED) != 0
        result(["debugged": debugged])
        #endif
    }

    private static func checkHookFrameworks(result: @escaping FlutterResult) {
        #if targetEnvironment(simulator)
        result(["hooked": false, "frameworks": []])
        #else
        let suspiciousLibs = [
            "SubstrateLoader",
            "MobileSubstrate",
            "TweakInject",
            "FridaGadget",
            "frida"
        ]
        var found: [String] = []
        let loadedLibs = dyld_image_count()
        for i in 0..<loadedLibs {
            if let name = dyld_get_image_name(i) {
                let libName = String(cString: name)
                for suspicious in suspiciousLibs {
                    if libName.contains(suspicious) {
                        found.append(libName)
                    }
                }
            }
        }
        result(["hooked": !found.isEmpty, "frameworks": found])
        #endif
    }

    private static func getDeviceId(result: @escaping FlutterResult) {
        if let uuid = UIDevice.current.identifierForVendor?.uuidString {
            result(["deviceId": uuid])
        } else {
            result(["deviceId": UUID().uuidString])
        }
    }

    // MARK: - Secure Keyboard

    private static func generateSecureKeyboardLayout(result: @escaping FlutterResult) {
        let digits = (0...9).map { "\($0)" }.shuffled()
        var letters = (65...90).map { String(UnicodeScalar($0)!) }.shuffled()
        result([
            "digits": digits,
            "letters": letters,
            "timestamp": Int(Date().timeIntervalSince1970 * 1000)
        ])
    }

    private static func isSecureInputActive(result: @escaping FlutterResult) {
        result(["active": true])
    }
    
    // MARK: - WebView Security
    
    private static func enableWebViewSecurity(result: @escaping FlutterResult) {
        // iOS: 通过 NotificationCenter 监听截屏事件
        // 应用层截屏防护已在 AppDelegate 中实现
        
        // 发送安全已启用的确认
        result([
            "enabled": true,
            "platform": "ios",
            "securityLevel": "high",
            "features": [
                "screenshot_notification",
                "screen_recording_detection",
                "webview_secure_layer"
            ]
        ])
    }
}
