import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_fr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('fr'),
    Locale('en'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In fr, this message translates to:
  /// **'UPA Wallpaper Manager'**
  String get appTitle;

  /// No description provided for @appVersion.
  ///
  /// In fr, this message translates to:
  /// **'Version {version}'**
  String appVersion(String version);

  /// No description provided for @navHome.
  ///
  /// In fr, this message translates to:
  /// **'Accueil'**
  String get navHome;

  /// No description provided for @navGallery.
  ///
  /// In fr, this message translates to:
  /// **'Galerie'**
  String get navGallery;

  /// No description provided for @navSettings.
  ///
  /// In fr, this message translates to:
  /// **'Paramètres'**
  String get navSettings;

  /// No description provided for @screenConfig.
  ///
  /// In fr, this message translates to:
  /// **'Configuration des écrans'**
  String get screenConfig;

  /// No description provided for @rotationDelay.
  ///
  /// In fr, this message translates to:
  /// **'Délai du diaporama :'**
  String get rotationDelay;

  /// No description provided for @rotationDelayMobileHint.
  ///
  /// In fr, this message translates to:
  /// **'En arrière-plan, Android n\'applique la rotation qu\'une fois toutes les 15 minutes au maximum.'**
  String get rotationDelayMobileHint;

  /// No description provided for @lockscreen.
  ///
  /// In fr, this message translates to:
  /// **'Appliquer aussi à l\'écran de verrouillage'**
  String get lockscreen;

  /// No description provided for @settingsLockscreenAndroidSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'À chaque rotation, la nouvelle photo est aussi appliquée à l\'écran de verrouillage du téléphone.'**
  String get settingsLockscreenAndroidSubtitle;

  /// No description provided for @lockscreenTooltip.
  ///
  /// In fr, this message translates to:
  /// **'Cette option fonctionnera uniquement si les deux conditions suivantes sont remplies :\n\n• L\'application est exécutée en tant qu\'administrateur.\n• Une version Pro / Enterprise / Education de Windows est installée.\n\nLe fond d\'écran de l\'écran 1 est utilisé pour l\'écran de verrouillage.'**
  String get lockscreenTooltip;

  /// No description provided for @lockscreenUnsupportedTitle.
  ///
  /// In fr, this message translates to:
  /// **'L\'écran de verrouillage ne peut pas être contrôlé sur ce système :'**
  String get lockscreenUnsupportedTitle;

  /// No description provided for @lockscreenReasonAdmin.
  ///
  /// In fr, this message translates to:
  /// **'L\'application n\'est pas exécutée en tant qu\'administrateur.'**
  String get lockscreenReasonAdmin;

  /// No description provided for @lockscreenReasonEdition.
  ///
  /// In fr, this message translates to:
  /// **'Cette édition de Windows (Famille) ne supporte pas le changement automatique du lockscreen. Pro / Enterprise / Education requise.'**
  String get lockscreenReasonEdition;

  /// No description provided for @applyNow.
  ///
  /// In fr, this message translates to:
  /// **'Appliquer maintenant'**
  String get applyNow;

  /// No description provided for @pause.
  ///
  /// In fr, this message translates to:
  /// **'Pause'**
  String get pause;

  /// No description provided for @resume.
  ///
  /// In fr, this message translates to:
  /// **'Reprendre'**
  String get resume;

  /// No description provided for @statusInitializing.
  ///
  /// In fr, this message translates to:
  /// **'Initialisation...'**
  String get statusInitializing;

  /// No description provided for @statusLoading.
  ///
  /// In fr, this message translates to:
  /// **'Chargement...'**
  String get statusLoading;

  /// No description provided for @statusConnected.
  ///
  /// In fr, this message translates to:
  /// **'Connecté'**
  String get statusConnected;

  /// No description provided for @statusOffline.
  ///
  /// In fr, this message translates to:
  /// **'Hors ligne'**
  String get statusOffline;

  /// No description provided for @statusThemes.
  ///
  /// In fr, this message translates to:
  /// **'{count} thèmes'**
  String statusThemes(int count);

  /// No description provided for @statusCache.
  ///
  /// In fr, this message translates to:
  /// **'Cache : {size} MB'**
  String statusCache(String size);

  /// No description provided for @statusDownloading.
  ///
  /// In fr, this message translates to:
  /// **'Téléchargement des images...'**
  String get statusDownloading;

  /// No description provided for @statusNoImages.
  ///
  /// In fr, this message translates to:
  /// **'Aucune image trouvée'**
  String get statusNoImages;

  /// No description provided for @statusPaused.
  ///
  /// In fr, this message translates to:
  /// **'En pause'**
  String get statusPaused;

  /// No description provided for @statusNewDelay.
  ///
  /// In fr, this message translates to:
  /// **'Nouveau délai configuré — Cliquez « Appliquer maintenant »'**
  String get statusNewDelay;

  /// No description provided for @statusLockscreenEnabled.
  ///
  /// In fr, this message translates to:
  /// **'Lockscreen activé'**
  String get statusLockscreenEnabled;

  /// No description provided for @statusLockscreenDisabled.
  ///
  /// In fr, this message translates to:
  /// **'Lockscreen désactivé — contrôle rendu à Windows'**
  String get statusLockscreenDisabled;

  /// No description provided for @statusLockscreenAdmin.
  ///
  /// In fr, this message translates to:
  /// **'Relancer en admin pour désactiver complètement le lockscreen'**
  String get statusLockscreenAdmin;

  /// No description provided for @timeSeconds.
  ///
  /// In fr, this message translates to:
  /// **'secondes'**
  String get timeSeconds;

  /// No description provided for @timeMinutes.
  ///
  /// In fr, this message translates to:
  /// **'minutes'**
  String get timeMinutes;

  /// No description provided for @timeHours.
  ///
  /// In fr, this message translates to:
  /// **'heures'**
  String get timeHours;

  /// No description provided for @screenName.
  ///
  /// In fr, this message translates to:
  /// **'Écran {id}'**
  String screenName(int id);

  /// No description provided for @screenPrimary.
  ///
  /// In fr, this message translates to:
  /// **'Principal'**
  String get screenPrimary;

  /// No description provided for @screenRotationEnabled.
  ///
  /// In fr, this message translates to:
  /// **'Diaporama activé'**
  String get screenRotationEnabled;

  /// No description provided for @screenTheme.
  ///
  /// In fr, this message translates to:
  /// **'Thème :'**
  String get screenTheme;

  /// No description provided for @screenAllThemes.
  ///
  /// In fr, this message translates to:
  /// **'Tous les thèmes'**
  String get screenAllThemes;

  /// No description provided for @screenResolution.
  ///
  /// In fr, this message translates to:
  /// **'Résolution :'**
  String get screenResolution;

  /// No description provided for @screenCurrentWallpaper.
  ///
  /// In fr, this message translates to:
  /// **'Fond d\'écran actuel :'**
  String get screenCurrentWallpaper;

  /// No description provided for @settingsTitle.
  ///
  /// In fr, this message translates to:
  /// **'Paramètres'**
  String get settingsTitle;

  /// No description provided for @settingsCancel.
  ///
  /// In fr, this message translates to:
  /// **'Annuler'**
  String get settingsCancel;

  /// No description provided for @settingsApply.
  ///
  /// In fr, this message translates to:
  /// **'Appliquer'**
  String get settingsApply;

  /// No description provided for @settingsGeneral.
  ///
  /// In fr, this message translates to:
  /// **'Général'**
  String get settingsGeneral;

  /// No description provided for @settingsDisplay.
  ///
  /// In fr, this message translates to:
  /// **'Affichage'**
  String get settingsDisplay;

  /// No description provided for @settingsCache.
  ///
  /// In fr, this message translates to:
  /// **'Cache'**
  String get settingsCache;

  /// No description provided for @settingsAdvanced.
  ///
  /// In fr, this message translates to:
  /// **'Avancé'**
  String get settingsAdvanced;

  /// No description provided for @settingsAbout.
  ///
  /// In fr, this message translates to:
  /// **'À propos'**
  String get settingsAbout;

  /// No description provided for @settingsLaunchStartup.
  ///
  /// In fr, this message translates to:
  /// **'Lancer au démarrage du système'**
  String get settingsLaunchStartup;

  /// No description provided for @settingsUiTheme.
  ///
  /// In fr, this message translates to:
  /// **'Thème de l\'interface :'**
  String get settingsUiTheme;

  /// No description provided for @settingsLanguage.
  ///
  /// In fr, this message translates to:
  /// **'Langue :'**
  String get settingsLanguage;

  /// No description provided for @settingsRandomMode.
  ///
  /// In fr, this message translates to:
  /// **'Mode aléatoire pour le diaporama'**
  String get settingsRandomMode;

  /// No description provided for @settingsThemeDark.
  ///
  /// In fr, this message translates to:
  /// **'Sombre'**
  String get settingsThemeDark;

  /// No description provided for @settingsThemeLight.
  ///
  /// In fr, this message translates to:
  /// **'Clair'**
  String get settingsThemeLight;

  /// No description provided for @settingsThemeSystem.
  ///
  /// In fr, this message translates to:
  /// **'Système'**
  String get settingsThemeSystem;

  /// No description provided for @settingsCacheMaxSize.
  ///
  /// In fr, this message translates to:
  /// **'Taille maximale du cache (MB) :'**
  String get settingsCacheMaxSize;

  /// No description provided for @settingsCacheCurrent.
  ///
  /// In fr, this message translates to:
  /// **'Taille actuelle du cache :'**
  String get settingsCacheCurrent;

  /// No description provided for @settingsCacheCalculating.
  ///
  /// In fr, this message translates to:
  /// **'Calcul de la taille du cache...'**
  String get settingsCacheCalculating;

  /// No description provided for @settingsClearCache.
  ///
  /// In fr, this message translates to:
  /// **'Vider le cache'**
  String get settingsClearCache;

  /// No description provided for @settingsReloadThemes.
  ///
  /// In fr, this message translates to:
  /// **'Recharger les thèmes'**
  String get settingsReloadThemes;

  /// No description provided for @settingsCacheCleared.
  ///
  /// In fr, this message translates to:
  /// **'Cache vidé avec succès !'**
  String get settingsCacheCleared;

  /// No description provided for @settingsThemesReloaded.
  ///
  /// In fr, this message translates to:
  /// **'Thèmes rechargés !'**
  String get settingsThemesReloaded;

  /// No description provided for @settingsClearCacheConfirm.
  ///
  /// In fr, this message translates to:
  /// **'Êtes-vous sûr de vouloir vider le cache ?'**
  String get settingsClearCacheConfirm;

  /// No description provided for @settingsRateLimit.
  ///
  /// In fr, this message translates to:
  /// **'Délai entre requêtes (secondes) :'**
  String get settingsRateLimit;

  /// No description provided for @settingsTimeout.
  ///
  /// In fr, this message translates to:
  /// **'Timeout réseau (secondes) :'**
  String get settingsTimeout;

  /// No description provided for @settingsDebugMode.
  ///
  /// In fr, this message translates to:
  /// **'Mode debug (logs détaillés)'**
  String get settingsDebugMode;

  /// No description provided for @settingsLogsTitle.
  ///
  /// In fr, this message translates to:
  /// **'Fichier de logs'**
  String get settingsLogsTitle;

  /// No description provided for @settingsLogsPath.
  ///
  /// In fr, this message translates to:
  /// **'Emplacement :'**
  String get settingsLogsPath;

  /// No description provided for @settingsLogsView.
  ///
  /// In fr, this message translates to:
  /// **'Voir les logs'**
  String get settingsLogsView;

  /// No description provided for @settingsLogsOpenInOs.
  ///
  /// In fr, this message translates to:
  /// **'Ouvrir dans l\'éditeur du système'**
  String get settingsLogsOpenInOs;

  /// No description provided for @settingsLogsOpenFolder.
  ///
  /// In fr, this message translates to:
  /// **'Ouvrir le dossier'**
  String get settingsLogsOpenFolder;

  /// No description provided for @settingsLogsClear.
  ///
  /// In fr, this message translates to:
  /// **'Vider les logs'**
  String get settingsLogsClear;

  /// No description provided for @settingsLogsCleared.
  ///
  /// In fr, this message translates to:
  /// **'Logs vidés'**
  String get settingsLogsCleared;

  /// No description provided for @settingsLogsClearConfirm.
  ///
  /// In fr, this message translates to:
  /// **'Êtes-vous sûr de vouloir vider le fichier de logs ?'**
  String get settingsLogsClearConfirm;

  /// No description provided for @settingsLogsEmpty.
  ///
  /// In fr, this message translates to:
  /// **'Le fichier de logs est vide pour le moment.'**
  String get settingsLogsEmpty;

  /// No description provided for @settingsLogsCopyPath.
  ///
  /// In fr, this message translates to:
  /// **'Copier le chemin'**
  String get settingsLogsCopyPath;

  /// No description provided for @settingsLogsPathCopied.
  ///
  /// In fr, this message translates to:
  /// **'Chemin copié dans le presse-papiers'**
  String get settingsLogsPathCopied;

  /// No description provided for @settingsLogsRefresh.
  ///
  /// In fr, this message translates to:
  /// **'Actualiser'**
  String get settingsLogsRefresh;

  /// No description provided for @settingsLogsCannotOpen.
  ///
  /// In fr, this message translates to:
  /// **'Impossible d\'ouvrir le fichier de logs'**
  String get settingsLogsCannotOpen;

  /// No description provided for @errorGeneral.
  ///
  /// In fr, this message translates to:
  /// **'Erreur : {message}'**
  String errorGeneral(String message);

  /// No description provided for @errorNetwork.
  ///
  /// In fr, this message translates to:
  /// **'Erreur réseau. Vérifiez votre connexion.'**
  String get errorNetwork;

  /// No description provided for @errorCache.
  ///
  /// In fr, this message translates to:
  /// **'Erreur du cache.'**
  String get errorCache;

  /// No description provided for @updateTitle.
  ///
  /// In fr, this message translates to:
  /// **'Mise à jour disponible'**
  String get updateTitle;

  /// No description provided for @updateMessage.
  ///
  /// In fr, this message translates to:
  /// **'Une nouvelle version ({latest}) est disponible.\n\nVersion actuelle : {current}\nNouvelle version : {latest}'**
  String updateMessage(String current, String latest);

  /// No description provided for @updateNow.
  ///
  /// In fr, this message translates to:
  /// **'Mettre à jour'**
  String get updateNow;

  /// No description provided for @updateLater.
  ///
  /// In fr, this message translates to:
  /// **'La prochaine fois'**
  String get updateLater;

  /// No description provided for @updateSkip.
  ///
  /// In fr, this message translates to:
  /// **'Ne plus me demander'**
  String get updateSkip;

  /// No description provided for @updateButton.
  ///
  /// In fr, this message translates to:
  /// **'Vérifier les mises à jour'**
  String get updateButton;

  /// No description provided for @updateChecking.
  ///
  /// In fr, this message translates to:
  /// **'Vérification des mises à jour...'**
  String get updateChecking;

  /// No description provided for @updateDownloading.
  ///
  /// In fr, this message translates to:
  /// **'Téléchargement de la mise à jour...'**
  String get updateDownloading;

  /// No description provided for @updateInstalling.
  ///
  /// In fr, this message translates to:
  /// **'Installation en cours...'**
  String get updateInstalling;

  /// No description provided for @updateSuccess.
  ///
  /// In fr, this message translates to:
  /// **'Mise à jour téléchargée ! L\'application va se fermer pour installer la nouvelle version.'**
  String get updateSuccess;

  /// No description provided for @updateNoUpdate.
  ///
  /// In fr, this message translates to:
  /// **'Aucune mise à jour disponible'**
  String get updateNoUpdate;

  /// No description provided for @updateUpToDate.
  ///
  /// In fr, this message translates to:
  /// **'Votre application est à jour (version {version})'**
  String updateUpToDate(String version);

  /// No description provided for @updateError.
  ///
  /// In fr, this message translates to:
  /// **'Erreur lors de la vérification des mises à jour'**
  String get updateError;

  /// No description provided for @galleryTitle.
  ///
  /// In fr, this message translates to:
  /// **'Galerie'**
  String get galleryTitle;

  /// No description provided for @galleryEmpty.
  ///
  /// In fr, this message translates to:
  /// **'Aucune image dans ce thème'**
  String get galleryEmpty;

  /// No description provided for @gallerySetWallpaper.
  ///
  /// In fr, this message translates to:
  /// **'Définir comme fond d\'écran'**
  String get gallerySetWallpaper;

  /// No description provided for @gallerySetAs.
  ///
  /// In fr, this message translates to:
  /// **'Définir comme :'**
  String get gallerySetAs;

  /// No description provided for @galleryTargetWallpaper.
  ///
  /// In fr, this message translates to:
  /// **'Fond d\'écran'**
  String get galleryTargetWallpaper;

  /// No description provided for @galleryTargetLockscreen.
  ///
  /// In fr, this message translates to:
  /// **'Écran de verrouillage'**
  String get galleryTargetLockscreen;

  /// No description provided for @galleryLockscreenApplied.
  ///
  /// In fr, this message translates to:
  /// **'Écran de verrouillage mis à jour'**
  String get galleryLockscreenApplied;

  /// No description provided for @gallerySetLockscreen.
  ///
  /// In fr, this message translates to:
  /// **'Définir comme lockscreen'**
  String get gallerySetLockscreen;

  /// No description provided for @gallerySaveToDevice.
  ///
  /// In fr, this message translates to:
  /// **'Enregistrer sur l\'appareil'**
  String get gallerySaveToDevice;

  /// No description provided for @galleryDownloading.
  ///
  /// In fr, this message translates to:
  /// **'Téléchargement...'**
  String get galleryDownloading;

  /// No description provided for @gallerySelectThemeHint.
  ///
  /// In fr, this message translates to:
  /// **'Sélectionnez un thème pour parcourir les fonds d\'écran'**
  String get gallerySelectThemeHint;

  /// No description provided for @galleryAllScreens.
  ///
  /// In fr, this message translates to:
  /// **'Tous les écrans'**
  String get galleryAllScreens;

  /// No description provided for @galleryWallpaperApplied.
  ///
  /// In fr, this message translates to:
  /// **'Fond d\'écran appliqué !'**
  String get galleryWallpaperApplied;

  /// No description provided for @galleryWallpaperAppliedAll.
  ///
  /// In fr, this message translates to:
  /// **'Fond d\'écran appliqué sur tous les écrans !'**
  String get galleryWallpaperAppliedAll;

  /// No description provided for @galleryWallpaperFailed.
  ///
  /// In fr, this message translates to:
  /// **'Échec de l\'application'**
  String get galleryWallpaperFailed;

  /// No description provided for @manageThemes.
  ///
  /// In fr, this message translates to:
  /// **'Gérer les thèmes'**
  String get manageThemes;

  /// No description provided for @manageThemesTitle.
  ///
  /// In fr, this message translates to:
  /// **'Gestion des thèmes'**
  String get manageThemesTitle;

  /// No description provided for @manageThemesAdd.
  ///
  /// In fr, this message translates to:
  /// **'Ajouter un thème'**
  String get manageThemesAdd;

  /// No description provided for @manageThemesRemove.
  ///
  /// In fr, this message translates to:
  /// **'Supprimer un thème'**
  String get manageThemesRemove;

  /// No description provided for @manageThemesChooseAction.
  ///
  /// In fr, this message translates to:
  /// **'Que souhaitez-vous faire ?'**
  String get manageThemesChooseAction;

  /// No description provided for @manageThemesChooseProvider.
  ///
  /// In fr, this message translates to:
  /// **'Choisissez le fournisseur de photos'**
  String get manageThemesChooseProvider;

  /// No description provided for @manageThemesProviderPiwigo.
  ///
  /// In fr, this message translates to:
  /// **'Piwigo'**
  String get manageThemesProviderPiwigo;

  /// No description provided for @manageThemesPiwigoDescription.
  ///
  /// In fr, this message translates to:
  /// **'Album d\'une galerie Piwigo'**
  String get manageThemesPiwigoDescription;

  /// No description provided for @manageThemesProviderLocal.
  ///
  /// In fr, this message translates to:
  /// **'Galerie locale'**
  String get manageThemesProviderLocal;

  /// No description provided for @manageThemesProviderDeviceImages.
  ///
  /// In fr, this message translates to:
  /// **'Images de l\'appareil'**
  String get manageThemesProviderDeviceImages;

  /// No description provided for @manageThemesDeviceImagesDescription.
  ///
  /// In fr, this message translates to:
  /// **'Choisissez des photos sur votre téléphone ; elles seront copiées dans l\'application'**
  String get manageThemesDeviceImagesDescription;

  /// No description provided for @manageThemesLocalDescription.
  ///
  /// In fr, this message translates to:
  /// **'Dossier d\'images depuis votre ordinateur'**
  String get manageThemesLocalDescription;

  /// No description provided for @manageThemesLocalPickFolder.
  ///
  /// In fr, this message translates to:
  /// **'Choisir un dossier d\'images'**
  String get manageThemesLocalPickFolder;

  /// No description provided for @manageThemesInvalidFolder.
  ///
  /// In fr, this message translates to:
  /// **'Dossier invalide ou inaccessible'**
  String get manageThemesInvalidFolder;

  /// No description provided for @manageThemesNoImagesInFolder.
  ///
  /// In fr, this message translates to:
  /// **'Aucune image trouvée dans ce dossier'**
  String get manageThemesNoImagesInFolder;

  /// No description provided for @manageThemesEnterUrl.
  ///
  /// In fr, this message translates to:
  /// **'URL de l\'album Piwigo'**
  String get manageThemesEnterUrl;

  /// No description provided for @manageThemesUrlHelp.
  ///
  /// In fr, this message translates to:
  /// **'Exemple : https://exemple.com/gallery/index.php?/category/123'**
  String get manageThemesUrlHelp;

  /// No description provided for @manageThemesValidate.
  ///
  /// In fr, this message translates to:
  /// **'Valider'**
  String get manageThemesValidate;

  /// No description provided for @manageThemesValidating.
  ///
  /// In fr, this message translates to:
  /// **'Validation en cours...'**
  String get manageThemesValidating;

  /// No description provided for @manageThemesAdded.
  ///
  /// In fr, this message translates to:
  /// **'Thème ajouté avec succès'**
  String get manageThemesAdded;

  /// No description provided for @manageThemesAddFailed.
  ///
  /// In fr, this message translates to:
  /// **'Impossible d\'ajouter ce thème. Vérifiez l\'URL.'**
  String get manageThemesAddFailed;

  /// No description provided for @manageThemesApiBlocked.
  ///
  /// In fr, this message translates to:
  /// **'Cette galerie bloque l\'accès à son API Piwigo : impossible d\'importer ses albums.'**
  String get manageThemesApiBlocked;

  /// No description provided for @manageThemesInvalidUrl.
  ///
  /// In fr, this message translates to:
  /// **'URL Piwigo invalide'**
  String get manageThemesInvalidUrl;

  /// No description provided for @manageThemesAlreadyExists.
  ///
  /// In fr, this message translates to:
  /// **'Ce thème existe déjà'**
  String get manageThemesAlreadyExists;

  /// No description provided for @manageThemesNoUserThemes.
  ///
  /// In fr, this message translates to:
  /// **'Aucun thème ajouté manuellement'**
  String get manageThemesNoUserThemes;

  /// No description provided for @manageThemesRemoveConfirm.
  ///
  /// In fr, this message translates to:
  /// **'Supprimer ce thème ?'**
  String get manageThemesRemoveConfirm;

  /// No description provided for @manageThemesRemoved.
  ///
  /// In fr, this message translates to:
  /// **'Thème supprimé'**
  String get manageThemesRemoved;

  /// No description provided for @manageThemesUserThemesList.
  ///
  /// In fr, this message translates to:
  /// **'Vos thèmes ajoutés'**
  String get manageThemesUserThemesList;

  /// No description provided for @manageThemesBack.
  ///
  /// In fr, this message translates to:
  /// **'Retour'**
  String get manageThemesBack;

  /// No description provided for @manageThemesClose.
  ///
  /// In fr, this message translates to:
  /// **'Fermer'**
  String get manageThemesClose;

  /// No description provided for @manageThemesDelete.
  ///
  /// In fr, this message translates to:
  /// **'Supprimer'**
  String get manageThemesDelete;

  /// No description provided for @aboutTitle.
  ///
  /// In fr, this message translates to:
  /// **'À propos'**
  String get aboutTitle;

  /// No description provided for @aboutDescription.
  ///
  /// In fr, this message translates to:
  /// **'UPA Wallpaper Manager est un gestionnaire de fonds d\'écran multi-plateformes alimenté par la galerie Universe Photo Archive.'**
  String get aboutDescription;

  /// No description provided for @aboutWebsite.
  ///
  /// In fr, this message translates to:
  /// **'Visiter le site web'**
  String get aboutWebsite;

  /// No description provided for @aboutGithub.
  ///
  /// In fr, this message translates to:
  /// **'GitHub'**
  String get aboutGithub;

  /// No description provided for @aboutLicense.
  ///
  /// In fr, this message translates to:
  /// **'Licence'**
  String get aboutLicense;

  /// No description provided for @trayOpen.
  ///
  /// In fr, this message translates to:
  /// **'Ouvrir'**
  String get trayOpen;

  /// No description provided for @trayChangeNow.
  ///
  /// In fr, this message translates to:
  /// **'Changer maintenant'**
  String get trayChangeNow;

  /// No description provided for @trayPause.
  ///
  /// In fr, this message translates to:
  /// **'Pause'**
  String get trayPause;

  /// No description provided for @trayResume.
  ///
  /// In fr, this message translates to:
  /// **'Reprendre'**
  String get trayResume;

  /// No description provided for @trayQuit.
  ///
  /// In fr, this message translates to:
  /// **'Quitter'**
  String get trayQuit;

  /// No description provided for @dialogConfirm.
  ///
  /// In fr, this message translates to:
  /// **'Confirmer'**
  String get dialogConfirm;

  /// No description provided for @dialogCancel.
  ///
  /// In fr, this message translates to:
  /// **'Annuler'**
  String get dialogCancel;

  /// No description provided for @dialogYes.
  ///
  /// In fr, this message translates to:
  /// **'Oui'**
  String get dialogYes;

  /// No description provided for @dialogNo.
  ///
  /// In fr, this message translates to:
  /// **'Non'**
  String get dialogNo;

  /// No description provided for @dialogOk.
  ///
  /// In fr, this message translates to:
  /// **'OK'**
  String get dialogOk;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'fr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'fr':
      return AppLocalizationsFr();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
