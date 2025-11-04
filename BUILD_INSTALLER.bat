@echo off
:: Script pour créer l'installateur UPA Wallpaper Manager
:: Nécessite Inno Setup 6.0 ou supérieur

cd /d "%~dp0"

echo ================================================
echo CRÉATION DE L'INSTALLATEUR
echo UPA Wallpaper Manager
echo ================================================
echo.

:: Vérifier si l'exécutable existe
if not exist "dist\UPAWallpaperManager.exe" (
    echo ERREUR: L'exécutable n'existe pas !
    echo.
    echo Veuillez d'abord construire l'exécutable avec build_exe.bat
    echo.
    pause
    exit /b 1
)

:: Vérifier si Inno Setup est installé
set INNO_COMPILER="C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
if not exist %INNO_COMPILER% (
    echo ERREUR: Inno Setup 6 n'est pas installé !
    echo.
    echo Téléchargez-le depuis: https://jrsoftware.org/isdl.php
    echo Installez-le dans le répertoire par défaut.
    echo.
    pause
    exit /b 1
)

echo Compilation du script d'installation...
echo.

:: Créer le répertoire de sortie s'il n'existe pas
if not exist "installer_output" mkdir installer_output

:: Compiler le script Inno Setup
%INNO_COMPILER% "installer_setup.iss"

if %errorlevel% neq 0 (
    echo.
    echo ERREUR lors de la création de l'installateur
    pause
    exit /b 1
)

echo.
echo ================================================
echo SUCCÈS !
echo ================================================
echo.
echo L'installateur a été créé dans: installer_output\
echo.
echo Vous pouvez maintenant distribuer le fichier:
echo UPA_Wallpaper_Manager_1.2.0_Setup.exe
echo.
pause

