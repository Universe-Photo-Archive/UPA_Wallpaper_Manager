"""Module de scraping du site Universe Photo Archive."""

import re
import time
from typing import Dict, List, Optional
from urllib.parse import urljoin, unquote

import requests
from bs4 import BeautifulSoup

from ..utils.logger import get_logger

logger = get_logger()


class UniverseScraper:
    """Scraper pour Universe Photo Archive."""
    
    BASE_URL = "https://universe-photo-archive.eu/wallpapers/"
    
    def __init__(self, rate_limit_seconds: float = 1.0, timeout_seconds: int = 10):
        """
        Initialise le scraper.
        
        Args:
            rate_limit_seconds: Délai minimum entre chaque requête
            timeout_seconds: Timeout des requêtes HTTP
        """
        self.rate_limit = rate_limit_seconds
        self.timeout = timeout_seconds
        self.last_request_time = 0
        self.session = requests.Session()
        self.session.headers.update({
            'User-Agent': 'Universe Wallpaper Manager/1.0'
        })
    
    def _rate_limited_request(self, url: str) -> Optional[requests.Response]:
        """
        Effectue une requête HTTP avec rate limiting.
        
        Args:
            url: URL à requêter
            
        Returns:
            Réponse HTTP ou None en cas d'erreur
        """
        # Appliquer le rate limiting
        elapsed = time.time() - self.last_request_time
        if elapsed < self.rate_limit:
            time.sleep(self.rate_limit - elapsed)
        
        try:
            response = self.session.get(url, timeout=self.timeout)
            self.last_request_time = time.time()
            response.raise_for_status()
            return response
        except requests.RequestException as e:
            logger.error(f"Erreur lors de la requête vers {url}: {e}")
            return None
    
    def get_themes(self) -> List[Dict[str, str]]:
        """
        Récupère la liste des thèmes disponibles.
        
        Returns:
            Liste de dictionnaires {'name': ..., 'url': ...}
        """
        logger.info("Récupération des thèmes depuis Universe Photo Archive")
        
        response = self._rate_limited_request(self.BASE_URL)
        if not response:
            logger.error("Impossible de récupérer la liste des thèmes")
            return []
        
        try:
            soup = BeautifulSoup(response.text, 'html.parser')
            themes = []
            
            # Directory Lister : chercher tous les liens
            for link in soup.find_all('a', href=True):
                href = link['href']
                link_text = link.get_text(strip=True)
                
                # Ignorer les liens de navigation et système
                if href in ['..', '/', '../', '?sort=name', '?sort=size', '?sort=date']:
                    continue
                
                # Ignorer les liens vides
                if not href or not link_text:
                    continue
                
                # Ignorer les fichiers d'images directement listés
                image_extensions = ('.jpg', '.jpeg', '.png', '.webp', '.bmp', '.gif')
                if any(href.lower().endswith(ext) for ext in image_extensions):
                    continue
                
                # Un dossier se termine généralement par / OU contient un texte sans extension
                is_folder = href.endswith('/') or '.' not in href.split('/')[-1]
                
                if is_folder:
                    # Nettoyer le nom du thème
                    # 1. Enlever les parties entre parenthèses (traductions)
                    theme_name = re.sub(r'\s*\([^)]*\)', '', link_text).strip()
                    
                    # 2. Enlever la date de modification (après le tiret cadratin —)
                    # Format: "Earth—2025-04-06 09:35:07"
                    theme_name = re.split(r'[—–-]\d{4}', theme_name)[0].strip()
                    
                    # 3. Nettoyer les caractères interdits par Windows: < > : " / \ | ? *
                    invalid_chars = '<>:"/\\|?*'
                    for char in invalid_chars:
                        theme_name = theme_name.replace(char, '')
                    
                    # 4. Enlever les espaces multiples et les espaces en fin
                    theme_name = ' '.join(theme_name.split())
                    
                    # Si le nom est vide après nettoyage, utiliser le href
                    if not theme_name:
                        # Extraire le nom du dossier depuis l'URL
                        theme_name = href.rstrip('/').split('/')[-1]
                        # Décoder l'URL
                        theme_name = unquote(theme_name)
                        # Nettoyer à nouveau
                        theme_name = re.sub(r'\s*\([^)]*\)', '', theme_name).strip()
                        for char in invalid_chars:
                            theme_name = theme_name.replace(char, '')
                    
                    # Construire l'URL complète
                    theme_url = urljoin(self.BASE_URL, href)
                    if not theme_url.endswith('/'):
                        theme_url += '/'
                    
                    themes.append({
                        'name': theme_name,
                        'url': theme_url,
                        'original_name': link_text
                    })
                    
                    logger.debug(f"Thème détecté: '{theme_name}' -> {theme_url}")
            
            logger.info(f"{len(themes)} thème(s) trouvé(s)")
            for theme in themes:
                logger.info(f"  ✓ {theme['name']}")
            
            return themes
            
        except Exception as e:
            logger.error(f"Erreur lors du parsing des thèmes: {e}", exc_info=True)
            return []
    
    def get_theme_images(self, theme_url: str) -> List[Dict[str, str]]:
        """
        Récupère la liste des images d'un thème.
        
        Args:
            theme_url: URL du thème
            
        Returns:
            Liste de dictionnaires {'filename': ..., 'url': ...}
        """
        logger.debug(f"Récupération des images depuis {theme_url}")
        
        response = self._rate_limited_request(theme_url)
        if not response:
            logger.error(f"Impossible de récupérer les images du thème: {theme_url}")
            return []
        
        try:
            soup = BeautifulSoup(response.text, 'html.parser')
            images = []
            
            # Extensions d'images supportées
            image_extensions = ('.jpg', '.jpeg', '.png', '.webp', '.bmp')
            
            for link in soup.find_all('a', href=True):
                href = link['href']
                
                # Vérifier si c'est une image
                if any(href.lower().endswith(ext) for ext in image_extensions):
                    # Décoder le nom du fichier pour affichage
                    filename = unquote(href.split('/')[-1])
                    # Ne pas ré-encoder : le href est déjà correctement encodé par le serveur
                    image_url = urljoin(theme_url, href)
                    
                    images.append({
                        'filename': filename,
                        'url': image_url
                    })
            
            logger.debug(f"{len(images)} images trouvées dans le thème")
            return images
            
        except Exception as e:
            logger.error(f"Erreur lors du parsing des images: {e}", exc_info=True)
            return []
    
    def get_all_themes_with_images(self) -> Dict[str, List[Dict[str, str]]]:
        """
        Récupère tous les thèmes avec leurs images.
        
        Returns:
            Dictionnaire {theme_name: [images]}
        """
        logger.info("Récupération de tous les thèmes et images")
        
        themes = self.get_themes()
        result = {}
        
        for theme in themes:
            theme_name = theme['name']
            theme_url = theme['url']
            
            images = self.get_theme_images(theme_url)
            if images:
                result[theme_name] = images
        
        total_images = sum(len(images) for images in result.values())
        logger.info(f"Total: {len(result)} thèmes, {total_images} images")
        
        return result
    
    def test_connection(self) -> bool:
        """
        Test la connexion au site.
        
        Returns:
            True si le site est accessible
        """
        logger.info("Test de connexion à Universe Photo Archive")
        
        try:
            response = self.session.get(self.BASE_URL, timeout=5)
            if response.status_code == 200:
                logger.info("Connexion réussie")
                return True
            else:
                logger.warning(f"Connexion échouée: HTTP {response.status_code}")
                return False
        except Exception as e:
            logger.error(f"Impossible de se connecter: {e}")
            return False


