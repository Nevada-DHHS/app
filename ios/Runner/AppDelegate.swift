import UIKit
import Flutter
import GoogleMaps
import location

public func registerLocationCallback(with registry: FlutterPluginRegistry) {
    GeneratedPluginRegistrant.register(with: registry)
}

let f: @convention(c) (FlutterPluginRegistry) -> Void = registerLocationCallback

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    LocationPlugin.setPluginRegistrantCallback(f)
    GMSServices.provideAPIKey("AIzaSyAPrVanVPxAlZOGgRecnNUew_zAneh8guw")
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
