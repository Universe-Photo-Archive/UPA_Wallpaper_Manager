import Flutter
import UIKit
import Photos

@main
@objc class AppDelegate: FlutterAppDelegate {
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let controller = window?.rootViewController as! FlutterViewController

        // Wallpaper channel (limited on iOS)
        let wallpaperChannel = FlutterMethodChannel(
            name: "eu.universe_photo_archive/wallpaper",
            binaryMessenger: controller.binaryMessenger
        )

        wallpaperChannel.setMethodCallHandler { (call, result) in
            switch call.method {
            case "setWallpaper":
                // iOS doesn't support programmatic wallpaper changes
                result(false)

            case "getScreens":
                let bounds = UIScreen.main.bounds
                let screen: [String: Any] = [
                    "id": 0,
                    "name": "iPhone Screen",
                    "width": Int(bounds.width * UIScreen.main.scale),
                    "height": Int(bounds.height * UIScreen.main.scale),
                    "left": 0,
                    "top": 0,
                    "isPrimary": true,
                ]
                result([screen])

            case "saveToPhotos":
                guard let args = call.arguments as? [String: Any],
                      let imagePath = args["imagePath"] as? String else {
                    result(false)
                    return
                }
                self.saveToPhotos(imagePath: imagePath, result: result)

            default:
                result(FlutterMethodNotImplemented)
            }
        }

        // Lockscreen channel (not supported on iOS)
        let lockscreenChannel = FlutterMethodChannel(
            name: "eu.universe_photo_archive/lockscreen",
            binaryMessenger: controller.binaryMessenger
        )

        lockscreenChannel.setMethodCallHandler { (call, result) in
            switch call.method {
            case "isSupported":
                result(false)
            case "isAdmin":
                result(false)
            default:
                result(FlutterMethodNotImplemented)
            }
        }

        GeneratedPluginRegistrant.register(with: self)
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    /// Save an image to the user's Photos library
    private func saveToPhotos(imagePath: String, result: @escaping FlutterResult) {
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized || status == .limited else {
                result(false)
                return
            }

            guard let image = UIImage(contentsOfFile: imagePath) else {
                result(false)
                return
            }

            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }) { success, error in
                DispatchQueue.main.async {
                    result(success)
                }
            }
        }
    }
}
