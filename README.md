# UPA Wallpaper Manager

Multi-screen wallpaper manager powered by [Universe Photo Archive](https://universe-photo-archive.eu) — galaxies, planets, astronauts and more, rotating on your desktop.

[Version française](README_FR.md)

## Features

- Multi-screen support: a different theme and rotation delay per monitor
- Themes fed by the Universe Photo Archive Piwigo gallery (Wallpapers, Thomas Pesquet, Sophie Adenot, ...)
- Add your own themes: any public Piwigo album URL, or a local folder
- Smart cache: on-demand downloads, full-cycle rotation (every image shown once per cycle), automatic cleanup
- Windows lock-screen wallpaper support (requires administrator, Windows Pro/Enterprise/Education)
- System tray: the app minimizes/closes to the tray next to the clock; quit via right-click > Quit
- Launch at Windows startup (elevated Scheduled Task, no UAC prompt at logon)
- Automatic update check against GitHub releases
- English / French UI, light & dark themes

## Download

Grab the latest Windows installer from the [Releases page](https://github.com/Universe-Photo-Archive/UPA_Wallpaper_Manager/releases): `UPA_Wallpaper_Manager_Setup_<version>.exe`.

The app requires administrator privileges (needed for the lock-screen feature), so Windows shows a UAC prompt when you launch it manually. When started automatically at logon it runs elevated without any prompt.

## Building from source

This is a [Flutter](https://flutter.dev) desktop application (currently Windows; Linux, macOS, Android and iOS planned).

```bash
flutter pub get
flutter run -d windows          # run a debug build (from an elevated terminal)
flutter build windows --release # produce the release build
```

To build the Windows installer (requires [Inno Setup 6](https://jrsoftware.org/isinfo.php)):

```bash
flutter build windows --release
"C:\Program Files (x86)\Inno Setup 6\ISCC.exe" installer\setup.iss
```

The installer is written to `installer/Output/`.

## Default themes configuration

The list of default themes lives in [`config/themes_default.json`](config/themes_default.json). The app fetches this file from GitHub at every start, so themes can be added or changed without shipping a new release. A copy is bundled in `assets/config/` as an offline fallback.

## License

[GPL-3.0](LICENSE)

## Version history

- **2.x** — complete rewrite in Flutter (this repository)
- **1.x** — original Python version
