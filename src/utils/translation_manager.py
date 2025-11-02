"""Module de gestion des traductions de l'application."""

import json
import os
import sys
import shutil
from pathlib import Path
from typing import Dict, List, Optional
from .logger import get_logger

logger = get_logger()


class TranslationManager:
    """Gestionnaire de traductions multilingues."""
    
    def __init__(self, config_manager=None):
        """
        Initialise le gestionnaire de traductions.
        
        Args:
            config_manager: Gestionnaire de configuration pour sauvegarder la langue
        """
        self.config_manager = config_manager
        self.current_language = "fr"
        self.translations: Dict[str, Dict[str, str]] = {}
        self.available_languages: List[Dict[str, str]] = []
        
        # Déterminer le dossier des langues
        if getattr(sys, 'frozen', False):
            # Mode .exe compilé
            # Toujours utiliser le dossier langs/ à côté de l'exe
            exe_dir = Path(os.path.dirname(sys.executable))
            self.langs_dir = exe_dir / "langs"
            
            # Si le dossier n'existe pas, copier depuis _MEIPASS
            if not self.langs_dir.exists() and hasattr(sys, '_MEIPASS'):
                logger.info("Premier lancement : copie des fichiers de langue...")
                bundled_langs = Path(sys._MEIPASS) / "langs"
                if bundled_langs.exists():
                    try:
                        shutil.copytree(bundled_langs, self.langs_dir)
                        logger.info(f"Fichiers de langue copiés dans: {self.langs_dir}")
                    except Exception as e:
                        logger.error(f"Erreur lors de la copie des fichiers de langue: {e}")
                        # Fallback : utiliser directement depuis _MEIPASS
                        self.langs_dir = bundled_langs
        else:
            # Mode développement
            self.langs_dir = Path(__file__).parent.parent.parent / "langs"
        
        self._load_available_languages()
        self._load_language_from_config()
    
    def _load_available_languages(self) -> None:
        """Charge la liste des langues disponibles depuis le dossier langs."""
        if not self.langs_dir.exists():
            logger.warning(f"Dossier des langues non trouvé: {self.langs_dir}")
            self.langs_dir.mkdir(parents=True, exist_ok=True)
            return
        
        self.available_languages = []
        
        for lang_file in self.langs_dir.glob("*.json"):
            try:
                with open(lang_file, 'r', encoding='utf-8') as f:
                    data = json.load(f)
                    
                    # Vérifier que le fichier contient les métadonnées nécessaires
                    if "language_code" in data and "language_name" in data:
                        self.available_languages.append({
                            "code": data["language_code"],
                            "name": data["language_name"],
                            "file": str(lang_file)
                        })
                        logger.info(f"Langue détectée: {data['language_name']} ({data['language_code']})")
            except Exception as e:
                logger.error(f"Erreur lors du chargement de {lang_file}: {e}")
        
        # Trier par code de langue
        self.available_languages.sort(key=lambda x: x["code"])
        
        logger.info(f"{len(self.available_languages)} langue(s) disponible(s)")
    
    def _load_language_from_config(self) -> None:
        """Charge la langue depuis la configuration."""
        if self.config_manager:
            saved_lang = self.config_manager.get('general.language', 'fr')
            self.set_language(saved_lang)
        else:
            self.set_language('fr')
    
    def set_language(self, language_code: str) -> bool:
        """
        Définit la langue actuelle.
        
        Args:
            language_code: Code de la langue (ex: 'fr', 'en')
            
        Returns:
            True si la langue a été chargée avec succès
        """
        # Trouver le fichier de langue
        lang_info = next((l for l in self.available_languages if l["code"] == language_code), None)
        
        if not lang_info:
            logger.warning(f"Langue '{language_code}' non trouvée, utilisation du français par défaut")
            language_code = "fr"
            lang_info = next((l for l in self.available_languages if l["code"] == language_code), None)
            
            if not lang_info:
                logger.error("Aucune langue disponible!")
                return False
        
        try:
            with open(lang_info["file"], 'r', encoding='utf-8') as f:
                data = json.load(f)
                self.translations = data.get("translations", {})
                self.current_language = language_code
                
                # Sauvegarder dans la config
                if self.config_manager:
                    self.config_manager.set('general.language', language_code)
                
                logger.info(f"Langue chargée: {lang_info['name']} ({language_code})")
                return True
                
        except Exception as e:
            logger.error(f"Erreur lors du chargement de la langue '{language_code}': {e}")
            return False
    
    def get(self, key: str, default: Optional[str] = None) -> str:
        """
        Récupère une traduction par clé.
        
        Args:
            key: Clé de traduction (ex: "app.title")
            default: Valeur par défaut si la clé n'existe pas
            
        Returns:
            Traduction ou clé si non trouvée
        """
        value = self.translations.get(key, default or key)
        return value
    
    def get_available_languages(self) -> List[Dict[str, str]]:
        """
        Récupère la liste des langues disponibles.
        
        Returns:
            Liste des langues avec leur code et nom
        """
        return self.available_languages
    
    def get_current_language(self) -> str:
        """
        Récupère le code de la langue actuelle.
        
        Returns:
            Code de la langue (ex: 'fr')
        """
        return self.current_language
    
    def get_current_language_name(self) -> str:
        """
        Récupère le nom de la langue actuelle.
        
        Returns:
            Nom de la langue (ex: 'Français')
        """
        lang_info = next((l for l in self.available_languages if l["code"] == self.current_language), None)
        return lang_info["name"] if lang_info else self.current_language


# Import sys pour la détection du mode .exe
import sys

