; WhisperDoc Inno Setup Script
; Version: 2.22.2

#define MyAppName "WhisperDoc"
#define MyAppVersion "2.22.2"
#define MyAppPublisher "EphremTil"
#define MyAppURL "https://github.com/EphremTil17/whisperdoc_release"
#define MyAppExeName "WhisperDoc.exe"

[Setup]
AppId={{5D2E1A7B-9F2C-4E1B-8C4D-3A2B1C0E9D8F}
AppName={#MyAppName}
AppVerName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppCopyright=Copyright (C) 2026 Ephrem
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DisableProgramGroupPage=yes
OutputDir=C:\Users\Ephrem\Documents\Projects\WhisperDoc\flutter_client\windows\installer
OutputBaseFilename=WhisperDoc_Setup_v{#MyAppVersion}
SetupIconFile=C:\Users\Ephrem\Documents\Projects\WhisperDoc\flutter_client\windows\runner\resources\app_icon.ico
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
Compression=lzma
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\{#MyAppExeName}
VersionInfoVersion={#MyAppVersion}
VersionInfoCompany={#MyAppPublisher}
VersionInfoDescription={#MyAppName} Setup
VersionInfoCopyright=Copyright (C) 2026 Ephrem

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "C:\Users\Ephrem\Documents\Projects\WhisperDoc\flutter_client\build\windows\x64\runner\Release\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "C:\Users\Ephrem\Documents\Projects\WhisperDoc\flutter_client\build\windows\x64\runner\Release\*.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "C:\Users\Ephrem\Documents\Projects\WhisperDoc\flutter_client\build\windows\x64\runner\Release\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
