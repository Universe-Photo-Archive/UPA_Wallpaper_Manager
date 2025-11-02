@echo off
:: Se placer dans le répertoire du script
cd /d "%~dp0"

echo ================================================
echo BUILD EXECUTABLE - Universe Wallpaper Manager
echo ================================================
echo.

REM Vérifier si Python est installé
python --version >nul 2>&1
if %errorlevel% neq 0 (
    echo ERREUR: Python n'est pas installé ou n'est pas dans le PATH
    pause
    exit /b 1
)

echo Installation de PyInstaller...
python -m pip install pyinstaller

REM S'assurer que le dossier data existe (même vide)
if not exist "data" mkdir "data"

echo.
echo ================================================
echo CRÉATION DE L'EXÉCUTABLE
echo ================================================
echo.

REM Créer le répertoire de build s'il n'existe pas
if not exist "build" mkdir build

REM Créer l'exécutable avec PyInstaller
pyinstaller --onefile ^
    --windowed ^
    --name "UPAWallpaperManager" ^
    --icon=assets/icons/app_icon.ico ^
    --add-data "data;data" ^
    --add-data "assets;assets" ^
    --add-data "langs;langs" ^
    --hidden-import=PIL._tkinter_finder ^
    --hidden-import=win32api ^
    --hidden-import=win32con ^
    --hidden-import=win32gui ^
    --hidden-import=pywintypes ^
    --noconsole ^
    --clean ^
    src/main.py

if %errorlevel% neq 0 (
    echo.
    echo ERREUR lors de la création de l'exécutable
    pause
    exit /b 1
)

echo.
echo ================================================
echo SUCCÈS!
echo ================================================
echo.
echo L'exécutable a été créé dans le dossier: dist/
echo Fichier: UPAWallpaperManager.exe
echo.
echo Vous pouvez maintenant:
echo 1. Tester l'exe: dist\UPAWallpaperManager.exe
echo 2. Distribuer ce fichier
echo.
pause


