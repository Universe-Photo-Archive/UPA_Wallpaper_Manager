@echo off
:: Se placer dans le répertoire du script (important pour lancement en admin)
cd /d "%~dp0"

echo ================================================
echo TEST RAPIDE - Universe Wallpaper Manager
echo ================================================
echo.
echo Ce script va lancer l'application en mode test
echo La console restera ouverte pour voir les logs
echo.
echo Appuyez sur une touche pour démarrer...
pause >nul

echo.
echo Lancement de l'application...
echo.

python src/main.py

echo.
echo Application fermée.
echo Vérifiez les logs dans: data/logs/wallpaper_manager.log
echo.
pause

