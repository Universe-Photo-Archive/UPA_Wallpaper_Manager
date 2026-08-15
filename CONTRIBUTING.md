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
- `android-apk` — l'APK de debug (installation directe sur un téléphone)
- `android-aab` — l'App Bundle de release (format exigé par le Play Store)

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

## Signature Android (Play Store)

Le Play Store n'accepte que des App Bundles (`.aab`) signés avec **votre** clé.
Cette clé ne doit jamais entrer dans le dépôt : la perdre rend toute mise à
jour de l'application impossible. Sauvegardez-la, ainsi que ses mots de passe.

### 1. Créer la clé (une seule fois)

```bash
keytool -genkey -v -keystore upload-keystore.jks ^
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

`keytool` ne demande qu'un seul mot de passe : depuis Java 9 le keystore est au
format PKCS12, où la clé et le fichier partagent le même mot de passe. C'est
donc celui-ci qu'il faut renseigner à la fois comme `storePassword` et comme
`keyPassword`.

Conservez le fichier `upload-keystore.jks` hors du dépôt (gestionnaire de mots
de passe, disque chiffré, sauvegarde externe).

### 2. Compiler en local

Créez `android/key.properties` (déjà git-ignoré) :

```properties
storeFile=../upload-keystore.jks
storePassword=<mot de passe du keystore>
keyAlias=upload
keyPassword=<mot de passe de la clé>
```

Puis :

```bash
flutter build appbundle --release
```

Le bundle est produit dans `build/app/outputs/bundle/release/app-release.aab`.

### 3. Compiler via GitHub (optionnel)

Ajoutez quatre secrets dans **Settings → Secrets and variables → Actions** :

| Secret | Contenu |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | le keystore encodé : `base64 -w0 upload-keystore.jks` |
| `ANDROID_KEYSTORE_PASSWORD` | mot de passe du keystore |
| `ANDROID_KEY_ALIAS` | `upload` |
| `ANDROID_KEY_PASSWORD` | mot de passe de la clé |

Le workflow signe alors automatiquement l'App Bundle. Sans ces secrets, il est
signé avec la clé de debug : la compilation est validée, mais le fichier est
refusé par le Play Store.

## Publier une version

1. Mettre à jour `version:` dans `pubspec.yaml` et `MyAppVersion` dans
   `installer/setup.iss`
2. Commiter et pousser sur `main`
3. Créer la release GitHub avec le tag `vX.Y.Z` et y joindre l'installateur
   produit par le workflow

La mise à jour automatique de l'application Windows lit la dernière release
non pré-publiée : une pré-version (`prerelease`) ne sera donc jamais proposée
aux utilisateurs. Sur Android, les mises à jour passeront par le Play Store.
