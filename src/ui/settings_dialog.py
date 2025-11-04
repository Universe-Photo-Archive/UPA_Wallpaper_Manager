"""Dialogue des paramètres de l'application."""

import customtkinter as ctk
import threading
from typing import Callable, Dict, Optional

from ..utils.logger import get_logger
from ..utils.startup_manager import StartupManager

logger = get_logger()


class SettingsDialog(ctk.CTkToplevel):
    """Dialogue de paramètres."""
    
    def __init__(
        self,
        parent,
        config_manager,
        translation_manager,
        on_apply: Optional[Callable] = None
    ):
        """
        Initialise le dialogue de paramètres.
        
        Args:
            parent: Fenêtre parent
            config_manager: Gestionnaire de configuration
            translation_manager: Gestionnaire de traductions
            on_apply: Callback lors de l'application des paramètres
        """
        super().__init__(parent)
        
        self.config_manager = config_manager
        self.translation_manager = translation_manager
        self.on_apply = on_apply
        self.startup_manager = StartupManager()
        
        self.title(translation_manager.get('settings.title'))
        self.geometry("600x650")
        
        # Rendre la fenêtre modale
        self.transient(parent)
        self.grab_set()
        
        self._setup_ui()
        self._load_settings()
    
    def _setup_ui(self) -> None:
        """Configure l'interface du dialogue."""
        # Onglets
        self.tabview = ctk.CTkTabview(self)
        self.tabview.pack(fill="both", expand=True, padx=20, pady=20)
        
        # Onglet Général
        self.tab_general = self.tabview.add(self.translation_manager.get('settings.general'))
        self._setup_general_tab()
        
        # Onglet Cache
        self.tab_cache = self.tabview.add(self.translation_manager.get('settings.cache'))
        self._setup_cache_tab()
        
        # Onglet Avancé
        self.tab_advanced = self.tabview.add(self.translation_manager.get('settings.advanced'))
        self._setup_advanced_tab()
        
        # Boutons
        button_frame = ctk.CTkFrame(self)
        button_frame.pack(fill="x", padx=20, pady=(0, 20))
        
        ctk.CTkButton(
            button_frame,
            text=self.translation_manager.get('settings.cancel'),
            command=self.destroy,
            width=100
        ).pack(side="right", padx=5)
        
        ctk.CTkButton(
            button_frame,
            text=self.translation_manager.get('settings.apply'),
            command=self._apply_settings,
            width=100
        ).pack(side="right", padx=5)
    
    def _setup_general_tab(self) -> None:
        """Configure l'onglet Général."""
        # Frame pour le lancement au démarrage
        startup_frame = ctk.CTkFrame(self.tab_general)
        startup_frame.pack(fill="x", padx=20, pady=20)
        
        # Switch lancement au démarrage
        self.startup_switch = ctk.CTkSwitch(
            startup_frame,
            text=self.translation_manager.get('settings.launch_startup')
        )
        self.startup_switch.pack(padx=10, pady=10, anchor="w")
        
        # Informations sur le statut admin et méthode de démarrage
        status_frame = ctk.CTkFrame(startup_frame)
        status_frame.pack(fill="x", padx=10, pady=5)
        
        # Statut admin
        is_admin = self.startup_manager.is_admin()
        admin_text = "✓ Application lancée en administrateur" if is_admin else "⚠️ Application lancée en mode utilisateur"
        admin_color = "green" if is_admin else "orange"
        
        self.admin_label = ctk.CTkLabel(
            status_frame,
            text=admin_text,
            text_color=admin_color,
            font=("", 11)
        )
        self.admin_label.pack(padx=10, pady=2, anchor="w")
        
        # Méthode de démarrage actuelle
        startup_method = self.startup_manager.get_startup_method()
        method_texts = {
            "scheduled_task": "📋 Méthode: Tâche planifiée (avec admin, sans UAC)",
            "shortcut": "🔗 Méthode: Raccourci Startup (mode utilisateur)",
            "none": "❌ Démarrage automatique désactivé"
        }
        
        self.method_label = ctk.CTkLabel(
            status_frame,
            text=method_texts.get(startup_method, ""),
            font=("", 10),
            text_color="gray"
        )
        self.method_label.pack(padx=10, pady=2, anchor="w")
        
        # Info bulle
        if not is_admin:
            info_label = ctk.CTkLabel(
                status_frame,
                text="💡 Lancez en admin pour créer une tâche planifiée (recommandé)",
                font=("", 9),
                text_color="gray",
                wraplength=500
            )
            info_label.pack(padx=10, pady=5, anchor="w")
        
        # Thème de l'interface
        theme_frame = ctk.CTkFrame(self.tab_general)
        theme_frame.pack(fill="x", padx=20, pady=10)
        
        ctk.CTkLabel(
            theme_frame, 
            text=self.translation_manager.get('settings.ui_theme')
        ).pack(side="left", padx=10)
        
        self.theme_combo = ctk.CTkComboBox(
            theme_frame,
            values=[
                self.translation_manager.get('settings.theme_dark'),
                self.translation_manager.get('settings.theme_light')
            ],
            width=150
        )
        self.theme_combo.pack(side="left", padx=10)
        
        # Langue
        lang_frame = ctk.CTkFrame(self.tab_general)
        lang_frame.pack(fill="x", padx=20, pady=10)
        
        ctk.CTkLabel(
            lang_frame,
            text=self.translation_manager.get('settings.language')
        ).pack(side="left", padx=10)
        
        # Récupérer les langues disponibles
        available_langs = self.translation_manager.get_available_languages()
        lang_names = [lang['name'] for lang in available_langs]
        
        self.language_combo = ctk.CTkComboBox(
            lang_frame,
            values=lang_names,
            width=150
        )
        self.language_combo.pack(side="left", padx=10)
        
        # Mode aléatoire
        self.random_switch = ctk.CTkSwitch(
            self.tab_general,
            text=self.translation_manager.get('settings.random_mode')
        )
        self.random_switch.pack(padx=20, pady=20, anchor="w")
        
        # Frame pour les mises à jour
        update_frame = ctk.CTkFrame(self.tab_general)
        update_frame.pack(fill="x", padx=20, pady=20)
        
        ctk.CTkLabel(
            update_frame,
            text="Mises à jour",
            font=("", 13, "bold")
        ).pack(padx=10, pady=5, anchor="w")
        
        ctk.CTkButton(
            update_frame,
            text=self.translation_manager.get('update.button'),
            command=self._check_for_updates,
            width=200
        ).pack(padx=10, pady=10, anchor="w")
    
    def _setup_cache_tab(self) -> None:
        """Configure l'onglet Cache."""
        # Taille maximale du cache
        size_frame = ctk.CTkFrame(self.tab_cache)
        size_frame.pack(fill="x", padx=20, pady=20)
        
        ctk.CTkLabel(
            size_frame, 
            text=self.translation_manager.get('settings.cache_max_size')
        ).pack(side="left", padx=10)
        
        self.cache_size_entry = ctk.CTkEntry(size_frame, width=100)
        self.cache_size_entry.pack(side="left", padx=10)
        
        # Info cache actuel
        self.cache_info_label = ctk.CTkLabel(
            self.tab_cache,
            text=self.translation_manager.get('settings.cache_calculating'),
            font=ctk.CTkFont(size=12)
        )
        self.cache_info_label.pack(padx=20, pady=10)
        
        # Boutons d'action
        button_frame = ctk.CTkFrame(self.tab_cache)
        button_frame.pack(fill="x", padx=20, pady=20)
        
        ctk.CTkButton(
            button_frame,
            text=self.translation_manager.get('settings.clear_cache'),
            command=self._clear_cache,
            fg_color="red",
            hover_color="darkred"
        ).pack(pady=10)
        
        ctk.CTkButton(
            button_frame,
            text=self.translation_manager.get('settings.reload_themes'),
            command=self._reload_themes
        ).pack(pady=10)
    
    def _setup_advanced_tab(self) -> None:
        """Configure l'onglet Avancé."""
        # Rate limiting
        rate_frame = ctk.CTkFrame(self.tab_advanced)
        rate_frame.pack(fill="x", padx=20, pady=20)
        
        ctk.CTkLabel(
            rate_frame, 
            text=self.translation_manager.get('settings.rate_limit')
        ).pack(side="left", padx=10)
        
        self.rate_limit_entry = ctk.CTkEntry(rate_frame, width=100)
        self.rate_limit_entry.pack(side="left", padx=10)
        
        # Timeout réseau
        timeout_frame = ctk.CTkFrame(self.tab_advanced)
        timeout_frame.pack(fill="x", padx=20, pady=20)
        
        ctk.CTkLabel(
            timeout_frame, 
            text=self.translation_manager.get('settings.timeout')
        ).pack(side="left", padx=10)
        
        self.timeout_entry = ctk.CTkEntry(timeout_frame, width=100)
        self.timeout_entry.pack(side="left", padx=10)
        
        # Mode debug
        self.debug_switch = ctk.CTkSwitch(
            self.tab_advanced,
            text=self.translation_manager.get('settings.debug_mode')
        )
        self.debug_switch.pack(padx=20, pady=20, anchor="w")
    
    def _load_settings(self) -> None:
        """Charge les paramètres actuels."""
        # Général
        # Vérifier l'état réel du registre Windows
        is_startup_enabled = self.startup_manager.is_enabled()
        # Synchroniser avec la config
        self.config_manager.set('general.launch_on_startup', is_startup_enabled)
        
        self.startup_switch.select() if is_startup_enabled else self.startup_switch.deselect()
        
        ui_theme = self.config_manager.get('general.ui_theme', 'dark')
        theme_map = {
            'dark': self.translation_manager.get('settings.theme_dark'),
            'light': self.translation_manager.get('settings.theme_light')
        }
        self.theme_combo.set(theme_map.get(ui_theme, self.translation_manager.get('settings.theme_dark')))
        
        # Langue
        current_lang = self.translation_manager.get_current_language()
        available_langs = self.translation_manager.get_available_languages()
        current_lang_info = next((l for l in available_langs if l['code'] == current_lang), None)
        if current_lang_info:
            self.language_combo.set(current_lang_info['name'])
        
        self.random_switch.select() if self.config_manager.get('general.random_mode', True) else self.random_switch.deselect()
        
        # Cache
        max_size = self.config_manager.get('cache.max_size_mb', 500)
        self.cache_size_entry.insert(0, str(max_size))
        
        # Avancé
        rate_limit = self.config_manager.get('network.rate_limit_seconds', 1)
        self.rate_limit_entry.insert(0, str(rate_limit))
        
        timeout = self.config_manager.get('network.timeout_seconds', 10)
        self.timeout_entry.insert(0, str(timeout))
    
    def _apply_settings(self) -> None:
        """Applique les paramètres modifiés."""
        try:
            # Général - Lancement au démarrage
            launch_on_startup = self.startup_switch.get() == 1
            previous_launch_on_startup = self.config_manager.get('general.launch_on_startup', False)
            self.config_manager.set('general.launch_on_startup', launch_on_startup)
            
            # Vérifier si l'état du lancement automatique a RÉELLEMENT changé
            startup_state_changed = (launch_on_startup != previous_launch_on_startup)
            
            # Appliquer au système Windows dans un thread séparé SEULEMENT si l'état a changé
            if startup_state_changed:
                def apply_startup_setting():
                    """Applique le paramètre de démarrage dans un thread."""
                    try:
                        if launch_on_startup:
                            success, message = self.startup_manager.enable()
                        else:
                            success, message = self.startup_manager.disable()
                        
                        # Retour dans le thread principal pour afficher le message
                        # SEULEMENT si c'est un vrai changement d'état
                        self.after(0, lambda: self._show_startup_result(success, message))
                        
                    except Exception as e:
                        error_msg = f"Erreur lors de la configuration du démarrage : {e}"
                        logger.error(error_msg, exc_info=True)
                        self.after(0, lambda: self._show_warning("Erreur", error_msg))
                
                # Lancer dans un thread pour éviter le gel de l'interface
                startup_thread = threading.Thread(target=apply_startup_setting, daemon=True)
                startup_thread.start()
            else:
                logger.debug("État du lancement automatique inchangé, pas de modification nécessaire")
            
            theme_map = {
                self.translation_manager.get('settings.theme_dark'): 'dark',
                self.translation_manager.get('settings.theme_light'): 'light'
            }
            ui_theme = theme_map.get(self.theme_combo.get(), 'dark')
            self.config_manager.set('general.ui_theme', ui_theme)
            
            # Langue
            selected_lang_name = self.language_combo.get()
            available_langs = self.translation_manager.get_available_languages()
            selected_lang = next((l for l in available_langs if l['name'] == selected_lang_name), None)
            if selected_lang:
                self.translation_manager.set_language(selected_lang['code'])
            
            self.config_manager.set('general.random_mode', self.random_switch.get() == 1)
            
            # Cache
            try:
                max_size = int(self.cache_size_entry.get())
                if max_size > 0:
                    self.config_manager.set('cache.max_size_mb', max_size)
            except ValueError:
                logger.warning("Taille de cache invalide")
            
            # Avancé
            try:
                rate_limit = float(self.rate_limit_entry.get())
                if rate_limit > 0:
                    self.config_manager.set('network.rate_limit_seconds', rate_limit)
            except ValueError:
                logger.warning("Rate limit invalide")
            
            try:
                timeout = int(self.timeout_entry.get())
                if timeout > 0:
                    self.config_manager.set('network.timeout_seconds', timeout)
            except ValueError:
                logger.warning("Timeout invalide")
            
            logger.info("Paramètres appliqués")
            
            # Fermer la fenêtre immédiatement
            self.destroy()
            
            # Callback dans un thread pour ne pas bloquer l'interface
            if self.on_apply:
                def run_callback():
                    """Exécute le callback dans un thread."""
                    try:
                        self.on_apply()
                    except Exception as e:
                        logger.error(f"Erreur dans le callback on_apply: {e}", exc_info=True)
                
                callback_thread = threading.Thread(target=run_callback, daemon=True)
                callback_thread.start()
            
        except Exception as e:
            logger.error(f"Erreur lors de l'application des paramètres: {e}", exc_info=True)
    
    def _clear_cache(self) -> None:
        """Vide le cache."""
        # Dialogue de confirmation
        dialog = ctk.CTkInputDialog(
            text=self.translation_manager.get('settings.clear_cache_confirm'),
            title=self.translation_manager.get('settings.clear_cache_title')
        )
        
        response = dialog.get_input()
        
        if response and response.upper() in ["OUI", "YES"]:
            try:
                # Import ici pour éviter les dépendances circulaires
                from ..scraper.image_downloader import ImageDownloader
                
                downloader = ImageDownloader()
                downloader.clear_cache()
                
                self.cache_info_label.configure(text=self.translation_manager.get('settings.cache_cleared'))
                logger.info("Cache vidé par l'utilisateur")
                
            except Exception as e:
                logger.error(f"Erreur lors du vidage du cache: {e}", exc_info=True)
                self.cache_info_label.configure(text=f"{self.translation_manager.get('error.cache')} {str(e)}")
    
    def _reload_themes(self) -> None:
        """Recharge les thèmes depuis la source."""
        self.cache_info_label.configure(text=f"{self.translation_manager.get('status.loading')}")
        
        # Callback pour informer la fenêtre principale
        if self.on_apply:
            self.on_apply()
        
        self.cache_info_label.configure(text=self.translation_manager.get('settings.themes_reloaded'))
        logger.info("Rechargement des thèmes demandé")
    
    def update_cache_info(self, size_mb: float) -> None:
        """
        Met à jour les informations du cache.
        
        Args:
            size_mb: Taille du cache en MB
        """
        self.cache_info_label.configure(text=f"{self.translation_manager.get('settings.cache_current')} {size_mb:.1f} MB")
    
    def _show_startup_result(self, success: bool, message: str) -> None:
        """
        Affiche le résultat de la configuration du démarrage automatique.
        
        Args:
            success: True si succès, False sinon
            message: Message à afficher
        """
        if success:
            self._show_info("Lancement automatique", message)
        else:
            self._show_warning("Erreur", message)
    
    def _show_info(self, title: str, message: str) -> None:
        """
        Affiche un message d'information.
        
        Args:
            title: Titre du message
            message: Contenu du message
        """
        from tkinter import messagebox
        messagebox.showinfo(title, message, parent=self)
    
    def _show_warning(self, title: str, message: str) -> None:
        """
        Affiche un avertissement.
        
        Args:
            title: Titre du message
            message: Contenu du message
        """
        from tkinter import messagebox
        messagebox.showwarning(title, message, parent=self)
    
    def _check_for_updates(self) -> None:
        """Vérifie les mises à jour (bouton dans les paramètres)."""
        # Déléguer à la fenêtre principale
        if hasattr(self.master, 'check_for_updates_manual'):
            self.master.check_for_updates_manual()
        else:
            logger.warning("Impossible de vérifier les mises à jour depuis ce dialogue")


