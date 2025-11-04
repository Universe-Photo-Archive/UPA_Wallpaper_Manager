"""Dialogue de mise à jour de l'application."""

import customtkinter as ctk
import threading
from typing import Callable, Optional

from ..utils.logger import get_logger

logger = get_logger()


class UpdateDialog(ctk.CTkToplevel):
    """Dialogue pour proposer une mise à jour."""
    
    def __init__(
        self,
        parent,
        translation_manager,
        current_version: str,
        latest_version: str,
        on_update: Optional[Callable] = None,
        on_skip: Optional[Callable] = None
    ):
        """
        Initialise le dialogue de mise à jour.
        
        Args:
            parent: Fenêtre parent
            translation_manager: Gestionnaire de traductions
            current_version: Version actuelle
            latest_version: Dernière version disponible
            on_update: Callback si l'utilisateur clique sur "Mettre à jour"
            on_skip: Callback si l'utilisateur coche "Ne plus me demander"
        """
        super().__init__(parent)
        
        self.translation_manager = translation_manager
        self.current_version = current_version
        self.latest_version = latest_version
        self.on_update = on_update
        self.on_skip = on_skip
        
        self.title(translation_manager.get('update.title'))
        self.geometry("500x250")
        
        # Rendre la fenêtre modale
        self.transient(parent)
        self.grab_set()
        
        # Centrer la fenêtre
        self.update_idletasks()
        x = parent.winfo_x() + (parent.winfo_width() - self.winfo_width()) // 2
        y = parent.winfo_y() + (parent.winfo_height() - self.winfo_height()) // 2
        self.geometry(f"+{x}+{y}")
        
        self._setup_ui()
    
    def _setup_ui(self) -> None:
        """Configure l'interface du dialogue."""
        # Message
        message = self.translation_manager.get('update.message').format(
            version=self.latest_version,
            current=self.current_version,
            latest=self.latest_version
        )
        
        message_label = ctk.CTkLabel(
            self,
            text=message,
            wraplength=450,
            justify="left",
            font=("", 12)
        )
        message_label.pack(padx=20, pady=20)
        
        # Checkbox "Ne plus me demander"
        self.skip_checkbox = ctk.CTkCheckBox(
            self,
            text=self.translation_manager.get('update.skip'),
            font=("", 11)
        )
        self.skip_checkbox.pack(padx=20, pady=10)
        
        # Boutons
        button_frame = ctk.CTkFrame(self)
        button_frame.pack(fill="x", padx=20, pady=20)
        
        ctk.CTkButton(
            button_frame,
            text=self.translation_manager.get('update.later'),
            command=self._on_later,
            width=120
        ).pack(side="right", padx=5)
        
        ctk.CTkButton(
            button_frame,
            text=self.translation_manager.get('update.update_now'),
            command=self._on_update,
            width=120,
            fg_color="green",
            hover_color="darkgreen"
        ).pack(side="right", padx=5)
    
    def _on_update(self) -> None:
        """Gère le clic sur "Mettre à jour"."""
        # Vérifier si "Ne plus me demander" est coché
        if self.skip_checkbox.get() and self.on_skip:
            self.on_skip()
        
        self.destroy()
        
        if self.on_update:
            self.on_update()
    
    def _on_later(self) -> None:
        """Gère le clic sur "La prochaine fois"."""
        # Vérifier si "Ne plus me demander" est coché
        if self.skip_checkbox.get() and self.on_skip:
            self.on_skip()
        
        self.destroy()


class UpdateProgressDialog(ctk.CTkToplevel):
    """Dialogue de progression du téléchargement de la mise à jour."""
    
    def __init__(self, parent, translation_manager):
        """
        Initialise le dialogue de progression.
        
        Args:
            parent: Fenêtre parent
            translation_manager: Gestionnaire de traductions
        """
        super().__init__(parent)
        
        self.translation_manager = translation_manager
        
        self.title(translation_manager.get('update.downloading'))
        self.geometry("400x150")
        
        # Rendre la fenêtre modale
        self.transient(parent)
        self.grab_set()
        
        # Centrer la fenêtre
        self.update_idletasks()
        x = parent.winfo_x() + (parent.winfo_width() - self.winfo_width()) // 2
        y = parent.winfo_y() + (parent.winfo_height() - self.winfo_height()) // 2
        self.geometry(f"+{x}+{y}")
        
        self._setup_ui()
    
    def _setup_ui(self) -> None:
        """Configure l'interface du dialogue."""
        # Label de statut
        self.status_label = ctk.CTkLabel(
            self,
            text=self.translation_manager.get('update.downloading'),
            font=("", 12)
        )
        self.status_label.pack(padx=20, pady=20)
        
        # Barre de progression
        self.progress_bar = ctk.CTkProgressBar(self, width=350)
        self.progress_bar.pack(padx=20, pady=10)
        self.progress_bar.set(0)
        
        # Label de pourcentage
        self.progress_label = ctk.CTkLabel(
            self,
            text="0%",
            font=("", 11)
        )
        self.progress_label.pack(padx=20, pady=5)
    
    def update_progress(self, downloaded: int, total: int) -> None:
        """
        Met à jour la barre de progression.
        
        Args:
            downloaded: Octets téléchargés
            total: Octets totaux
        """
        if total > 0:
            progress = downloaded / total
            self.progress_bar.set(progress)
            percentage = int(progress * 100)
            mb_downloaded = downloaded / 1024 / 1024
            mb_total = total / 1024 / 1024
            self.progress_label.configure(text=f"{percentage}% ({mb_downloaded:.1f} / {mb_total:.1f} MB)")
    
    def set_status(self, text: str) -> None:
        """
        Définit le texte de statut.
        
        Args:
            text: Texte à afficher
        """
        self.status_label.configure(text=text)

