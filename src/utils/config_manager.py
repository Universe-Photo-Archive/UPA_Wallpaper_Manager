"""Module de gestion de la configuration utilisateur."""

import json
import os
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional

from .logger import get_logger

logger = get_logger()


class ConfigManager:
    """Gestionnaire de configuration de l'application."""
    
    DEFAULT_CONFIG = {
        "version": "1.0.0",
        "general": {
            "launch_on_startup": False,
            "ui_theme": "dark",
            "rotation_delay": 900,
            "rotation_delay_unit": "seconds",
            "random_mode": True
        },
        "screens": [],
        "cache": {
            "max_size_mb": 500,
            "last_cleanup": None
        },
        "network": {
            "rate_limit_seconds": 1,
            "timeout_seconds": 10
        }
    }
    
    def __init__(self, config_file: str = "data/config.json"):
        """
        Initialise le gestionnaire de configuration.
        
        Args:
            config_file: Chemin du fichier de configuration
        """
        self.config_file = Path(config_file)
        self.config: Dict[str, Any] = {}
        self._ensure_config_dir()
        self.load()
    
    def _ensure_config_dir(self) -> None:
        """Crée le répertoire de configuration si nécessaire."""
        self.config_file.parent.mkdir(parents=True, exist_ok=True)
    
    def load(self) -> None:
        """Charge la configuration depuis le fichier."""
        if self.config_file.exists():
            try:
                with open(self.config_file, 'r', encoding='utf-8') as f:
                    loaded_config = json.load(f)
                    # Fusionner avec la config par défaut pour ajouter les clés manquantes
                    self.config = self._merge_configs(self.DEFAULT_CONFIG.copy(), loaded_config)
                    logger.info(f"Configuration chargée depuis {self.config_file}")
            except Exception as e:
                logger.error(f"Erreur lors du chargement de la configuration: {e}", exc_info=True)
                self.config = self.DEFAULT_CONFIG.copy()
        else:
            logger.info("Aucune configuration trouvée, utilisation des valeurs par défaut")
            self.config = self.DEFAULT_CONFIG.copy()
            self.save()
    
    def _merge_configs(self, default: Dict, loaded: Dict) -> Dict:
        """
        Fusionne deux dictionnaires de configuration.
        
        Args:
            default: Configuration par défaut
            loaded: Configuration chargée
            
        Returns:
            Configuration fusionnée
        """
        result = default.copy()
        for key, value in loaded.items():
            if key in result and isinstance(result[key], dict) and isinstance(value, dict):
                result[key] = self._merge_configs(result[key], value)
            else:
                result[key] = value
        return result
    
    def save(self) -> None:
        """Sauvegarde la configuration dans le fichier."""
        try:
            with open(self.config_file, 'w', encoding='utf-8') as f:
                json.dump(self.config, f, indent=2, ensure_ascii=False)
            logger.debug(f"Configuration sauvegardée dans {self.config_file}")
        except Exception as e:
            logger.error(f"Erreur lors de la sauvegarde de la configuration: {e}", exc_info=True)
    
    def get(self, key_path: str, default: Any = None) -> Any:
        """
        Récupère une valeur de configuration par chemin.
        
        Args:
            key_path: Chemin de la clé (ex: "general.ui_theme")
            default: Valeur par défaut si la clé n'existe pas
            
        Returns:
            Valeur de configuration
        """
        keys = key_path.split('.')
        value = self.config
        
        for key in keys:
            if isinstance(value, dict) and key in value:
                value = value[key]
            else:
                return default
        
        return value
    
    def set(self, key_path: str, value: Any) -> None:
        """
        Définit une valeur de configuration par chemin.
        
        Args:
            key_path: Chemin de la clé (ex: "general.ui_theme")
            value: Valeur à définir
        """
        keys = key_path.split('.')
        config = self.config
        
        for key in keys[:-1]:
            if key not in config:
                config[key] = {}
            config = config[key]
        
        config[keys[-1]] = value
        self.save()
    
    def get_screens(self) -> List[Dict[str, Any]]:
        """
        Récupère la configuration des écrans.
        
        Returns:
            Liste des configurations d'écrans
        """
        return self.config.get('screens', [])
    
    def update_screens(self, screens: List[Dict[str, Any]]) -> None:
        """
        Met à jour la configuration des écrans.
        
        Args:
            screens: Liste des configurations d'écrans
        """
        self.config['screens'] = screens
        self.save()
    
    def get_rotation_delay_seconds(self) -> int:
        """
        Récupère le délai de rotation en secondes.
        
        Returns:
            Délai en secondes
        """
        delay = self.get('general.rotation_delay', 900)
        unit = self.get('general.rotation_delay_unit', 'seconds')
        
        if unit == 'minutes':
            return delay * 60
        elif unit == 'hours':
            return delay * 3600
        else:
            return delay
    
    def update_cache_cleanup(self) -> None:
        """Met à jour la date du dernier nettoyage du cache."""
        self.set('cache.last_cleanup', datetime.now().isoformat())
    
    def get_cache_max_size_bytes(self) -> int:
        """
        Récupère la taille maximale du cache en octets.
        
        Returns:
            Taille en octets
        """
        max_size_mb = self.get('cache.max_size_mb', 500)
        return max_size_mb * 1024 * 1024


