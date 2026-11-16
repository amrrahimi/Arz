; Inno Setup script for Barfak (per-user install, no admin rights needed)
#define AppVersion GetEnv("BARFAK_VERSION")
#if AppVersion == ""
  #define AppVersion "1.0.0"
#endif

[Setup]
AppId={{6B8E3C2A-5F1D-4C7E-9A3B-2D4F8E1C7B90}
AppName=Barfak
AppVersion={#AppVersion}
AppPublisher=Barfak
DefaultDirName={localappdata}\Programs\Barfak
DefaultGroupName=Barfak
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\out
OutputBaseFilename=Barfak-Setup
SetupIconFile=..\App\Barfak.ico
UninstallDisplayIcon={app}\Barfak.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=force

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
Name: "startup"; Description: "Start Barfak when Windows starts"; GroupDescription: "Startup:"

[Files]
Source: "..\out\publish\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs

[Icons]
Name: "{group}\Barfak"; Filename: "{app}\Barfak.exe"
Name: "{group}\Uninstall Barfak"; Filename: "{uninstallexe}"
Name: "{userdesktop}\Barfak"; Filename: "{app}\Barfak.exe"; Tasks: desktopicon

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "Barfak"; \
  ValueData: """{app}\Barfak.exe"""; Flags: uninsdeletevalue; Tasks: startup

[Run]
Filename: "{app}\Barfak.exe"; Description: "{cm:LaunchProgram,Barfak}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "{cmd}"; Parameters: "/C taskkill /IM Barfak.exe /F"; Flags: runhidden; RunOnceId: "KillBarfak"

[UninstallDelete]
Type: filesandordirs; Name: "{userappdata}\Barfak"
