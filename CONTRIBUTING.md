# Développement

Un seul dépôt, un seul dossier de travail, une seule branche principale
(`main`) pour toutes les plateformes : Windows, Android, et plus tard Linux,
macOS et iOS.

## Organisation du code

| Dossier | Rôle |
|---|---|
| `lib/` | Tout le code applicatif, commun à toutes les plateformes |
| `android/`, `windows/`, `linux/`, `macos/`, `ios/` | Coquille native de chaque plateforme (manifestes, code Kotlin / C++, icônes) |
| `installer/` | Script Inno Setup de l'installateur Windows |
| `config/` | `themes_default.json` servi par GitHub aux applications installées |
| `.github/workflows/` | Compilation automatique Windows + Android |

Les différences de comportement entre plateformes se gèrent dans le code
commun avec `Platform.isAndroid`, `Platform.isWindows`, etc. — jamais en
dupliquant des fichiers ou en créant une branche par plateforme.

## Compiler en local

```bash
flutter pub get

# Android (nécessite le SDK Android)
flutter build apk --debug
flutter run -d <appareil>

# Windows (nécessite Visual Studio avec la charge de travail C++)
flutter build windows --release
"C:\Program Files (x86)\Inno Setup 6\ISCC.exe" installer\setup.iss
```

Sous Windows, l'exécutable exige les droits administrateur (fonction écran de
verrouillage) : lancez `flutter run -d windows` depuis un terminal élevé.

## Compilation automatique

Chaque push sur `main` (ou sur une branche `cursor/**`) déclenche
[le workflow `Build`](.github/workflows/build.yml), qui produit sur GitHub :

- `windows-installer` — l'installateur `.exe`
- `android-apk` — l'APK de debug

Les fichiers se récupèrent dans l'onglet **Actions**, section *Artifacts* du
build concerné. C'est ce qui permet de vérifier les deux plateformes sans
posséder les deux environnements de développement.

## Travailler sur deux plateformes en parallèle

Pas besoin de deuxième copie du dépôt. Si vous voulez garder un dossier par
plateforme (pour ne pas écraser les dossiers `build/` en changeant de
branche), utilisez `git worktree` plutôt qu'un second clone :

```bash
git worktree add ../UPA_Wallpaper_Manager-android
```

Les deux dossiers partagent le même historique : un commit fait d'un côté est
immédiatement visible de l'autre. Deux clones indépendants, eux, finissent
toujours par diverger.

## Publier une version

1. Mettre à jour `version:` dans `pubspec.yaml` et `MyAppVersion` dans
   `installer/setup.iss`
2. Commiter et pousser sur `main`
3. Créer la release GitHub avec le tag `vX.Y.Z` et y joindre l'installateur
   produit par le workflow

La mise à jour automatique de l'application Windows lit la dernière release
non pré-publiée : une pré-version (`prerelease`) ne sera donc jamais proposée
aux utilisateurs. Sur Android, les mises à jour passeront par le Play Store.
