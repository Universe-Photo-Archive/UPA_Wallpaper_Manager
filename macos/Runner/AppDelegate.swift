import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
    override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false // Keep running in background (system tray)
    }

    override func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = mainFlutterWindow?.contentViewController as! FlutterViewController

        // Wallpaper channel
        let wallpaperChannel = FlutterMethodChannel(
            name: "eu.universe_photo_archive/wallpaper",
            binaryMessenger: controller.engine.binaryMessenger
        )

        wallpaperChannel.setMethodCallHandler { (call, result) in
            switch call.method {
            case "setWallpaper":
                guard let args = call.arguments as? [String: Any],
                      let imagePath = args["imagePath"] as? String else {
                    result(false)
                    return
                }
                let screenId = args["screenId"] as? Int
                let success = self.setWallpaper(imagePath: imagePath, screenId: screenId)
                result(success)

            case "getScreens":
                result(self.getScreens())

            default:
                result(FlutterMethodNotImplemented)
            }
        }

        // Lockscreen channel
        let lockscreenChannel = FlutterMethodChannel(
            name: "eu.universe_photo_archive/lockscreen",
            binaryMessenger: controller.engine.binaryMessenger
        )

        lockscreenChannel.setMethodCallHandler { (call, result) in
            switch call.method {
            case "isSupported":
                result(false) // macOS lockscreen requires MDM profile
            case "isAdmin":
                result(NSUserName() == "root")
            case "setLockscreen", "removeLockscreen":
                result(false) // Not supported on macOS without MDM
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    private func setWallpaper(imagePath: String, screenId: Int?) -> Bool {
        let url = URL(fileURLWithPath: imagePath)
        guard FileManager.default.fileExists(atPath: imagePath) else { return false }

        do {
            let workspace = NSWorkspace.shared
            let screens = NSScreen.screens

            if let screenId = screenId, screenId < screens.count {
                try workspace.setDesktopImageURL(url, for: screens[screenId], options: [:])
            } else {
                // Set for all screens
                for screen in screens {
                    try workspace.setDesktopImageURL(url, for: screen, options: [:])
                }
            }
            return true
        } catch {
            print("Failed to set wallpaper: \(error)")
            return false
        }
    }

    private func getScreens() -> [[String: Any]] {
        return NSScreen.screens.enumerated().map { (index, screen) in
            let frame = screen.frame
            return [
                "id": index,
                "name": screen.localizedName,
                "width": Int(frame.width),
                "height": Int(frame.height),
                "left": Int(frame.origin.x),
                "top": Int(frame.origin.y),
                "isPrimary": index == 0,
            ]
        }
    }
}
