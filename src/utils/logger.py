"""Module de logging pour l'application."""

import logging
import os
from logging.handlers import RotatingFileHandler
from pathlib import Path
from typing import Optional


class AppLogger:
    """Gestionnaire de logs de l'application."""
    
    def __init__(self, log_dir: str = "data/logs", log_file: str = "wallpaper_manager.log"):
        """
        Initialise le système de logging.
        
        Args:
            log_dir: Répertoire des fichiers de logs
            log_file: Nom du fichier de log principal
        """
        self.log_dir = Path(log_dir)
        self.log_file = self.log_dir / log_file
        
        # Créer le répertoire si nécessaire
        self.log_dir.mkdir(parents=True, exist_ok=True)
        
        # Configurer le logger
        self.logger = logging.getLogger("WallpaperManager")
        self.logger.setLevel(logging.DEBUG)
        
        # Éviter la duplication des handlers
        if not self.logger.handlers:
            self._setup_handlers()
    
    def _setup_handlers(self) -> None:
        """Configure les handlers de logging."""
        # Handler fichier avec rotation
        file_handler = RotatingFileHandler(
            self.log_file,
            maxBytes=10 * 1024 * 1024,  # 10 MB
            backupCount=5,
            encoding='utf-8'
        )
        file_handler.setLevel(logging.DEBUG)
        
        # Handler console
        console_handler = logging.StreamHandler()
        console_handler.setLevel(logging.INFO)
        
        # Format des logs
        formatter = logging.Formatter(
            '[%(asctime)s] [%(levelname)s] %(message)s',
            datefmt='%Y-%m-%d %H:%M:%S'
        )
        
        file_handler.setFormatter(formatter)
        console_handler.setFormatter(formatter)
        
        self.logger.addHandler(file_handler)
        self.logger.addHandler(console_handler)
    
    def info(self, message: str) -> None:
        """Log un message de niveau INFO."""
        self.logger.info(message)
    
    def warning(self, message: str) -> None:
        """Log un message de niveau WARNING."""
        self.logger.warning(message)
    
    def error(self, message: str, exc_info: bool = False) -> None:
        """
        Log un message de niveau ERROR.
        
        Args:
            message: Message d'erreur
            exc_info: Inclure les informations d'exception
        """
        self.logger.error(message, exc_info=exc_info)
    
    def debug(self, message: str) -> None:
        """Log un message de niveau DEBUG."""
        self.logger.debug(message)
    
    def set_debug_mode(self, enabled: bool) -> None:
        """
        Active ou désactive le mode debug.
        
        Args:
            enabled: True pour activer le mode debug
        """
        level = logging.DEBUG if enabled else logging.INFO
        for handler in self.logger.handlers:
            if isinstance(handler, logging.StreamHandler):
                handler.setLevel(level)


# Instance globale du logger
_logger_instance: Optional[AppLogger] = None


def get_logger() -> AppLogger:
    """
    Récupère l'instance unique du logger.
    
    Returns:
        Instance du logger
    """
    global _logger_instance
    if _logger_instance is None:
        _logger_instance = AppLogger()
    return _logger_instance


