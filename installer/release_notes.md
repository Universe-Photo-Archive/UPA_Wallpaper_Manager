## UPA Wallpaper Manager 2.1.3

Version de maintenance : compilée avec Flutter 3.50 et une chaîne de compilation à jour / maintenance release built with Flutter 3.50 and an up-to-date build pipeline.

- **Android** : corrige le plantage au lancement des versions 2.1.2 et du premier build 2.1.3 / fixes the crash on launch of 2.1.2 and of the first 2.1.3 build

Elle reprend les changements de la 2.1.2, faits pour suivre les recommandations de la Play Console / it carries the 2.1.2 changes made to follow the Play Console recommendations:

### Android

- **Affichage bord à bord** : l'application s'affiche désormais bord à bord sur toutes les versions d'Android, comme Android 15 l'impose déjà / the app now draws edge-to-edge on every Android version, as Android 15 already enforces
- **Images importées** : le sélecteur de fichiers décode les images en taille réduite, ce qui évite les pics de mémoire / the file picker now decodes images subsampled, avoiding memory spikes
- **Application plus légère** : compilation avec Android Gradle Plugin 9 et la réduction optimisée des ressources R8 / built with Android Gradle Plugin 9 and R8 optimized resource shrinking

### Windows et Android

- **Import / export des paramètres** : passage à la dernière version du sélecteur de fichiers / settings import and export use the latest file picker

### Installation

Téléchargez et exécutez / download and run: [`UPA_Wallpaper_Manager_Setup.exe`](https://github.com/Universe-Photo-Archive/UPA_Wallpaper_Manager/releases/latest/download/UPA_Wallpaper_Manager_Setup.exe)

L'application requiert les droits administrateur (fonction écran de verrouillage) / the app requires administrator privileges (lock-screen feature).
