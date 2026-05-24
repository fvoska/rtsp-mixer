; Inno Setup script for RTSP Mixer.
; AppVersion is passed in by CI: ISCC /DAppVersion=1.2.3 installer.iss
; The AppId GUID below must NEVER change once a release has shipped — Windows
; uses it to recognize the app for upgrade/uninstall. Regenerating it would
; turn every future installer into a separate, parallel install.

#ifndef AppVersion
  #define AppVersion "0.0.0-dev"
#endif

#define AppName    "RTSP Mixer"
#define AppId      "{2064C59D-4FBA-4BCA-9366-58D1DEA29078}"
#define AppExe     "rtsp_mixer.exe"
#define AppPub     "Filip Voska"
#define AppUrl     "https://github.com/fvoska/rtsp-mixer"

[Setup]
AppId={{#AppId}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPub}
AppPublisherURL={#AppUrl}
AppSupportURL={#AppUrl}
AppUpdatesURL={#AppUrl}/releases
DefaultDirName={autopf}\RTSP Mixer
DefaultGroupName=RTSP Mixer
DisableProgramGroupPage=yes
OutputDir=..\build\windows\installer
OutputBaseFilename=rtsp-mixer-{#AppVersion}-windows-setup
Compression=lzma
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
UninstallDisplayIcon={app}\{#AppExe}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; \
  GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; \
  Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{group}\Uninstall {#AppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "Launch {#AppName}"; \
  Flags: nowait postinstall skipifsilent
