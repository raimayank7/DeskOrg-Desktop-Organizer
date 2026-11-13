; DeskOrg.iss - Inno Setup script for DeskOrgSetup.exe
; Builds a single portable installer that installs DeskOrg to Program Files,
; trusts the code-signing certificate for all users, adds shortcuts, and
; registers an uninstaller. Designed & Developed by: Nivesh Sahayak | https://www.niveshsahayak.in

#define AppName       "DeskOrg"
#define AppVersion    "1.2.0"
#define AppPublisher  "Nivesh Sahayak"
#define AppURL        "https://www.niveshsahayak.in/"
#define SrcDir        "C:\Users\Mayank-Rai\OneDrive\Mayank-Rai\MKR-Personal\ClaudeAi\DeskOrg"

[Setup]
AppId={{8F6C2A94-3E7D-4B1A-9C5E-2D1F0A6B8E34}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppCopyright=Designed & Developed by: Nivesh Sahayak
AppSupportURL={#AppURL}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=admin
OutputDir={#SrcDir}\Installer
OutputBaseFilename=DeskOrgSetup
SetupIconFile={#SrcDir}\DeskOrg.ico
UninstallDisplayIcon={app}\DeskOrg.ico
UninstallDisplayName={#AppName}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Shortcuts:"

[Files]
; Program launcher + scripts
; No .exe is shipped: antivirus programs (K7) quarantine script-wrapped exes. Shortcuts run this .bat instead.
Source: "{#SrcDir}\DeskOrgStart.bat";           DestDir: "{app}"; Flags: ignoreversion
Source: "{#SrcDir}\DeskOrgLauncher.ps1";        DestDir: "{app}"; Flags: ignoreversion
Source: "{#SrcDir}\DeskOrgSplash.ps1";          DestDir: "{app}"; Flags: ignoreversion
Source: "{#SrcDir}\DeskOrgControlCenter.ps1";   DestDir: "{app}"; Flags: ignoreversion
Source: "{#SrcDir}\DeskOrgExtras.ps1";          DestDir: "{app}"; Flags: ignoreversion
Source: "{#SrcDir}\DeskOrgOrganizer.ps1";       DestDir: "{app}"; Flags: ignoreversion
Source: "{#SrcDir}\DeskOrgWatcher.ps1";         DestDir: "{app}"; Flags: ignoreversion
Source: "{#SrcDir}\DeskOrgAutomation.ps1";      DestDir: "{app}"; Flags: ignoreversion
Source: "{#SrcDir}\DeskOrg.bat";                DestDir: "{app}"; Flags: ignoreversion
; Config default + assets (rules is copied to %LOCALAPPDATA%\DeskOrg on first run)
Source: "{#SrcDir}\DeskOrgRules.json";          DestDir: "{app}"; Flags: ignoreversion
Source: "{#SrcDir}\DeskOrgLogo.png";            DestDir: "{app}"; Flags: ignoreversion
Source: "{#SrcDir}\DeskOrg.ico";                DestDir: "{app}"; Flags: ignoreversion
Source: "{#SrcDir}\Unbounded.ttf";              DestDir: "{app}"; Flags: ignoreversion
; Onboarding guide (opens after a successful install) + setup-help page
Source: "{#SrcDir}\DeskOrg-Guide.html";         DestDir: "{app}"; Flags: ignoreversion
Source: "{#SrcDir}\DeskOrg-Setup-Help.html";    DestDir: "{app}"; Flags: ignoreversion
; Same help page embedded for use if the install fails (opened from TEMP)
Source: "{#SrcDir}\DeskOrg-Setup-Help.html";    Flags: dontcopy
; Public certificate (trusted during install)
Source: "{#SrcDir}\DeskOrg-CodeSigning.cer";    DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#AppName}";           Filename: "{app}\DeskOrgStart.bat"; IconFilename: "{app}\DeskOrg.ico"; WorkingDir: "{app}"; Flags: runminimized
Name: "{group}\DeskOrg Guide";        Filename: "{app}\DeskOrg-Guide.html";      IconFilename: "{app}\DeskOrg.ico"
Name: "{group}\Setup Help";           Filename: "{app}\DeskOrg-Setup-Help.html"; IconFilename: "{app}\DeskOrg.ico"
Name: "{group}\Uninstall {#AppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}";     Filename: "{app}\DeskOrgStart.bat"; IconFilename: "{app}\DeskOrg.ico"; WorkingDir: "{app}"; Flags: runminimized; Tasks: desktopicon

[InstallDelete]
; Remove the old launcher exe left by earlier versions.
Type: files; Name: "{app}\DeskOrg.exe"

[Run]
; Trust the DeskOrg certificate for ALL users (runs elevated during install).
Filename: "powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -Command ""Import-Certificate -FilePath '{app}\DeskOrg-CodeSigning.cer' -CertStoreLocation Cert:\LocalMachine\Root | Out-Null; Import-Certificate -FilePath '{app}\DeskOrg-CodeSigning.cer' -CertStoreLocation Cert:\LocalMachine\TrustedPublisher | Out-Null"""; \
  StatusMsg: "Trusting the DeskOrg certificate..."; Flags: runhidden waituntilterminated
; After a successful install, open the guide (checked by default) and offer to launch.
Filename: "{app}\DeskOrg-Guide.html"; Description: "Open the DeskOrg guide (what it is & how to use it)"; Flags: shellexec postinstall skipifsilent
Filename: "{app}\DeskOrgStart.bat"; Description: "Launch {#AppName} now"; Flags: nowait postinstall skipifsilent shellexec runminimized

[UninstallRun]
; Stop the background watcher and remove its startup task first.
Filename: "powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\DeskOrgAutomation.ps1"" Uninstall"; \
  Flags: runhidden waituntilterminated skipifdoesntexist; RunOnceId: "RemoveDeskOrgTask"
; Remove the trusted certificate on uninstall (matches by subject).
Filename: "powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -Command ""Get-ChildItem Cert:\LocalMachine\Root, Cert:\LocalMachine\TrustedPublisher | Where-Object {{ $_.Subject -eq 'CN=DeskOrg Code Signing (Nivesh Sahayak)' } | Remove-Item -Force -ErrorAction SilentlyContinue"""; \
  Flags: runhidden waituntilterminated; RunOnceId: "RemoveDeskOrgCert"

[Code]
var
  StartedInstalling, InstallSucceeded: Boolean;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssInstall then
    StartedInstalling := True;
  if CurStep = ssDone then
    InstallSucceeded := True;
end;

procedure DeinitializeSetup();
var
  Src, Dst: string;
  ErrorCode: Integer;
begin
  { If file copying began but setup never finished cleanly, open the help page. }
  if StartedInstalling and (not InstallSucceeded) then
  begin
    try
      ExtractTemporaryFile('DeskOrg-Setup-Help.html');
      Src := ExpandConstant('{tmp}\DeskOrg-Setup-Help.html');
      Dst := ExpandConstant('{%TEMP}\DeskOrg-Setup-Help.html');
      if FileCopy(Src, Dst, False) then
        ShellExec('open', Dst, '', '', SW_SHOW, ewNoWait, ErrorCode)
      else
        ShellExec('open', Src, '', '', SW_SHOW, ewNoWait, ErrorCode);
    except
    end;
  end;
end;
