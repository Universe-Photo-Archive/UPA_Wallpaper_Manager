"""Gestionnaire de cache intelligent pour les images."""

import json
import time
from pathlib import Path
from typing import Dict, List, Optional
from datetime import datetime, timedelta
from .logger import get_logger

logger = get_logger()


class SmartCacheManager:
    """Gère intelligemment le cache des images avec téléchargement progressif."""
    
    def __init__(self, cache_dir: Path, max_cached_images: int = 25, prefetch_count: int = 10):
        """
        Initialise le gestionnaire de cache.
        
        Args:
            cache_dir: Répertoire du cache
            max_cached_images: Nombre maximum d'images en cache
            prefetch_count: Nombre d'images à télécharger par lot
        """
        self.cache_dir = cache_dir
        self.max_cached_images = max_cached_images
        self.prefetch_count = prefetch_count
        self.index_file = cache_dir / "smart_index.json"
        self.index: Dict = {
            "themes": {},
            "settings": {
                "max_cached_images": max_cached_images,
                "prefetch_count": prefetch_count,
                "last_global_scan": None
            }
        }
        self._load_index()
    
    def _load_index(self) -> None:
        """Charge l'index depuis le disque."""
        if self.index_file.exists():
            try:
                with open(self.index_file, 'r', encoding='utf-8') as f:
                    self.index = json.load(f)
                logger.info(f"Index chargé: {len(self.index['themes'])} thèmes")
            except Exception as e:
                logger.error(f"Erreur lors du chargement de l'index: {e}")
    
    def _save_index(self) -> None:
        """Sauvegarde l'index sur le disque."""
        try:
            self.index_file.parent.mkdir(parents=True, exist_ok=True)
            with open(self.index_file, 'w', encoding='utf-8') as f:
                json.dump(self.index, f, indent=2, ensure_ascii=False)
            logger.debug("Index sauvegardé")
        except Exception as e:
            logger.error(f"Erreur lors de la sauvegarde de l'index: {e}")
    
    def update_theme_images(self, theme_name: str, theme_url: str, images: List[Dict]) -> None:
        """
        Met à jour la liste des images d'un thème.
        
        Args:
            theme_name: Nom du thème
            theme_url: URL du thème
            images: Liste des images {'filename': ..., 'url': ...}
        """
        if theme_name not in self.index['themes']:
            self.index['themes'][theme_name] = {
                "url": theme_url,
                "images": [],
                "last_scan": None,
                "current_cycle": 0
            }
        
        theme_data = self.index['themes'][theme_name]
        existing_urls = {img['url'] for img in theme_data['images']}
        
        # Ajouter les nouvelles images
        new_count = 0
        for img in images:
            if img['url'] not in existing_urls:
                theme_data['images'].append({
                    "filename": img['filename'],
                    "url": img['url'],
                    "displayed": False,
                    "display_count": 0,
                    "last_displayed": None,
                    "local_path": None,
                    "downloaded": False
                })
                new_count += 1
        
        theme_data['last_scan'] = datetime.now().isoformat()
        theme_data['total_images'] = len(theme_data['images'])
        
        if new_count > 0:
            logger.info(f"{new_count} nouvelles images détectées pour '{theme_name}' (Total: {theme_data['total_images']})")
        
        self._save_index()
    
    def get_next_batch(self, theme_name: str, count: Optional[int] = None) -> List[Dict]:
        """
        Récupère le prochain lot d'images à télécharger.
        
        Args:
            theme_name: Nom du thème
            count: Nombre d'images (None = prefetch_count par défaut)
        
        Returns:
            Liste d'images non téléchargées
        """
        if count is None:
            count = self.prefetch_count
        
        if theme_name not in self.index['themes']:
            return []
        
        theme_data = self.index['themes'][theme_name]
        
        # Récupérer les images non téléchargées et non affichées
        available = [
            img for img in theme_data['images']
            if not img['downloaded'] and not img['displayed']
        ]
        
        # Si toutes les images du cycle actuel ont été vues, réinitialiser
        if not available:
            undisplayed = [img for img in theme_data['images'] if not img['displayed']]
            if not undisplayed:
                logger.info(f"Cycle complet terminé pour '{theme_name}', réinitialisation...")
                self.reset_cycle(theme_name)
                available = [img for img in theme_data['images'] if not img['downloaded']]
            else:
                available = undisplayed
        
        # Retourner le lot demandé
        batch = available[:count]
        logger.info(f"Lot de {len(batch)} images prêt pour '{theme_name}'")
        return batch
    
    def get_cached_images(self, theme_name: str, only_undisplayed: bool = False) -> List[str]:
        """
        Récupère les chemins des images déjà en cache.
        
        Args:
            theme_name: Nom du thème
            only_undisplayed: Si True, ne retourne que les images non encore affichées
        
        Returns:
            Liste des chemins locaux
        """
        if theme_name not in self.index['themes']:
            return []
        
        theme_data = self.index['themes'][theme_name]
        paths = []
        
        for img in theme_data['images']:
            if img['downloaded'] and img['local_path']:
                # Filtrer selon le paramètre only_undisplayed
                if only_undisplayed and img['displayed']:
                    continue
                
                local_path = Path(img['local_path'])
                if local_path.exists():
                    paths.append(str(local_path))
                else:
                    # Fichier supprimé, mettre à jour l'index
                    img['downloaded'] = False
                    img['local_path'] = None
        
        return paths
    
    def mark_as_downloaded(self, theme_name: str, image_url: str, local_path: str) -> None:
        """
        Marque une image comme téléchargée.
        
        Args:
            theme_name: Nom du thème
            image_url: URL de l'image
            local_path: Chemin local où l'image est stockée
        """
        if theme_name not in self.index['themes']:
            return
        
        theme_data = self.index['themes'][theme_name]
        for img in theme_data['images']:
            if img['url'] == image_url:
                img['downloaded'] = True
                img['local_path'] = local_path
                break
        
        self._save_index()
    
    def mark_as_displayed(self, theme_name: str, image_path: str) -> None:
        """
        Marque une image comme affichée.
        
        Args:
            theme_name: Nom du thème
            image_path: Chemin local de l'image
        """
        if theme_name not in self.index['themes']:
            return
        
        theme_data = self.index['themes'][theme_name]
        for img in theme_data['images']:
            if img['local_path'] == image_path:
                img['displayed'] = True
                img['display_count'] += 1
                img['last_displayed'] = datetime.now().isoformat()
                logger.debug(f"Image marquée comme affichée: {Path(image_path).name}")
                break
        
        self._save_index()
    
    def cleanup_old_images(self, theme_name: Optional[str] = None) -> int:
        """
        Nettoie les anciennes images déjà affichées si le cache est plein.
        Fonctionne globalement sur tous les thèmes.
        
        Args:
            theme_name: Nom du thème (ignoré, nettoyage global)
        
        Returns:
            Nombre d'images supprimées
        """
        # Compter toutes les images téléchargées (tous thèmes confondus)
        all_downloaded = []
        for t_name, theme_data in self.index['themes'].items():  # Renommé pour éviter conflit
            for img in theme_data['images']:
                if img['downloaded'] and img['local_path']:
                    all_downloaded.append({
                        'theme': t_name,
                        'image': img
                    })
        
        total_downloaded = len(all_downloaded)
        logger.info(f"Vérification du cache: {total_downloaded}/{self.max_cached_images} images téléchargées")
        
        if total_downloaded <= self.max_cached_images:
            logger.info(f"✓ Cache OK, pas de nettoyage nécessaire")
            return 0
        
        logger.warning(f"⚠️ Cache plein: {total_downloaded}/{self.max_cached_images} images, nettoyage nécessaire...")
        
        # Trouver les images déjà affichées à supprimer (tous thèmes)
        displayed_images = [
            item for item in all_downloaded
            if item['image']['displayed']
        ]
        
        logger.info(f"Images affichées disponibles pour suppression: {len(displayed_images)}")
        
        if len(displayed_images) == 0:
            logger.warning("Aucune image affichée à supprimer, impossible de nettoyer le cache!")
            return 0
        
        # Trier par date d'affichage (les plus anciennes d'abord)
        displayed_images.sort(
            key=lambda x: x['image']['last_displayed'] or '',
            reverse=False
        )
        
        # Supprimer jusqu'à atteindre la limite
        to_delete = total_downloaded - self.max_cached_images
        deleted = 0
        logger.info(f"Suppression de {min(to_delete, len(displayed_images))} images...")
        
        for item in displayed_images[:to_delete]:
            try:
                img = item['image']
                local_path = Path(img['local_path'])
                if local_path.exists():
                    local_path.unlink()
                    logger.debug(f"Image supprimée: {local_path.name}")
                
                # Mettre à jour l'index
                img['downloaded'] = False
                img['local_path'] = None
                deleted += 1
                
            except Exception as e:
                logger.error(f"Erreur lors de la suppression: {e}")
        
        if deleted > 0:
            logger.info(f"{deleted} image(s) supprimée(s) du cache global ({total_downloaded} -> {total_downloaded - deleted})")
            self._save_index()
        
        return deleted
    
    def reset_cycle(self, theme_name: str) -> None:
        """
        Réinitialise le cycle d'affichage pour un thème.
        
        Args:
            theme_name: Nom du thème
        """
        if theme_name not in self.index['themes']:
            return
        
        theme_data = self.index['themes'][theme_name]
        theme_data['current_cycle'] += 1
        
        # Réinitialiser le flag 'displayed' pour toutes les images
        for img in theme_data['images']:
            img['displayed'] = False
        
        logger.info(f"Cycle réinitialisé pour '{theme_name}' (Cycle #{theme_data['current_cycle']})")
        self._save_index()
    
    def should_rescan(self, hours: int = 24) -> bool:
        """
        Vérifie si un re-scan global est nécessaire.
        
        Args:
            hours: Nombre d'heures avant un re-scan
        
        Returns:
            True si un re-scan est nécessaire
        """
        last_scan = self.index['settings'].get('last_global_scan')
        if not last_scan:
            return True
        
        try:
            last_scan_time = datetime.fromisoformat(last_scan)
            return datetime.now() - last_scan_time > timedelta(hours=hours)
        except:
            return True
    
    def mark_global_scan(self) -> None:
        """Marque qu'un scan global a été effectué."""
        self.index['settings']['last_global_scan'] = datetime.now().isoformat()
        self._save_index()
    
    def get_stats(self, theme_name: str) -> Dict:
        """
        Récupère les statistiques d'un thème.
        
        Args:
            theme_name: Nom du thème
        
        Returns:
            Dictionnaire de statistiques
        """
        # Retourner des stats par défaut si le thème n'existe pas
        if theme_name not in self.index['themes']:
            return {
                "total": 0,
                "downloaded": 0,
                "displayed": 0,
                "remaining": 0,
                "cycle": 0
            }
        
        theme_data = self.index['themes'][theme_name]
        images = theme_data['images']
        
        return {
            "total": len(images),
            "downloaded": sum(1 for img in images if img['downloaded']),
            "displayed": sum(1 for img in images if img['displayed']),
            "remaining": sum(1 for img in images if not img['displayed']),
            "cycle": theme_data.get('current_cycle', 0)
        }

