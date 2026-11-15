; 公仔櫃 Desk Pals：Windows 安裝程式（Inno Setup 6，免費）。由 packaging\windows\build.ps1 呼叫：
;   ISCC /DAppVersion=x.y.z /DRoot=<repo> /DBuildDir=<build\win> /DIconDir=<build\icons> /DLangFile=<ChineseTraditional.isl> /O<dist> DeskPals.iss
; 安裝給「目前這個使用者」（不用系統管理員）：%LOCALAPPDATA%\Programs\DeskPals
; 開機自動啟動＝「啟動」資料夾裡的「公仔櫃 Desk Pals.lnk」（跟 VS Code 擴充套件同一個名字 → 直接換成 exe 版，不會開兩次）
; 裝好會寫 %LOCALAPPDATA%\DeskPals\standalone.json：VS Code 擴充套件看到它就不再自己編一份、不再建開機捷徑，只負責連上這個 exe。

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#define AppName "公仔櫃 Desk Pals"
#define ExeName "DeskPals.exe"

[Setup]
; AppId 不能改：升級、解除安裝都靠它認出同一套
AppId={{63CF3CC4-F964-4964-A39D-B1703A4A9496}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=Desk Pals
AppCopyright=Desk Pals
VersionInfoVersion={#AppVersion}
VersionInfoProductName={#AppName}
VersionInfoDescription={#AppName} 安裝程式
PrivilegesRequired=lowest
DefaultDirName={autopf}\DeskPals
DisableDirPage=yes
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
DisableReadyPage=yes
OutputBaseFilename=DeskPals-Setup-{#AppVersion}
SetupIconFile={#IconDir}\DeskPals.ico
UninstallDisplayIcon={app}\{#ExeName}
UninstallDisplayName={#AppName}
WizardStyle=modern
WizardImageFile={#IconDir}\inno\wizard-100.bmp,{#IconDir}\inno\wizard-125.bmp,{#IconDir}\inno\wizard-150.bmp,{#IconDir}\inno\wizard-175.bmp,{#IconDir}\inno\wizard-200.bmp
WizardSmallImageFile={#IconDir}\inno\small-100.bmp,{#IconDir}\inno\small-125.bmp,{#IconDir}\inno\small-150.bmp,{#IconDir}\inno\small-175.bmp,{#IconDir}\inno\small-200.bmp
Compression=lzma2/max
SolidCompression=yes
MinVersion=10.0
; 舊版還開著：PrepareToInstall 先用 --quit 請它收工；萬一沒收，Windows 的重新啟動管理員再幫忙關
CloseApplications=yes
RestartApplications=no
ShowLanguageDialog=no
LanguageDetectionMethod=none
#ifdef SIGN
SignTool=dpsign
SignedUninstaller=yes
#endif

[Languages]
Name: "zhtw"; MessagesFile: "{#LangFile}"

[CustomMessages]
zhtw.TaskGroup=要不要：
zhtw.AutoStart=開機時自動出現在桌面（建議）
zhtw.DesktopIcon=在桌面放一個捷徑
zhtw.LaunchNow=現在就打開公仔櫃
zhtw.AskDeleteData=要一併刪除你的公仔設定和紀錄嗎？%n%n（%1）%n%n選「否」會保留：之後重新安裝，或用 VS Code 擴充套件，都會接著用。
zhtw.StartComment=整個螢幕的像素公仔

[Tasks]
Name: "autostart"; Description: "{cm:AutoStart}"; GroupDescription: "{cm:TaskGroup}"
Name: "desktopicon"; Description: "{cm:DesktopIcon}"; GroupDescription: "{cm:TaskGroup}"; Flags: unchecked

[Files]
Source: "{#BuildDir}\{#ExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#Root}\extension\desktop\claude-hook.js"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#Root}\extension\desktop\ci-watch.js"; DestDir: "{app}"; Flags: ignoreversion
; Claude Code hooks 的設定指著 %LOCALAPPDATA%\DeskPals\claude-hook.js（安裝說明這樣寫）：放一份過去；解除安裝時留著（使用者資料夾）
Source: "{#Root}\extension\desktop\claude-hook.js"; DestDir: "{localappdata}\DeskPals"; Flags: ignoreversion uninsneveruninstall
Source: "{#Root}\extension\desktop\ci-watch.js"; DestDir: "{localappdata}\DeskPals"; Flags: ignoreversion uninsneveruninstall

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#ExeName}"; Comment: "{cm:StartComment}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#ExeName}"; Comment: "{cm:StartComment}"; Tasks: desktopicon
; 跟 VS Code 擴充套件同名：有舊的（指著 powershell + desk-pals.ps1）就直接換掉
Name: "{userstartup}\{#AppName}"; Filename: "{app}\{#ExeName}"; Comment: "{cm:StartComment}"; Tasks: autostart

[InstallDelete]
; 沒勾開機啟動：連擴充套件之前建的那個也拿掉（不然開機還是會跑出舊的那份）
Type: files; Name: "{userstartup}\{#AppName}.lnk"; Tasks: not autostart

[Registry]
Root: HKCU; Subkey: "Software\DeskPals"; ValueType: string; ValueName: "InstallDir"; ValueData: "{app}"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\DeskPals"; ValueType: string; ValueName: "Version"; ValueData: "{#AppVersion}"; Flags: uninsdeletekey

[Run]
; --replace：VS Code 擴充套件編的那份（或舊版）如果還開著，先請它收工，再換這個上來
Filename: "{app}\{#ExeName}"; Parameters: "--replace"; Description: "{cm:LaunchNow}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "{app}\{#ExeName}"; Parameters: "--quit"; Flags: runhidden waituntilterminated; RunOnceId: "QuitDeskPals"

[UninstallDelete]
Type: files; Name: "{localappdata}\DeskPals\standalone.json"

[Code]
var
  DeleteData: Boolean;

{ 不管開著的是舊版 exe 還是 VS Code 擴充套件編的那份，都用新的 exe 送 quit 過去，等它真的關掉 }
procedure QuitRunning();
var
  Rc: Integer;
begin
  ExtractTemporaryFile('{#ExeName}');
  Exec(ExpandConstant('{tmp}\{#ExeName}'), '--quit', '', SW_HIDE, ewWaitUntilTerminated, Rc);
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  QuitRunning();
  Result := '';
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  Dir, Exe: String;
  Lines: TArrayOfString;
begin
  if CurStep = ssPostInstall then
  begin
    Dir := ExpandConstant('{localappdata}\DeskPals');
    ForceDirectories(Dir);
    Exe := ExpandConstant('{app}\{#ExeName}');
    StringChangeEx(Exe, '\', '\\', True);
    SetArrayLength(Lines, 1);
    Lines[0] := '{"kind":"installer","exe":"' + Exe + '","version":"{#AppVersion}"}';
    SaveStringsToUTF8File(Dir + '\standalone.json', Lines, False);
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then
  begin
    DeleteData := False;
    if not UninstallSilent() then
      DeleteData := MsgBox(FmtMessage(CustomMessage('AskDeleteData'), [ExpandConstant('{localappdata}\DeskPals')]),
        mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES;
  end;
  if (CurUninstallStep = usPostUninstall) and DeleteData then
    DelTree(ExpandConstant('{localappdata}\DeskPals'), True, True, True);
end;
