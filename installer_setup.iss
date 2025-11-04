; Script Inno Setup pour UPA Wallpaper Manager
; Nécessite Inno Setup 6.0 ou supérieur
; Téléchargement : https://jrsoftware.org/isdl.php

#define MyAppName "UPA Wallpaper Manager"
#define MyAppVersion "1.2.0"
#define MyAppPublisher "Universe Photo Archive"
#define MyAppURL "https://universe-photo-archive.eu/"
#define MyAppExeName "UPAWallpaperManager.exe"

[Setup]
; Informations de base
AppId={{A5F3C8B2-9D4E-4F3A-8B2C-1E7D9F4A3C5B}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}

; Répertoire d'installation par défaut
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}

; Icône de l'installateur
SetupIconFile=assets\icons\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}

; Options d'installation
AllowNoIcons=yes
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
PrivilegesRequiredOverridesAllowed=dialog

; Répertoire de sortie
OutputDir=installer_output
OutputBaseFilename=UPA_Wallpaper_Manager_{#MyAppVersion}_Setup

; Licence et informations
LicenseFile=LICENSE
InfoBeforeFile=installer_info.txt

; Désinstallation
UninstallDisplayName={#MyAppName}
UninstallFilesDir={app}\uninstall

; Architecture
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "french"; MessagesFile: "compiler:Languages\French.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
; Case à cocher pour le raccourci bureau (DÉCOCHÉE par défaut)
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Fichier exécutable principal
Source: "dist\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion

; Fichiers de données (langs, assets)
Source: "langs\*"; DestDir: "{app}\langs"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "assets\*"; DestDir: "{app}\assets"; Flags: ignoreversion recursesubdirs createallsubdirs

; Documentation
Source: "README.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "README_FR.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "LICENSE"; DestDir: "{app}"; Flags: ignoreversion

; Créer le dossier data vide (sera rempli par l'application)
; Note: Le dossier se créera automatiquement au premier lancement

[Icons]
; Entrée dans le menu Démarrer - Raccourci vers le programme (avec droits admin)
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Comment: "Gestionnaire de fonds d'écran de l'univers"; AfterInstall: SetRunAsAdmin(ExpandConstant('{group}\{#MyAppName}.lnk'))

; Entrée dans le menu Démarrer - Raccourci vers la désinstallation
Name: "{group}\Désinstaller {#MyAppName}"; Filename: "{uninstallexe}"; Comment: "Désinstaller {#MyAppName}"

; Raccourci bureau (SI la case est cochée) - avec droits admin
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon; WorkingDir: "{app}"; Comment: "Gestionnaire de fonds d'écran de l'univers"; AfterInstall: SetRunAsAdmin(ExpandConstant('{autodesktop}\{#MyAppName}.lnk'))

[Run]
; Proposer de lancer l'application en tant qu'administrateur après l'installation
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent shellexec runasoriginaluser

[UninstallDelete]
; Supprimer les dossiers et fichiers du programme (toujours supprimés)
Type: filesandordirs; Name: "{app}\langs"
Type: filesandordirs; Name: "{app}\assets"
Type: filesandordirs; Name: "{app}\logs"
Type: files; Name: "{app}\*.md"
Type: files; Name: "{app}\LICENSE"
; Note : Le dossier data est géré dans le code de désinstallation (choix utilisateur)

[Code]
// Code Pascal pour personnalisation avancée si nécessaire

// Fonction pour configurer un raccourci pour s'exécuter en tant qu'administrateur
// Utilise PowerShell pour modifier les propriétés du raccourci
procedure SetRunAsAdmin(ShortcutPath: String);
var
  ResultCode: Integer;
  PowerShellScript: String;
begin
  if FileExists(ShortcutPath) then
  begin
    try
      // Script PowerShell pour définir le raccourci en mode administrateur
      PowerShellScript := 
        '$bytes = [System.IO.File]::ReadAllBytes(''' + ShortcutPath + '''); ' +
        'if ($bytes.Length -gt 21) { ' +
        '  $bytes[21] = $bytes[21] -bor 0x20; ' +
        '  [System.IO.File]::WriteAllBytes(''' + ShortcutPath + ''', $bytes); ' +
        '  Write-Host \"OK\" ' +
        '} else { ' +
        '  Write-Host \"ERROR\" ' +
        '}';
      
      // Exécuter le script PowerShell
      Exec('powershell.exe', '-NoProfile -ExecutionPolicy Bypass -Command "' + PowerShellScript + '"', 
           '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
      
      if ResultCode = 0 then
        Log('Raccourci configuré pour s''exécuter en administrateur : ' + ShortcutPath)
      else
        Log('Impossible de configurer le raccourci en administrateur : ' + ShortcutPath);
    except
      // En cas d'erreur, on continue sans bloquer l'installation
      Log('Erreur lors de la configuration du raccourci : ' + ShortcutPath);
    end;
  end;
end;

// Message personnalisé avant installation
function InitializeSetup(): Boolean;
begin
  Result := True;
  // Vous pouvez ajouter des vérifications ici si nécessaire
end;

// Message après installation réussie
procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    // Actions après installation
  end;
end;

// Fonction pour tuer le processus de l'application
procedure KillApplication();
var
  ResultCode: Integer;
begin
  // Tenter de fermer l'application proprement avec taskkill
  Exec('taskkill.exe', '/F /IM UPAWallpaperManager.exe', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  // Attendre un peu que le processus se termine
  Sleep(1000);
end;

// Personnalisation de la désinstallation
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  DataPath: String;
  AppPath: String;
begin
  if CurUninstallStep = usUninstall then
  begin
    // Fermer l'application si elle est en cours d'exécution
    KillApplication();
    
    AppPath := ExpandConstant('{app}');
    DataPath := AppPath + '\data';
    
    // Demander confirmation avant de supprimer les données utilisateur
    if DirExists(DataPath) then
    begin
      if MsgBox('Voulez-vous également supprimer tous les fonds d''écran téléchargés et la configuration ?'#13#10#13#10 +
                'Oui : Supprimer toutes les données (fonds d''écran, configuration, logs)'#13#10 +
                'Non : Conserver vos données personnelles', 
                mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES then
      begin
        // Supprimer le dossier data avec tout son contenu
        if DelTree(DataPath, True, True, True) then
        begin
          Log('Dossier data supprimé avec succès');
        end
        else
        begin
          Log('Erreur lors de la suppression du dossier data');
        end;
      end
      else
      begin
        Log('L''utilisateur a choisi de conserver le dossier data');
      end;
    end;
  end;
  
  // Après la désinstallation, supprimer le dossier principal s'il est vide
  if CurUninstallStep = usPostUninstall then
  begin
    AppPath := ExpandConstant('{app}');
    
    // Tenter de supprimer le dossier s'il est vide
    if DirExists(AppPath) then
    begin
      RemoveDir(AppPath);
    end;
  end;
end;

