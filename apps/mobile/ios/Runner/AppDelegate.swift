import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(
      name: "work.yuiop.ahadi/share",
      binaryMessenger: engineBridge.pluginRegistry.registrar(forPlugin: "AhadiShare")!.messenger()
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "shareImage" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard
        let args = call.arguments as? [String: Any],
        let path = args["path"] as? String
      else {
        result(FlutterError(code: "INVALID_INPUT", message: "Missing image path", details: nil))
        return
      }
      let url = URL(fileURLWithPath: path)
      let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
      let controller = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap { $0.windows }
        .first { $0.isKeyWindow }?
        .rootViewController
      controller?.present(activity, animated: true)
      result(nil)
    }
  }
}
