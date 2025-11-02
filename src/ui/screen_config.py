"""Widget de configuration d'un écran."""

import customtkinter as ctk
from pathlib import Path
from typing import Callable, Dict, List, Optional
from PIL import Image

from ..utils.logger import get_logger

logger = get_logger()


class ScreenConfigWidget(ctk.CTkFrame):
    """Widget de configuration pour un écran."""
    
    def __init__(
        self,
        master,
        screen_info: Dict,
        themes: List[str],
        translation_manager=None,
        on_theme_change: Optional[Callable] = None,
        on_rotation_toggle: Optional[Callable] = None,
        **kwargs
    ):
        """
        Initialise le widget de configuration d'écran.
        
        Args:
            master: Widget parent
            screen_info: Informations de l'écran
            themes: Liste des thèmes disponibles
            translation_manager: Gestionnaire de traductions
            on_theme_change: Callback lors du changement de thème
            on_rotation_toggle: Callback lors du toggle de rotation
        """
        super().__init__(master, **kwargs)
        
        self.screen_info = screen_info
        self.translation_manager = translation_manager
        all_themes_text = translation_manager.get('screen.all_themes') if translation_manager else "Tous les thèmes"
        self.themes = [all_themes_text] + themes
        self.all_themes_text = all_themes_text
        self.on_theme_change = on_theme_change
        self.on_rotation_toggle = on_rotation_toggle
        self.current_wallpaper_path: Optional[str] = None
        
        self._setup_ui()
    
    def _setup_ui(self) -> None:
        """Configure l'interface du widget."""
        # En-tête avec info écran
        header = ctk.CTkFrame(self)
        header.pack(fill="x", padx=10, pady=(10, 5))
        
        # Construire le nom de l'écran avec traduction
        screen_num = self.screen_info.get('id', 0) + 1
        screen_name_key = self.translation_manager.get('screen.name') if self.translation_manager else "Screen"
        is_primary = self.screen_info.get('is_primary', False)
        if is_primary:
            primary_key = self.translation_manager.get('screen.primary') if self.translation_manager else "Primary"
            primary_text = f" ({primary_key})"
        else:
            primary_text = ""
        screen_name = f"{screen_name_key} {screen_num}{primary_text}"
        resolution = self.screen_info.get('resolution', '')
        
        title_label = ctk.CTkLabel(
            header,
            text=f"{screen_name} - {resolution}",
            font=ctk.CTkFont(size=14, weight="bold")
        )
        title_label.pack(side="left", padx=5)
        
        # Frame de contrôles
        controls_frame = ctk.CTkFrame(self)
        controls_frame.pack(fill="x", padx=10, pady=5)
        
        # Sélection du thème
        theme_frame = ctk.CTkFrame(controls_frame)
        theme_frame.pack(side="left", padx=5, pady=5)
        
        theme_label_text = self.translation_manager.get('screen.theme') if self.translation_manager else "Thème:"
        ctk.CTkLabel(theme_frame, text=theme_label_text).pack(side="left", padx=5)
        
        self.theme_combo = ctk.CTkComboBox(
            theme_frame,
            values=self.themes,
            width=200,
            command=self._on_theme_changed
        )
        self.theme_combo.set(self.all_themes_text)
        self.theme_combo.pack(side="left", padx=5)
        
        # Toggle rotation
        rotation_frame = ctk.CTkFrame(controls_frame)
        rotation_frame.pack(side="left", padx=20, pady=5)
        
        rotation_text = self.translation_manager.get('screen.rotation_enabled') if self.translation_manager else "Rotation activée"
        self.rotation_switch = ctk.CTkSwitch(
            rotation_frame,
            text=rotation_text,
            command=self._on_rotation_toggled
        )
        self.rotation_switch.select()
        self.rotation_switch.pack(padx=5)
        
        # Zone d'aperçu
        preview_frame = ctk.CTkFrame(self)
        preview_frame.pack(fill="both", expand=True, padx=10, pady=5)
        
        self.preview_label = ctk.CTkLabel(
            preview_frame,
            text="Aucun fond d'écran actif",
            width=400,
            height=200
        )
        self.preview_label.pack(padx=10, pady=10)
        
        # Label du nom du fichier
        self.filename_label = ctk.CTkLabel(
            preview_frame,
            text="",
            font=ctk.CTkFont(size=10)
        )
        self.filename_label.pack(pady=5)
    
    def _on_theme_changed(self, theme: str) -> None:
        """Gère le changement de thème."""
        logger.debug(f"Thème changé pour écran {self.screen_info['id']}: {theme}")
        
        if self.on_theme_change:
            # Convertir "Tous les thèmes" (ou sa traduction) en "all"
            theme_value = "all" if theme == self.all_themes_text else theme
            self.on_theme_change(self.screen_info['id'], theme_value)
    
    def _on_rotation_toggled(self) -> None:
        """Gère le toggle de la rotation."""
        is_enabled = self.rotation_switch.get() == 1
        logger.debug(f"Rotation {'activée' if is_enabled else 'désactivée'} pour écran {self.screen_info['id']}")
        
        if self.on_rotation_toggle:
            self.on_rotation_toggle(self.screen_info['id'], is_enabled)
    
    def update_preview(self, image_path: str) -> None:
        """
        Met à jour l'aperçu de l'image.
        
        Args:
            image_path: Chemin de l'image
        """
        try:
            self.current_wallpaper_path = image_path
            filename = Path(image_path).name
            
            # Charger et afficher l'image
            if Path(image_path).exists():
                # Charger l'image avec PIL
                pil_image = Image.open(image_path)
                
                # Calculer les dimensions pour l'aperçu (max 400x200)
                preview_width = 400
                preview_height = 200
                
                # Calculer le ratio pour garder les proportions
                img_ratio = pil_image.width / pil_image.height
                preview_ratio = preview_width / preview_height
                
                if img_ratio > preview_ratio:
                    # Image plus large
                    width = preview_width
                    height = int(width / img_ratio)
                else:
                    # Image plus haute
                    height = preview_height
                    width = int(height * img_ratio)
                
                # Redimensionner
                pil_image = pil_image.resize((width, height), Image.Resampling.LANCZOS)
                
                # Convertir en CTkImage
                ctk_image = ctk.CTkImage(
                    light_image=pil_image,
                    dark_image=pil_image,
                    size=(width, height)
                )
                
                # Afficher l'image
                self.preview_label.configure(image=ctk_image, text="")
                self.preview_label.image = ctk_image  # Garder une référence
                
                # Afficher le nom du fichier en bas
                self.filename_label.configure(text=filename)
            else:
                self.preview_label.configure(text=f"❌ Fichier introuvable", image=None)
                self.filename_label.configure(text=filename)
            
        except Exception as e:
            logger.error(f"Erreur lors de la mise à jour de l'aperçu: {e}")
            self.preview_label.configure(text=f"❌ Erreur de chargement", image=None)
            self.filename_label.configure(text=filename if 'filename' in locals() else "")
    
    def get_theme(self) -> str:
        """
        Récupère le thème sélectionné.
        
        Returns:
            Nom du thème ou "all"
        """
        theme = self.theme_combo.get()
        return "all" if theme == self.all_themes_text else theme
    
    def set_theme(self, theme: str) -> None:
        """
        Définit le thème sélectionné.
        
        Args:
            theme: Nom du thème ou "all"
        """
        display_theme = self.all_themes_text if theme == "all" else theme
        if display_theme in self.themes:
            self.theme_combo.set(display_theme)
    
    def is_rotation_enabled(self) -> bool:
        """
        Vérifie si la rotation est activée.
        
        Returns:
            True si activée
        """
        return self.rotation_switch.get() == 1
    
    def set_rotation_enabled(self, enabled: bool) -> None:
        """
        Active ou désactive la rotation.
        
        Args:
            enabled: True pour activer
        """
        if enabled:
            self.rotation_switch.select()
        else:
            self.rotation_switch.deselect()
    
    def update_themes(self, themes: List[str]) -> None:
        """
        Met à jour la liste des thèmes disponibles.
        
        Args:
            themes: Liste des thèmes
        """
        self.themes = [self.all_themes_text] + themes
        current = self.theme_combo.get()
        self.theme_combo.configure(values=self.themes)
        self.theme_combo.set(current if current in self.themes else self.all_themes_text)


