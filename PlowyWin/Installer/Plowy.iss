; Inno Setup script for Plowy (per-user install, no admin rights needed)
#define AppVersion GetEnv("PLOWY_VERSION")
#if AppVersion == ""
  #define AppVersion "1.0.0"
#endif

[Setup]
AppId={{6B8E3C2A-5F1D-4C7E-9A3B-2D4F8E1C7B90}
AppName=Plowy
AppVersion={#AppVersion}
AppPublisher=Plowy
DefaultDirName={localappdata}\Programs\Plowy
DefaultGroupName=Plowy
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\out
OutputBaseFilename=Plowy-Setup
SetupIconFile=..\App\Plowy.ico
UninstallDisplayIcon={app}\Plowy.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=force

ShowLanguageDialog=auto

[Languages]
Name: "en"; MessagesFile: "compiler:Default.isl"
Name: "de"; MessagesFile: "compiler:Languages\German.isl"
Name: "es"; MessagesFile: "compiler:Languages\Spanish.isl"
Name: "fr"; MessagesFile: "compiler:Languages\French.isl"
Name: "it"; MessagesFile: "compiler:Languages\Italian.isl"
Name: "pt"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"
Name: "ru"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "tr"; MessagesFile: "compiler:Languages\Turkish.isl"
Name: "ja"; MessagesFile: "compiler:Languages\Japanese.isl"
Name: "ko"; MessagesFile: "compiler:Languages\Korean.isl"

[CustomMessages]
en.StartWithWindows=Start Plowy when Windows starts
de.StartWithWindows=Plowy beim Windows-Start ausführen
es.StartWithWindows=Iniciar Plowy al arrancar Windows
fr.StartWithWindows=Lancer Plowy au démarrage de Windows
it.StartWithWindows=Avvia Plowy all'avvio di Windows
pt.StartWithWindows=Iniciar o Plowy com o Windows
ru.StartWithWindows=Запускать Plowy вместе с Windows
tr.StartWithWindows=Plowy'ı Windows ile başlat
ja.StartWithWindows=Windows の起動時に Plowy を開始
ko.StartWithWindows=Windows 시작 시 Plowy 실행

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
Name: "startup"; Description: "{cm:StartWithWindows}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\out\publish\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs

[Icons]
Name: "{group}\Plowy"; Filename: "{app}\Plowy.exe"
Name: "{group}\Uninstall Plowy"; Filename: "{uninstallexe}"
Name: "{userdesktop}\Plowy"; Filename: "{app}\Plowy.exe"; Tasks: desktopicon

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "Plowy"; \
  ValueData: """{app}\Plowy.exe"""; Flags: uninsdeletevalue; Tasks: startup

[Run]
Filename: "{app}\Plowy.exe"; Description: "{cm:LaunchProgram,Plowy}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "{cmd}"; Parameters: "/C taskkill /IM Plowy.exe /F"; Flags: runhidden; RunOnceId: "KillPlowy"

[UninstallDelete]
Type: filesandordirs; Name: "{userappdata}\Plowy"
