"""Gestionnaire de mises à jour automatiques depuis GitHub."""

import os
import sys
import requests
import json
import subprocess
import tempfile
import shutil
from pathlib import Path
from typing import Optional, Tuple
from packaging import version

from .logger import get_logger

logger = get_logger()


# Version actuelle de l'application
# ⚠️ IMPORTANT : Modifier ce numéro à chaque nouvelle version !
CURRENT_VERSION = "1.2.0"

# URL de la dernière release GitHub
GITHUB_RELEASES_URL = "https://api.github.com/repos/Universe-Photo-Archive/UPA_Wallpaper_Manager/releases/latest"


class UpdateManager:
    """Gestionnaire de mises à jour automatiques."""
    
    def __init__(self, config_manager):
        """
        Initialise le gestionnaire de mises à jour.
        
        Args:
            config_manager: Gestionnaire de configuration
        """
        self.config_manager = config_manager
        self.current_version = CURRENT_VERSION
        self.latest_version: Optional[str] = None
        self.download_url: Optional[str] = None
    
    def get_current_version(self) -> str:
        """
        Retourne la version actuelle de l'application.
        
        Returns:
            Numéro de version (ex: "1.0.1")
        """
        return self.current_version
    
    def check_for_updates(self, timeout: int = 5) -> Tuple[bool, Optional[str], Optional[str]]:
        """
        Vérifie s'il y a une nouvelle version disponible sur GitHub.
        
        Args:
            timeout: Timeout en secondes pour la requête
            
        Returns:
            Tuple (update_available, latest_version, download_url)
        """
        try:
            logger.info("Vérification des mises à jour sur GitHub...")
            
            # Requête à l'API GitHub
            headers = {
                'Accept': 'application/vnd.github.v3+json',
                'User-Agent': 'UPA-Wallpaper-Manager'
            }
            
            response = requests.get(
                GITHUB_RELEASES_URL,
                headers=headers,
                timeout=timeout
            )
            
            if response.status_code != 200:
                logger.warning(f"Impossible de vérifier les mises à jour (HTTP {response.status_code})")
                return False, None, None
            
            data = response.json()
            
            # Extraire la version du tag (ex: "v1.0.2" → "1.0.2")
            tag_name = data.get('tag_name', '')
            latest_version = tag_name.lstrip('v')
            
            # Trouver l'asset .exe
            download_url = None
            assets = data.get('assets', [])
            for asset in assets:
                if asset['name'].endswith('.exe'):
                    download_url = asset['browser_download_url']
                    break
            
            if not latest_version:
                logger.warning("Impossible d'extraire le numéro de version")
                return False, None, None
            
            self.latest_version = latest_version
            self.download_url = download_url
            
            # Comparer les versions
            try:
                current_v = version.parse(self.current_version)
                latest_v = version.parse(latest_version)
                
                update_available = latest_v > current_v
                
                if update_available:
                    logger.info(f"✓ Nouvelle version disponible : {latest_version} (actuelle: {self.current_version})")
                else:
                    logger.info(f"✓ Application à jour (version {self.current_version})")
                
                return update_available, latest_version, download_url
                
            except Exception as e:
                logger.error(f"Erreur lors de la comparaison de versions: {e}")
                return False, None, None
            
        except requests.Timeout:
            logger.warning("Timeout lors de la vérification des mises à jour")
            return False, None, None
            
        except requests.RequestException as e:
            logger.warning(f"Erreur réseau lors de la vérification des mises à jour: {e}")
            return False, None, None
            
        except Exception as e:
            logger.error(f"Erreur lors de la vérification des mises à jour: {e}", exc_info=True)
            return False, None, None
    
    def should_check_update(self) -> bool:
        """
        Vérifie si on doit vérifier les mises à jour.
        
        Returns:
            True si on doit vérifier, False si l'utilisateur a désactivé
        """
        # Vérifier si l'utilisateur a coché "Ne plus me demander"
        return not self.config_manager.get('update.skip_check', False)
    
    def set_skip_update_check(self, skip: bool) -> None:
        """
        Active/désactive la vérification automatique des mises à jour.
        
        Args:
            skip: True pour désactiver, False pour activer
        """
        self.config_manager.set('update.skip_check', skip)
        logger.info(f"Vérification automatique des mises à jour: {'désactivée' if skip else 'activée'}")
    
    def download_and_install_update(self, download_url: str, on_progress=None, on_complete=None) -> bool:
        """
        Télécharge et installe la mise à jour.
        
        Args:
            download_url: URL de téléchargement de la nouvelle version
            on_progress: Callback optionnel pour la progression (bytes_downloaded, total_bytes)
            
        Returns:
            True si succès, False sinon
        """
        try:
            logger.info(f"Téléchargement de la mise à jour depuis {download_url}")
            
            # Créer un dossier temporaire
            temp_dir = Path(tempfile.gettempdir()) / "UPA_Update"
            temp_dir.mkdir(parents=True, exist_ok=True)
            
            # Nom du fichier téléchargé
            new_exe_path = temp_dir / "UPAWallpaperManager_new.exe"
            
            # Télécharger le fichier
            logger.info("Téléchargement en cours...")
            response = requests.get(download_url, stream=True, timeout=60)
            total_size = int(response.headers.get('content-length', 0))
            
            downloaded = 0
            with open(new_exe_path, 'wb') as f:
                for chunk in response.iter_content(chunk_size=8192):
                    if chunk:
                        f.write(chunk)
                        downloaded += len(chunk)
                        
                        if on_progress and total_size > 0:
                            on_progress(downloaded, total_size)
            
            logger.info(f"✓ Téléchargement terminé: {new_exe_path} ({downloaded / 1024 / 1024:.2f} MB)")
            
            # Vérifier que le fichier existe
            if not new_exe_path.exists():
                logger.error("Le fichier téléchargé n'existe pas")
                return False
            
            # Créer un script batch pour remplacer l'exe
            self._create_update_script(new_exe_path, on_complete)
            
            return True
            
        except Exception as e:
            logger.error(f"Erreur lors du téléchargement de la mise à jour: {e}", exc_info=True)
            return False
    
    def _create_update_script(self, new_exe_path: Path, on_complete=None) -> None:
        """
        Crée un script batch qui remplace l'exe actuel et ferme l'application.
        
        Args:
            new_exe_path: Chemin du nouvel exe téléchargé
            on_complete: Callback à appeler pour fermer l'application
        """
        try:
            # Chemin de l'exe actuel
            if getattr(sys, 'frozen', False):
                current_exe = Path(sys.executable)
            else:
                # Mode développement - pointer vers dist
                current_exe = Path("dist/UPAWallpaperManager.exe").absolute()
            
            # Chemin du répertoire de l'application
            app_dir = current_exe.parent
            
            # Créer le script batch simplifié
            script_content = f"""@echo off
REM Script de mise à jour automatique
echo ================================================
echo Mise a jour de UPA Wallpaper Manager
echo ================================================
echo.

REM Attendre que l'application se ferme completement
echo Fermeture de l'application...
timeout /t 3 /nobreak >nul

REM Sauvegarder l'ancien exe
echo Sauvegarde de l'ancienne version...
if exist "{current_exe}" (
    move /y "{current_exe}" "{current_exe}.old" >nul 2>&1
)

REM Copier le nouvel exe
echo Installation de la nouvelle version...
move /y "{new_exe_path}" "{current_exe}"

if exist "{current_exe}" (
    echo.
    echo ================================================
    echo Mise a jour terminee avec succes !
    echo ================================================
    echo.
    echo Vous pouvez maintenant relancer l'application.
    echo.
    
    REM Supprimer l'ancien exe
    timeout /t 2 /nobreak >nul
    if exist "{current_exe}.old" del "{current_exe}.old" >nul 2>&1
    
    REM Pause pour laisser l'utilisateur lire le message
    timeout /t 5 /nobreak >nul
) else (
    echo.
    echo ERREUR: La mise a jour a echoue
    echo.
    pause
)

REM Supprimer ce script
del "%~f0" >nul 2>&1
"""
            
            # Sauvegarder le script
            script_path = Path(tempfile.gettempdir()) / "UPA_Update.bat"
            with open(script_path, 'w', encoding='utf-8') as f:
                f.write(script_content)
            
            logger.info(f"Script de mise à jour créé: {script_path}")
            
            # Lancer le script
            logger.info("Lancement du script de mise à jour...")
            subprocess.Popen(
                str(script_path),
                shell=True,
                creationflags=subprocess.CREATE_NEW_CONSOLE
            )
            
            # Attendre un peu puis fermer l'application via le callback
            logger.info("Fermeture de l'application pour mise à jour...")
            import time
            time.sleep(1)
            
            # Appeler le callback pour fermer l'application depuis le thread principal
            if on_complete:
                on_complete()
            
        except Exception as e:
            logger.error(f"Erreur lors de la création du script de mise à jour: {e}", exc_info=True)
            raise

