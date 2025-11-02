"""Module de détection et gestion des écrans Windows."""

import ctypes
from typing import Dict, List, Tuple

try:
    import win32api
    import win32con
except ImportError:
    print("pywin32 n'est pas installé. Exécutez: pip install pywin32")
    raise

from ..utils.logger import get_logger

logger = get_logger()


class ScreenDetector:
    """Détecteur d'écrans Windows."""
    
    def __init__(self):
        """Initialise le détecteur d'écrans."""
        self.screens: List[Dict] = []
        self.detect_screens()
    
    def detect_screens(self) -> List[Dict]:
        """
        Détecte tous les écrans connectés.
        
        Returns:
            Liste des informations d'écrans
        """
        try:
            monitors = win32api.EnumDisplayMonitors()
            temp_screens = []
            
            # Récupérer tous les moniteurs avec leurs informations
            for i, monitor in enumerate(monitors):
                monitor_info = win32api.GetMonitorInfo(monitor[0])
                monitor_data = monitor_info['Monitor']
                is_primary = monitor_info['Flags'] & win32con.MONITORINFOF_PRIMARY == win32con.MONITORINFOF_PRIMARY
                device_name = monitor_info.get('Device', f'DISPLAY{i+1}')
                
                screen_info = {
                    'enum_index': i,  # Index d'énumération original
                    'handle': monitor[0],
                    'device_name': device_name,
                    'resolution': f"{monitor_data[2] - monitor_data[0]}x{monitor_data[3] - monitor_data[1]}",
                    'width': monitor_data[2] - monitor_data[0],
                    'height': monitor_data[3] - monitor_data[1],
                    'left': monitor_data[0],
                    'top': monitor_data[1],
                    'right': monitor_data[2],
                    'bottom': monitor_data[3],
                    'is_primary': is_primary
                }
                
                temp_screens.append(screen_info)
            
            # Trier par device name pour correspondre à l'ordre des paramètres Windows
            # DISPLAY1, DISPLAY2, DISPLAY3, etc.
            temp_screens.sort(key=lambda x: x['device_name'])
            
            # Maintenant assigner les IDs et noms basés sur l'ordre trié
            self.screens = []
            for i, screen in enumerate(temp_screens):
                screen_number = i + 1
                if screen['is_primary']:
                    screen_name = f"Écran {screen_number} (Principal)"
                else:
                    screen_name = f"Écran {screen_number}"
                
                screen['id'] = i  # ID pour l'interface (1, 2, 3...)
                screen['windows_index'] = screen['enum_index']  # Index d'énumération original pour les API
                screen['name'] = screen_name
                
                self.screens.append(screen)
                
                logger.debug(f"Écran {i}: {screen['device_name']} (enum_index={screen['enum_index']})")
            
            logger.info(f"{len(self.screens)} écran(s) détecté(s)")
            for screen in self.screens:
                primary_marker = " ← ÉCRAN PRINCIPAL" if screen['is_primary'] else ""
                device_name = screen.get('device_name', 'Unknown')
                enum_idx = screen.get('windows_index', screen['id'])
                logger.info(f"  - {screen['name']}: {screen['resolution']} at ({screen['left']}, {screen['top']}) [{device_name}, enum={enum_idx}]{primary_marker}")
            
            return self.screens
            
        except Exception as e:
            logger.error(f"Erreur lors de la détection des écrans: {e}", exc_info=True)
            return []
    
    def get_screens(self) -> List[Dict]:
        """
        Récupère la liste des écrans détectés.
        
        Returns:
            Liste des écrans
        """
        return self.screens
    
    def get_screen_count(self) -> int:
        """
        Récupère le nombre d'écrans détectés.
        
        Returns:
            Nombre d'écrans
        """
        return len(self.screens)
    
    def get_primary_screen(self) -> Dict:
        """
        Récupère l'écran principal.
        
        Returns:
            Informations de l'écran principal
        """
        for screen in self.screens:
            if screen['is_primary']:
                return screen
        
        # Fallback sur le premier écran si aucun n'est marqué comme principal
        return self.screens[0] if self.screens else {}
    
    def get_screen_by_id(self, screen_id: int) -> Dict:
        """
        Récupère un écran par son ID.
        
        Args:
            screen_id: ID de l'écran
            
        Returns:
            Informations de l'écran ou dict vide si non trouvé
        """
        for screen in self.screens:
            if screen['id'] == screen_id:
                return screen
        return {}
    
    def refresh(self) -> List[Dict]:
        """
        Rafraîchit la détection des écrans.
        
        Returns:
            Liste mise à jour des écrans
        """
        logger.info("Rafraîchissement de la détection des écrans")
        return self.detect_screens()


