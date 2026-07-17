; Inno Setup script for the Watchparty Windows desktop app.
;
; Produces a classic Setup.exe from the Flutter release build. The build folder
; (watchparty.exe + Flutter DLLs + data\, plus the bundled VC++ redistributable
; DLLs) is staged by the CI "Package .zip" step at dist\stage\Watchparty; this
; installer packages that same staged tree.
;
; Values are injected by ISCC via /D defines (see release-desktop.yml); the
; #ifndef fallbacks let you also run `iscc packaging\windows\watchparty.iss`
; locally after a `flutter build windows --release` + staging.
;
; NOTE: unsigned. Without an Authenticode cert, SmartScreen will still warn on
; first run ("More info -> Run anyway") — same as the portable zip.

#define MyAppName "Watchparty"

#ifndef MyAppVersion
  #define MyAppVersion "0.0.0"
#endif
#ifndef MySourceDir
  #define MySourceDir "..\..\build\windows\x64\runner\Release"
#endif
#ifndef MyOutputDir
  #define MyOutputDir "..\..\dist"
#endif
#ifndef MyOutputBase
  #define MyOutputBase "Watchparty-windows-setup"
#endif

[Setup]
; Stable AppId so upgrades replace the previous install instead of stacking.
AppId={{B2A1E7C4-1F3D-4E56-9A7B-0A1B2C3D4E5F}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher=Watchparty
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\watchparty.exe
OutputDir={#MyOutputDir}
OutputBaseFilename={#MyOutputBase}
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; Flags: unchecked

[Files]
Source: "{#MySourceDir}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\watchparty.exe"
Name: "{group}\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\watchparty.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\watchparty.exe"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent
