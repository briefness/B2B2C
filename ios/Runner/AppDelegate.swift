import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
    
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        
        // 注册 Method Channel
        if let controller = window?.rootViewController as? FlutterViewController {
            WalletMethodChannel.register(with: controller.binaryMessenger)
        }
        
        // 安全配置
        setupSecurity()
        
        GeneratedPluginRegistrant.register(with: self)
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
    
    private func setupSecurity() {
        // 防止截屏 (敏感页面可在 ViewController 中单独设置)
        
        // 监听截屏通知 (iOS 11+)
        if #available(iOS 11.0, *) {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleScreenCapture),
                name: UIScreen.capturedDidChangeNotification,
                object: nil
            )
            
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleScreenshot),
                name: UIApplication.userDidTakeScreenshotNotification,
                object: nil
            )
        }
    }
    
    @objc private func handleScreenCapture() {
        if UIScreen.main.isCaptured {
            NotificationCenter.default.post(name: NSNotification.Name("ScreenCaptureChanged"), object: true)
        } else {
            NotificationCenter.default.post(name: NSNotification.Name("ScreenCaptureChanged"), object: false)
        }
    }
    
    @objc private func handleScreenshot() {
        NotificationCenter.default.post(name: NSNotification.Name("ScreenshotTaken"), object: nil)
    }
    
    // 防止应用被暂停时内容预览
    override func applicationWillResignActive(_ application: UIApplication) {
        if let window = self.window {
            let blurEffect = UIBlurEffect(style: .light)
            let blurView = UIVisualEffectView(effect: blurEffect)
            blurView.frame = window.bounds
            blurView.tag = 999
            window.addSubview(blurView)
        }
    }
    
    override func applicationDidBecomeActive(_ application: UIApplication) {
        if let window = self.window {
            window.viewWithTag(999)?.removeFromSuperview()
        }
    }
    
    override func applicationWillTerminate(_ application: UIApplication) {
        // 安全清理
    }
}
