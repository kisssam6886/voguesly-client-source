[Setup]
AppId={{APP_ID}}
AppVersion={{APP_VERSION}}
AppName={{DISPLAY_NAME}}
AppPublisher={{PUBLISHER_NAME}}
AppPublisherURL={{PUBLISHER_URL}}
AppSupportURL={{PUBLISHER_URL}}
AppUpdatesURL={{PUBLISHER_URL}}
DefaultDirName={autopf}\Voguesly
DisableProgramGroupPage=yes
OutputDir=.
OutputBaseFilename={{OUTPUT_BASE_FILENAME}}
Compression=lzma
SolidCompression=yes
SetupIconFile={{SETUP_ICON_FILE}}
WizardStyle=modern
PrivilegesRequired={{PRIVILEGES_REQUIRED}}
ArchitecturesAllowed={{ARCH}}
ArchitecturesInstallIn64BitMode={{ARCH}}
; [0.9.85] 安装向导换成易联品牌图(以前是 Inno 默认图)。左侧大图 164×314 / 200% 328×628,右上小图 55×55 / 110×110;
; 逗号分隔多张时 Inno 按系统 DPI 自动选最合适的一张。路径与 [Languages] 的 isl 同基准(.iss 在 dist\ 编译)。
WizardImageFile=..\windows\packaging\exe\wizard_image.bmp,..\windows\packaging\exe\wizard_image_200.bmp
WizardSmallImageFile=..\windows\packaging\exe\wizard_small.bmp,..\windows\packaging\exe\wizard_small_200.bmp
; Inno Setup 6 默认不显示欢迎页(DisableWelcomePage=yes),易联大图只会在完成页出现;打开欢迎页让用户一开始就看到品牌。
; 一键更新走 /SILENT,不显示任何页面,不受影响。
DisableWelcomePage=no
; 「应用和功能」/ 控制面板里的名称和图标:固定显示「易联 Voguesly」+ 易联图标(默认会带上版本号、图标取卸载程序)。
UninstallDisplayName={{DISPLAY_NAME}}
UninstallDisplayIcon={app}\{{EXECUTABLE_NAME}}

; 🔴 [2026-09-23 实机第二轮] 关闭占用文件嘅程序 —— 交返畀 Inno 自己嘅 RestartManager。
;
; 上一轮用 PowerShell 逐个 `Stop-Process` 杀,实测:命令本身啱(手动跑 KILLED OK)、
; PrepareToInstall 亦确实行咗(安装日志 18:15:58→18:16:11 中间 12 秒就係佢),
; 但之后 RestartManager 仍然报 `found an application using one of our files: Voguesly`
; ⇒ `Some applications could not be shut down` ⇒ **exitcode 5,成个安装回滚**。
; 而 /SUPPRESSMSGBOXES 之下 Abort/Retry/Ignore 默认揀 Abort;如果係用户手动装,
; 就会见到「安装程序无法自动关闭所有应用程序」—— 一样係坏体验。
;
; RestartManager 本身就係**按「边个进程占住我哋要装嘅文件」**匹配,唔係按进程名 ——
; 正正就係我哋要嘅判据(官方 FlClash 装喺佢自己目录,文件路径唔同,**唔会**被匹配到,
; 所以唔会误杀人哋条 VPN)。`force` = 关唔掉就强制终止,唔再弹框问用户。
; 呢个比自己砌 PowerShell 更准、更快(慳返 5 次 PowerShell 冷启动≈10 秒),亦冇咗
; 「杀完又俾人拉返起身」嘅竞态。
CloseApplications=force
; 装完唔好自动重开被关嘅程序:[Run] 段本身已经有 postinstall 启动一次,
; RestartApplications=yes 会变成开两个实例。
RestartApplications=no

[Code]
// ⚠️ 升级要「干净落场」,唔係净係 taskkill(2026-08-10 实测根因):
//   旧写法直接 `taskkill /f` 强杀 FlClashHelperService.exe,但**冇 sc stop / sc delete**,
//   服务注册留喺 SCM 度、状态係脏嘅。App 启动时 registerService() 见到服务仲喺(presence)
//   就行 `sc delete` → `sc create`;而强杀之后 `sc delete` 会令服务变成
//   **"marked for deletion"**,跟住同名 `sc create` 直接失败(error 1072),要等 SCM 释放晒
//   句柄先得。App 嗰边只重试 5 次 × 1 秒,远远唔够 → helper 起唔到 → TUN 建唔起 →
//   **用户装完新版有 4-7 分钟完全连唔上**,以为新版坏咗就退版(一位付费用户实测踩过)。
// 修法:装之前先 `sc stop` 畀佢自己干净收场,再 `sc delete` 清走注册,最后先 taskkill 兜底。
//   咁装完之后系统度冇残留服务记录,App 一开就 `sc create` 得,唔使等 SCM。
// [0.9.96] 旧服务名 FlClashHelperService 只可以删**我哋自己旧版**登记嘅(ImagePath 喺我哋安装目录)。
//   09-30 实测:用户装住官方 FlClash 并开住增强模式时,装 / 升级易联会无条件删走官方个服务
//   ⇒ 官方 FlClash 当场断网(sc query 1060)。呢个係我哋单方面整烂人哋嘅嘢,唔可以。
function LegacyHelperIsOurs: Boolean;
var
  ImagePath: String;
begin
  Result := False;
  if RegQueryStringValue(HKEY_LOCAL_MACHINE, 'SYSTEM\CurrentControlSet\Services\FlClashHelperService', 'ImagePath', ImagePath) then
    Result := Pos(Lowercase(ExpandConstant('{app}')), Lowercase(ImagePath)) > 0;
end;

