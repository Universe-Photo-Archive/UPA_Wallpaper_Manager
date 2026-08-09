# UPA Wallpaper Manager

Gestionnaire de fonds d'écran multi-écrans propulsé par [Universe Photo Archive](https://universe-photo-archive.eu) — galaxies, planètes, astronautes et plus encore, en rotation sur votre bureau.

[English version](README.md)

## Fonctionnalités

- Multi-écrans : un thème et un délai de rotation différents par moniteur
- Thèmes alimentés par la galerie Piwigo Universe Photo Archive (Fonds d'écran, Thomas Pesquet, Sophie Adenot, ...)
- Ajoutez vos propres thèmes : n'importe quelle URL d'album Piwigo public, ou un dossier local
- Cache intelligent : téléchargements à la demande, rotation en cycle complet (chaque image affichée une fois par cycle), nettoyage automatique
- Fond d'écran de verrouillage Windows (nécessite les droits administrateur, Windows Pro/Entreprise/Éducation)
- Zone de notification : réduire ou fermer la fenêtre envoie l'application à côté de l'horloge ; quitter via clic droit > Quitter
- Lancement au démarrage de Windows (tâche planifiée élevée, sans invite UAC à l'ouverture de session)
- Vérification automatique des mises à jour via les releases GitHub
- Interface français / anglais, thèmes clair et sombre

## Téléchargement

Téléchargez le dernier installateur Windows depuis la [page Releases](https://github.com/Universe-Photo-Archive/UPA_Wallpaper_Manager/releases) : `UPA_Wallpaper_Manager_Setup_<version>.exe`.

L'application requiert les droits administrateur (nécessaires pour le fond d'écran de verrouillage) : Windows affiche donc une invite UAC au lancement manuel. Au démarrage automatique de session, elle se lance élevée sans invite.

## Compiler depuis les sources

Application de bureau [Flutter](https://flutter.dev) (Windows pour l'instant ; Linux, macOS, Android et iOS prévus).

```bash
flutter pub get
flutter run -d windows          # build de debug (depuis un terminal élevé)
flutter build windows --release # build de release
```

Pour construire l'installateur Windows (nécessite [Inno Setup 6](https://jrsoftware.org/isinfo.php)) :

```bash
flutter build windows --release
"C:\Program Files (x86)\Inno Setup 6\ISCC.exe" installer\setup.iss
```

L'installateur est produit dans `installer/Output/`.

## Configuration des thèmes par défaut

La liste des thèmes par défaut se trouve dans [`config/themes_default.json`](config/themes_default.json). L'application récupère ce fichier depuis GitHub à chaque démarrage : on peut donc ajouter ou modifier des thèmes sans publier de nouvelle version. Une copie est embarquée dans `assets/config/` comme secours hors-ligne.

## Licence

[GPL-3.0](LICENSE)

## Historique des versions

- **2.x** — réécriture complète en Flutter (ce dépôt)
- **1.x** — version Python d'origine
