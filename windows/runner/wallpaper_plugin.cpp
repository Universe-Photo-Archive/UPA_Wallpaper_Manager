#include "wallpaper_plugin.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <shobjidl.h>
#include <shlobj.h>
#include <KnownFolders.h>
#include <string>
#include <memory>

using flutter::EncodableMap;
using flutter::EncodableValue;
using flutter::EncodableList;

static std::wstring Utf8ToWide(const std::string& utf8) {
  if (utf8.empty()) return L"";
  int size = MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), -1, nullptr, 0);
  std::wstring wide(size - 1, 0);
  MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), -1, &wide[0], size);
  return wide;
}

static std::string WideToUtf8(const std::wstring& wide) {
  if (wide.empty()) return "";
  int size = WideCharToMultiByte(CP_UTF8, 0, wide.c_str(), -1, nullptr, 0, nullptr, nullptr);
  std::string utf8(size - 1, 0);
  WideCharToMultiByte(CP_UTF8, 0, wide.c_str(), -1, &utf8[0], size, nullptr, nullptr);
  return utf8;
}

void WallpaperPlugin::RegisterWithRegistrar(flutter::FlutterEngine* engine) {
  auto plugin = std::make_shared<WallpaperPlugin>();

  auto wallpaper_channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      engine->messenger(), "eu.universe_photo_archive/wallpaper",
      &flutter::StandardMethodCodec::GetInstance());

  auto lockscreen_channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      engine->messenger(), "eu.universe_photo_archive/lockscreen",
      &flutter::StandardMethodCodec::GetInstance());

  wallpaper_channel->SetMethodCallHandler(
      [plugin](const auto& call, auto result) {
        plugin->HandleMethodCall(call, std::move(result));
      });

  lockscreen_channel->SetMethodCallHandler(
      [plugin](const auto& call, auto result) {
        plugin->HandleMethodCall(call, std::move(result));
      });
}

WallpaperPlugin::WallpaperPlugin() {
  InitCOM();
}

WallpaperPlugin::~WallpaperPlugin() {
  CleanupCOM();
}

bool WallpaperPlugin::InitCOM() {
  CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  HRESULT hr = CoCreateInstance(
      CLSID_DesktopWallpaper, nullptr, CLSCTX_ALL,
      IID_IDesktopWallpaper, (void**)&desktop_wallpaper_);
  return SUCCEEDED(hr);
}

void WallpaperPlugin::CleanupCOM() {
  if (desktop_wallpaper_) {
    desktop_wallpaper_->Release();
    desktop_wallpaper_ = nullptr;
  }
  CoUninitialize();
}

void WallpaperPlugin::HandleMethodCall(
    const flutter::MethodCall<EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  const auto& method = method_call.method_name();

  if (method == "setWallpaper") {
    const auto* args = std::get_if<EncodableMap>(method_call.arguments());
    if (!args) {
      result->Error("INVALID_ARGS", "Expected map arguments");
      return;
    }
    auto path_it = args->find(EncodableValue("imagePath"));
    auto screen_it = args->find(EncodableValue("screenId"));
    auto fit_it = args->find(EncodableValue("fitMode"));

    std::string pathStr = std::get<std::string>(path_it->second);
    int screenId = -1;
    if (screen_it != args->end() && !screen_it->second.IsNull()) {
      screenId = std::get<int>(screen_it->second);
    }
    std::string fitMode = "fill";
    if (fit_it != args->end()) {
      fitMode = std::get<std::string>(fit_it->second);
    }

    bool success = SetWallpaper(Utf8ToWide(pathStr), screenId, fitMode);
    result->Success(EncodableValue(success));

  } else if (method == "getScreens") {
    result->Success(EncodableValue(GetScreens()));

  } else if (method == "getWallpaper") {
    int screenId = -1;
    const auto* args = std::get_if<EncodableMap>(method_call.arguments());
    if (args) {
      auto screen_it = args->find(EncodableValue("screenId"));
      if (screen_it != args->end() && !screen_it->second.IsNull()) {
        screenId = std::get<int>(screen_it->second);
      }
    }
    result->Success(EncodableValue(GetWallpaper(screenId)));

  } else if (method == "setLockscreen") {
    const auto* args = std::get_if<EncodableMap>(method_call.arguments());
    if (!args) {
      result->Error("INVALID_ARGS", "Expected map arguments");
      return;
    }
    auto path_it = args->find(EncodableValue("imagePath"));
    std::string pathStr = std::get<std::string>(path_it->second);
    bool success = SetLockscreen(Utf8ToWide(pathStr));
    result->Success(EncodableValue(success));

  } else if (method == "removeLockscreen") {
    result->Success(EncodableValue(RemoveLockscreen()));

  } else if (method == "isSupported") {
    result->Success(EncodableValue(true));

  } else if (method == "isAdmin") {
    result->Success(EncodableValue(IsAdmin()));

  } else if (method == "isWindowsEditionSupported") {
    result->Success(EncodableValue(IsWindowsEditionSupported()));

  } else if (method == "isLockscreenSupported") {
    result->Success(EncodableValue(IsLockscreenSupported()));

  } else {
    result->NotImplemented();
  }
}