procedure StopAndRemoveHelperService;
var
  ResultCode: Integer;
begin
  // [2026-09-23] 服务名由 FlClashHelperService 改咗做 VogueslyHelperService
  //   (官方 FlClash 用紧前者,撞名 = 两个 App 抢同一个 root 服务)。
  //   ⚠️ 两个都要处理:新名係而家嘅,旧名係**升级时清残留**。
  //   旧名嗰条**唔可以喺用户装咗官方 FlClash 嗰阵乱删** —— 但 sc stop/delete
  //   要管理员权限而且只影响本机注册嘅同名服务,官方 App 会喺佢自己下次启动时重建,
  //   所以呢度保留(唔删旧名嘅话,我哋自己嘅升级会留低一个 root 服务)。
  Exec('sc', 'stop VogueslyHelperService', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Sleep(1000);
  Exec('sc', 'delete VogueslyHelperService', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Sleep(500);
  if LegacyHelperIsOurs then
  begin
    Exec('sc', 'stop FlClashHelperService', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    Sleep(1500);
    Exec('sc', 'delete FlClashHelperService', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    Sleep(500);
  end;
end;

// 🔴 [2026-09-23] 按**完整路径**杀,唔准按进程名。
//
// 原本係 `taskkill /f /im FlClashCore.exe`(仲有 FlClash.exe)—— `/im` 只认名唔认路径。
// 用户如果装咗**官方 FlClash** 而且开住,我哋一装就会把佢个核心同主程序一齐强杀,
// 佢条 VPN 当场断线。呢个係我哋单方面整烂人哋嘅嘢,唔可以接受。
//
// 改用 PowerShell 按 `$_.Path` 过滤,只杀**我哋自己安装目录下面**嗰啲。
// [2026-09-23 第二轮] 原本呢度有 KillProcessByPath / KillProcesses 两个 procedure,
// 用 PowerShell 按 $_.Path 过滤嚟杀我哋自己目录下面嘅进程(为咗唔误杀官方 FlClash)。
// 而家改由 [Setup] 嘅 CloseApplications=force 做(见上面嗰段注释),所以删走 ——
// RestartManager 本身就係按文件路径匹配,又准又快,唔使自己砌。
// ⚠️ 但**服务清理 RestartManager 做唔到**(佢只管进程占文件,唔管 SCM 注册),
//    所以 StopAndRemoveHelperService 一定要留,而且要喺复制文件之前行。

// [0.9.96] 服务停咗之后,旧版 helper(0.9.96 build 11 或更早)唔会收埋佢起嘅核心 ⇒ 核心变成 session 0 嘅孤儿,
//   RestartManager 关唔到(Permission Denied + Session Mismatch)⇒ 安装 Abort(09-30 实测,开住增强模式覆盖安装必中)。
//   呢度按**完整路径**收埋我哋安装目录下面嘅核心 / helper(唔准按进程名:官方 FlClash 核心都叫 FlClashCore.exe)。
procedure KillOurLeftoverProcesses;
var
  ResultCode: Integer;
  AppDir: String;
begin
  AppDir := ExpandConstant('{app}');
  Exec('powershell.exe',
    '-NoProfile -ExecutionPolicy Bypass -Command "Get-Process -Name FlClashCore,VogueslyHelperService,FlClashHelperService -ErrorAction SilentlyContinue | Where-Object { $_.Path -like ''' + AppDir + '\*'' } | Stop-Process -Force -ErrorAction SilentlyContinue"',
    '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Sleep(500);
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  // 服务清理 + 收埋我哋自己嘅孤儿核心;主程序(用户会话)交畀 CloseApplications=force。
  StopAndRemoveHelperService;
  KillOurLeftoverProcesses;
  Result := '';
end;

[Languages]
; ⚠️ Inno Setup 6 默认安装(含 CI 的 choco 安装)NOT bundle 中文 isl —— 用 compiler:Languages\Chinese*.isl 会
; 令 ISCC "Can't open file" 编译失败(只出 -setup_exe 暂存夹冇 installer)。故繁/简 isl 随仓库 vendor,
; 用相对路径引(与 SETUP_ICON_FILE 的 ..\windows\ 同基准,.iss 在 dist/ 编译)。英文 Default.isl 是内置故照用。
Name: "chineseSimplified"; MessagesFile: "..\windows\packaging\exe\ChineseSimplified.isl"
Name: "chineseTraditional"; MessagesFile: "..\windows\packaging\exe\ChineseTraditional.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
; [0.9.85] 「创建桌面快捷方式」默认勾选(以前默认不勾,但下载页写的是「安装版会自动建桌面快捷方式」)。
; 不带 Flags = 默认勾选;升级安装时 Inno 默认 UsePreviousTasks=yes,沿用用户上次的选择。
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
[Files]
Source: "{{SOURCE_DIR}}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; NOTE: Don't use "Flags: ignoreversion" on any shared system files

[Icons]
Name: "{autoprograms}\{{DISPLAY_NAME}}"; Filename: "{app}\{{EXECUTABLE_NAME}}"
Name: "{autodesktop}\{{DISPLAY_NAME}}"; Filename: "{app}\{{EXECUTABLE_NAME}}"; Tasks: desktopicon
[Run]
; [2026-09-18] 拿走 skipifsilent:app 内一键更新用 /SILENT 起安装程序,装完要自动重开新版(postinstall 喺 silent 模式下会自动执行)
Filename: "{app}\{{EXECUTABLE_NAME}}"; Description: "{cm:LaunchProgram,{{DISPLAY_NAME}}}"; Flags: {% if PRIVILEGES_REQUIRED == 'admin' %}runascurrentuser{% endif %} nowait postinstall