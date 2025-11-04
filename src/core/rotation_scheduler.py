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
    
    def __init__(self, delay_seconds: int = 900, smart_cache_manager=None):
        """
        Initialise le planificateur.
        
        Args:
            delay_seconds: Délai entre chaque rotation en secondes
            smart_cache_manager: Gestionnaire de cache intelligent pour le téléchargement à la demande
        """
        self.delay_seconds = delay_seconds
        self.is_running = False
        self.is_paused = False
        self.thread: Optional[threading.Thread] = None
        self.playlists: Dict[int, List[str]] = {}  # {screen_id: [image_paths]}
        self.theme_configs: Dict[int, Dict] = {}  # {screen_id: {theme, images_metadata}}
        self.current_indices: Dict[int, int] = {}  # {screen_id: current_index}
        self.current_wallpapers: Dict[int, str] = {}  # {screen_id: current_filename}
        self.current_themes: Dict[int, str] = {}  # {screen_id: current_theme_name}
        self.random_mode = True
        self.callback: Optional[Callable] = None
        self.smart_cache = smart_cache_manager
        self._stop_event = threading.Event()
    
    def set_playlist(self, screen_id: int, image_paths: List[str]) -> None:
        """
        Définit la playlist pour un écran (méthode legacy pour compatibilité).
        
        Args:
            screen_id: ID de l'écran
            image_paths: Liste des chemins d'images
        """
        self.playlists[screen_id] = image_paths.copy()
        self.current_indices[screen_id] = 0
    
    def set_theme_config(self, screen_id: int, theme_name: str, images_metadata: List[Dict]) -> None:
        """
        Définit la configuration du thème pour un écran (avec téléchargement progressif).
        
        Args:
            screen_id: ID de l'écran
            theme_name: Nom du thème
            images_metadata: Liste des métadonnées d'images (avec 'url', 'filename', etc.)
        """
        self.theme_configs[screen_id] = {
            'theme': theme_name,
            'images': images_metadata.copy()
        }
        self.current_indices[screen_id] = 0
        logger.info(f"Configuration du thème '{theme_name}' pour écran {screen_id}: {len(images_metadata)} images disponibles")
    
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
    
    def _extract_theme_from_path(self, image_path: str) -> str:
        """
        Extrait le nom du thème depuis le chemin de l'image.
        
        Args:
            image_path: Chemin de l'image (ex: data/wallpapers/Earth/image.jpg)
            
        Returns:
            Nom du thème ou "Unknown"
        """
        try:
            path_parts = Path(image_path).parts
            # Chercher "wallpapers" dans le chemin
            if "wallpapers" in path_parts:
                wallpapers_index = path_parts.index("wallpapers")
                if wallpapers_index + 1 < len(path_parts):
                    return path_parts[wallpapers_index + 1]
            return "Unknown"
        except Exception:
            return "Unknown"
    
    def get_next_image(self, screen_id: int) -> Optional[str]:
        """
        Récupère la prochaine image pour un écran (évite les doublons entre écrans).
        
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
        
        # Récupérer les images et thèmes actuellement affichés sur les autres écrans
        currently_displayed_filenames = set()
        currently_displayed_themes = set()
        for other_screen_id, current_filename in self.current_wallpapers.items():
            if other_screen_id != screen_id:
                currently_displayed_filenames.add(current_filename)
        
        for other_screen_id, current_theme in self.current_themes.items():
            if other_screen_id != screen_id:
                currently_displayed_themes.add(current_theme)
        
        if currently_displayed_themes:
            logger.info(f"📋 Thèmes actuellement affichés sur d'autres écrans: {currently_displayed_themes}")
        
        # Essayer de trouver une image différente de celles affichées sur d'autres écrans
        # ET d'un thème différent (pour le mode "Tous les thèmes")
        max_attempts = len(playlist)
        for attempt in range(max_attempts):
            image_path = playlist[current_index]
            filename = Path(image_path).name
            theme_name = self._extract_theme_from_path(image_path)
            
            # Vérifier que l'image n'est pas affichée sur un autre écran
            if filename in currently_displayed_filenames:
                current_index = (current_index + 1) % len(playlist)
                logger.debug(f"Image {filename} déjà sur un autre écran, essai suivante")
                continue
            
            # Vérifier que le thème n'est pas affiché sur un autre écran (pour "Tous les thèmes")
            if theme_name in currently_displayed_themes:
                current_index = (current_index + 1) % len(playlist)
                logger.info(f"⚠️ Thème '{theme_name}' déjà affiché sur un autre écran, recherche d'un autre thème...")
                continue
            
            # Image et thème OK, on peut l'utiliser
            self.current_indices[screen_id] = current_index + 1
            logger.info(f"✓ Thème '{theme_name}' sélectionné pour écran {screen_id} (différent des autres écrans)")
            return image_path
        
        # Si aucune image ne satisfait les critères, prendre n'importe laquelle
        logger.warning(f"⚠️ Impossible de trouver une image sans doublon de thème, autorisation d'un doublon temporaire")
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
        
        if not self.playlists and not self.theme_configs:
            logger.warning("Aucune configuration définie pour la rotation")
            return
        
        # Combiner les deux systèmes
        screens_to_rotate = set(list(self.playlists.keys()) + list(self.theme_configs.keys()))
        
        logger.debug(f"Rotation en cours pour {len(screens_to_rotate)} écran(s)")
        
        for screen_id in screens_to_rotate:
            try:
                next_image_path = None
                
                # Essayer d'abord le nouveau système avec téléchargement progressif
                if screen_id in self.theme_configs and self.smart_cache:
                    next_image_path = self._get_next_image_with_download(screen_id)
                
                # Fallback sur l'ancien système si le nouveau échoue ou n'est pas configuré
                if not next_image_path and screen_id in self.playlists:
                    next_image_path = self.get_next_image(screen_id)
                
                if next_image_path:
                    # Vérifier que le fichier existe
                    if Path(next_image_path).exists():
                        filename = Path(next_image_path).name
                        theme_from_path = self._extract_theme_from_path(next_image_path)
                        
                        logger.debug(f"Application image écran {screen_id}: {filename} (thème: {theme_from_path})")
                        self.callback(screen_id, next_image_path)
                        
                        # Enregistrer l'image et le thème actuellement affichés sur cet écran
                        self.current_wallpapers[screen_id] = filename
                        self.current_themes[screen_id] = theme_from_path
                        
                        # Marquer l'image comme affichée dans le cache intelligent
                        if self.smart_cache and screen_id in self.theme_configs:
                            theme_name = self.theme_configs[screen_id]['theme']
                            self.smart_cache.mark_as_displayed(theme_name, next_image_path)
                            logger.debug(f"Image marquée comme affichée: {filename}")
                    else:
                        logger.warning(f"Image introuvable: {next_image_path}")
                else:
                    logger.warning(f"Aucune image disponible pour l'écran {screen_id}")
                
            except Exception as e:
                logger.error(f"Erreur lors de la rotation pour l'écran {screen_id}: {e}", exc_info=True)
    
    def _get_next_image_with_download(self, screen_id: int) -> Optional[str]:
        """
        Récupère la prochaine image avec téléchargement automatique si nécessaire.
        
        Args:
            screen_id: ID de l'écran
            
        Returns:
            Chemin local de l'image, ou None si échec
        """
        if screen_id not in self.theme_configs:
            return None
        
        theme_config = self.theme_configs[screen_id]
        theme_name = theme_config['theme']
        images_metadata = theme_config['images']
        
        if not images_metadata:
            logger.warning(f"Aucune image disponible pour le thème '{theme_name}'")
            return None
        
        # Récupérer les images et thèmes actuellement affichés sur les autres écrans
        currently_displayed_on_other_screens = set()
        currently_displayed_themes_on_other_screens = set()
        
        for other_screen_id, current_filename in self.current_wallpapers.items():
            if other_screen_id != screen_id:  # Exclure l'écran actuel
                currently_displayed_on_other_screens.add(current_filename)
        
        for other_screen_id, current_theme in self.current_themes.items():
            if other_screen_id != screen_id:
                currently_displayed_themes_on_other_screens.add(current_theme)
        
        logger.debug(f"Images actuellement affichées sur d'autres écrans: {currently_displayed_on_other_screens}")
        logger.debug(f"Thèmes actuellement affichés sur d'autres écrans: {currently_displayed_themes_on_other_screens}")
        
        # Filtrer les images déjà affichées pour ce cycle ET celles affichées sur d'autres écrans
        undisplayed_images = []
        for img in images_metadata:
            filename = img.get('filename', '')
            if not filename:
                continue
            
            # Vérifier si l'image est affichée sur un autre écran
            if filename in currently_displayed_on_other_screens:
                logger.debug(f"Image {filename} déjà affichée sur un autre écran, ignorée")
                continue
            
            # Vérifier si l'image a déjà été affichée dans ce cycle
            if self.smart_cache:
                is_displayed = self.smart_cache.is_image_displayed(theme_name, filename)
                if not is_displayed:
                    undisplayed_images.append(img)
            else:
                undisplayed_images.append(img)
        
        logger.debug(f"Images non affichées pour '{theme_name}': {len(undisplayed_images)}/{len(images_metadata)}")
        
        # Si toutes les images non affichées sont sur d'autres écrans, autoriser les doublons
        if not undisplayed_images:
            # Vérifier si c'est parce que le cycle est terminé ou juste des doublons
            total_undisplayed = sum(1 for img in images_metadata 
                                   if not self.smart_cache.is_image_displayed(theme_name, img.get('filename', ''))
                                   if self.smart_cache)
            
            if total_undisplayed == 0:
                # Cycle vraiment terminé
                logger.info(f"🔄 Cycle terminé pour '{theme_name}' ! Réinitialisation...")
                if self.smart_cache:
                    self.smart_cache.reset_cycle(theme_name)
                # Toutes les images sont maintenant disponibles à nouveau
                undisplayed_images = [img for img in images_metadata 
                                     if img.get('filename') not in currently_displayed_on_other_screens]
                logger.info(f"Nouveau cycle commencé, {len(undisplayed_images)} images disponibles")
            else:
                # Des images sont dispo mais affichées sur d'autres écrans
                # Dans ce cas, on autorise un doublon temporaire
                logger.warning(f"Toutes les images non affichées sont sur d'autres écrans, sélection parmi toutes")
                undisplayed_images = [img for img in images_metadata 
                                     if not self.smart_cache.is_image_displayed(theme_name, img.get('filename', ''))
                                     if self.smart_cache]
                
                # Si vraiment aucune image dispo, autoriser n'importe quelle image
                if not undisplayed_images:
                    undisplayed_images = images_metadata.copy()
        
        # Sélectionner l'image suivante parmi les images non affichées
        if self.random_mode:
            # Mode aléatoire
            image_metadata = random.choice(undisplayed_images)
        else:
            # Mode séquentiel
            current_index = self.current_indices.get(screen_id, 0)
            image_metadata = undisplayed_images[current_index % len(undisplayed_images)]
            self.current_indices[screen_id] = (current_index + 1) % len(undisplayed_images)
        
        filename = image_metadata.get('filename', '')
        url = image_metadata.get('url', '')
        
        if not filename or not url:
            logger.error(f"Métadonnées invalides pour l'image: {image_metadata}")
            return None
        
        logger.debug(f"Image sélectionnée pour écran {screen_id}: {filename}")
        
        # Vérifier si l'image est déjà téléchargée localement
        if self.smart_cache:
            local_path = self.smart_cache.get_image_local_path(theme_name, filename)
            
            if local_path and Path(local_path).exists():
                logger.debug(f"Image déjà en cache: {filename}")
                # Ne pas marquer ici, ce sera fait après l'application du fond d'écran
                return local_path
            
            # Image pas encore téléchargée, télécharger maintenant
            logger.info(f"📥 Téléchargement de l'image {filename} pour le thème '{theme_name}'...")
            
            try:
                downloaded_path = self.smart_cache.download_single_image(
                    theme_name=theme_name,
                    image_url=url,
                    filename=filename
                )
                
                if downloaded_path and Path(downloaded_path).exists():
                    logger.info(f"✓ Image téléchargée avec succès: {filename}")
                    # Ne pas marquer ici, ce sera fait après l'application du fond d'écran
                    return downloaded_path
                else:
                    logger.error(f"Échec du téléchargement de {filename}")
                    return None
                    
            except Exception as e:
                logger.error(f"Erreur lors du téléchargement de {filename}: {e}", exc_info=True)
                return None
        else:
            logger.error("SmartCacheManager non disponible pour le téléchargement")
            return None
    
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


