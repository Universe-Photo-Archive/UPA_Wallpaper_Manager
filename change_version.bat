@echo off
chcp 65001 >nul 2>&1
setlocal enabledelayedexpansion

cd /d "%~dp0"

echo.
echo ================================================
echo   CHANGEMENT DE VERSION
echo   UPA Wallpaper Manager
echo ================================================
echo.

:: Vérifier que le fichier existe
if not exist "src\utils\update_manager.py" (
    echo ERREUR: Le fichier src\utils\update_manager.py n'existe pas
    echo.
    pause
    exit /b 1
)

:: Détecter la version actuelle - méthode ultra simple
:: Créer un fichier temp avec juste la ligne qui nous intéresse
type "src\utils\update_manager.py" | findstr "CURRENT_VERSION = " | findstr """" > temp_version.txt

:: Lire le fichier
set /p LINE=<temp_version.txt
del temp_version.txt >nul 2>&1

:: Extraire la version - méthode batch pure
:: Supprimer tout avant le premier guillemet puis supprimer les guillemets
set "TEMP1=!LINE:*"=!"
set "CURRENT_VERSION=!TEMP1:"=!"

if "!CURRENT_VERSION!"=="" (
    echo.
    echo ERREUR: Impossible de detecter la version actuelle
    echo.
    pause
    exit /b 1
)

echo.
echo Version actuelle detectee : !CURRENT_VERSION!
echo.

:: Afficher les fichiers qui seront modifiés
echo Fichiers qui seront modifies :
echo   1. src\utils\update_manager.py
echo   2. langs\fr.json
echo   3. langs\en.json
echo   4. installer_setup.iss
echo   5. BUILD_INSTALLER.bat
echo   6. version_info.txt
echo.

:: Demander la nouvelle version
set /p NEW_VERSION="Entrez la nouvelle version (ex: 1.2.0) : "

if "!NEW_VERSION!"=="" (
    echo.
    echo ERREUR : Aucune version specifiee
    echo.
    pause
    exit /b 1
)

:: Confirmation
echo.
echo Changement de version :
echo   !CURRENT_VERSION! ---^> !NEW_VERSION!
echo.
set /p CONFIRM="Confirmer ? (O/N) : "

if /i not "!CONFIRM!"=="O" (
    echo.
    echo Operation annulee
    pause
    exit /b 0
)

echo.
echo ================================================
echo MODIFICATION DES FICHIERS EN COURS...
echo ================================================
echo.

:: Appeler le script PowerShell pour faire les modifications
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0change_version.ps1" "!CURRENT_VERSION!" "!NEW_VERSION!"

if !errorlevel! equ 0 (
    echo.
    echo ================================================
    echo SUCCES !
    echo ================================================
    echo.
    echo Tous les fichiers ont ete mis a jour avec la version !NEW_VERSION!
    echo.
    echo N'oubliez pas de :
    echo   1. Tester l'application
    echo   2. Reconstruire l'executable avec build_exe.bat
    echo   3. Creer l'installateur avec BUILD_INSTALLER.bat
    echo   4. Commiter les changements dans Git
    echo.
) else (
    echo.
    echo ERREUR lors de la modification des fichiers
    echo Consultez les messages ci-dessus pour plus de details
    echo.
)

pause

