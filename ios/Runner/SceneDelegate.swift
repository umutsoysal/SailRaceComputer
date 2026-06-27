import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  // Buffered when the app is cold-launched by tapping a file.
  private static var pendingContent: String?
  private var fileChannel: FlutterMethodChannel?

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)

    if let vc = window?.rootViewController as? FlutterViewController {
      fileChannel = FlutterMethodChannel(
        name: "sail_race/file_open",
        binaryMessenger: vc.binaryMessenger
      )
      fileChannel?.setMethodCallHandler { call, result in
        if call.method == "getInitialFile" {
          result(SceneDelegate.pendingContent)
          SceneDelegate.pendingContent = nil
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }

    if let url = connectionOptions.urlContexts.first?.url {
      SceneDelegate.pendingContent = try? String(contentsOf: url, encoding: .utf8)
    }
  }

  override func scene(_ scene: UIScene, openURLContexts contexts: Set<UIOpenURLContext>) {
    guard let url = contexts.first?.url,
      let content = try? String(contentsOf: url, encoding: .utf8)
    else { return }
    fileChannel?.invokeMethod("openCourse", arguments: content)
  }
}
