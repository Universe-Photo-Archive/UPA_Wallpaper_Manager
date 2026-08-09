#ifndef WALLPAPER_PLUGIN_H_
#define WALLPAPER_PLUGIN_H_

#include <flutter/flutter_engine.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <shobjidl.h>
#include <string>
#include <vector>
#include <memory>

class WallpaperPlugin {
 public:
  static void RegisterWithRegistrar(flutter::FlutterEngine* engine);

  WallpaperPlugin();
  ~WallpaperPlugin();

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  bool SetWallpaper(const std::wstring& imagePath, int screenId, const std::string& fitMode);
  std::string GetWallpaper(int screenId);
  flutter::EncodableList GetScreens();

  bool SetLockscreen(const std::wstring& imagePath);
  bool RemoveLockscreen();
  bool IsAdmin();
  bool IsWindowsEditionSupported();
  bool IsLockscreenSupported();

  IDesktopWallpaper* desktop_wallpaper_ = nullptr;
  bool InitCOM();
  void CleanupCOM();
};

#endif  // WALLPAPER_PLUGIN_H_
