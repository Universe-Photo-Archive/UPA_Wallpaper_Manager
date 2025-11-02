"""Gestionnaire du lancement automatique au démarrage de Windows."""

import os
import sys
import shutil
import ctypes
import subprocess
from pathlib import Path
from typing import Optional, Tuple

from .logger import get_logger

logger = get_logger()


class StartupManager:
    """Gère le lancement automatique de l'application au démarrage de Windows."""
    
    APP_NAME = "UPA Wallpaper Manager"
    TASK_NAME = "UPAWallpaperManager_Startup"
    
    def __init__(self):
        """Initialise le gestionnaire de démarrage."""
        # Chemin du dossier Startup de Windows (méthode legacy)
        self.startup_folder = Path(os.path.expandvars(
            r'%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup'
        ))
        self.shortcut_path = self.startup_folder / f"{self.APP_NAME}.lnk"
    
    def is_admin(self) -> bool:
        """
        Vérifie si l'application s'exécute avec des droits administrateur.
        
        Returns:
            True si admin, False sinon
        """
        try:
            return ctypes.windll.shell32.IsUserAnAdmin() != 0
        except Exception:
            return False
    
    def is_enabled(self) -> bool:
        """
        Vérifie si le lancement automatique est activé.
        Vérifie d'abord la tâche planifiée, puis le raccourci en fallback.
        
        Returns:
            True si activé, False sinon
        """
        # Vérifier d'abord la tâche planifiée (méthode recommandée)
        if self._is_scheduled_task_exists():
            return True
        
        # Fallback : vérifier le raccourci dans Startup
        try:
            exists = self.shortcut_path.exists()
            logger.debug(f"Vérification raccourci Startup: {exists}")
            return exists
        except Exception as e:
            logger.error(f"Erreur lors de la vérification du démarrage automatique: {e}")
            return False
    
    def enable(self) -> Tuple[bool, str]:
        """
        Active le lancement automatique au démarrage de Windows.
        
        Si l'application tourne en admin : crée une tâche planifiée (recommandé)
        Sinon : crée un raccourci dans le dossier Startup (limité)
        
        Returns:
            Tuple (succès, message)
        """
        exe_path = self._get_executable_path()
        
        if not exe_path:
            msg = "Impossible de déterminer le chemin de l'exécutable"
            logger.error(msg)
            return False, msg
        
        # Si on est admin : utiliser une tâche planifiée (méthode recommandée)
        if self.is_admin():
            logger.info("Droits admin détectés - Création d'une tâche planifiée...")
            success, message = self._create_scheduled_task(exe_path)
            
            if success:
                # Supprimer l'ancien raccourci Startup s'il existe
                if self.shortcut_path.exists():
                    try:
                        self.shortcut_path.unlink()
                        logger.debug("Ancien raccourci Startup supprimé")
                    except Exception as e:
                        logger.warning(f"Impossible de supprimer l'ancien raccourci: {e}")
            
            return success, message
        
        # Sinon : méthode classique (raccourci dans Startup)
        # Note: Ne fonctionne pas si l'exe nécessite des droits admin
        else:
            logger.info("Pas de droits admin - Création d'un raccourci Startup...")
            try:
                self.startup_folder.mkdir(parents=True, exist_ok=True)
                self._create_shortcut(exe_path, self.shortcut_path)
                
                msg = "Lancement automatique activé (raccourci Startup)"
                logger.info(f"✓ {msg}")
                return True, msg
                
            except Exception as e:
                msg = f"Erreur lors de la création du raccourci: {e}"
                logger.error(msg, exc_info=True)
                return False, msg
    
    def disable(self) -> Tuple[bool, str]:
        """
        Désactive le lancement automatique au démarrage de Windows.
        Supprime la tâche planifiée ET le raccourci Startup s'ils existent.
        
        Returns:
            Tuple (succès, message)
        """
        success_task = True
        success_shortcut = True
        messages = []
        
        # Supprimer la tâche planifiée si elle existe
        if self._is_scheduled_task_exists():
            if self.is_admin():
                success_task, msg = self._remove_scheduled_task()
                messages.append(msg)
            else:
                success_task = False
                messages.append("⚠️ Tâche planifiée détectée mais droits admin requis pour la supprimer")
        
        # Supprimer le raccourci Startup s'il existe
        try:
            if self.shortcut_path.exists():
                self.shortcut_path.unlink()
                messages.append("Raccourci Startup supprimé")
                logger.info("✓ Raccourci Startup supprimé")
        except Exception as e:
            success_shortcut = False
            msg = f"Erreur lors de la suppression du raccourci: {e}"
            messages.append(msg)
            logger.error(msg)
        
        # Si rien n'était activé
        if not messages:
            messages.append("Lancement automatique déjà désactivé")
        
        overall_success = success_task and success_shortcut
        return overall_success, "\n".join(messages)
    
    def _get_executable_path(self) -> Optional[str]:
        """
        Obtient le chemin de l'exécutable de l'application.
        
        Returns:
            Chemin de l'exécutable ou None si impossible à déterminer
        """
        if getattr(sys, 'frozen', False):
            # Mode exécutable compilé (.exe)
            return sys.executable
        else:
            # Mode développement - retourner le chemin du script Python
            # Le raccourci pointera vers python.exe avec le script
            return sys.executable
    
    def _create_shortcut(self, target_path: str, shortcut_path: Path) -> None:
        """
        Crée un raccourci Windows (.lnk).
        
        Args:
            target_path: Chemin vers l'exécutable/script
            shortcut_path: Chemin où créer le raccourci
        """
        try:
            import win32com.client
            
            shell = win32com.client.Dispatch("WScript.Shell")
            shortcut = shell.CreateShortcut(str(shortcut_path))
            
            if getattr(sys, 'frozen', False):
                # Mode .exe compilé
                shortcut.TargetPath = target_path
                shortcut.Arguments = "--minimized"
                shortcut.WorkingDirectory = str(Path(target_path).parent)
            else:
                # Mode développement
                main_script = Path(__file__).parent.parent / "main.py"
                shortcut.TargetPath = target_path  # python.exe
                shortcut.Arguments = f'"{main_script}" --minimized'
                shortcut.WorkingDirectory = str(main_script.parent.parent)
            
            shortcut.Description = "UPA Wallpaper Manager"
            shortcut.IconLocation = target_path
            shortcut.save()
            
            logger.debug(f"Raccourci créé: {shortcut_path}")
            
        except Exception as e:
            logger.error(f"Erreur lors de la création du raccourci: {e}", exc_info=True)
            raise
    
    def _is_scheduled_task_exists(self) -> bool:
        """
        Vérifie si la tâche planifiée existe.
        
        Returns:
            True si la tâche existe, False sinon
        """
        try:
            result = subprocess.run(
                ["schtasks", "/Query", "/TN", self.TASK_NAME],
                capture_output=True,
                text=True,
                timeout=5
            )
            return result.returncode == 0
        except Exception as e:
            logger.debug(f"Erreur lors de la vérification de la tâche: {e}")
            return False
    
    def _create_scheduled_task(self, exe_path: str) -> Tuple[bool, str]:
        """
        Crée une tâche planifiée Windows qui lance l'application au démarrage
        avec droits admin SANS invite UAC.
        
        Args:
            exe_path: Chemin vers l'exécutable
            
        Returns:
            Tuple (succès, message)
        """
        try:
            # Supprimer la tâche si elle existe déjà
            if self._is_scheduled_task_exists():
                logger.info("Tâche existante détectée, suppression...")
                self._remove_scheduled_task()
            
            username = os.environ.get('USERNAME', 'SYSTEM')
            
            # Construire la commande schtasks
            # /SC ONLOGON : Se déclenche à l'ouverture de session
            # /RL HIGHEST : Exécuter avec les droits maximaux (admin)
            # /TR : Chemin de l'exécutable
            # /TN : Nom de la tâche
            # /F : Force la création (écrase si existe)
            
            cmd = [
                "schtasks",
                "/Create",
                "/SC", "ONLOGON",
                "/TN", self.TASK_NAME,
                "/TR", f'"{exe_path}" --minimized',
                "/RL", "HIGHEST",
                "/F"  # Force (écrase si existe)
            ]
            
            logger.debug(f"Commande schtasks: {' '.join(cmd)}")
            
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=10
            )
            
            if result.returncode == 0:
                msg = "✓ Tâche planifiée créée avec succès !\nL'application se lancera automatiquement au démarrage avec droits admin (sans UAC)."
                logger.info(msg)
                return True, msg
            else:
                msg = f"Erreur lors de la création de la tâche:\n{result.stderr}"
                logger.error(msg)
                return False, msg
                
        except subprocess.TimeoutExpired:
            msg = "Timeout lors de la création de la tâche planifiée"
            logger.error(msg)
            return False, msg
            
        except Exception as e:
            msg = f"Erreur lors de la création de la tâche planifiée: {e}"
            logger.error(msg, exc_info=True)
            return False, msg
    
    def _remove_scheduled_task(self) -> Tuple[bool, str]:
        """
        Supprime la tâche planifiée Windows.
        
        Returns:
            Tuple (succès, message)
        """
        try:
            if not self._is_scheduled_task_exists():
                msg = "Tâche planifiée déjà absente"
                logger.debug(msg)
                return True, msg
            
            cmd = [
                "schtasks",
                "/Delete",
                "/TN", self.TASK_NAME,
                "/F"  # Force (pas de confirmation)
            ]
            
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=10
            )
            
            if result.returncode == 0:
                msg = "✓ Tâche planifiée supprimée"
                logger.info(msg)
                return True, msg
            else:
                msg = f"Erreur lors de la suppression de la tâche:\n{result.stderr}"
                logger.error(msg)
                return False, msg
                
        except subprocess.TimeoutExpired:
            msg = "Timeout lors de la suppression de la tâche"
            logger.error(msg)
            return False, msg
            
        except Exception as e:
            msg = f"Erreur lors de la suppression de la tâche: {e}"
            logger.error(msg, exc_info=True)
            return False, msg
    
    def get_startup_method(self) -> str:
        """
        Retourne la méthode de démarrage utilisée.
        
        Returns:
            "scheduled_task", "shortcut", ou "none"
        """
        if self._is_scheduled_task_exists():
            return "scheduled_task"
        elif self.shortcut_path.exists():
            return "shortcut"
        else:
            return "none"

