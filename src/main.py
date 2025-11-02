"""Point d'entrée principal de l'application Universe Wallpaper Manager."""

import sys
import os
import argparse
from pathlib import Path

# IMPORTANT : Définir le répertoire de travail au répertoire du script/exe
# Ceci corrige le problème "Accès refusé: 'data'" au démarrage automatique
if getattr(sys, 'frozen', False):
    # Mode .exe compilé
    application_path = Path(sys.executable).parent
else:
    # Mode développement
    application_path = Path(__file__).parent.parent

os.chdir(application_path)

# Ajouter le répertoire parent au path pour les imports
sys.path.insert(0, str(application_path))

import customtkinter as ctk

from src.ui.main_window import MainWindow
from src.utils.logger import get_logger

logger = get_logger()


def main():
    """Fonction principale."""
    try:
        # Parser les arguments de ligne de commande
        parser = argparse.ArgumentParser(description='UPA Wallpaper Manager')
        parser.add_argument(
            '--minimized',
            action='store_true',
            help='Démarrer l\'application réduite dans la zone de notification'
        )
        args = parser.parse_args()
        
        logger.info("=" * 60)
        logger.info("UPA Wallpaper Manager v1.0.0")
        logger.info("=" * 60)
        logger.info("Démarrage de l'application")
        
        if args.minimized:
            logger.info("Mode démarrage réduit (--minimized)")
        
        # Configurer CustomTkinter
        ctk.set_default_color_theme("blue")
        
        # Créer et lancer l'application
        app = MainWindow(start_minimized=args.minimized)
        app.mainloop()
        
        logger.info("Application fermée normalement")
        
    except Exception as e:
        logger.error(f"Erreur fatale: {e}", exc_info=True)
        sys.exit(1)


if __name__ == "__main__":
    main()


