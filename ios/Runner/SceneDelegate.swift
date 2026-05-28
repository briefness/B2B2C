import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {

    override func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        super.scene(scene, willConnectTo: session, options: connectionOptions)

        // 注册 Method Channel (Scene 生命周期下 window 在此时可用)
        if let windowScene = scene as? UIWindowScene,
           let window = windowScene.windows.first,
           let controller = window.rootViewController as? FlutterViewController {
            WalletMethodChannel.register(with: controller.binaryMessenger)
        }
    }
}
