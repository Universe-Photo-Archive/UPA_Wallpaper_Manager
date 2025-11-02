"""Module de gestion des fonds d'écran Windows."""

import ctypes
import os
from pathlib import Path
from typing import Dict, Optional

try:
    import win32api
    import win32con
    import win32gui
except ImportError:
    print("pywin32 n'est pas installé. Exécutez: pip install pywin32")
    raise

from PIL import Image

from ..utils.logger import get_logger

logger = get_logger()

# Définition de l'interface IDesktopWallpaper pour comtypes
try:
    import comtypes
    from comtypes import GUID, COMMETHOD, HRESULT
    from ctypes import POINTER, c_uint, c_wchar_p
    from ctypes.wintypes import DWORD, RECT
    
    class IDesktopWallpaper(comtypes.IUnknown):
        _iid_ = GUID("{B92B56A9-8B55-4E14-9A89-0199BBB6F93B}")
        _methods_ = [
            COMMETHOD([], HRESULT, 'SetWallpaper',
                      (['in'], c_wchar_p, 'monitorID'),
                      (['in'], c_wchar_p, 'wallpaper')),
            COMMETHOD([], HRESULT, 'GetWallpaper',
                      (['in'], c_wchar_p, 'monitorID'),
                      (['out'], POINTER(c_wchar_p), 'wallpaper')),
            COMMETHOD([], HRESULT, 'GetMonitorDevicePathAt',
                      (['in'], c_uint, 'monitorIndex'),
                      (['out'], POINTER(c_wchar_p), 'monitorID')),
            COMMETHOD([], HRESULT, 'GetMonitorDevicePathCount',
                      (['out'], POINTER(c_uint), 'count')),
            COMMETHOD([], HRESULT, 'GetMonitorRECT',
                      (['in'], c_wchar_p, 'monitorID'),
                      (['out'], POINTER(RECT), 'displayRect')),
            COMMETHOD([], HRESULT, 'SetBackgroundColor',
                      (['in'], DWORD, 'color')),
            COMMETHOD([], HRESULT, 'GetBackgroundColor',
                      (['out'], POINTER(DWORD), 'color')),
            COMMETHOD([], HRESULT, 'SetPosition',
                      (['in'], c_uint, 'position')),
            COMMETHOD([], HRESULT, 'GetPosition',
                      (['out'], POINTER(c_uint), 'position')),
            COMMETHOD([], HRESULT, 'SetSlideshow',
                      (['in'], c_wchar_p, 'items')),
            COMMETHOD([], HRESULT, 'GetSlideshow',
                      (['out'], POINTER(c_wchar_p), 'items')),
            COMMETHOD([], HRESULT, 'SetSlideshowOptions',
                      (['in'], c_uint, 'options'),
                      (['in'], c_uint, 'slideshowTick')),
            COMMETHOD([], HRESULT, 'GetSlideshowOptions',
                      (['out'], POINTER(c_uint), 'options'),
                      (['out'], POINTER(c_uint), 'slideshowTick')),
            COMMETHOD([], HRESULT, 'AdvanceSlideshow',
                      (['in'], c_wchar_p, 'monitorID'),
                      (['in'], c_uint, 'direction')),
            COMMETHOD([], HRESULT, 'GetStatus',
                      (['out'], POINTER(c_uint), 'state')),
            COMMETHOD([], HRESULT, 'Enable',
                      (['in'], c_uint, 'enable')),
        ]
    
    COMTYPES_AVAILABLE = True
except ImportError:
    COMTYPES_AVAILABLE = False
    logger.debug("comtypes non disponible")


