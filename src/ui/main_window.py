"""Fenêtre principale de l'application."""

import os
import sys
import threading
from pathlib import Path
from typing import Dict, List, Optional

import customtkinter as ctk

from ..core.screen_detector import ScreenDetector
from ..core.wallpaper_manager import WallpaperManager
from ..core.lockscreen_manager import LockscreenManager
from ..core.rotation_scheduler import RotationScheduler
from ..scraper.universe_scraper import UniverseScraper
from ..scraper.image_downloader import ImageDownloader
from ..utils.config_manager import ConfigManager
from ..utils.translation_manager import TranslationManager
from ..utils.smart_cache_manager import SmartCacheManager
from ..utils.system_tray import SystemTrayManager
from ..utils.update_manager import UpdateManager
from ..utils.logger import get_logger
from .screen_config import ScreenConfigWidget
from .settings_dialog import SettingsDialog

logger = get_logger()


class MainWindow(ctk.CTk):
    """Fenêtre principale de l'application."""
    
    def __init__(self, start_minimized: bool = False):
        """
        Initialise la fenêtre principale.
        
        Args:
            start_minimized: Si True, démarre l'application réduite dans le tray
        """
        super().__init__()
        
        # Configuration de la fenêtre
        self.title("UPA Wallpaper Manager")
        self.geometry("900x700")
        
        # Définir l'icône de l'application
        try:
            import tkinter as tk
            
            # Déterminer le chemin des assets
            if getattr(sys, 'frozen', False) and hasattr(sys, '_MEIPASS'):
                # Mode .exe compilé
                base_path = Path(sys._MEIPASS)
            else:
                # Mode développement
                base_path = Path(__file__).parent.parent.parent
            
            icon_path = base_path / "assets" / "favicon.png"
            if icon_path.exists():
                icon_img = tk.PhotoImage(file=str(icon_path))
                self.iconphoto(True, icon_img)
                # Garder une référence pour éviter la garbage collection
                self._icon_img = icon_img
                logger.info(f"Icône de l'application définie: {icon_path}")
            else:
                logger.warning(f"Icône non trouvée: {icon_path}")
        except Exception as e:
            logger.warning(f"Impossible de définir l'icône: {e}")
        
        # Composants
        self.config_manager = ConfigManager()
        self.translation_manager = TranslationManager(self.config_manager)
        self.screen_detector = ScreenDetector()
        self.wallpaper_manager = WallpaperManager()
        self.lockscreen_manager = LockscreenManager()
        self.scraper = UniverseScraper(
            rate_limit_seconds=self.config_manager.get('network.rate_limit_seconds', 1),
            timeout_seconds=self.config_manager.get('network.timeout_seconds', 10)
        )
        self.image_downloader = ImageDownloader()
        self.smart_cache = SmartCacheManager(
            cache_dir=Path("data/wallpapers"),
            max_cached_images=25,
            prefetch_count=10
        )
        # Initialiser le rotation_scheduler APRÈS smart_cache pour lui passer en paramètre
        self.rotation_scheduler = RotationScheduler(smart_cache_manager=self.smart_cache)
        # Gestionnaire de mises à jour
        self.update_manager = UpdateManager(self.config_manager)
        
        # Nettoyer le cache au démarrage si nécessaire
        logger.info("Vérification du cache au démarrage...")
        self.smart_cache.cleanup_old_images()
        
        # System tray
        self.system_tray = SystemTrayManager(
            on_show=self._show_window,
            on_quit=self._quit_application,
            on_rotate_now=self._apply_now,
            on_toggle_pause=self._toggle_pause
        )
        
        # Données
        self.themes: List[str] = []
        self.theme_urls: Dict[str, str] = {}  # Stocke les URLs des thèmes
        self.theme_images: Dict[str, List[Dict]] = {}
        self.screen_widgets: List[ScreenConfigWidget] = []
        self.is_online = False
        self.is_hidden = False  # Pour savoir si la fenêtre est cachée dans le tray
        
        # Configuration du scheduler
        self.rotation_scheduler.set_callback(self._on_rotation_callback)
        
        # Appliquer le thème
        self._apply_theme()
        
        # Setup UI
        self._setup_ui()
        
        # Charger les données
        self._initialize_app()
        
        # Démarrer le system tray
        self.system_tray.start()
        
        # Protocole de fermeture (minimiser dans le tray au lieu de fermer)
        self.protocol("WM_DELETE_WINDOW", self._on_closing)
        
        logger.info("Fenêtre principale initialisée")
        
        # Vérifier les mises à jour au démarrage (après un court délai)
        if not start_minimized:
            self.after(2000, self._check_for_updates_on_startup)
        
        # Si démarrage réduit demandé, cacher la fenêtre immédiatement
        if start_minimized:
            logger.info("Démarrage en mode réduit")
            # Attendre que la fenêtre soit complètement créée avant de la cacher
            self.after(500, self._minimize_to_tray_on_startup)
    
    def _apply_theme(self) -> None:
        """Applique le thème de l'interface."""
        ui_theme = self.config_manager.get('general.ui_theme', 'dark')
        
        if ui_theme == 'light':
            ctk.set_appearance_mode("light")
        else:
            # Par défaut : sombre
            ctk.set_appearance_mode("dark")
    
    def _setup_banner(self) -> None:
        """Affiche la bannière du site."""
        try:
            from PIL import Image
            
            # Déterminer le chemin des assets
            if getattr(sys, 'frozen', False) and hasattr(sys, '_MEIPASS'):
                # Mode .exe compilé
                base_path = Path(sys._MEIPASS)
            else:
                # Mode développement
                base_path = Path(__file__).parent.parent.parent
            
            # Choisir la bonne bannière selon le thème
            ui_theme = self.config_manager.get('general.ui_theme', 'dark')
            if ui_theme == 'light':
                banner_path = base_path / "assets" / "logo_black.png"
            else:
                banner_path = base_path / "assets" / "logo_white.png"
            
            if banner_path.exists():
                # Charger l'image
                banner_img = Image.open(banner_path)
                
                # Calculer la hauteur pour garder les proportions (largeur max 533px = 2/3 de 800px)
                max_width = 533
                ratio = max_width / banner_img.width
                new_height = int(banner_img.height * ratio)
                
                # Créer l'image CTk
                banner_ctk = ctk.CTkImage(
                    light_image=banner_img,
                    dark_image=banner_img,
                    size=(max_width, new_height)
                )
                
                # Frame pour la bannière
                banner_frame = ctk.CTkFrame(self)
                banner_frame.pack(fill="x", padx=20, pady=(0, 10))
                
                # Label avec l'image
                banner_label = ctk.CTkLabel(banner_frame, image=banner_ctk, text="")
                banner_label.pack(pady=10)
                
                logger.info(f"Bannière chargée: {banner_path}")
            else:
                logger.warning(f"Bannière non trouvée: {banner_path}")
                
        except Exception as e:
            logger.error(f"Erreur lors du chargement de la bannière: {e}", exc_info=True)
    
    def _setup_ui(self) -> None:
        """Configure l'interface utilisateur."""
        # En-tête
        header = ctk.CTkFrame(self)
        header.pack(fill="x", padx=20, pady=20)
        
        # Charger l'icône favicon
        try:
            from PIL import Image
            
            # Déterminer le chemin des assets
            if getattr(sys, 'frozen', False) and hasattr(sys, '_MEIPASS'):
                # Mode .exe compilé
                base_path = Path(sys._MEIPASS)
            else:
                # Mode développement
                base_path = Path(__file__).parent.parent.parent
            
            favicon_path = base_path / "assets" / "favicon.png"
            if favicon_path.exists():
                favicon_img = Image.open(favicon_path)
                # Redimensionner l'icône pour le titre (24x24)
                favicon_img = favicon_img.resize((24, 24), Image.Resampling.LANCZOS)
                favicon_ctk = ctk.CTkImage(
                    light_image=favicon_img,
                    dark_image=favicon_img,
                    size=(24, 24)
                )
                
                # Label avec l'icône
                icon_label = ctk.CTkLabel(header, image=favicon_ctk, text="")
                icon_label.image = favicon_ctk  # Garder une référence
                icon_label.pack(side="left", padx=(10, 5))
        except Exception as e:
            logger.warning(f"Impossible de charger l'icône pour le titre: {e}")
        
        # Label avec le titre
        title_label = ctk.CTkLabel(
            header,
            text=self.translation_manager.get('app.title'),
            font=ctk.CTkFont(size=20, weight="bold")
        )
        title_label.pack(side="left", padx=(5, 10))
        
        # Bannière du site
        self._setup_banner()
        
        # Zone de défilement pour les écrans
        self.scrollable_frame = ctk.CTkScrollableFrame(
            self, 
            label_text=self.translation_manager.get('main.screen_config')
        )
        self.scrollable_frame.pack(fill="both", expand=True, padx=20, pady=10)
        
        # Configuration globale
        global_config_frame = ctk.CTkFrame(self)
        global_config_frame.pack(fill="x", padx=20, pady=10)
        
        # Délai de rotation
        delay_frame = ctk.CTkFrame(global_config_frame)
        delay_frame.pack(side="left", padx=10, pady=10)
        
        ctk.CTkLabel(
            delay_frame, 
            text=self.translation_manager.get('main.rotation_delay')
        ).pack(side="left", padx=5)
        
        self.delay_entry = ctk.CTkEntry(delay_frame, width=80)
        self.delay_entry.insert(0, str(self.config_manager.get('general.rotation_delay', 15)))
        self.delay_entry.pack(side="left", padx=5)
        
        self.delay_unit_combo = ctk.CTkComboBox(
            delay_frame,
            values=[
                self.translation_manager.get('time.seconds'),
                self.translation_manager.get('time.minutes'),
                self.translation_manager.get('time.hours')
            ],
            width=100,
            command=self._on_delay_changed
        )
        delay_unit = self.config_manager.get('general.rotation_delay_unit', 'minutes')
        # Convertir l'unité en traduction
        unit_map = {'seconds': 'time.seconds', 'minutes': 'time.minutes', 'hours': 'time.hours'}
        translated_unit = self.translation_manager.get(unit_map.get(delay_unit, 'time.minutes'))
        self.delay_unit_combo.set(translated_unit)
        self.delay_unit_combo.pack(side="left", padx=5)
        
        # Lockscreen
        lockscreen_frame = ctk.CTkFrame(global_config_frame)
        lockscreen_frame.pack(side="left", padx=20, pady=10)
        
        # Container pour checkbox et info
        lockscreen_container = ctk.CTkFrame(lockscreen_frame)
        lockscreen_container.pack(padx=5, pady=5)
        
        self.lockscreen_checkbox = ctk.CTkCheckBox(
            lockscreen_container,
            text=f"🔒 {self.translation_manager.get('main.lockscreen')}",
            command=self._on_lockscreen_toggled
        )
        # Charger l'état depuis la config
        lockscreen_enabled = self.config_manager.get('general.lockscreen_enabled', False)
        if lockscreen_enabled:
            self.lockscreen_checkbox.select()
        self.lockscreen_checkbox.pack(side="left", padx=(0, 5))
        
        # Point d'interrogation avec fenêtre d'info
        self.info_label = ctk.CTkLabel(
            lockscreen_container,
            text="❓",
            font=ctk.CTkFont(size=14),
            cursor="hand2"
        )
        self.info_label.pack(side="left")
        
        # Lier le clic pour ouvrir la fenêtre d'information
        self.info_label.bind("<Button-1>", lambda e: self._show_lockscreen_info())
        
        # Boutons d'action
        button_frame = ctk.CTkFrame(self)
        button_frame.pack(fill="x", padx=20, pady=10)
        
        self.apply_btn = ctk.CTkButton(
            button_frame,
            text=f"🔄 {self.translation_manager.get('main.apply_now')}",
            command=self._apply_now,
            width=180
        )
        self.apply_btn.pack(side="left", padx=10)
        
        self.pause_btn = ctk.CTkButton(
            button_frame,
            text=f"⏸️ {self.translation_manager.get('main.pause')}",
            command=self._toggle_pause,
            width=120
        )
        self.pause_btn.pack(side="left", padx=10)
        
        ctk.CTkButton(
            button_frame,
            text=f"⚙️ {self.translation_manager.get('main.settings')}",
            command=self._open_settings,
            width=120
        ).pack(side="left", padx=10)
        
        # Barre de statut
        status_frame = ctk.CTkFrame(self)
        status_frame.pack(fill="x", padx=20, pady=(0, 20))
        
        self.status_label = ctk.CTkLabel(
            status_frame,
            text=self.translation_manager.get('status.initializing'),
            font=ctk.CTkFont(size=10)
        )
        self.status_label.pack(side="left", padx=10, pady=5)
        
        self.cache_label = ctk.CTkLabel(
            status_frame,
            text=f"💾 {self.translation_manager.get('status.cache')} 0 MB",
            font=ctk.CTkFont(size=10)
        )
        self.cache_label.pack(side="left", padx=10, pady=5)
    
    def _initialize_app(self) -> None:
        """Initialise l'application."""
        # Afficher un message de chargement
        self.status_label.configure(text=f"📡 {self.translation_manager.get('status.loading')}")
        self.update()
        
        # Charger immédiatement les thèmes depuis le cache local
        self._load_themes_from_cache()
        
        # Afficher les widgets d'écrans immédiatement avec les thèmes du cache
        self._setup_screen_widgets()
        self._load_configuration()
        self._update_status()
        
        # Lancer le chargement en ligne en arrière-plan
        thread = threading.Thread(target=self._initialize_app_thread, daemon=True)
        thread.start()
    
    def _initialize_app_thread(self) -> None:
        """Thread d'initialisation de l'application en arrière-plan."""
        try:
            # Test de connexion
            self.is_online = self.scraper.test_connection()
            
            if self.is_online:
                logger.info("Mode en ligne - mise à jour des thèmes en arrière-plan")
                
                # Vérifier si un re-scan est nécessaire (toutes les 24h)
                should_rescan = self.smart_cache.should_rescan(hours=24)
                
                # Récupérer uniquement la liste des thèmes (pas les images)
                online_themes = self.scraper.get_themes()
                
                # Construire un dictionnaire avec les thèmes disponibles en ligne
                online_themes_data = {}
                online_theme_urls = {}
                for theme_info in online_themes:
                    theme_name = theme_info['name']
                    theme_url = theme_info['url']
                    
                    # Stocker l'URL du thème
                    online_theme_urls[theme_name] = theme_url
                    
                    # Ne charger les images que si le thème n'est pas dans le cache
                    if theme_name not in self.theme_images:
                        logger.info(f"Nouveau thème détecté: {theme_name}")
                        # On ajoute le thème avec une liste vide, les images seront chargées à la demande
                        online_themes_data[theme_name] = []
                    else:
                        # Utiliser les images du cache
                        online_themes_data[theme_name] = self.theme_images[theme_name]
                
                # Mettre à jour la liste des thèmes et leurs URLs
                self.themes = list(online_themes_data.keys())
                self.theme_urls = online_theme_urls
                self.theme_images = online_themes_data
                
                # Pas de téléchargement automatique au démarrage
                # Le téléchargement se fera à la demande selon les thèmes sélectionnés
                
                # Si un re-scan est nécessaire, mettre à jour l'index avec les nouvelles images
                if should_rescan:
                    logger.info("Re-scan nécessaire, mise à jour de l'index des images...")
                    for theme_name, theme_url in online_theme_urls.items():
                        try:
                            # Récupérer la liste des images (rapide, pas de téléchargement)
                            images = self.scraper.get_theme_images(theme_url)
                            if images:
                                self.smart_cache.update_theme_images(theme_name, theme_url, images)
                                self.theme_images[theme_name] = images
                        except Exception as e:
                            logger.error(f"Erreur lors du scan de '{theme_name}': {e}")
                    
                    self.smart_cache.mark_global_scan()
                    logger.info("Re-scan terminé, index mis à jour")
                    
                    # NE PAS télécharger au démarrage
                    # Le téléchargement se fera à la demande quand l'utilisateur sélectionne un thème
                    logger.info("Index créé, téléchargement à la demande selon les thèmes sélectionnés")
                
                # Mettre à jour les widgets d'écrans avec les nouveaux thèmes
                self.after(0, self._update_screen_widgets_themes)
                
            else:
                logger.warning("Mode hors ligne - utilisation du cache uniquement")
            
            # Mettre à jour le statut
            self.after(0, self._update_status)
            
        except Exception as e:
            logger.error(f"Erreur lors de l'initialisation en arrière-plan: {e}", exc_info=True)
            self.after(0, lambda: self.status_label.configure(text=f"❌ {self.translation_manager.get('error.general')} {str(e)}"))
    
    def _load_themes_from_cache(self) -> None:
        """Charge les thèmes depuis le cache local."""
        cache_dir = Path("data/wallpapers")
        
        # Réinitialiser les listes
        self.themes = []
        self.theme_images = {}
        
        if cache_dir.exists() and cache_dir.is_dir():
            theme_count = 0
            image_count = 0
            
            for theme_dir in cache_dir.iterdir():
                if theme_dir.is_dir():
                    theme_name = theme_dir.name
                    images = []
                    
                    # Compter rapidement les fichiers images sans les charger
                    image_extensions = {'.jpg', '.jpeg', '.png', '.webp', '.bmp'}
                    for img_file in theme_dir.iterdir():
                        if img_file.is_file() and img_file.suffix.lower() in image_extensions:
                            images.append({
                                'filename': img_file.name,
                                'url': '',
                                'local_path': str(img_file)
                            })
                    
                    if images:
                        self.themes.append(theme_name)
                        self.theme_images[theme_name] = images
                        theme_count += 1
                        image_count += len(images)
            
            logger.info(f"Cache chargé: {theme_count} thèmes, {image_count} images")
        else:
            logger.info("Aucun cache trouvé - les thèmes seront chargés en ligne")
    
    def _setup_screen_widgets(self) -> None:
        """Crée les widgets de configuration pour chaque écran."""
        # Nettoyer les widgets existants
        for widget in self.screen_widgets:
            widget.destroy()
        self.screen_widgets.clear()
        
        # Créer un widget par écran
        screens = self.screen_detector.get_screens()
        
        for screen in screens:
            widget = ScreenConfigWidget(
                self.scrollable_frame,
                screen_info=screen,
                themes=self.themes,
                translation_manager=self.translation_manager,
                on_theme_change=self._on_screen_theme_changed,
                on_rotation_toggle=self._on_screen_rotation_toggled
            )
            widget.pack(fill="x", padx=10, pady=10)
            self.screen_widgets.append(widget)
        
        logger.debug(f"{len(self.screen_widgets)} widgets d'écrans créés")
    
    def _update_screen_widgets_themes(self) -> None:
        """Met à jour la liste des thèmes dans les widgets d'écrans."""
        for widget in self.screen_widgets:
            widget.update_themes(self.themes)
        
        logger.debug(f"Thèmes mis à jour dans {len(self.screen_widgets)} widgets")
    
    def _load_configuration(self) -> None:
        """Charge la configuration sauvegardée."""
        saved_screens = self.config_manager.get_screens()
        
        for widget in self.screen_widgets:
            screen_id = widget.screen_info['id']
            
            # Trouver la config sauvegardée pour cet écran
            saved_config = next((s for s in saved_screens if s.get('id') == screen_id), None)
            
            if saved_config:
                widget.set_theme(saved_config.get('theme', 'all'))
                widget.set_rotation_enabled(saved_config.get('enabled', True))
        
        # Démarrer la rotation si configuré
        if self.config_manager.get('general.rotation_delay'):
            self._start_rotation()
    
    def _update_status(self) -> None:
        """Met à jour la barre de statut."""
        # Statut de connexion
        status_text = self.translation_manager.get('status.connected') if self.is_online else self.translation_manager.get('status.offline')
        connection_status = f"📡 {status_text}" if self.is_online else f"📴 {status_text}"
        
        # Taille du cache
        cache_size = self.image_downloader.get_cache_size()
        cache_size_mb = cache_size / 1024 / 1024
        
        # Nombre de thèmes
        theme_count = len(self.themes)
        
        self.status_label.configure(text=f"{connection_status} | {theme_count} {self.translation_manager.get('status.themes')}")
        self.cache_label.configure(text=f"💾 {self.translation_manager.get('status.cache')} {cache_size_mb:.1f} MB")
    
    def _on_screen_theme_changed(self, screen_id: int, theme: str) -> None:
        """
        Gère le changement de thème pour un écran.
        
        Args:
            screen_id: ID de l'écran
            theme: Nom du thème ou "all"
        """
        logger.info(f"Changement de thème pour écran {screen_id}: {theme}")
        
        # Sauvegarder dans la config
        self._save_screen_config(screen_id)
        
        # Mettre à jour la playlist
        self._update_screen_playlist(screen_id, theme)
    
    def _on_screen_rotation_toggled(self, screen_id: int, enabled: bool) -> None:
        """
        Gère le toggle de rotation pour un écran.
        
        Args:
            screen_id: ID de l'écran
            enabled: True si activé
        """
        logger.info(f"Rotation {'activée' if enabled else 'désactivée'} pour écran {screen_id}")
        
        # Sauvegarder dans la config
        self._save_screen_config(screen_id)
        
        if enabled:
            # Réactiver la playlist
            widget = self.screen_widgets[screen_id] if screen_id < len(self.screen_widgets) else None
            if widget:
                theme = widget.get_theme()
                self._update_screen_playlist(screen_id, theme)
        else:
            # Supprimer la playlist
            if screen_id in self.rotation_scheduler.playlists:
                del self.rotation_scheduler.playlists[screen_id]
    
    def _update_screen_playlist(self, screen_id: int, theme: str) -> None:
        """
        Met à jour la playlist d'un écran.
        
        Args:
            screen_id: ID de l'écran
            theme: Nom du thème ou "all"
        """
        images = []
        
        if theme == "all" or theme == "Tous les thèmes":
            # Toutes les images de tous les thèmes
            for theme_name, theme_imgs in self.theme_images.items():
                images.extend(self._get_image_paths(theme_name, theme_imgs))
                
        elif theme in self.theme_images:
            # Images d'un thème spécifique
            images = self._get_image_paths(theme, self.theme_images[theme])
            
            # Configurer aussi le nouveau système pour le téléchargement progressif
            if theme in self.theme_images:
                images_metadata = self.theme_images[theme]
                if images_metadata:
                    self.rotation_scheduler.set_theme_config(screen_id, theme, images_metadata)
        
        if images:
            self.rotation_scheduler.set_playlist(screen_id, images)
            logger.debug(f"Playlist mise à jour pour écran {screen_id}: {len(images)} images")
        else:
            logger.warning(f"Aucune image trouvée pour l'écran {screen_id} (thème: {theme})")
    
    def _get_image_paths(self, theme_name: str, images: List[Dict]) -> List[str]:
        """
        Récupère les chemins locaux des images d'un thème (système de cache intelligent).
        
        Args:
            theme_name: Nom du thème
            images: Liste des images depuis le scraper
            
        Returns:
            Liste des chemins locaux disponibles
        """
        # Si les images ne sont pas encore chargées et qu'on est en ligne, les charger maintenant
        if not images and self.is_online and theme_name in self.theme_urls:
            logger.info(f"Récupération de la liste des images pour '{theme_name}'...")
            theme_url = self.theme_urls[theme_name]
            images = self.scraper.get_theme_images(theme_url)
            logger.info(f"Total: {len(images)} images trouvées pour '{theme_name}'")
            self.theme_images[theme_name] = images
        
        if not images:
            logger.warning(f"Aucune image trouvée pour '{theme_name}'")
            return []
        
        # Mettre à jour l'index du cache intelligent avec toutes les URLs
        if theme_name in self.theme_urls:
            self.smart_cache.update_theme_images(theme_name, self.theme_urls[theme_name], images)
        
        # Récupérer toutes les images déjà en cache
        cached_paths = self.smart_cache.get_cached_images(theme_name, only_undisplayed=False)
        logger.debug(f"Images en cache pour '{theme_name}': {len(cached_paths)}")
        
        # Télécharger seulement si on a moins de 5 images pour ce thème
        if len(cached_paths) < 5 and self.is_online:
            stats = self.smart_cache.get_stats(theme_name)
            remaining = stats['remaining']
            
            if remaining > 0:
                # Télécharger seulement 5 images à la fois
                logger.info(f"Téléchargement de 5 images max pour '{theme_name}'...")
                self._download_next_batch(theme_name, count=5)
                cached_paths = self.smart_cache.get_cached_images(theme_name, only_undisplayed=False)
        
        stats = self.smart_cache.get_stats(theme_name)
        logger.info(f"Stats '{theme_name}': {stats['downloaded']}/{stats['total']} téléchargées, "
                   f"{stats['displayed']} affichées, {stats['remaining']} restantes (Cycle #{stats['cycle']})")
        
        return cached_paths
    
    def _download_next_batch(self, theme_name: str, count: int = 10) -> int:
        """
        Télécharge le prochain lot d'images.
        
        Args:
            theme_name: Nom du thème
            count: Nombre max d'images à télécharger (par défaut 10, mais peut être limité à 5)
        
        Returns:
            Nombre d'images téléchargées
        """
        batch = self.smart_cache.get_next_batch(theme_name, count)
        if not batch:
            logger.debug(f"Aucune nouvelle image à télécharger pour '{theme_name}'")
            return 0
        
        logger.info(f"Téléchargement de {len(batch)} images pour '{theme_name}'...")
        downloaded = 0
        
        for i, img in enumerate(batch, 1):
            try:
                logger.debug(f"Téléchargement {i}/{len(batch)}: {img['filename']}")
                local_path = self.image_downloader.download_image(
                    img['url'],
                    theme_name,
                    img['filename']
                )
                if local_path:
                    self.smart_cache.mark_as_downloaded(theme_name, img['url'], local_path)
                    downloaded += 1
                    
            except Exception as e:
                logger.error(f"Erreur lors du téléchargement de {img['filename']}: {e}")
        
        logger.info(f"{downloaded}/{len(batch)} images téléchargées avec succès pour '{theme_name}'")
        
        # Nettoyer le cache si nécessaire (limite globale)
        self.smart_cache.cleanup_old_images()
        
        return downloaded
    
    def _save_screen_config(self, screen_id: int) -> None:
        """
        Sauvegarde la configuration d'un écran.
        
        Args:
            screen_id: ID de l'écran
        """
        if screen_id >= len(self.screen_widgets):
            return
        
        widget = self.screen_widgets[screen_id]
        screen_info = widget.screen_info
        
        # Récupérer la config existante
        saved_screens = self.config_manager.get_screens()
        
        # Mettre à jour ou ajouter
        screen_config = {
            'id': screen_id,
            'name': screen_info['name'],
            'resolution': screen_info['resolution'],
            'enabled': widget.is_rotation_enabled(),
            'theme': widget.get_theme(),
            'fit_mode': 'fill',
            'current_wallpaper': widget.current_wallpaper_path or ""
        }
        
        # Remplacer ou ajouter
        existing_index = next((i for i, s in enumerate(saved_screens) if s['id'] == screen_id), None)
        
        if existing_index is not None:
            saved_screens[existing_index] = screen_config
        else:
            saved_screens.append(screen_config)
        
        self.config_manager.update_screens(saved_screens)
    
    def _on_delay_changed(self, unit: str = None) -> None:
        """Gère le changement d'unité de délai."""
        try:
            delay = int(self.delay_entry.get())
            
            # Si unit n'est pas fourni, récupérer depuis le combo
            if unit is None:
                unit = self.delay_unit_combo.get()
            
            # Convertir la traduction en code d'unité
            unit_reverse_map = {
                self.translation_manager.get('time.seconds'): 'seconds',
                self.translation_manager.get('time.minutes'): 'minutes',
                self.translation_manager.get('time.hours'): 'hours'
            }
            unit_code = unit_reverse_map.get(unit, 'minutes')
            
            self.config_manager.set('general.rotation_delay', delay)
            self.config_manager.set('general.rotation_delay_unit', unit_code)
            
            delay_seconds = self.config_manager.get_rotation_delay_seconds()
            logger.info(f"Délai de rotation mis à jour: {delay} {unit} ({delay_seconds}s) - Cliquez sur 'Appliquer maintenant' pour appliquer")
            
            # Mettre à jour la barre de statut pour indiquer qu'il faut appliquer
            self.status_label.configure(text=f"⚠️ {self.translation_manager.get('status.new_delay')}")
            
        except ValueError:
            logger.warning("Délai invalide")
    
    def _on_lockscreen_toggled(self) -> None:
        """Gère l'activation/désactivation du lockscreen."""
        is_enabled = self.lockscreen_checkbox.get() == 1
        self.config_manager.set('general.lockscreen_enabled', is_enabled)
        
        if is_enabled:
            logger.info("✓ Lockscreen activé - sera appliqué avec l'écran principal")
            # Désactiver Windows Spotlight pour permettre le lockscreen personnalisé
            self.lockscreen_manager.disable_windows_spotlight()
        else:
            logger.info("Lockscreen désactivé - suppression de la configuration PersonalizationCSP")
            # Supprimer la clé PersonalizationCSP pour rendre le contrôle à l'utilisateur
            # Sans cela, Windows affichera "Géré par votre organisation"
            success = self.lockscreen_manager.remove_lockscreen()
            if success:
                logger.info("✓ Contrôle du lockscreen rendu à l'utilisateur")
                self.status_label.configure(text=f"🔒 {self.translation_manager.get('status.lockscreen_disabled')}")
            else:
                logger.warning("⚠️ Impossible de supprimer PersonalizationCSP - relancez en administrateur")
                self.status_label.configure(text=f"⚠️ {self.translation_manager.get('status.lockscreen_admin')}")
                return
        
        if is_enabled:
            self.status_label.configure(text=f"🔒 {self.translation_manager.get('status.lockscreen_enabled')}")
    
    def _apply_now(self) -> None:
        """Force une rotation immédiate."""
        logger.info("Application immédiate des fonds d'écran")
        
        # Sauvegarder le délai avant de redémarrer
        try:
            delay = int(self.delay_entry.get())
            unit = self.delay_unit_combo.get()
            self.config_manager.set('general.rotation_delay', delay)
            self.config_manager.set('general.rotation_delay_unit', unit)
            delay_seconds = self.config_manager.get_rotation_delay_seconds()
            logger.info(f"Délai configuré: {delay} {unit} ({delay_seconds}s)")
        except ValueError:
            logger.warning("Délai invalide, utilisation du délai par défaut")
        
        # Afficher un message de chargement
        self.status_label.configure(text=f"⏳ {self.translation_manager.get('status.downloading')}")
        self.update()
        
        # Lancer le traitement dans un thread séparé
        thread = threading.Thread(target=self._apply_now_in_thread, daemon=True)
        thread.start()
    
    def _apply_now_in_thread(self):
        """Applique les fonds d'écran dans un thread séparé pour ne pas bloquer l'UI."""
        try:
            # Mettre à jour les playlists et télécharger si nécessaire
            for widget in self.screen_widgets:
                if widget.is_rotation_enabled():
                    screen_id = widget.screen_info['id']
                    theme = widget.get_theme()
                    logger.info(f"Préparation playlist pour écran {screen_id}, thème: {theme}")
                    self._update_screen_playlist(screen_id, theme)
            
            # Vérifier qu'on a des images
            total_images = sum(len(pl) for pl in self.rotation_scheduler.playlists.values())
            
            if total_images == 0:
                logger.warning("Aucune image disponible pour appliquer")
                self.after(0, lambda: self.status_label.configure(text=f"❌ {self.translation_manager.get('status.no_images')}"))
                return
            
            logger.info(f"Total images disponibles: {total_images}")
            
            # Arrêter et redémarrer la rotation avec le nouveau délai (dans le thread principal UI)
            def restart_rotation():
                was_running = self.rotation_scheduler.is_running
                if was_running:
                    logger.info("Arrêt du scheduler existant")
                    self.rotation_scheduler.stop()
                
                # Redémarrer avec le nouveau délai
                logger.info("Démarrage/redémarrage du scheduler")
                self._start_rotation()
                
                # Mettre à jour le statut
                self._update_status()
            
            # Exécuter le redémarrage dans le thread principal
            self.after(0, restart_rotation)
            
        except Exception as e:
            logger.error(f"Erreur dans _apply_now_in_thread: {e}", exc_info=True)
            self.after(0, lambda: self.status_label.configure(text=f"❌ Erreur: {str(e)}"))
    
    def _toggle_pause(self) -> None:
        """Bascule entre pause et lecture."""
        if not self.rotation_scheduler.is_running:
            self._start_rotation()
            return
        
        is_paused = self.rotation_scheduler.toggle_pause()
        
        if is_paused:
            self.pause_btn.configure(text=f"▶️ {self.translation_manager.get('main.resume')}")
            self.status_label.configure(text=f"⏸️ {self.translation_manager.get('status.paused')}")
        else:
            self.pause_btn.configure(text=f"⏸️ {self.translation_manager.get('main.pause')}")
            self._update_status()
        
        # Mettre à jour l'état dans le system tray
        self.system_tray.update_pause_state(is_paused)
    
    def _start_rotation(self) -> None:
        """Démarre la rotation automatique."""
        # Mettre à jour le délai
        delay_seconds = self.config_manager.get_rotation_delay_seconds()
        self.rotation_scheduler.set_delay(delay_seconds)
        
        # Mettre à jour le mode aléatoire
        random_mode = self.config_manager.get('general.random_mode', True)
        self.rotation_scheduler.set_random_mode(random_mode)
        
        # Mettre à jour les playlists
        for widget in self.screen_widgets:
            if widget.is_rotation_enabled():
                screen_id = widget.screen_info['id']
                theme = widget.get_theme()
                self._update_screen_playlist(screen_id, theme)
        
        # Démarrer
        self.rotation_scheduler.start()
        
        # Forcer une rotation immédiate au démarrage
        self.after(100, self.rotation_scheduler.rotate_now)
        
        self.pause_btn.configure(text=f"⏸️ {self.translation_manager.get('main.pause')}")
        logger.info("Rotation démarrée")
    
    def _on_rotation_callback(self, screen_id: int, image_path: str) -> None:
        """
        Callback appelé lors de chaque rotation.
        
        Args:
            screen_id: ID de l'écran
            image_path: Chemin de l'image
        """
        try:
            logger.info(f"Callback rotation: écran {screen_id}, image: {Path(image_path).name}")
            
            # Sauvegarder l'image actuelle pour ce widget
            if screen_id < len(self.screen_widgets):
                self.screen_widgets[screen_id].current_wallpaper_path = image_path
                
                # Marquer l'image comme affichée IMMÉDIATEMENT
                # pour éviter qu'un autre écran ne choisisse la même image
                # On cherche dans tous les thèmes pour trouver celui qui contient cette image
                for theme_name in self.theme_urls.keys():
                    # Vérifier si l'image appartient à ce thème
                    theme_imgs = self.theme_images.get(theme_name, [])
                    for img in theme_imgs:
                        if img.get('local_path') == image_path:
                            self.smart_cache.mark_as_displayed(theme_name, image_path)
                            logger.debug(f"Image marquée comme affichée dans le thème '{theme_name}'")
                            break
                
                # Le téléchargement progressif est géré par _progressive_download
                # Pas besoin de télécharger automatiquement ici
            
            # Si API moderne disponible, appliquer directement sur le moniteur
            if self.wallpaper_manager.desktop_wallpaper is not None:
                success = self.wallpaper_manager.set_wallpaper(image_path, screen_id=screen_id, fit_mode='fill')
                
                if success and screen_id < len(self.screen_widgets):
                    widget = self.screen_widgets[screen_id]
                    self._update_widget_preview(widget, image_path)
            else:
                # Mode composite : attendre que tous les écrans aient leur image
                # avant de créer le composite
                if len(self.screen_widgets) > 1:
                    # Vérifier si tous les écrans actifs ont une image
                    all_ready = True
                    image_paths = {}
                    
                    for widget in self.screen_widgets:
                        if widget.is_rotation_enabled():
                            sid = widget.screen_info['id']
                            if widget.current_wallpaper_path:
                                image_paths[sid] = widget.current_wallpaper_path
                            else:
                                all_ready = False
                                break
                    
                    if all_ready and image_paths:
                        logger.info(f"Mode composite: création avec {len(image_paths)} images")
                        
                        screens = self.screen_detector.get_screens()
                        composite_path = "data/composite_wallpaper.jpg"
                        result = self.wallpaper_manager.create_multi_screen_wallpaper(
                            screens,
                            image_paths,
                            composite_path
                        )
                        
                        if result:
                            # IMPORTANT : Utiliser is_composite=True pour activer le mode SPAN
                            success = self.wallpaper_manager.set_wallpaper(result, fit_mode='span', is_composite=True)
                            
                            if success:
                                # Mettre à jour les aperçus
                                for sid, img_path in image_paths.items():
                                    if sid < len(self.screen_widgets):
                                        widget = self.screen_widgets[sid]
                                        self._update_widget_preview(widget, img_path)
                else:
                    # Un seul écran
                    success = self.wallpaper_manager.set_wallpaper(image_path, fit_mode='fill')
                    
                    if success and screen_id < len(self.screen_widgets):
                        widget = self.screen_widgets[screen_id]
                        self._update_widget_preview(widget, image_path)
            
            # Appliquer au lockscreen si activé (utilise l'image de l'écran principal = écran 0)
            if self.lockscreen_checkbox.get() == 1 and screen_id == 0:
                logger.debug("Application de l'image au lockscreen")
                self.lockscreen_manager.set_lockscreen(image_path)
            
            # Sauvegarder
            self._save_screen_config(screen_id)
            
            # Mettre à jour le statut
            self.after(0, self._update_status)
            
        except Exception as e:
            logger.error(f"Erreur lors de la rotation: {e}", exc_info=True)
    
    def _update_widget_preview(self, widget: ScreenConfigWidget, image_path: str) -> None:
        """
        Met à jour l'aperçu d'un widget (appelée depuis le thread principal).
        
        Args:
            widget: Widget à mettre à jour
            image_path: Chemin de l'image
        """
        def update():
            widget.update_preview(image_path)
        
        self.after(0, update)
    
    def _open_settings(self) -> None:
        """Ouvre le dialogue des paramètres."""
        dialog = SettingsDialog(self, self.config_manager, self.translation_manager, on_apply=self._on_settings_applied)
        
        # Mettre à jour les infos du cache
        cache_size = self.image_downloader.get_cache_size()
        cache_size_mb = cache_size / 1024 / 1024
        dialog.update_cache_info(cache_size_mb)
    
    def _on_settings_applied(self) -> None:
        """Callback lorsque les paramètres sont appliqués."""
        # Recharger les paramètres
        self._apply_theme()
        
        # Recharger les traductions (si la langue a changé)
        self.translation_manager._load_language_from_config()
        
        # Mettre à jour le scraper
        self.scraper = UniverseScraper(
            rate_limit_seconds=self.config_manager.get('network.rate_limit_seconds', 1),
            timeout_seconds=self.config_manager.get('network.timeout_seconds', 10)
        )
        
        # Mettre à jour le statut
        self._update_status()
        
        # Recréer l'interface pour appliquer les traductions
        logger.info("Rechargement de l'interface pour appliquer les changements de langue...")
        self.after(100, lambda: self._reload_interface())
        
        logger.info("Paramètres appliqués")
    
    def _reload_interface(self) -> None:
        """Recharge l'interface pour appliquer les changements de langue."""
        # Sauvegarder l'état actuel
        was_running = self.rotation_scheduler.is_running
        
        # Arrêter la rotation
        if was_running:
            self.rotation_scheduler.stop()
        
        # Détruire tous les widgets
        for widget in self.winfo_children():
            widget.destroy()
        
        # Recréer l'interface
        self._setup_ui()
        
        # Réinitialiser l'application
        self._setup_screen_widgets()
        self._load_configuration()
        self._update_status()
        
        # Redémarrer la rotation si elle était active
        if was_running:
            self._start_rotation()
    
    def _show_lockscreen_info(self) -> None:
        """Affiche une fenêtre d'information sur l'option lockscreen."""
        # Créer une fenêtre toplevel modale
        info_window = ctk.CTkToplevel(self)
        info_window.title("ℹ️ Information")
        info_window.geometry("500x300")
        info_window.resizable(False, False)
        
        # Centrer la fenêtre
        info_window.update_idletasks()
        x = self.winfo_x() + (self.winfo_width() // 2) - (500 // 2)
        y = self.winfo_y() + (self.winfo_height() // 2) - (300 // 2)
        info_window.geometry(f"+{x}+{y}")
        
        # Rendre la fenêtre modale
        info_window.transient(self)
        info_window.grab_set()
        info_window.attributes('-topmost', True)
        
        # Frame principal avec padding
        main_frame = ctk.CTkFrame(info_window)
        main_frame.pack(fill="both", expand=True, padx=20, pady=20)
        
        # Titre
        title_label = ctk.CTkLabel(
            main_frame,
            text="🔒 Écran de verrouillage",
            font=ctk.CTkFont(size=16, weight="bold")
        )
        title_label.pack(pady=(0, 15))
        
        # Texte d'information
        info_text = self.translation_manager.get('main.lockscreen_tooltip')
        info_label = ctk.CTkLabel(
            main_frame,
            text=info_text,
            justify="left",
            wraplength=450
        )
        info_label.pack(pady=10, fill="both", expand=True)
        
        # Bouton de fermeture
        close_btn = ctk.CTkButton(
            main_frame,
            text="OK",
            command=info_window.destroy,
            width=100
        )
        close_btn.pack(pady=(10, 0))
    
    def _on_closing(self) -> None:
        """Gère la fermeture de l'application (minimise dans le tray)."""
        logger.info("Réduction de l'application dans la zone de notification")
        
        # Cacher la fenêtre au lieu de la fermer
        self.withdraw()
        self.is_hidden = True
        
        # Afficher une notification
        self.system_tray.show_notification(
            "UPA Wallpaper Manager",
            "L'application a été réduite dans la zone de notifications.\nCliquez sur l'icône pour la réafficher."
        )
    
    def _check_for_updates_on_startup(self) -> None:
        """Vérifie les mises à jour au démarrage de l'application."""
        # Vérifier si l'utilisateur n'a pas désactivé la vérification
        if not self.update_manager.should_check_update():
            logger.debug("Vérification des mises à jour désactivée par l'utilisateur")
            return
        
        def check_updates_thread():
            """Thread pour vérifier les mises à jour sans bloquer l'interface."""
            try:
                update_available, latest_version, download_url = self.update_manager.check_for_updates()
                
                if update_available and latest_version and download_url:
                    # Afficher la boîte de dialogue dans le thread principal
                    self.after(0, lambda: self._show_update_dialog(latest_version, download_url))
                    
            except Exception as e:
                logger.error(f"Erreur lors de la vérification des mises à jour: {e}", exc_info=True)
        
        # Lancer la vérification dans un thread
        import threading
        threading.Thread(target=check_updates_thread, daemon=True).start()
    
    def _show_update_dialog(self, latest_version: str, download_url: str) -> None:
        """
        Affiche la boîte de dialogue de mise à jour.
        
        Args:
            latest_version: Dernière version disponible
            download_url: URL de téléchargement
        """
        from .update_dialog import UpdateDialog
        
        dialog = UpdateDialog(
            self,
            self.translation_manager,
            self.update_manager.get_current_version(),
            latest_version,
            on_update=lambda: self._perform_update(download_url),
            on_skip=lambda: self.update_manager.set_skip_update_check(True)
        )
    
    def _perform_update(self, download_url: str) -> None:
        """
        Effectue la mise à jour de l'application.
        
        Args:
            download_url: URL de téléchargement de la nouvelle version
        """
        from .update_dialog import UpdateProgressDialog
        
        # Afficher la boîte de dialogue de progression
        progress_dialog = UpdateProgressDialog(self, self.translation_manager)
        
        def download_thread():
            """Thread pour télécharger la mise à jour."""
            try:
                def on_progress(downloaded, total):
                    """Callback de progression."""
                    self.after(0, lambda: progress_dialog.update_progress(downloaded, total))
                
                def on_complete():
                    """Callback pour fermer l'application."""
                    self.after(0, self._quit_application)
                
                # Télécharger et installer
                progress_dialog.set_status(self.translation_manager.get('update.downloading'))
                success = self.update_manager.download_and_install_update(
                    download_url,
                    on_progress=on_progress,
                    on_complete=on_complete
                )
                
                if success:
                    # Mise à jour réussie, le script de mise à jour va installer la nouvelle version
                    self.after(0, lambda: progress_dialog.set_status(self.translation_manager.get('update.success')))
                    # L'application va se fermer automatiquement (sans redémarrage)
                else:
                    self.after(0, lambda: progress_dialog.destroy())
                    self.after(0, lambda: self._show_error_dialog(
                        self.translation_manager.get('update.title'),
                        self.translation_manager.get('update.download_error')
                    ))
                    
            except Exception as e:
                logger.error(f"Erreur lors du téléchargement de la mise à jour: {e}", exc_info=True)
                self.after(0, lambda: progress_dialog.destroy())
                self.after(0, lambda: self._show_error_dialog(
                    self.translation_manager.get('update.title'),
                    str(e)
                ))
        
        import threading
        threading.Thread(target=download_thread, daemon=True).start()
    
    def check_for_updates_manual(self) -> None:
        """Vérifie manuellement les mises à jour (bouton dans les paramètres)."""
        self.status_label.configure(text=self.translation_manager.get('update.checking'))
        
        def check_thread():
            """Thread pour vérifier."""
            try:
                update_available, latest_version, download_url = self.update_manager.check_for_updates()
                
                if update_available and latest_version and download_url:
                    self.after(0, lambda: self._show_update_dialog(latest_version, download_url))
                else:
                    message = self.translation_manager.get('update.up_to_date').format(
                        version=self.update_manager.get_current_version()
                    )
                    self.after(0, lambda: self._show_info_dialog(
                        self.translation_manager.get('update.title'),
                        message
                    ))
                    
            except Exception as e:
                logger.error(f"Erreur: {e}", exc_info=True)
                self.after(0, lambda: self._show_error_dialog(
                    self.translation_manager.get('update.title'),
                    self.translation_manager.get('update.error')
                ))
        
        import threading
        threading.Thread(target=check_thread, daemon=True).start()
    
    def _show_info_dialog(self, title: str, message: str) -> None:
        """Affiche une boîte de dialogue d'information."""
        from tkinter import messagebox
        messagebox.showinfo(title, message, parent=self)
    
    def _show_error_dialog(self, title: str, message: str) -> None:
        """Affiche une boîte de dialogue d'erreur."""
        from tkinter import messagebox
        messagebox.showerror(title, message, parent=self)
    
    def _minimize_to_tray_on_startup(self) -> None:
        """Cache la fenêtre au démarrage (sans notification)."""
        logger.info("Réduction silencieuse au démarrage")
        self.withdraw()
        self.is_hidden = True
    
    def _show_window(self) -> None:
        """Réaffiche la fenêtre depuis le system tray."""
        logger.info("=== RÉAFFICHAGE DE L'APPLICATION DEMANDÉ ===")
        try:
            self.deiconify()
            self.lift()
            self.focus_force()
            self.is_hidden = False
            logger.info("✓ Fenêtre réaffichée avec succès")
        except Exception as e:
            logger.error(f"Erreur lors du réaffichage: {e}", exc_info=True)
    
    def _quit_application(self) -> None:
        """Ferme réellement l'application."""
        logger.info("Fermeture définitive de l'application")
        
        # Arrêter la rotation
        self.rotation_scheduler.stop()
        
        # Arrêter le system tray dans un thread séparé pour éviter les blocages
        try:
            import threading
            thread = threading.Thread(target=self.system_tray.stop, daemon=True)
            thread.start()
            # Attendre un peu que le tray s'arrête proprement
            thread.join(timeout=0.5)
        except Exception as e:
            logger.error(f"Erreur lors de l'arrêt du system tray: {e}")
        
        # Détruire proprement la fenêtre Tkinter
        try:
            self.quit()  # Arrête la mainloop
            self.destroy()  # Détruit la fenêtre
        except Exception as e:
            logger.error(f"Erreur lors de la fermeture de la fenêtre: {e}")
        
        # Sortie propre
        sys.exit(0)


