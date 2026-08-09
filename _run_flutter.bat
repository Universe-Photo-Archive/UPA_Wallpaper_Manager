@echo off
subst M: "E:\Documents\Sites Web\UNIVERSE-PHOTO-ARCHIVE.EU\OUTILS (DEV)" >nul 2>nul
M:
cd "M:\UPA_Wallpaper_Manager-1.1.0"
call M:\Flutter\bin\flutter.bat %*
set FLUTTER_EXIT=%ERRORLEVEL%
E:
subst M: /d >nul 2>nul
exit /b %FLUTTER_EXIT%
