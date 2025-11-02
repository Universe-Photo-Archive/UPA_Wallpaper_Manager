"""Module de planification de la rotation des fonds d'écran."""

import random
import threading
import time
from pathlib import Path
from typing import Callable, Dict, List, Optional

from ..utils.logger import get_logger

logger = get_logger()


class RotationScheduler:
    """Planificateur de rotation des fonds d'écran."""
    
    def __init__(self, delay_seconds: int = 900):
        """
        Initialise le planificateur.
        
        Args:
            delay_seconds: Délai entre chaque rotation en secondes
        """
        self.delay_seconds = delay_seconds
        self.is_running = False
        self.is_paused = False
        self.thread: Optional[threading.Thread] = None
        self.playlists: Dict[int, List[str]] = {}  # {screen_id: [image_paths]}
        self.current_indices: Dict[int, int] = {}  # {screen_id: current_index}
        self.random_mode = True
        self.callback: Optional[Callable] = None
        self._stop_event = threading.Event()
    
    def set_playlist(self, screen_id: int, image_paths: List[str]) -> None:
        """
        Définit la playlist pour un écran.
        
        Args:
            screen_id: ID de l'écran
            image_paths: Liste des chemins d'images
        """
        self.playlists[screen_id] = image_paths.copy()
        self.current_indices[screen_id] = 0
        
        if self.random_mode and image_paths:
            random.shuffle(self.playlists[screen_id])
        
        logger.debug(f"Playlist définie pour l'écran {screen_id}: {len(image_paths)} images")
    
    def set_random_mode(self, enabled: bool) -> None:
        """
        Active ou désactive le mode aléatoire.
        
        Args:
            enabled: True pour activer le mode aléatoire
        """
        self.random_mode = enabled
        
        # Réorganiser les playlists existantes
        if enabled:
            for screen_id in self.playlists:
                random.shuffle(self.playlists[screen_id])
                self.current_indices[screen_id] = 0
    
    def set_delay(self, seconds: int) -> None:
        """
        Définit le délai de rotation.
        
        Args:
            seconds: Délai en secondes
        """
        self.delay_seconds = seconds
        logger.info(f"Délai de rotation défini à {seconds} secondes")
    
    def set_callback(self, callback: Callable[[int, str], None]) -> None:
        """
        Définit la fonction de callback appelée lors de chaque rotation.
        
        Args:
            callback: Fonction callback(screen_id, image_path)
        """
        self.callback = callback
    
    def get_next_image(self, screen_id: int) -> Optional[str]:
        """
        Récupère la prochaine image pour un écran.
        
        Args:
            screen_id: ID de l'écran
            
        Returns:
            Chemin de l'image suivante ou None
        """
        if screen_id not in self.playlists or not self.playlists[screen_id]:
            return None
        
        playlist = self.playlists[screen_id]
        current_index = self.current_indices.get(screen_id, 0)
        
        if current_index >= len(playlist):
            # Recommencer la playlist
            current_index = 0
            if self.random_mode:
                random.shuffle(playlist)
        
        image_path = playlist[current_index]
        self.current_indices[screen_id] = current_index + 1
        
        return image_path
    
    def start(self) -> None:
        """Démarre la rotation automatique."""
        if self.is_running:
            logger.warning("La rotation est déjà en cours")
            return
        
        self.is_running = True
        self.is_paused = False
        self._stop_event.clear()
        
        self.thread = threading.Thread(target=self._rotation_loop, daemon=True)
        self.thread.start()
        
        logger.info(f"Rotation démarrée (délai: {self.delay_seconds}s)")
    
    def stop(self) -> None:
        """Arrête la rotation automatique."""
        if not self.is_running:
            return
        
        self.is_running = False
        self._stop_event.set()
        
        if self.thread:
            self.thread.join(timeout=2)
        
        logger.info("Rotation arrêtée")
    
    def pause(self) -> None:
        """Met en pause la rotation."""
        if not self.is_running:
            return
        
        self.is_paused = True
        logger.info("Rotation mise en pause")
    
    def resume(self) -> None:
        """Reprend la rotation."""
        if not self.is_running or not self.is_paused:
            return
        
        self.is_paused = False
        logger.info("Rotation reprise")
    
    def toggle_pause(self) -> bool:
        """
        Bascule entre pause et lecture.
        
        Returns:
            True si en pause après le toggle
        """
        if self.is_paused:
            self.resume()
        else:
            self.pause()
        return self.is_paused
    
    def rotate_now(self) -> None:
        """Force une rotation immédiate."""
        logger.info("Rotation forcée")
        self._perform_rotation()
    
    def _rotation_loop(self) -> None:
        """Boucle principale de rotation (exécutée dans un thread)."""
        while self.is_running:
            # Si en pause, attendre un peu et continuer
            if self.is_paused:
                if self._stop_event.wait(timeout=1):
                    break
                continue
            
            # Attendre le délai (avec possibilité d'interruption)
            logger.debug(f"Attente de {self.delay_seconds}s avant prochaine rotation")
            if self._stop_event.wait(timeout=self.delay_seconds):
                break
            
            # Effectuer la rotation
            logger.debug("Déclenchement rotation automatique")
            self._perform_rotation()
    
    def _perform_rotation(self) -> None:
        """Effectue une rotation pour tous les écrans actifs."""
        if not self.callback:
            logger.warning("Aucun callback défini pour la rotation")
            return
        
        if not self.playlists:
            logger.warning("Aucune playlist définie pour la rotation")
            return
        
        logger.debug(f"Rotation en cours pour {len(self.playlists)} écran(s)")
        
        for screen_id in self.playlists:
            try:
                playlist = self.playlists.get(screen_id, [])
                logger.debug(f"Écran {screen_id}: playlist de {len(playlist)} images")
                
                next_image = self.get_next_image(screen_id)
                
                if next_image:
                    # Vérifier que le fichier existe
                    if Path(next_image).exists():
                        logger.debug(f"Application image écran {screen_id}: {Path(next_image).name}")
                        self.callback(screen_id, next_image)
                    else:
                        logger.warning(f"Image introuvable: {next_image}")
                        # Retirer de la playlist
                        if next_image in self.playlists[screen_id]:
                            self.playlists[screen_id].remove(next_image)
                else:
                    logger.warning(f"Aucune image disponible pour l'écran {screen_id}")
                
            except Exception as e:
                logger.error(f"Erreur lors de la rotation pour l'écran {screen_id}: {e}", exc_info=True)
    
    def get_playlist_info(self, screen_id: int) -> Dict:
        """
        Récupère les informations de la playlist d'un écran.
        
        Args:
            screen_id: ID de l'écran
            
        Returns:
            Dictionnaire avec les informations
        """
        playlist = self.playlists.get(screen_id, [])
        current_index = self.current_indices.get(screen_id, 0)
        
        return {
            'total_images': len(playlist),
            'current_index': current_index,
            'remaining': len(playlist) - current_index if playlist else 0
        }
    
    def is_active(self) -> bool:
        """
        Vérifie si la rotation est active.
        
        Returns:
            True si active (démarrée et non en pause)
        """
        return self.is_running and not self.is_paused


