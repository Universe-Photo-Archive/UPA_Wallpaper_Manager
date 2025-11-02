"""Module de gestion du lockscreen Windows."""

import os
import shutil
import winreg
from pathlib import Path
from typing import Optional

from ..utils.logger import get_logger

logger = get_logger()


class LockscreenManager:
    """Gestionnaire du lockscreen Windows."""
    
    def __init__(self):
        """Initialise le gestionnaire de lockscreen."""
        self.csp_key_path = r"SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP"
        self.windows_screen_folder = Path(r"C:\Windows\Web\Screen")
    
    def set_lockscreen(self, image_path: str) -> bool:
        """
        Définit l'image du lockscreen via PersonalizationCSP.
        
        Cette méthode utilise la clé de registre PersonalizationCSP
        qui contourne Windows Spotlight et force l'application de l'image.
        
        IMPORTANT: Nécessite des droits administrateur.
        
        Args:
            image_path: Chemin de l'image
            
        Returns:
            True si succès, False sinon
        """
        try:
            image_path = os.path.abspath(image_path)
            
            if not os.path.exists(image_path):
                logger.error(f"Image introuvable pour lockscreen: {image_path}")
                return False
            
            # S'assurer que le dossier C:\Windows\Web\Screen existe
            try:
                self.windows_screen_folder.mkdir(parents=True, exist_ok=True)
            except PermissionError:
                logger.error("❌ Droits administrateur requis pour créer le dossier lockscreen")
                return False
            
            # Copier l'image dans C:\Windows\Web\Screen avec un nom unique basé sur le timestamp
            import time
            timestamp = int(time.time())
            filename = f"Lockscreen_{timestamp}.jpg"
            lockscreen_image_path = self.windows_screen_folder / filename
            
            try:
                shutil.copy2(image_path, lockscreen_image_path)
                logger.debug(f"Image copiée dans: {lockscreen_image_path}")
            except PermissionError:
                logger.error("❌ Droits administrateur requis pour copier dans C:\\Windows\\Web\\Screen")
                return False
            
            # Mettre à jour le registre via PersonalizationCSP (HKEY_LOCAL_MACHINE)
            try:
                # Créer la clé PersonalizationCSP si elle n'existe pas
                try:
                    key = winreg.OpenKey(
                        winreg.HKEY_LOCAL_MACHINE,
                        self.csp_key_path,
                        0,
                        winreg.KEY_READ
                    )
                    winreg.CloseKey(key)
                    logger.debug("Clé PersonalizationCSP existe déjà")
                except FileNotFoundError:
                    # La clé n'existe pas, la créer
                    key = winreg.CreateKey(winreg.HKEY_LOCAL_MACHINE, self.csp_key_path)
                    winreg.CloseKey(key)
                    logger.debug("Clé PersonalizationCSP créée")
                
                # Ouvrir la clé en écriture
                key = winreg.OpenKey(
                    winreg.HKEY_LOCAL_MACHINE,
                    self.csp_key_path,
                    0,
                    winreg.KEY_SET_VALUE
                )
                
                # Définir les valeurs de registre
                lockscreen_path_str = str(lockscreen_image_path)
                
                winreg.SetValueEx(
                    key,
                    "LockScreenImagePath",
                    0,
                    winreg.REG_SZ,
                    lockscreen_path_str
                )
                
                winreg.SetValueEx(
                    key,
                    "LockScreenImageUrl",
                    0,
                    winreg.REG_SZ,
                    lockscreen_path_str
                )
                
                winreg.SetValueEx(
                    key,
                    "LockScreenImageStatus",
                    0,
                    winreg.REG_DWORD,
                    1
                )
                
                winreg.CloseKey(key)
                logger.info(f"✓ Lockscreen défini via PersonalizationCSP: {os.path.basename(image_path)}")
                return True
                
            except PermissionError:
                logger.error("❌ Droits administrateur requis pour modifier HKEY_LOCAL_MACHINE")
                logger.info("💡 Lancez l'application en tant qu'administrateur pour utiliser le lockscreen")
                return False
                
        except Exception as e:
            logger.error(f"Erreur lors de la définition du lockscreen: {e}", exc_info=True)
            return False
    
    def remove_lockscreen(self) -> bool:
        """
        Supprime la configuration PersonalizationCSP pour rendre le contrôle à l'utilisateur.
        
        IMPORTANT: Nécessite des droits administrateur.
        Sans cette suppression, Windows affichera "Géré par votre organisation"
        et l'utilisateur ne pourra plus modifier le lockscreen manuellement.
        
        Returns:
            True si succès, False sinon
        """
        try:
            # Supprimer complètement la clé PersonalizationCSP
            try:
                winreg.DeleteKey(winreg.HKEY_LOCAL_MACHINE, self.csp_key_path)
                logger.info("✓ Clé PersonalizationCSP supprimée - contrôle rendu à l'utilisateur")
                return True
                
            except FileNotFoundError:
                # La clé n'existe pas, c'est OK
                logger.debug("Clé PersonalizationCSP déjà absente")
                return True
                
            except PermissionError:
                logger.error("❌ Droits administrateur requis pour supprimer la clé PersonalizationCSP")
                logger.info("💡 Lancez l'application en tant qu'administrateur pour désactiver le lockscreen")
                return False
                
        except Exception as e:
            logger.error(f"Erreur lors de la suppression de PersonalizationCSP: {e}", exc_info=True)
            return False
    
    def disable_windows_spotlight(self) -> bool:
        """
        Désactive Windows Spotlight pour permettre le lockscreen personnalisé.
        
        Returns:
            True si succès, False sinon
        """
        try:
            # Clé pour désactiver Windows Spotlight
            personalization_key = r"SOFTWARE\Policies\Microsoft\Windows\Personalization"
            
            try:
                key = winreg.CreateKey(winreg.HKEY_CURRENT_USER, personalization_key)
                
                # Désactiver le lockscreen dynamique (Windows Spotlight)
                winreg.SetValueEx(key, "NoLockScreen", 0, winreg.REG_DWORD, 0)
                winreg.SetValueEx(key, "LockScreenOverlaysDisabled", 0, winreg.REG_DWORD, 1)
                
                winreg.CloseKey(key)
                logger.info("✓ Windows Spotlight désactivé pour le lockscreen")
                return True
                
            except PermissionError:
                logger.warning("Permissions insuffisantes pour désactiver Windows Spotlight")
                return False
                
        except Exception as e:
            logger.error(f"Erreur lors de la désactivation de Windows Spotlight: {e}")
            return False
    
    def get_current_lockscreen(self) -> Optional[str]:
        """
        Récupère le chemin de l'image du lockscreen actuel.
        
        Returns:
            Chemin de l'image ou None
        """
        try:
            key = winreg.OpenKey(
                winreg.HKEY_CURRENT_USER,
                self.registry_key_path,
                0,
                winreg.KEY_READ
            )
            
            lockscreen_image, _ = winreg.QueryValueEx(key, "LockScreenImage")
            winreg.CloseKey(key)
            
            return lockscreen_image if lockscreen_image else None
            
        except Exception as e:
            logger.debug(f"Impossible de récupérer le lockscreen actuel: {e}")
            return None

