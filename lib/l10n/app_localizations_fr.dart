// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get appTitle => 'UPA Wallpaper Manager';

  @override
  String appVersion(String version) {
    return 'Version $version';
  }

  @override
  String get navHome => 'Accueil';

  @override
  String get navGallery => 'Galerie';

  @override
  String get navSettings => 'Paramètres';

  @override
  String get screenConfig => 'Configuration des écrans';

  @override
  String get rotationDelay => 'Délai du diaporama :';

  @override
  String get lockscreen => 'Appliquer aussi à l\'écran de verrouillage';

  @override
  String get lockscreenTooltip =>
      'Cette option fonctionnera uniquement si les deux conditions suivantes sont remplies :\n\n• L\'application est exécutée en tant qu\'administrateur.\n• Une version Pro / Enterprise / Education de Windows est installée.\n\nLe fond d\'écran de l\'écran 1 est utilisé pour l\'écran de verrouillage.';

  @override
  String get lockscreenUnsupportedTitle =>
      'L\'écran de verrouillage ne peut pas être contrôlé sur ce système :';

  @override
  String get lockscreenReasonAdmin =>
      'L\'application n\'est pas exécutée en tant qu\'administrateur.';

  @override
  String get lockscreenReasonEdition =>
      'Cette édition de Windows (Famille) ne supporte pas le changement automatique du lockscreen. Pro / Enterprise / Education requise.';

  @override
  String get applyNow => 'Appliquer maintenant';

  @override
  String get pause => 'Pause';

  @override
  String get resume => 'Reprendre';

  @override
  String get statusInitializing => 'Initialisation...';

  @override
  String get statusLoading => 'Chargement...';

  @override
  String get statusConnected => 'Connecté';

  @override
  String get statusOffline => 'Hors ligne';

  @override
  String statusThemes(int count) {
    return '$count thèmes';
  }

  @override
  String statusCache(String size) {
    return 'Cache : $size MB';
  }

  @override
  String get statusDownloading => 'Téléchargement des images...';

  @override
  String get statusNoImages => 'Aucune image trouvée';

  @override
  String get statusPaused => 'En pause';

  @override
  String get statusNewDelay =>
      'Nouveau délai configuré — Cliquez « Appliquer maintenant »';

  @override
  String get statusLockscreenEnabled => 'Lockscreen activé';

  @override
  String get statusLockscreenDisabled =>
      'Lockscreen désactivé — contrôle rendu à Windows';

  @override
  String get statusLockscreenAdmin =>
      'Relancer en admin pour désactiver complètement le lockscreen';

  @override
  String get timeSeconds => 'secondes';

  @override
  String get timeMinutes => 'minutes';

  @override
  String get timeHours => 'heures';

  @override
  String screenName(int id) {
    return 'Écran $id';
  }

  @override
  String get screenPrimary => 'Principal';

  @override
  String get screenRotationEnabled => 'Diaporama activé';

  @override
  String get screenTheme => 'Thème :';

  @override
  String get screenAllThemes => 'Tous les thèmes';

  @override
  String get screenResolution => 'Résolution :';

  @override
  String get screenCurrentWallpaper => 'Fond d\'écran actuel :';

  @override
  String get settingsTitle => 'Paramètres';

  @override
  String get settingsCancel => 'Annuler';

  @override
  String get settingsApply => 'Appliquer';

  @override
  String get settingsGeneral => 'Général';

  @override
  String get settingsDisplay => 'Affichage';

  @override
  String get settingsCache => 'Cache';

  @override
  String get settingsAdvanced => 'Avancé';

  @override
  String get settingsAbout => 'À propos';

  @override
  String get settingsLaunchStartup => 'Lancer au démarrage du système';

  @override
  String get settingsUiTheme => 'Thème de l\'interface :';

  @override
  String get settingsLanguage => 'Langue :';

  @override
  String get settingsRandomMode => 'Mode aléatoire pour le diaporama';

  @override
  String get settingsThemeDark => 'Sombre';

  @override
  String get settingsThemeLight => 'Clair';

  @override
  String get settingsThemeSystem => 'Système';

  @override
  String get settingsCacheMaxSize => 'Taille maximale du cache (MB) :';

  @override
  String get settingsCacheCurrent => 'Taille actuelle du cache :';

  @override
  String get settingsCacheCalculating => 'Calcul de la taille du cache...';

  @override
  String get settingsClearCache => 'Vider le cache';

  @override
  String get settingsReloadThemes => 'Recharger les thèmes';

  @override
  String get settingsCacheCleared => 'Cache vidé avec succès !';

  @override
  String get settingsThemesReloaded => 'Thèmes rechargés !';

  @override
  String get settingsClearCacheConfirm =>
      'Êtes-vous sûr de vouloir vider le cache ?';

  @override
  String get settingsRateLimit => 'Délai entre requêtes (secondes) :';

  @override
  String get settingsTimeout => 'Timeout réseau (secondes) :';

  @override
  String get settingsDebugMode => 'Mode debug (logs détaillés)';

  @override
  String get settingsLogsTitle => 'Fichier de logs';

  @override
  String get settingsLogsPath => 'Emplacement :';

  @override
  String get settingsLogsView => 'Voir les logs';

  @override
  String get settingsLogsOpenInOs => 'Ouvrir dans l\'éditeur du système';

  @override
  String get settingsLogsOpenFolder => 'Ouvrir le dossier';

  @override
  String get settingsLogsClear => 'Vider les logs';

  @override
  String get settingsLogsCleared => 'Logs vidés';

  @override
  String get settingsLogsClearConfirm =>
      'Êtes-vous sûr de vouloir vider le fichier de logs ?';

  @override
  String get settingsLogsEmpty => 'Le fichier de logs est vide pour le moment.';

  @override
  String get settingsLogsCopyPath => 'Copier le chemin';

  @override
  String get settingsLogsPathCopied => 'Chemin copié dans le presse-papiers';

  @override
  String get settingsLogsRefresh => 'Actualiser';

  @override
  String get settingsLogsCannotOpen =>
      'Impossible d\'ouvrir le fichier de logs';

  @override
  String errorGeneral(String message) {
    return 'Erreur : $message';
  }

  @override
  String get errorNetwork => 'Erreur réseau. Vérifiez votre connexion.';

  @override
  String get errorCache => 'Erreur du cache.';

  @override
  String get updateTitle => 'Mise à jour disponible';

  @override
  String updateMessage(String current, String latest) {
    return 'Une nouvelle version ($latest) est disponible.\n\nVersion actuelle : $current\nNouvelle version : $latest';
  }

  @override
  String get updateNow => 'Mettre à jour';

  @override
  String get updateLater => 'La prochaine fois';

  @override
  String get updateSkip => 'Ne plus me demander';

  @override
  String get updateButton => 'Vérifier les mises à jour';

  @override
  String get updateChecking => 'Vérification des mises à jour...';

  @override
  String get updateDownloading => 'Téléchargement de la mise à jour...';

  @override
  String get updateInstalling => 'Installation en cours...';

  @override
  String get updateSuccess =>
      'Mise à jour téléchargée ! L\'application va se fermer pour installer la nouvelle version.';

  @override
  String get updateNoUpdate => 'Aucune mise à jour disponible';

  @override
  String updateUpToDate(String version) {
    return 'Votre application est à jour (version $version)';
  }

  @override
  String get updateError => 'Erreur lors de la vérification des mises à jour';

  @override
  String get galleryTitle => 'Galerie';

  @override
  String get galleryEmpty => 'Aucune image dans ce thème';

  @override
  String get gallerySetWallpaper => 'Définir comme fond d\'écran';

  @override
  String get gallerySetLockscreen => 'Définir comme lockscreen';

  @override
  String get gallerySaveToDevice => 'Enregistrer sur l\'appareil';

  @override
  String get galleryDownloading => 'Téléchargement...';

  @override
  String get gallerySelectThemeHint =>
      'Sélectionnez un thème pour parcourir les fonds d\'écran';

  @override
  String get galleryAllScreens => 'Tous les écrans';

  @override
  String get galleryWallpaperApplied => 'Fond d\'écran appliqué !';

  @override
  String get galleryWallpaperAppliedAll =>
      'Fond d\'écran appliqué sur tous les écrans !';

  @override
  String get galleryWallpaperFailed => 'Échec de l\'application';

  @override
  String get manageThemes => 'Gérer les thèmes';

  @override
  String get manageThemesTitle => 'Gestion des thèmes';

  @override
  String get manageThemesAdd => 'Ajouter un thème';

  @override
  String get manageThemesRemove => 'Supprimer un thème';

  @override
  String get manageThemesChooseAction => 'Que souhaitez-vous faire ?';

  @override
  String get manageThemesChooseProvider =>
      'Choisissez le fournisseur de photos';

  @override
  String get manageThemesProviderPiwigo => 'Piwigo';

  @override
  String get manageThemesPiwigoDescription => 'Album d\'une galerie Piwigo';

  @override
  String get manageThemesProviderLocal => 'Galerie locale';

  @override
  String get manageThemesLocalDescription =>
      'Dossier d\'images depuis votre ordinateur';

  @override
  String get manageThemesLocalPickFolder => 'Choisir un dossier d\'images';

  @override
  String get manageThemesInvalidFolder => 'Dossier invalide ou inaccessible';

  @override
  String get manageThemesNoImagesInFolder =>
      'Aucune image trouvée dans ce dossier';

  @override
  String get manageThemesEnterUrl => 'URL de l\'album Piwigo';

  @override
  String get manageThemesUrlHelp =>
      'Exemple : https://exemple.com/gallery/index.php?/category/123';

  @override
  String get manageThemesValidate => 'Valider';

  @override
  String get manageThemesValidating => 'Validation en cours...';

  @override
  String get manageThemesAdded => 'Thème ajouté avec succès';

  @override
  String get manageThemesAddFailed =>
      'Impossible d\'ajouter ce thème. Vérifiez l\'URL.';

  @override
  String get manageThemesInvalidUrl => 'URL Piwigo invalide';

  @override
  String get manageThemesAlreadyExists => 'Ce thème existe déjà';

  @override
  String get manageThemesNoUserThemes => 'Aucun thème ajouté manuellement';

  @override
  String get manageThemesRemoveConfirm => 'Supprimer ce thème ?';

  @override
  String get manageThemesRemoved => 'Thème supprimé';

  @override
  String get manageThemesUserThemesList => 'Vos thèmes ajoutés';

  @override
  String get manageThemesBack => 'Retour';

  @override
  String get manageThemesClose => 'Fermer';

  @override
  String get manageThemesDelete => 'Supprimer';

  @override
  String get aboutTitle => 'À propos';

  @override
  String get aboutDescription =>
      'UPA Wallpaper Manager est un gestionnaire de fonds d\'écran multi-plateformes alimenté par la galerie Universe Photo Archive.';

  @override
  String get aboutWebsite => 'Visiter le site web';

  @override
  String get aboutGithub => 'GitHub';

  @override
  String get aboutLicense => 'Licence';

  @override
  String get trayOpen => 'Ouvrir';

  @override
  String get trayChangeNow => 'Changer maintenant';

  @override
  String get trayPause => 'Pause';

  @override
  String get trayResume => 'Reprendre';

  @override
  String get trayQuit => 'Quitter';

  @override
  String get dialogConfirm => 'Confirmer';

  @override
  String get dialogCancel => 'Annuler';

  @override
  String get dialogYes => 'Oui';

  @override
  String get dialogNo => 'Non';

  @override
  String get dialogOk => 'OK';
}
