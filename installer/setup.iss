; UPA Wallpaper Manager — Windows installer (Inno Setup 6)
;
; Build:
;   1. flutter build windows --release
;   2. "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" installer\setup.iss
;
; Output: installer\Output\UPA_Wallpaper_Manager_Setup_<version>.exe
;
; Notes:
;   - The app embeds a requireAdministrator manifest (needed for the
;     lock-screen wallpaper feature), so the installer installs machine-wide
;     and requires elevation too.
;   - "Launch at Windows startup" is managed inside the app (Settings) via an
;     elevated Scheduled Task; the installer does not create it.

#define MyAppName "UPA Wallpaper Manager"
#define MyAppVersion "2.0.0"
#define MyAppPublisher "Universe Photo Archive"
#define MyAppURL "https://universe-photo-archive.eu"
#define MyAppExeName "upa_wallpaper_manager.exe"

[Setup]
AppId={{6F9E2B7A-1D24-4C8B-9E3F-A5C6D0B18F42}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL=https://github.com/Universe-Photo-Archive/UPA_Wallpaper_Manager/releases
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=admin
OutputDir=Output
OutputBaseFilename=UPA_Wallpaper_Manager_Setup_{#MyAppVersion}
SetupIconFile=..\assets\icons\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "french"; MessagesFile: "compiler:Languages\French.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
; Stop the app and remove the autostart scheduled task the app may have created.
Filename: "taskkill.exe"; Parameters: "/F /IM {#MyAppExeName}"; Flags: runhidden; RunOnceId: "KillApp"
Filename: "schtasks.exe"; Parameters: "/Delete /F /TN ""{#MyAppName}"""; Flags: runhidden; RunOnceId: "DelAutostartTask"

[Code]
// Make sure a running instance never blocks file replacement (the auto-update
// flow launches this installer while the app is still running).
function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ResultCode: Integer;
begin
  Exec('taskkill.exe', '/F /IM {#MyAppExeName}', '', SW_HIDE,
       ewWaitUntilTerminated, ResultCode);
  // Give Windows a moment to release file locks.
  Sleep(500);
  Result := '';
end;
