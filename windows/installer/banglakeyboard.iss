; Bangla Keyboard (Windows) installer — Inno Setup. Produces a branded
; BanglaKeyboard-Setup-<ver>.exe that installs the tray app to Program Files.
; Build (after windows\build-all.bat has produced dist\bangla-tray.exe):
;   iscc banglakeyboard.iss     -> installer\dist\BanglaKeyboard-Setup-<ver>.exe
; Unsigned for now — users click "More info -> Run anyway" on SmartScreen.
;
; Keep the version in sync across THREE places: windows\VERSION, windows\tray\tray.rc,
; and MyAppVersion below.

#define MyAppName "Bangla Keyboard"
#define MyAppVersion "1.1.5"
#define MyAppPublisher "AiCMS.BD"
#define MyAppExe "bangla-tray.exe"
#define MyAppURL "https://github.com/aicmsbd/bangla-keyboard"

[Setup]
AppId={{5BD4FB21-7946-4912-98C0-C178E33747BD}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}/releases
; Per-user install: no admin/UAC, lands in %LocalAppData%\Programs, and the
; "start at sign-in" shortcut + Start Menu entry are correctly per-user. (A tray
; utility doesn't need a system-wide install.)
PrivilegesRequired=lowest
DefaultDirName={autopf}\Bangla Keyboard
DefaultGroupName=Bangla Keyboard
DisableProgramGroupPage=yes
DisableWelcomePage=no
OutputDir=dist
OutputBaseFilename=BanglaKeyboard-Setup-{#MyAppVersion}
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern
SetupIconFile=..\tray\banglakeyboard.ico
UninstallDisplayIcon={app}\{#MyAppExe}
; The tray app force-closes via taskkill in [Code] before file copy, so don't
; involve the Restart Manager (it would stall on the hidden tray window).
CloseApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Messages]
WelcomeLabel1=Welcome to Bangla Keyboard
WelcomeLabel2=A free phonetic Bangla keyboard for Windows — type Banglish (amar → আমার) in any app, with live suggestions.%n%n      -   Ctrl+Alt+B = বাংলা,   Ctrl+Alt+E = English%n      -   Includes an editor window (Bangla Keyboard Editor) with the same UI as the macOS app%n      -   Works in every app; all English shortcuts keep working%n%nAICMS Public License v1.0, free & open-source — by AiCMS.BD.

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional icons:"; Flags: unchecked
Name: "startup"; Description: "Start Bangla Keyboard automatically when I sign in"; GroupDescription: "Startup:"

[Files]
Source: "..\dist\bangla-tray.exe"; DestDir: "{app}"; Flags: ignoreversion
; --- Preview panel window (WebView2 twin of the macOS/Linux editor windows) ---
Source: "..\dist\bangla-panel.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\dist\WebView2Loader.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\dist\WebView2Loader-LICENSE.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\dist\ui\*"; DestDir: "{app}\ui"; Flags: ignoreversion recursesubdirs createallsubdirs
; Offline dictionary + AiCMS romanization aliases — the tray loads these from its own folder
; to power the Banglish suggestion popup. Same data as the macOS build.
Source: "..\dist\bangla-dictionary.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\dist\hardwords_raw.tsv"; DestDir: "{app}"; Flags: ignoreversion
; Ship the shortcut icon under a fresh name so Windows' per-path icon cache can't keep showing
; the previous logo on the desktop/Start shortcuts after an upgrade.
Source: "..\tray\banglakeyboard.ico"; DestDir: "{app}"; DestName: "bangla-logo.ico"; Flags: ignoreversion
; Also overwrite the previously-installed name with the new logo, so a desktop shortcut left over
; from an older version (pointing at the old path) also picks up the new icon after the cache refresh.
Source: "..\tray\banglakeyboard.ico"; DestDir: "{app}"; DestName: "banglakeyboard.ico"; Flags: ignoreversion
Source: "USAGE.txt"; DestDir: "{app}"; Flags: ignoreversion isreadme
; License + attribution (bundled in every copy, per the AICMS Public License).
Source: "..\..\LICENSE"; DestDir: "{app}"; DestName: "LICENSE.txt"; Flags: ignoreversion
Source: "..\..\NOTICE"; DestDir: "{app}"; DestName: "NOTICE.txt"; Flags: ignoreversion
; No fonts are bundled — the keyboard emits standard Unicode and renders with any
; system Bangla font (Windows ships "Nirmala UI" with Bengali coverage).

[Registry]
Root: HKCU; Subkey: "Software\BanglaKeyboard"; Flags: uninsdeletekeyifempty

[Icons]
Name: "{group}\Bangla Keyboard"; Filename: "{app}\{#MyAppExe}"; IconFilename: "{app}\bangla-logo.ico"
Name: "{group}\Bangla Keyboard (Editor)"; Filename: "{app}\bangla-panel.exe"; IconFilename: "{app}\bangla-logo.ico"
Name: "{group}\Uninstall Bangla Keyboard"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Bangla Keyboard"; Filename: "{app}\{#MyAppExe}"; IconFilename: "{app}\bangla-logo.ico"; Tasks: desktopicon
Name: "{userstartup}\Bangla Keyboard"; Filename: "{app}\{#MyAppExe}"; Tasks: startup

[Run]
; Rebuild the shell icon cache so the new logo shows on the desktop/Start shortcuts immediately
; (Windows caches rendered icons; without this an upgrade can keep showing the previous logo).
Filename: "{sys}\ie4uinit.exe"; Parameters: "-show"; Flags: runhidden
Filename: "{app}\{#MyAppExe}"; Description: "Launch Bangla Keyboard now"; Flags: nowait postinstall skipifsilent

[Code]
// Force-close any running tray instance before install / uninstall so the EXE
// isn't locked (the app hides to the tray, so a window-based close won't do).
procedure KillTray;
var ResultCode: Integer;
begin
  Exec(ExpandConstant('{cmd}'), '/c taskkill /f /im {#MyAppExe}', '',
       SW_HIDE, ewWaitUntilTerminated, ResultCode);
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  KillTray;
  Result := '';
end;

function InitializeUninstall(): Boolean;
begin
  KillTray;
  Result := True;
end;
