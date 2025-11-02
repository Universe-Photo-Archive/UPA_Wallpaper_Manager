@echo off
:: Se placer dans le répertoire du script
cd /d "%~dp0"

echo ================================================
echo Installation de Universe Wallpaper Manager
echo ================================================
echo.

REM Vérifier si Python est installé
python --version >nul 2>&1
if %errorlevel% neq 0 (
    echo ERREUR: Python n'est pas installé ou n'est pas dans le PATH
    echo Veuillez installer Python 3.10 ou supérieur
    pause
    exit /b 1
)

echo Installation des dépendances...
echo.

python -m pip install --upgrade pip
python -m pip install -r requirements.txt

if %errorlevel% neq 0 (
    echo.
    echo ERREUR lors de l'installation des dépendances
    pause
    exit /b 1
)

echo.
echo ================================================
echo Installation terminée avec succès!
echo ================================================
echo.
echo Pour lancer l'application, exécutez: run.bat
echo.
pause


