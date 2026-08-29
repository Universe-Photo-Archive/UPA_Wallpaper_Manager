import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:path_provider/path_provider.dart';
import 'package:system_tray/system_tray.dart';
import 'package:window_manager/window_manager.dart';

class SystemTrayService with WindowListener {
  static bool get isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  final SystemTray _tray = SystemTray();

  VoidCallback? onShow;
  VoidCallback? onQuit;
  VoidCallback? onRotateNow;
  VoidCallback? onTogglePause;

  bool _isPaused = false;

  /// Desktop notice shown when the window leaves for the tray, so nobody
  /// thinks the app just vanished. The user can switch it off in Settings.
  bool notifyOnHide = true;
  String hideNoticeTitle = 'UPA Wallpaper Manager';
  String hideNoticeBody = '';

  Future<void> init() async {
    if (!isDesktop) return;

    // Windows shows toasts on behalf of a Start-menu shortcut, which the
    // plugin creates when missing.
    try {
      await localNotifier.setup(
        appName: 'UPA Wallpaper Manager',
        shortcutPolicy: ShortcutPolicy.requireCreate,
      );
    } catch (_) {
      // Without it the app simply hides without a notice.
    }

    // Minimize and close both send the app to the tray (next to the clock)
    // instead of keeping a taskbar entry / quitting. Quitting is only
    // possible via the tray menu ("Quit / Quitter").
    windowManager.addListener(this);
    await windowManager.setPreventClose(true);

    // Extract icon to a temp file so system_tray can find it
    String iconPath;
    if (Platform.isWindows) {
      iconPath = await _extractAssetToFile('assets/icons/app_icon.ico', 'app_icon.ico');
    } else {
      iconPath = await _extractAssetToFile('assets/icons/app_icon.png', 'app_icon.png');
    }

    await _tray.initSystemTray(
      title: 'UPA Wallpaper Manager',
      iconPath: iconPath,
      toolTip: 'UPA Wallpaper Manager',
    );

    await _updateMenu();

    _tray.registerSystemTrayEventHandler((eventName) {
      if (eventName == kSystemTrayEventClick) {
        // Left click: open the window (menu on macOS, where this is the
        // conventional behavior).
        Platform.isWindows ? onShow?.call() : _tray.popUpContextMenu();
      } else if (eventName == kSystemTrayEventRightClick) {
        // Right click: context menu with "Quit / Quitter".
        Platform.isWindows ? _tray.popUpContextMenu() : onShow?.call();
      }
    });
  }

  Future<String> _extractAssetToFile(String assetPath, String filename) async {
    try {
      final data = await rootBundle.load(assetPath);
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/$filename');
      await file.writeAsBytes(data.buffer.asUint8List());
      return file.path;
    } catch (e) {
      return assetPath;
    }
  }

  Future<void> _updateMenu() async {
    final menu = Menu();
    await menu.buildFrom([
      MenuItemLabel(
        label: 'Open / Ouvrir',
        onClicked: (item) => onShow?.call(),
      ),
      MenuSeparator(),
      MenuItemLabel(
        label: 'Change now / Changer',
        onClicked: (item) => onRotateNow?.call(),
      ),
      MenuItemLabel(
        label: _isPaused ? 'Resume / Reprendre' : 'Pause',
        onClicked: (item) {
          _isPaused = !_isPaused;
          onTogglePause?.call();
          _updateMenu();
        },
      ),
      MenuSeparator(),
      MenuItemLabel(
        label: 'Quit / Quitter',
        onClicked: (item) => onQuit?.call(),
      ),
    ]);
    await _tray.setContextMenu(menu);
  }

  void updatePauseState(bool isPaused) {
    _isPaused = isPaused;
    _updateMenu();
  }

  /// Window minimized -> hide it completely so only the tray icon remains
  /// (no entry left in the taskbar).
  @override
  void onWindowMinimize() {
    hideWindow(notify: true);
  }

  /// Close button (X) -> hide to tray instead of quitting. Requires
  /// [windowManager.setPreventClose] to be true (done in [init]).
  @override
  void onWindowClose() {
    hideWindow(notify: true);
  }

  /// [notify] tells the user where the window went; it stays false when the
  /// app starts up already hidden, which needs no explanation.
  Future<void> hideWindow({bool notify = false}) async {
    if (!isDesktop) return;
    try {
      await windowManager.setSkipTaskbar(true);
    } catch (_) {
      // [setSkipTaskbar] is a no-op on platforms that do not support it.
    }
    await windowManager.hide();
    if (notify && notifyOnHide) _showHideNotice();
  }

  Future<void> _showHideNotice() async {
    if (hideNoticeBody.isEmpty) return;
    try {
      final notification = LocalNotification(
        title: hideNoticeTitle,
        body: hideNoticeBody,
      );
      notification.onClick = () => onShow?.call();
      await notification.show();
    } catch (_) {
      // A missing notification must never keep the window from hiding.
    }
  }

  Future<void> showWindow() async {
    if (!isDesktop) return;
    // The window may have been hidden with [skipTaskbar=true] (minimize/close
    // to tray, or --minimized startup). Once the user explicitly opens it,
    // restore the normal taskbar behavior.
    try {
      await windowManager.setSkipTaskbar(false);
    } catch (_) {
      // [setSkipTaskbar] is a no-op on platforms that do not support it.
    }
    await windowManager.show();
    if (await windowManager.isMinimized()) {
      await windowManager.restore();
    }
    await windowManager.focus();
  }

  void dispose() {
    windowManager.removeListener(this);
    _tray.destroy();
  }
}