bool WallpaperPlugin::SetWallpaper(const std::wstring& imagePath, int screenId,
                                    const std::string& fitMode) {
  if (!desktop_wallpaper_) {
    if (!InitCOM()) return false;
  }

  HRESULT hr;

  if (screenId >= 0) {
    UINT count = 0;
    hr = desktop_wallpaper_->GetMonitorDevicePathCount(&count);
    if (FAILED(hr) || (UINT)screenId >= count) return false;

    LPWSTR monitorId = nullptr;
    hr = desktop_wallpaper_->GetMonitorDevicePathAt(screenId, &monitorId);
    if (FAILED(hr)) return false;

    hr = desktop_wallpaper_->SetWallpaper(monitorId, imagePath.c_str());
    CoTaskMemFree(monitorId);
  } else {
    hr = desktop_wallpaper_->SetWallpaper(nullptr, imagePath.c_str());
  }

  DESKTOP_WALLPAPER_POSITION pos = DWPOS_FILL;
  if (fitMode == "fit") pos = DWPOS_FIT;
  else if (fitMode == "stretch") pos = DWPOS_STRETCH;
  else if (fitMode == "center") pos = DWPOS_CENTER;
  else if (fitMode == "tile") pos = DWPOS_TILE;
  else if (fitMode == "span") pos = DWPOS_SPAN;

  desktop_wallpaper_->SetPosition(pos);

  return SUCCEEDED(hr);
}

std::string WallpaperPlugin::GetWallpaper(int screenId) {
  if (!desktop_wallpaper_) {
    if (!InitCOM()) return "";
  }

  HRESULT hr;
  LPWSTR wallpaperPath = nullptr;

  if (screenId >= 0) {
    UINT count = 0;
    hr = desktop_wallpaper_->GetMonitorDevicePathCount(&count);
    if (FAILED(hr) || (UINT)screenId >= count) return "";

    LPWSTR monitorId = nullptr;
    hr = desktop_wallpaper_->GetMonitorDevicePathAt(screenId, &monitorId);
    if (FAILED(hr)) return "";

    hr = desktop_wallpaper_->GetWallpaper(monitorId, &wallpaperPath);
    CoTaskMemFree(monitorId);
  } else {
    hr = desktop_wallpaper_->GetWallpaper(nullptr, &wallpaperPath);
  }

  if (FAILED(hr) || !wallpaperPath) return "";

  std::string result = WideToUtf8(wallpaperPath);
  CoTaskMemFree(wallpaperPath);
  return result;
}

static BOOL CALLBACK MonitorEnumProc(HMONITOR hMonitor, HDC, LPRECT, LPARAM lParam) {
  auto* monitors = reinterpret_cast<std::vector<HMONITOR>*>(lParam);
  monitors->push_back(hMonitor);
  return TRUE;
}

EncodableList WallpaperPlugin::GetScreens() {
  EncodableList screens;

  std::vector<HMONITOR> monitors;
  EnumDisplayMonitors(nullptr, nullptr, MonitorEnumProc, (LPARAM)&monitors);

  for (int i = 0; i < (int)monitors.size(); i++) {
    MONITORINFOEXW mi;
    mi.cbSize = sizeof(mi);
    GetMonitorInfoW(monitors[i], &mi);

    int width = mi.rcMonitor.right - mi.rcMonitor.left;
    int height = mi.rcMonitor.bottom - mi.rcMonitor.top;
    bool isPrimary = (mi.dwFlags & MONITORINFOF_PRIMARY) != 0;

    EncodableMap screen;
    screen[EncodableValue("id")] = EncodableValue(i);
    screen[EncodableValue("name")] = EncodableValue(WideToUtf8(mi.szDevice));
    screen[EncodableValue("width")] = EncodableValue(width);
    screen[EncodableValue("height")] = EncodableValue(height);
    screen[EncodableValue("left")] = EncodableValue((int)mi.rcMonitor.left);
    screen[EncodableValue("top")] = EncodableValue((int)mi.rcMonitor.top);
    screen[EncodableValue("isPrimary")] = EncodableValue(isPrimary);

    screens.push_back(EncodableValue(screen));
  }

  return screens;
}

// Resolves %ProgramData%\UPA Wallpaper Manager and ensures the directory
// exists. Returns an empty string on failure. Files placed there are readable
// by SYSTEM (LogonUI), which is required for the lockscreen image to display.
static std::wstring ResolveLockscreenStagingDir() {
  PWSTR programData = nullptr;
  HRESULT hr = SHGetKnownFolderPath(FOLDERID_ProgramData, 0, nullptr,
                                    &programData);
  if (FAILED(hr) || !programData) {
    if (programData) CoTaskMemFree(programData);
    return L"";
  }

  std::wstring dir = programData;
  CoTaskMemFree(programData);
  dir += L"\\UPA Wallpaper Manager";

  if (!CreateDirectoryW(dir.c_str(), nullptr)) {
    DWORD err = GetLastError();
    if (err != ERROR_ALREADY_EXISTS) return L"";
  }
  return dir;
}