class WallpaperManager:
    """Gestionnaire de fonds d'écran Windows."""
    
    # Styles d'affichage Windows
    STYLE_FILL = 10  # Remplir
    STYLE_FIT = 6    # Ajuster
    STYLE_STRETCH = 2  # Étirer
    STYLE_CENTER = 0   # Centrer
    STYLE_TILE = 1     # Mosaïque
    STYLE_SPAN = 22    # Étendre (multi-moniteurs)
    
    STYLE_MAP = {
        'fill': STYLE_FILL,
        'fit': STYLE_FIT,
        'stretch': STYLE_STRETCH,
        'center': STYLE_CENTER,
        'tile': STYLE_TILE,
        'span': STYLE_SPAN
    }
    
    def __init__(self):
        """Initialise le gestionnaire de fonds d'écran."""
        self.SPI_SETDESKWALLPAPER = 20
        self.SPIF_UPDATEINIFILE = 0x01
        self.SPIF_SENDCHANGE = 0x02
        
        # Essayer d'initialiser l'API moderne IDesktopWallpaper (Windows 10+)
        self.desktop_wallpaper = None
        if COMTYPES_AVAILABLE:
            try:
                import comtypes.client
                # CLSID de DesktopWallpaper
                desktop_wallpaper_clsid = GUID("{C2CF3110-460E-4fc1-B9D0-8A1C0C9CC4BD}")
                self.desktop_wallpaper = comtypes.client.CreateObject(
                    desktop_wallpaper_clsid,
                    interface=IDesktopWallpaper
                )
                logger.info("✓ API moderne IDesktopWallpaper disponible (multi-moniteurs natif)")
            except Exception as e:
                logger.warning(f"API IDesktopWallpaper non disponible, utilisation du mode composite: {e}")
        else:
            logger.info("comtypes non installé, utilisation du mode composite")
    
    def set_wallpaper(
        self,
        image_path: str,
        screen_id: Optional[int] = None,
        fit_mode: str = 'fill',
        is_composite: bool = False
    ) -> bool:
        """
        Définit le fond d'écran.
        
        Args:
            image_path: Chemin de l'image
            screen_id: ID de l'écran (si None, applique à tous les écrans)
            fit_mode: Mode d'ajustement ('fill', 'fit', 'stretch', 'center', 'tile', 'span')
            is_composite: True si c'est une image composite multi-moniteurs
            
        Returns:
            True si succès, False sinon
        """
        try:
            # Vérifier que le fichier existe
            image_path = os.path.abspath(image_path)
            if not os.path.exists(image_path):
                logger.error(f"Le fichier n'existe pas: {image_path}")
                return False
            
            # Si API moderne disponible ET screen_id spécifié, utiliser IDesktopWallpaper
            if self.desktop_wallpaper is not None and screen_id is not None:
                return self._set_wallpaper_per_monitor(image_path, screen_id)
            
            # Sinon, utiliser l'API classique (tous les écrans)
            # Pour un composite multi-moniteurs, forcer le mode "span"
            if is_composite:
                style_value = self.STYLE_SPAN
                logger.info("Mode SPAN activé pour composite multi-moniteurs")
            else:
                style_value = self.STYLE_MAP.get(fit_mode, self.STYLE_FILL)
            
            self._set_wallpaper_style(style_value)
            
            # Appliquer le fond d'écran
            result = ctypes.windll.user32.SystemParametersInfoW(
                self.SPI_SETDESKWALLPAPER,
                0,
                image_path,
                self.SPIF_UPDATEINIFILE | self.SPIF_SENDCHANGE
            )
            
            if result:
                mode_name = "span" if is_composite else fit_mode
                logger.info(f"Fond d'écran appliqué: {os.path.basename(image_path)} (mode: {mode_name})")
                return True
            else:
                logger.error(f"Échec de l'application du fond d'écran: {image_path}")
                return False
                
        except Exception as e:
            logger.error(f"Erreur lors de l'application du fond d'écran: {e}", exc_info=True)
            return False
    
    def _set_wallpaper_per_monitor(self, image_path: str, screen_id: int) -> bool:
        """
        Définit le fond d'écran pour un moniteur spécifique (Windows 10+).
        
        Args:
            image_path: Chemin de l'image
            screen_id: ID de l'écran
            
        Returns:
            True si succès
        """
        try:
            # Initialiser COM pour ce thread si nécessaire
            import pythoncom
            try:
                pythoncom.CoInitialize()
                logger.debug("COM initialisé pour ce thread")
            except Exception:
                # Déjà initialisé, pas grave
                pass
            
            # Créer une nouvelle instance COM pour ce thread
            # (les objets COM ne peuvent pas être partagés entre threads)
            import comtypes.client
            desktop_wallpaper = comtypes.client.CreateObject(
                GUID("{C2CF3110-460E-4fc1-B9D0-8A1C0C9CC4BD}"),
                interface=IDesktopWallpaper
            )
            
            # Récupérer les informations de l'écran pour les logs
            from .screen_detector import ScreenDetector
            detector = ScreenDetector()
            screens = detector.get_screens()
            
            # Trouver l'écran correspondant
            screen_info = None
            for screen in screens:
                if screen['id'] == screen_id:
                    screen_info = screen
                    break
            
            if screen_info is None:
                logger.error(f"Écran avec ID {screen_id} introuvable")
                return False
            
            device_name = screen_info.get('device_name', 'Unknown')
            
            # Récupérer le nombre de moniteurs via l'interface COM
            monitor_count = desktop_wallpaper.GetMonitorDevicePathCount()
            logger.debug(f"Nombre de moniteurs détectés par COM: {monitor_count}")
            
            if screen_id >= monitor_count:
                logger.error(f"Screen ID {screen_id} invalide (max: {monitor_count-1})")
                return False
            
            # IMPORTANT : GetMonitorDevicePathAt() retourne les moniteurs dans l'ordre
            # DISPLAY1, DISPLAY2, DISPLAY3... (ordre alphabétique/trié)
            # qui correspond à notre screen_id après tri par device_name !
            # Donc on utilise directement screen_id, pas windows_index
            monitor_id = desktop_wallpaper.GetMonitorDevicePathAt(screen_id)
            logger.debug(f"Device path pour screen_id {screen_id}: {monitor_id}")
            
            # Définir le fond d'écran pour ce moniteur
            desktop_wallpaper.SetWallpaper(monitor_id, image_path)
            
            logger.info(f"✓ Fond d'écran appliqué sur écran {screen_id} ({device_name}): {os.path.basename(image_path)}")
            return True
            
        except Exception as e:
            logger.error(f"Erreur IDesktopWallpaper: {e}", exc_info=True)
            return False
    
    def _set_wallpaper_style(self, style: int) -> None:
        """
        Définit le style d'affichage du fond d'écran dans le registre Windows.
        
        Args:
            style: Valeur du style
        """
        try:
            import winreg
            
            key = winreg.OpenKey(
                winreg.HKEY_CURRENT_USER,
                r"Control Panel\Desktop",
                0,
                winreg.KEY_SET_VALUE
            )
            
            if style == self.STYLE_TILE:
                winreg.SetValueEx(key, "WallpaperStyle", 0, winreg.REG_SZ, "0")
                winreg.SetValueEx(key, "TileWallpaper", 0, winreg.REG_SZ, "1")
            elif style == self.STYLE_CENTER:
                winreg.SetValueEx(key, "WallpaperStyle", 0, winreg.REG_SZ, "0")
                winreg.SetValueEx(key, "TileWallpaper", 0, winreg.REG_SZ, "0")
            elif style == self.STYLE_STRETCH:
                winreg.SetValueEx(key, "WallpaperStyle", 0, winreg.REG_SZ, "2")
                winreg.SetValueEx(key, "TileWallpaper", 0, winreg.REG_SZ, "0")
            elif style == self.STYLE_FIT:
                winreg.SetValueEx(key, "WallpaperStyle", 0, winreg.REG_SZ, "6")
                winreg.SetValueEx(key, "TileWallpaper", 0, winreg.REG_SZ, "0")
            elif style == self.STYLE_FILL:
                winreg.SetValueEx(key, "WallpaperStyle", 0, winreg.REG_SZ, "10")
                winreg.SetValueEx(key, "TileWallpaper", 0, winreg.REG_SZ, "0")
            elif style == self.STYLE_SPAN:
                # Mode SPAN (22) : étend l'image sur tous les moniteurs
                winreg.SetValueEx(key, "WallpaperStyle", 0, winreg.REG_SZ, "22")
                winreg.SetValueEx(key, "TileWallpaper", 0, winreg.REG_SZ, "0")
            
            winreg.CloseKey(key)
            
            logger.debug(f"Style de fond d'écran défini : {style}")
            
        except Exception as e:
            logger.warning(f"Impossible de définir le style dans le registre: {e}")
    
    def get_current_wallpaper(self) -> Optional[str]:
        """
        Récupère le chemin du fond d'écran actuel.
        
        Returns:
            Chemin du fond d'écran ou None
        """
        try:
            import winreg
            
            key = winreg.OpenKey(
                winreg.HKEY_CURRENT_USER,
                r"Control Panel\Desktop",
                0,
                winreg.KEY_READ
            )
            
            wallpaper, _ = winreg.QueryValueEx(key, "Wallpaper")
            winreg.CloseKey(key)
            
            return wallpaper if wallpaper else None
            
        except Exception as e:
            logger.warning(f"Impossible de récupérer le fond d'écran actuel: {e}")
            return None
    
    def validate_image(self, image_path: str) -> bool:
        """
        Valide qu'une image est utilisable comme fond d'écran.
        
        Args:
            image_path: Chemin de l'image
            
        Returns:
            True si valide, False sinon
        """
        try:
            if not os.path.exists(image_path):
                return False
            
            # Vérifier que c'est une image valide
            with Image.open(image_path) as img:
                img.verify()
            
            return True
            
        except Exception as e:
            logger.warning(f"Image invalide {image_path}: {e}")
            return False
    
    def create_multi_screen_wallpaper(
        self,
        screens: list,
        image_paths: Dict[int, str],
        output_path: str
    ) -> Optional[str]:
        """
        Crée une image composite pour gérer plusieurs écrans.
        
        Args:
            screens: Liste des informations d'écrans
            image_paths: Dictionnaire {screen_id: image_path}
            output_path: Chemin de sortie de l'image composite
            
        Returns:
            Chemin de l'image composite créée ou None
        """
        try:
            # Calculer les bornes exactes selon les positions Windows
            min_x = min(s['left'] for s in screens)
            min_y = min(s['top'] for s in screens)
            max_x = max(s['right'] for s in screens)
            max_y = max(s['bottom'] for s in screens)
            
            total_width = max_x - min_x
            total_height = max_y - min_y
            
            logger.info("=== CRÉATION FOND D'ÉCRAN MULTI-MONITEURS ===")
            logger.info(f"Espace virtuel Windows : {total_width}x{total_height}")
            for screen in screens:
                width = screen['right'] - screen['left']
                height = screen['bottom'] - screen['top']
                logger.info(f"  Écran {screen['id']}: {width}x{height} à position ({screen['left']}, {screen['top']})")
            
            # Créer l'image composite avec les positions RÉELLES de Windows
            composite = Image.new('RGB', (total_width, total_height), (0, 0, 0))
            
            # Placer chaque image à sa position EXACTE dans l'espace virtuel Windows
            for screen in screens:
                screen_id = screen['id']
                if screen_id in image_paths:
                    img_path = image_paths[screen_id]
                    
                    if os.path.exists(img_path):
                        with Image.open(img_path) as img:
                            screen_width = screen['right'] - screen['left']
                            screen_height = screen['bottom'] - screen['top']
                            
                            # Redimensionner l'image en mode "fill" (couvrir tout l'écran)
                            img_ratio = img.width / img.height
                            screen_ratio = screen_width / screen_height
                            
                            if img_ratio > screen_ratio:
                                # Image plus large : ajuster sur la hauteur
                                new_height = screen_height
                                new_width = int(new_height * img_ratio)
                            else:
                                # Image plus haute : ajuster sur la largeur
                                new_width = screen_width
                                new_height = int(new_width / img_ratio)
                            
                            img_resized = img.resize((new_width, new_height), Image.Resampling.LANCZOS)
                            
                            # Centrer et rogner
                            left = (new_width - screen_width) // 2
                            top = (new_height - screen_height) // 2
                            img_cropped = img_resized.crop((left, top, left + screen_width, top + screen_height))
                            
                            # Placer à la position EXACTE de l'écran dans Windows
                            x = screen['left'] - min_x
                            y = screen['top'] - min_y
                            composite.paste(img_cropped, (x, y))
                            
                            logger.info(f"  ✓ Image {screen_id} placée à ({x}, {y}), taille {screen_width}x{screen_height}")
            
            # Sauvegarder
            os.makedirs(os.path.dirname(output_path), exist_ok=True)
            composite.save(output_path, 'JPEG', quality=95)
            
            logger.info(f"✓ Composite créé : {output_path} ({total_width}x{total_height})")
            logger.info("=" * 50)
            return output_path
            
        except Exception as e:
            logger.error(f"Erreur lors de la création de l'image composite: {e}", exc_info=True)
            return None


