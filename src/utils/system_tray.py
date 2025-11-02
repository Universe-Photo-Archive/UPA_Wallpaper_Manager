"""Gestionnaire de l'icône dans la zone de notification (system tray)."""

import sys
import threading
from pathlib import Path
from typing import Callable, Optional

try:
    import pystray
    from PIL import Image
    PYSTRAY_AVAILABLE = True
except ImportError:
    PYSTRAY_AVAILABLE = False

# Pour les notifications Windows natives (alternative à pystray.notify)
try:
    import warnings
    # Supprimer les warnings de win10toast sur pkg_resources
    warnings.filterwarnings("ignore", message=".*pkg_resources.*")
    from win10toast import ToastNotifier
    WIN10TOAST_AVAILABLE = True
except ImportError:
    WIN10TOAST_AVAILABLE = False

from .logger import get_logger

logger = get_logger()


class SystemTrayManager:
    """Gère l'icône de l'application dans la zone de notification."""
    
    def __init__(
        self,
        on_show: Optional[Callable] = None,
        on_quit: Optional[Callable] = None,
        on_rotate_now: Optional[Callable] = None,
        on_toggle_pause: Optional[Callable] = None
    ):
        """
        Initialise le gestionnaire de system tray.
        
        Args:
            on_show: Callback pour afficher la fenêtre
            on_quit: Callback pour quitter l'application
            on_rotate_now: Callback pour forcer une rotation
            on_toggle_pause: Callback pour mettre en pause/reprendre
        """
        if not PYSTRAY_AVAILABLE:
            logger.warning("pystray n'est pas installé, system tray désactivé")
            self.enabled = False
            return
        
        self.enabled = True
        self.on_show = on_show
        self.on_quit = on_quit
        self.on_rotate_now = on_rotate_now
        self.on_toggle_pause = on_toggle_pause
        
        self.icon: Optional[pystray.Icon] = None
        self.is_paused = False
        
        # Notificateur Windows alternatif
        self.toast_notifier = None
        if WIN10TOAST_AVAILABLE:
            try:
                self.toast_notifier = ToastNotifier()
            except Exception as e:
                logger.warning(f"Impossible d'initialiser win10toast: {e}")
        
        # Charger l'icône
        self.image = self._load_icon()
    
    def _load_icon(self) -> Optional[Image.Image]:
        """
        Charge l'icône depuis les assets.
        
        Returns:
            Image PIL ou None si échec
        """
        try:
            # Déterminer le chemin des assets
            if getattr(sys, 'frozen', False) and hasattr(sys, '_MEIPASS'):
                # Mode .exe compilé
                base_path = Path(sys._MEIPASS)
            else:
                # Mode développement
                base_path = Path(__file__).parent.parent.parent
            
            # Essayer favicon.png en premier
            icon_path = base_path / "assets" / "favicon.png"
            if icon_path.exists():
                logger.info(f"Icône system tray chargée: {icon_path}")
                return Image.open(icon_path)
            
            # Sinon essayer app_icon.ico
            icon_path = base_path / "assets" / "icons" / "app_icon.ico"
            if icon_path.exists():
                logger.info(f"Icône system tray chargée: {icon_path}")
                return Image.open(icon_path)
            
            logger.warning("Aucune icône trouvée, création d'une icône par défaut")
            # Créer une icône par défaut simple
            return self._create_default_icon()
            
        except Exception as e:
            logger.error(f"Erreur lors du chargement de l'icône: {e}")
            return self._create_default_icon()
    
    def _create_default_icon(self) -> Image.Image:
        """
        Crée une icône par défaut simple.
        
        Returns:
            Image PIL
        """
        from PIL import ImageDraw
        
        # Créer une image 64x64 avec un fond bleu
        img = Image.new('RGBA', (64, 64), (30, 136, 229, 255))
        draw = ImageDraw.Draw(img)
        
        # Dessiner un cercle blanc au centre
        draw.ellipse([16, 16, 48, 48], fill=(255, 255, 255, 255))
        
        return img
    
    def _create_menu(self) -> pystray.Menu:
        """
        Crée le menu contextuel du system tray.
        
        Returns:
            Menu pystray
        """
        return pystray.Menu(
            # Premier item = option par défaut (en gras sous Windows)
            pystray.MenuItem(
                "⚙️ Ouvrir l'application",
                self._menu_show,
                default=True  # Marque comme action par défaut
            ),
            pystray.Menu.SEPARATOR,
            pystray.MenuItem(
                "🔄 Changer maintenant",
                self._menu_rotate_now
            ),
            pystray.MenuItem(
                lambda _: "▶️ Reprendre rotation" if self.is_paused else "⏸️ Pause rotation",
                self._menu_toggle_pause
            ),
            pystray.Menu.SEPARATOR,
            pystray.MenuItem(
                "✕ Quitter",
                self._menu_quit
            )
        )
    
    def _menu_show(self, icon=None, item=None) -> None:
        """Callback pour afficher la fenêtre."""
        if self.on_show:
            self.on_show()
    
    def _menu_quit(self, icon, item) -> None:
        """Callback pour quitter l'application."""
        logger.info("Fermeture depuis le system tray")
        if self.icon:
            self.icon.stop()
        if self.on_quit:
            self.on_quit()
    
    def _menu_rotate_now(self, icon, item) -> None:
        """Callback pour forcer une rotation."""
        if self.on_rotate_now:
            self.on_rotate_now()
    
    def _menu_toggle_pause(self, icon, item) -> None:
        """Callback pour mettre en pause/reprendre."""
        if self.on_toggle_pause:
            self.is_paused = not self.is_paused
            self.on_toggle_pause()
    
    def start(self) -> None:
        """Démarre l'icône dans le system tray."""
        if not self.enabled or self.icon is not None:
            return
        
        try:
            # Définir une fonction pour le clic gauche (ouverture de l'app)
            def on_left_click(icon, item=None):
                """Appelé lors d'un clic gauche sur l'icône."""
                logger.debug("Clic gauche détecté sur l'icône du tray")
                if self.on_show:
                    self.on_show()
            
            # Créer l'icône
            self.icon = pystray.Icon(
                "UPAWallpaperManager",  # Nom court sans espaces pour l'ID
                self.image,
                "UPA Wallpaper Manager",  # Tooltip
                menu=self._create_menu()
            )
            
            # Définir l'action par défaut (clic gauche ou double-clic)
            # Sous Windows, pystray déclenche ceci sur le clic gauche
            self.icon.default_action = on_left_click
            
            # Lancer dans un thread séparé pour ne pas bloquer l'UI
            thread = threading.Thread(target=self._run_icon, daemon=True)
            thread.start()
            
            logger.info("System tray démarré avec action de clic configurée")
            
        except Exception as e:
            logger.error(f"Erreur lors du démarrage du system tray: {e}")
            self.enabled = False
    
    def _run_icon(self) -> None:
        """Lance l'icône (bloquant)."""
        try:
            if self.icon:
                self.icon.run()
        except KeyboardInterrupt:
            # Interruption normale
            pass
        except Exception as e:
            # Ignorer les erreurs WNDPROC/LRESULT de pystray (bugs internes Windows)
            error_msg = str(e).lower()
            if "wndproc" not in error_msg and "lresult" not in error_msg and "wparam" not in error_msg:
                logger.error(f"Erreur dans le thread du system tray: {e}")
    
    def stop(self) -> None:
        """Arrête l'icône du system tray."""
        if self.icon:
            try:
                self.icon.stop()
                logger.info("System tray arrêté")
            except Exception as e:
                logger.error(f"Erreur lors de l'arrêt du system tray: {e}")
            finally:
                self.icon = None
    
    def update_pause_state(self, is_paused: bool) -> None:
        """
        Met à jour l'état de pause.
        
        Args:
            is_paused: True si en pause
        """
        self.is_paused = is_paused
        
        # Mettre à jour le menu
        if self.icon:
            self.icon.menu = self._create_menu()
    
    def show_notification(self, title: str, message: str, duration: int = 5) -> None:
        """
        Affiche une notification Windows.
        
        Args:
            title: Titre de la notification
            message: Message de la notification
            duration: Durée d'affichage en secondes
        """
        if not self.enabled:
            return
        
        # Forcer le titre à être "UPA Wallpaper Manager" si c'est vide ou "Python"
        if not title or title.lower() == "python":
            title = "UPA Wallpaper Manager"
        
        # Essayer win10toast UNIQUEMENT en mode développement
        # En mode compilé (.exe), win10toast ne fonctionne pas bien avec PyInstaller
        if self.toast_notifier and not getattr(sys, 'frozen', False):
            try:
                # Utiliser un thread pour ne pas bloquer
                def show_toast():
                    try:
                        self.toast_notifier.show_toast(
                            title,
                            message,
                            duration=duration,
                            threaded=True
                        )
                    except Exception as e:
                        logger.error(f"Erreur win10toast: {e}")
                
                thread = threading.Thread(target=show_toast, daemon=True)
                thread.start()
                logger.debug(f"Notification win10toast affichée: {title}")
                return
            except Exception as e:
                logger.warning(f"Échec win10toast, fallback vers pystray: {e}")
        
        # Fallback vers pystray (peut afficher "Python" comme titre)
        if self.icon:
            try:
                self.icon.notify(message, title)
                logger.debug(f"Notification pystray affichée: {title}")
            except Exception as e:
                logger.error(f"Erreur lors de l'affichage de la notification: {e}")

