"""Module de téléchargement et gestion du cache d'images."""

import hashlib
import json
import os
import shutil
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional

import requests
from PIL import Image

from ..utils.logger import get_logger

logger = get_logger()


class ImageDownloader:
    """Gestionnaire de téléchargement et cache d'images."""
    
    def __init__(
        self,
        cache_dir: str = "data/wallpapers",
        cache_index_file: str = "data/cache_index.json"
    ):
        """
        Initialise le gestionnaire de cache.
        
        Args:
            cache_dir: Répertoire du cache
            cache_index_file: Fichier d'index du cache
        """
        self.cache_dir = Path(cache_dir)
        self.cache_index_file = Path(cache_index_file)
        self.cache_index: Dict = {}
        
        # Créer les répertoires
        self.cache_dir.mkdir(parents=True, exist_ok=True)
        self.cache_index_file.parent.mkdir(parents=True, exist_ok=True)
        
        # Charger l'index
        self.load_cache_index()
    
    def load_cache_index(self) -> None:
        """Charge l'index du cache depuis le fichier."""
        if self.cache_index_file.exists():
            try:
                with open(self.cache_index_file, 'r', encoding='utf-8') as f:
                    self.cache_index = json.load(f)
                logger.debug("Index du cache chargé")
            except Exception as e:
                logger.error(f"Erreur lors du chargement de l'index: {e}")
                self.cache_index = self._create_empty_index()
        else:
            self.cache_index = self._create_empty_index()
            self.save_cache_index()
    
    def save_cache_index(self) -> None:
        """Sauvegarde l'index du cache dans le fichier."""
        try:
            with open(self.cache_index_file, 'w', encoding='utf-8') as f:
                json.dump(self.cache_index, f, indent=2, ensure_ascii=False)
            logger.debug("Index du cache sauvegardé")
        except Exception as e:
            logger.error(f"Erreur lors de la sauvegarde de l'index: {e}")
    
    def _create_empty_index(self) -> Dict:
        """
        Crée un index vide.
        
        Returns:
            Structure d'index vide
        """
        return {
            "themes": {},
            "total_size": 0,
            "last_update": datetime.now().isoformat()
        }
    
    def download_image(
        self,
        url: str,
        theme_name: str,
        filename: Optional[str] = None,
        force: bool = False
    ) -> Optional[str]:
        """
        Télécharge une image et la met en cache.
        
        Args:
            url: URL de l'image
            theme_name: Nom du thème
            filename: Nom du fichier (extrait de l'URL si None)
            force: Forcer le téléchargement même si en cache
            
        Returns:
            Chemin local de l'image ou None en cas d'erreur
        """
        if not filename:
            filename = url.split('/')[-1].split('?')[0]
        
        # Nettoyer le nom du thème et du fichier
        theme_name = self._sanitize_filename(theme_name)
        filename = self._sanitize_filename(filename)
        
        # Créer le répertoire du thème
        theme_dir = self.cache_dir / theme_name
        theme_dir.mkdir(parents=True, exist_ok=True)
        
        # Chemin local
        local_path = theme_dir / filename
        
        # Vérifier si déjà en cache
        if not force and local_path.exists():
            logger.debug(f"Image déjà en cache: {filename}")
            return str(local_path)
        
        # Télécharger
        try:
            logger.debug(f"Téléchargement de {filename} depuis {url}")
            response = requests.get(url, timeout=30, stream=True)
            response.raise_for_status()
            
            # Sauvegarder
            with open(local_path, 'wb') as f:
                for chunk in response.iter_content(chunk_size=8192):
                    f.write(chunk)
            
            # Vérifier que c'est une image valide
            try:
                with Image.open(local_path) as img:
                    img.verify()
            except Exception as e:
                logger.error(f"Image invalide téléchargée: {e}")
                local_path.unlink(missing_ok=True)
                return None
            
            # Mettre à jour l'index
            file_size = local_path.stat().st_size
            self._update_index(theme_name, filename, url, file_size)
            
            logger.info(f"Image téléchargée: {filename} ({file_size / 1024:.1f} KB)")
            return str(local_path)
            
        except Exception as e:
            logger.error(f"Erreur lors du téléchargement de {url}: {e}")
            if local_path.exists():
                local_path.unlink(missing_ok=True)
            return None
    
    def _sanitize_filename(self, filename: str) -> str:
        """
        Nettoie un nom de fichier.
        
        Args:
            filename: Nom à nettoyer
            
        Returns:
            Nom nettoyé
        """
        # Remplacer les caractères interdits
        invalid_chars = '<>:"/\\|?*'
        for char in invalid_chars:
            filename = filename.replace(char, '_')
        
        return filename
    
    def _update_index(self, theme_name: str, filename: str, url: str, size: int) -> None:
        """
        Met à jour l'index du cache.
        
        Args:
            theme_name: Nom du thème
            filename: Nom du fichier
            url: URL de l'image
            size: Taille du fichier
        """
        if theme_name not in self.cache_index['themes']:
            self.cache_index['themes'][theme_name] = {
                'last_update': datetime.now().isoformat(),
                'images': []
            }
        
        theme = self.cache_index['themes'][theme_name]
        
        # Vérifier si l'image existe déjà dans l'index
        existing = next((img for img in theme['images'] if img['filename'] == filename), None)
        
        if existing:
            # Mettre à jour
            self.cache_index['total_size'] -= existing.get('size', 0)
            existing['url'] = url
            existing['size'] = size
            existing['downloaded'] = True
        else:
            # Ajouter
            theme['images'].append({
                'filename': filename,
                'url': url,
                'size': size,
                'downloaded': True
            })
        
        self.cache_index['total_size'] += size
        self.cache_index['last_update'] = datetime.now().isoformat()
        theme['last_update'] = datetime.now().isoformat()
        
        self.save_cache_index()
    
    def get_cached_images(self, theme_name: Optional[str] = None) -> List[str]:
        """
        Récupère la liste des images en cache.
        
        Args:
            theme_name: Nom du thème (tous si None)
            
        Returns:
            Liste des chemins d'images
        """
        images = []
        
        if theme_name:
            # Images d'un thème spécifique
            theme_dir = self.cache_dir / theme_name
            if theme_dir.exists():
                for img_file in theme_dir.glob('*'):
                    if img_file.is_file() and img_file.suffix.lower() in ['.jpg', '.jpeg', '.png', '.webp', '.bmp']:
                        images.append(str(img_file))
        else:
            # Toutes les images
            for theme_dir in self.cache_dir.iterdir():
                if theme_dir.is_dir():
                    for img_file in theme_dir.glob('*'):
                        if img_file.is_file() and img_file.suffix.lower() in ['.jpg', '.jpeg', '.png', '.webp', '.bmp']:
                            images.append(str(img_file))
        
        return images
    
    def get_cache_size(self) -> int:
        """
        Calcule la taille totale du cache.
        
        Returns:
            Taille en octets
        """
        total_size = 0
        
        for theme_dir in self.cache_dir.iterdir():
            if theme_dir.is_dir():
                for img_file in theme_dir.rglob('*'):
                    if img_file.is_file():
                        total_size += img_file.stat().st_size
        
        return total_size
    
    def clear_cache(self, theme_name: Optional[str] = None) -> None:
        """
        Vide le cache.
        
        Args:
            theme_name: Nom du thème à vider (tous si None)
        """
        try:
            if theme_name:
                # Vider un thème spécifique
                theme_dir = self.cache_dir / theme_name
                if theme_dir.exists():
                    shutil.rmtree(theme_dir)
                    logger.info(f"Cache du thème '{theme_name}' vidé")
                
                # Mettre à jour l'index
                if theme_name in self.cache_index['themes']:
                    theme_size = sum(img.get('size', 0) for img in self.cache_index['themes'][theme_name]['images'])
                    self.cache_index['total_size'] -= theme_size
                    del self.cache_index['themes'][theme_name]
            else:
                # Vider tout le cache
                if self.cache_dir.exists():
                    shutil.rmtree(self.cache_dir)
                    self.cache_dir.mkdir(parents=True, exist_ok=True)
                    logger.info("Cache complet vidé")
                
                self.cache_index = self._create_empty_index()
            
            self.save_cache_index()
            
        except Exception as e:
            logger.error(f"Erreur lors du vidage du cache: {e}", exc_info=True)
    
    def cleanup_old_images(self, max_size_bytes: int) -> None:
        """
        Nettoie les anciennes images si le cache dépasse la taille maximale.
        
        Args:
            max_size_bytes: Taille maximale en octets
        """
        current_size = self.get_cache_size()
        
        if current_size <= max_size_bytes:
            logger.debug(f"Cache sous la limite ({current_size / 1024 / 1024:.1f} MB)")
            return
        
        logger.info(f"Nettoyage du cache ({current_size / 1024 / 1024:.1f} MB > {max_size_bytes / 1024 / 1024:.1f} MB)")
        
        # Récupérer tous les fichiers avec leur date de modification
        files = []
        for theme_dir in self.cache_dir.iterdir():
            if theme_dir.is_dir():
                for img_file in theme_dir.glob('*'):
                    if img_file.is_file():
                        files.append({
                            'path': img_file,
                            'size': img_file.stat().st_size,
                            'mtime': img_file.stat().st_mtime
                        })
        
        # Trier par date (plus ancien en premier)
        files.sort(key=lambda x: x['mtime'])
        
        # Supprimer les plus anciens jusqu'à atteindre la limite
        for file_info in files:
            if current_size <= max_size_bytes:
                break
            
            try:
                file_info['path'].unlink()
                current_size -= file_info['size']
                logger.debug(f"Supprimé: {file_info['path'].name}")
            except Exception as e:
                logger.error(f"Erreur lors de la suppression de {file_info['path']}: {e}")
        
        # Reconstruire l'index
        self._rebuild_index()
        
        logger.info(f"Nettoyage terminé. Taille actuelle: {current_size / 1024 / 1024:.1f} MB")
    
    def _rebuild_index(self) -> None:
        """Reconstruit l'index du cache à partir des fichiers présents."""
        logger.debug("Reconstruction de l'index du cache")
        
        self.cache_index = self._create_empty_index()
        
        for theme_dir in self.cache_dir.iterdir():
            if theme_dir.is_dir():
                theme_name = theme_dir.name
                
                for img_file in theme_dir.glob('*'):
                    if img_file.is_file():
                        size = img_file.stat().st_size
                        self._update_index(theme_name, img_file.name, "", size)