bool WallpaperPlugin::SetLockscreen(const std::wstring& imagePath) {
  if (!IsLockscreenSupported()) return false;

  // Lockscreen is rendered by LogonUI under the SYSTEM account, which has no
  // read access to %APPDATA%. Stage the image into %ProgramData% (readable by
  // SYSTEM) so the lockscreen actually displays it instead of going black or
  // falling back to the default Windows picture.
  std::wstring stagingDir = ResolveLockscreenStagingDir();
  if (stagingDir.empty()) return false;

  // Preserve extension (.jpg/.png/...) so Windows keeps decoding properly.
  std::wstring ext = L".jpg";
  size_t dot = imagePath.find_last_of(L'.');
  if (dot != std::wstring::npos && imagePath.size() - dot <= 5) {
    ext = imagePath.substr(dot);
  }
  std::wstring stagedPath = stagingDir + L"\\lockscreen" + ext;

  if (!CopyFileW(imagePath.c_str(), stagedPath.c_str(), FALSE)) {
    return false;
  }

  HKEY hKey;
  LPCWSTR subKey = L"SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\PersonalizationCSP";

  LONG res = RegCreateKeyExW(HKEY_LOCAL_MACHINE, subKey, 0, nullptr,
                             REG_OPTION_NON_VOLATILE, KEY_SET_VALUE, nullptr,
                             &hKey, nullptr);
  if (res != ERROR_SUCCESS) return false;

  RegSetValueExW(hKey, L"LockScreenImagePath", 0, REG_SZ,
                 (const BYTE*)stagedPath.c_str(),
                 (DWORD)((stagedPath.size() + 1) * sizeof(wchar_t)));

  RegSetValueExW(hKey, L"LockScreenImageUrl", 0, REG_SZ,
                 (const BYTE*)stagedPath.c_str(),
                 (DWORD)((stagedPath.size() + 1) * sizeof(wchar_t)));

  DWORD status = 1;
  RegSetValueExW(hKey, L"LockScreenImageStatus", 0, REG_DWORD,
                 (const BYTE*)&status, sizeof(status));

  RegCloseKey(hKey);
  return true;
}

bool WallpaperPlugin::RemoveLockscreen() {
  HKEY hKey;
  LPCWSTR subKey = L"SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\PersonalizationCSP";
  LONG res = RegOpenKeyExW(HKEY_LOCAL_MACHINE, subKey, 0, KEY_SET_VALUE, &hKey);
  if (res == ERROR_FILE_NOT_FOUND) return true;
  if (res != ERROR_SUCCESS) return false;

  RegDeleteValueW(hKey, L"LockScreenImagePath");
  RegDeleteValueW(hKey, L"LockScreenImageUrl");
  RegDeleteValueW(hKey, L"LockScreenImageStatus");
  RegCloseKey(hKey);
  return true;
}

bool WallpaperPlugin::IsAdmin() {
  BOOL isAdmin = FALSE;
  SID_IDENTIFIER_AUTHORITY ntAuthority = SECURITY_NT_AUTHORITY;
  PSID adminGroup = nullptr;
  if (AllocateAndInitializeSid(&ntAuthority, 2, SECURITY_BUILTIN_DOMAIN_RID,
                                DOMAIN_ALIAS_RID_ADMINS, 0, 0, 0, 0, 0, 0,
                                &adminGroup)) {
    CheckTokenMembership(nullptr, adminGroup, &isAdmin);
    FreeSid(adminGroup);
  }
  return isAdmin != FALSE;
}

bool WallpaperPlugin::IsWindowsEditionSupported() {
  // PersonalizationCSP (the registry mechanism we rely on for the lock screen)
  // is honored only by Pro / Enterprise / Education / Server editions. Windows
  // Home silently ignores it, which makes any lockscreen image we set never
  // appear. Detect the edition via the EditionID registry value.
  HKEY hKey;
  LONG res = RegOpenKeyExW(HKEY_LOCAL_MACHINE,
      L"SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion",
      0, KEY_READ, &hKey);
  if (res != ERROR_SUCCESS) return false;

  wchar_t edition[128] = {0};
  DWORD size = sizeof(edition);
  DWORD type = 0;
  res = RegQueryValueExW(hKey, L"EditionID", nullptr, &type,
                         (LPBYTE)edition, &size);
  RegCloseKey(hKey);
  if (res != ERROR_SUCCESS || type != REG_SZ) return false;

  std::wstring ed(edition);
  // Home variants all start with "Core" (Core, CoreN, CoreSingleLanguage,
  // CoreCountrySpecific, CoreConnected*, etc.). Anything else is Pro,
  // Enterprise, Education, IoT, or Server -> all supported.
  if (ed.compare(0, 4, L"Core") == 0) return false;
  return true;
}

bool WallpaperPlugin::IsLockscreenSupported() {
  return IsAdmin() && IsWindowsEditionSupported();
}
