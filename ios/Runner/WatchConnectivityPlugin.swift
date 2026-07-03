import Flutter
import Foundation
import WatchConnectivity

final class WatchConnectivityPlugin: NSObject, FlutterPlugin, WCSessionDelegate {
  private let session: WCSession?

  override init() {
    if WCSession.isSupported() {
      let sharedSession = WCSession.default
      session = sharedSession
      super.init()
      sharedSession.delegate = self
      sharedSession.activate()
    } else {
      session = nil
      super.init()
    }
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "sail_race/watch",
      binaryMessenger: registrar.messenger()
    )
    let instance = WatchConnectivityPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "sendMetrics" else {
      result(FlutterMethodNotImplemented)
      return
    }

    guard let payload = call.arguments as? [String: Any] else {
      result(
        FlutterError(
          code: "invalid-args",
          message: "Expected a metrics payload dictionary.",
          details: nil
        )
      )
      return
    }

    send(payload: payload)
    result(nil)
  }

  private func send(payload: [String: Any]) {
    guard let session else { return }

    do {
      try session.updateApplicationContext(payload)
    } catch {
      // Ignore transient sync failures; the phone app should keep running.
    }

    guard session.isReachable else { return }
    session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
  }

  func session(
    _ session: WCSession,
    activationDidCompleteWith activationState: WCSessionActivationState,
    error: Error?
  ) {
    // No-op. The app treats watch connectivity as best-effort only.
  }

  func sessionDidBecomeInactive(_ session: WCSession) {}

  func sessionDidDeactivate(_ session: WCSession) {
    session.activate()
  }
}
