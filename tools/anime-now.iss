; Inno Setup script for the Windows installer.
;
; Built by tools/make-windows.ps1, which passes the version in:
;   iscc /DAppVersion=2026.9.3.1 tools\anime-now.iss
;
; Installs per-user under %LOCALAPPDATA%\Programs so no admin prompt appears.
; The build is unsigned, so SmartScreen will warn on first run either way.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

#define AppName "Anime Now"
#define AppPublisher "erichuanp"
#define AppExeName "anime_now.exe"
#define AppUrl "https://github.com/erichuanp/anime-now"

[Setup]
AppId={{6F2A7C41-8E5B-4D93-9A17-2C0B5E8D4F31}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppUrl}
AppSupportURL={#AppUrl}/issues
AppUpdatesURL={#AppUrl}/releases
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputDir=..\dist
OutputBaseFilename=anime-now-{#AppVersion}-windows-setup
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExeName}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; The whole Release folder: the exe alone will not run, it needs the DLLs and data\.
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(AppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
