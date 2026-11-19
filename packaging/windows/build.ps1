# 公仔櫃 Desk Pals：Windows 獨立版打包（exe → 安裝程式 → MSIX）。只用免費工具：
#   csc.exe（Windows 內建 .NET Framework 4.x）、Inno Setup 6（ISCC.exe）、Windows SDK（makeappx／makepri／signtool）、Python + Pillow（畫圖示）
#
# 用法（在 repo 根目錄）：
#   powershell -NoProfile -File packaging\windows\build.ps1                    # 全部（找不到 Inno／SDK 的那一步會略過並提示）
#   powershell -NoProfile -File packaging\windows\build.ps1 -Steps exe         # 只編 exe
#   ... -Steps exe,installer,msix -Strict                                       # CI：缺工具就失敗
#   ... -Variant personal                                                       # 個人版（全部角色，含同人；自己用，不要公開）
# 產出（版號＝extension/package.json 的 version）：
#   公開版（預設；上架 Microsoft Store、公開下載只能用這個）：dist\DeskPals.exe、dist\DeskPals-Setup-<版號>.exe、dist\DeskPals-<版號>.msix
#   個人版：dist\DeskPals-personal.exe、dist\DeskPals-Setup-<版號>-personal.exe（預設不打 MSIX）
# 公開版的原始碼由 tools/variant.py 從 extension/desktop 減掉同人角色產生（build\public\extension\desktop），
# 編好的 exe、MSIX 會再用 variant.py guard 掃一次同人字眼，有就失敗。
#
# 簽章（之後有憑證再開）：設了環境變數 DESKPALS_SIGN_PFX（.pfx 路徑）＋ DESKPALS_SIGN_PASSWORD 就會用 signtool 簽 exe、安裝程式（含解除安裝程式）；
# 沒設就安靜略過。MSIX 一律不簽（上架時 Microsoft Store 會簽）。
# MSIX 的身分（Partner Center 給的）：環境變數 MSIX_IDENTITY_NAME、MSIX_PUBLISHER、MSIX_PUBLISHER_DISPLAY_NAME；沒設＝佔位值（只能拿來檢查，不能上架）。
# 匿名回報（只有公開版）：環境變數 GA4_MEASUREMENT_ID、GA4_API_SECRET（CI 的 repo variable／secret）→ tools/variant.py 寫成 pals\ga4.txt，
#   跟其他 pals 檔一起內嵌進 exe（MSIX、安裝程式都是同一支 exe）。沒設＝這一版不回報（程式裡沒有寫死任何 ID）。
param(
    [string[]]$Steps = @(),
    [string]$OutDir = "dist",
    [ValidateSet("public", "personal")][string]$Variant = "public",
    [switch]$Strict
)
$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $Root
$Steps = @($Steps | ForEach-Object { $_ -split "," } | Where-Object { $_ })
$Personal = $Variant -eq "personal"
if ($Steps.Count -eq 0) { $Steps = if ($Personal) { @("exe", "installer") } else { @("exe", "installer", "msix") } }
$Suffix = if ($Personal) { "-personal" } else { "" }
$Build = Join-Path $Root $(if ($Personal) { "build\win-personal" } else { "build\win" })
$Icons = Join-Path $Root "build\icons"
$Out = Join-Path $Root $OutDir
New-Item -ItemType Directory -Force -Path $Build, $Out | Out-Null

$pkg = Get-Content (Join-Path $Root "extension\package.json") -Raw -Encoding UTF8 | ConvertFrom-Json
$Version = $pkg.version
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw "extension/package.json version '$Version' must be x.y.z" }
$Version4 = "$Version.0"
Write-Host "Desk Pals $Version ($Variant)"

function Skip([string]$what) {
    if ($Strict) { throw $what }
    Write-Warning "$what — skipped"
}

function Find-SdkTool([string]$name) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $kits = Join-Path ${env:ProgramFiles(x86)} "Windows Kits\10\bin"
    if (Test-Path $kits) {
        $hit = Get-ChildItem $kits -Directory | Where-Object { $_.Name -match '^10\.' } | Sort-Object { [version]$_.Name } -Descending |
            ForEach-Object { Join-Path $_.FullName "x64\$name" } | Where-Object { Test-Path $_ } | Select-Object -First 1
        if ($hit) { return $hit }
    }
    return $null
}

$Sign = $env:DESKPALS_SIGN_PFX -and (Test-Path $env:DESKPALS_SIGN_PFX)
$SignTool = if ($Sign) { Find-SdkTool "signtool.exe" } else { $null }
if ($Sign -and -not $SignTool) { throw "DESKPALS_SIGN_PFX is set but signtool.exe was not found" }
function Sign-File([string]$file) {
    if (-not $Sign) { return }
    & $SignTool sign /fd sha256 /f $env:DESKPALS_SIGN_PFX /p $env:DESKPALS_SIGN_PASSWORD /tr http://timestamp.digicert.com /td sha256 /d "WoWo Pals" $file
    if ($LASTEXITCODE -ne 0) { throw "signtool failed on $file" }
    Write-Host "signed $file"
}

# ---------- 圖示 ----------
$py = (Get-Command python -ErrorAction SilentlyContinue)
if (-not $py) { $py = Get-Command py -ErrorAction SilentlyContinue }
if (-not $py) { throw "python (with Pillow) is needed to draw the icons" }
& $py.Source -I (Join-Path $Root "packaging\icons\make_icons.py") $Icons
if ($LASTEXITCODE -ne 0) { throw "make_icons.py failed" }

$Exe = Join-Path $Build "DeskPals.exe"

# ---------- 原始碼：個人版＝repo 本身；公開版＝減掉同人角色（並掃一次）----------
if ($Personal) { $Desk = Join-Path $Root "extension\desktop" }
else {
    & $py.Source -I (Join-Path $Root "tools\variant.py") public
    if ($LASTEXITCODE -ne 0) { throw "tools/variant.py public failed (fan content in the public variant?)" }
    $Desk = Join-Path $Root "build\public\extension\desktop"
}
function Guard([string[]]$paths) {
    if ($Personal) { return }
    & $py.Source -I (Join-Path $Root "tools\variant.py") guard @paths
    if ($LASTEXITCODE -ne 0) { throw "fan content in the public build: $($paths -join ', ')" }
}

# ---------- exe ----------
if ($Steps -contains "exe") {
    $csc = Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319\csc.exe"
    if (-not (Test-Path $csc)) { $csc = Join-Path $env:WINDIR "Microsoft.NET\Framework\v4.0.30319\csc.exe" }
    if (-not (Test-Path $csc)) { throw "csc.exe (.NET Framework 4.x) not found" }
    # 跟 desk-pals.ps1 一模一樣的組法：DeskPals.cs ＋ DeskPals.*.cs（照名字排序）接成一份，同一個編譯器（C# 5）
    $desk = $Desk
    $src = [System.IO.File]::ReadAllText((Join-Path $desk "DeskPals.cs"), [System.Text.Encoding]::UTF8)
    foreach ($f in (Get-ChildItem -Path $desk -Filter "DeskPals.*.cs" | Sort-Object Name)) { $src += "`n" + [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8) }
    $utf8 = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllText((Join-Path $Build "DeskPals.all.cs"), $src, $utf8)
    $year = (Get-Date).Year
    $info = @"
using System.Reflection;
[assembly: AssemblyTitle("WoWo Pals")]
[assembly: AssemblyDescription("桌面上的像素公仔櫃")]
[assembly: AssemblyProduct("WoWo Pals")]
[assembly: AssemblyCompany("Desk Pals")]
[assembly: AssemblyCopyright("© $year Desk Pals")]
[assembly: AssemblyVersion("$Version4")]
[assembly: AssemblyFileVersion("$Version4")]
[assembly: AssemblyInformationalVersion("$Version")]
"@
    [System.IO.File]::WriteAllText((Join-Path $Build "AssemblyInfo.g.cs"), $info, $utf8)
    # Store 版的開機啟動（StartupTask）用 Windows 內建的 WinRT 中繼資料；找不到（很舊的 Windows）就不編那段
    $winmd = Join-Path $env:WINDIR "System32\WinMetadata"
    $facade = Join-Path (Split-Path $csc) "System.Runtime.dll"
    $winrt = @()
    if ((Test-Path "$winmd\Windows.ApplicationModel.winmd") -and (Test-Path "$winmd\Windows.Foundation.winmd") -and (Test-Path $facade)) {
        $winrt = @("/r:$winmd\Windows.ApplicationModel.winmd", "/r:$winmd\Windows.Foundation.winmd", "/r:$facade")
    } else { Write-Warning "WinMetadata not found: building without the Store startup switch (NO_WINRT)"; $winrt = @("/define:NO_WINRT") }
    $cscArgs = @(
        "/nologo", "/target:winexe", "/platform:anycpu", "/optimize+", "/codepage:65001", "/utf8output",
        "/out:$Exe",
        "/win32icon:$(Join-Path $Icons 'DeskPals.ico')",
        "/win32manifest:$(Join-Path $PSScriptRoot 'DeskPals.exe.manifest')",
        "/r:System.Windows.Forms.dll", "/r:System.Drawing.dll", "/r:System.Web.Extensions.dll"
    ) + $winrt + @(
        (Join-Path $Build "DeskPals.all.cs"), (Join-Path $PSScriptRoot "DeskPals.Main.cs"), (Join-Path $Build "AssemblyInfo.g.cs")
    )
    # 續命小隊的圖（pals\squad\…）、紙箱櫃（pals\shelf\…）＋lineups.txt、窩伴小世界（pals\woban\…）放進 exe 的資源（名字＝pals/squad/<id>/<1x|2x>/<動作>.png、pals/shelf/<1x|2x>/box.png）：exe、安裝程式、MSIX 都不用另外帶檔案
    $pals = Join-Path $desk "pals"
    foreach ($f in (Get-ChildItem -Path $pals -Recurse -File | Where-Object { $_.Extension -eq ".png" -or $_.Extension -eq ".txt" })) {
        $rel = "pals/" + $f.FullName.Substring($pals.Length + 1).Replace("\", "/")
        $cscArgs += "/resource:$($f.FullName),$rel"
    }
    & $csc @cscArgs
    if ($LASTEXITCODE -ne 0) { throw "csc failed" }
    Guard @($Exe, (Join-Path $Build "DeskPals.all.cs"))
    Sign-File $Exe
    Copy-Item $Exe (Join-Path $Out "DeskPals$Suffix.exe") -Force
    Write-Host ("built {0} ({1:N0} bytes)" -f $Exe, (Get-Item $Exe).Length)
}
if (($Steps -contains "installer" -or $Steps -contains "msix") -and -not (Test-Path $Exe)) { throw "DeskPals.exe not built yet (add -Steps exe)" }

# ---------- 安裝程式（Inno Setup）----------
if ($Steps -contains "installer") {
    $iscc = (Get-Command ISCC.exe -ErrorAction SilentlyContinue)
    $iscc = if ($iscc) { $iscc.Source } else { @("${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe", "$env:ProgramFiles\Inno Setup 6\ISCC.exe", "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1 }
    if (-not $iscc) { Skip "Inno Setup 6 (ISCC.exe) not found — install it (free) from https://jrsoftware.org/isdl.php or 'choco install innosetup'" }
    else {
        # 繁體中文介面：Inno 內建的（新版有）優先，沒有就用 repo 裡的那份
        $innoDir = Split-Path $iscc
        $isl = @("$innoDir\Languages\ChineseTraditional.isl", "$innoDir\Languages\Unofficial\ChineseTraditional.isl") | Where-Object { Test-Path $_ } | Select-Object -First 1
        if (-not $isl) { $isl = Join-Path $PSScriptRoot "ChineseTraditional.isl" }
        $isccArgs = @("/Q", "/DAppVersion=$Version", "/DRoot=$Root", "/DSrcDir=$Desk", "/DBuildDir=$Build", "/DIconDir=$Icons", "/DLangFile=$isl", "/O$Out")
        if ($Personal) { $isccArgs += "/DOutSuffix=$Suffix" }
        if ($Sign) {
            $isccArgs += "/DSIGN"
            $isccArgs += "/Sdpsign=`"$SignTool`" sign /fd sha256 /f `"$($env:DESKPALS_SIGN_PFX)`" /p `"$($env:DESKPALS_SIGN_PASSWORD)`" /tr http://timestamp.digicert.com /td sha256 `$f"
        }
        & $iscc @isccArgs (Join-Path $PSScriptRoot "DeskPals.iss")
        if ($LASTEXITCODE -ne 0) { throw "ISCC failed" }
        $setup = Join-Path $Out "DeskPals-Setup-$Version$Suffix.exe"
        Write-Host ("built {0} ({1:N0} bytes)" -f $setup, (Get-Item $setup).Length)
    }
}

# ---------- MSIX（Microsoft Store）----------
if ($Steps -contains "msix") {
    $makeappx = Find-SdkTool "makeappx.exe"
    $makepri = Find-SdkTool "makepri.exe"
    if (-not $makeappx -or -not $makepri) { Skip "Windows SDK (makeappx.exe / makepri.exe) not found" }
    else {
        $stage = Join-Path $Build "msix"
        if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
        New-Item -ItemType Directory -Force -Path $stage | Out-Null
        Copy-Item $Exe $stage
        Copy-Item (Join-Path $Desk "claude-hook.js"), (Join-Path $Desk "ci-watch.js") $stage
        Copy-Item (Join-Path $Icons "msix\Assets") (Join-Path $stage "Assets") -Recurse
        $name = if ($env:MSIX_IDENTITY_NAME) { $env:MSIX_IDENTITY_NAME } else { "DeskPals.Placeholder" }
        $publisher = if ($env:MSIX_PUBLISHER) { $env:MSIX_PUBLISHER } else { "CN=DeskPals-Placeholder" }
        $pubName = if ($env:MSIX_PUBLISHER_DISPLAY_NAME) { $env:MSIX_PUBLISHER_DISPLAY_NAME } else { "Desk Pals (placeholder)" }
        $esc = { param($s) [System.Security.SecurityElement]::Escape($s) }
        $manifest = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot "msix\AppxManifest.xml"), [System.Text.Encoding]::UTF8)
        $manifest = $manifest.Replace("__IDENTITY_NAME__", (& $esc $name)).Replace("__PUBLISHER__", (& $esc $publisher)).Replace("__PUBLISHER_DISPLAY_NAME__", (& $esc $pubName)).Replace("__VERSION__", $Version4)
        [System.IO.File]::WriteAllText((Join-Path $stage "AppxManifest.xml"), $manifest, (New-Object System.Text.UTF8Encoding($false)))
        # resources.pri：讓 Windows 依 DPI／主題挑對的磚圖（scale-100／200、targetsize、altform-unplated）
        $pricfg = Join-Path $Build "priconfig.xml"
        function Quiet([string]$what, [scriptblock]$cmd) { $log = & $cmd 2>&1; if ($LASTEXITCODE -ne 0) { $log | Out-Host; throw "$what failed" } }
        Quiet "makepri createconfig" { & $makepri createconfig /cf $pricfg /dq zh-TW /pv 10.0.0 /o }
        # 單一套件（不拆語言／縮放資源包）：拿掉 autoResourcePackage，所有圖都進同一個 resources.pri
        [xml]$cfg = Get-Content $pricfg -Raw
        $pk = $cfg.resources.SelectSingleNode("packaging")
        if ($pk) { [void]$cfg.resources.RemoveChild($pk) }
        $cfg.Save($pricfg)
        Quiet "makepri new" { & $makepri new /pr $stage /cf $pricfg /mn (Join-Path $stage "AppxManifest.xml") /of (Join-Path $stage "resources.pri") /o }
        $msix = Join-Path $Out "DeskPals-$Version$Suffix.msix"
        Quiet "makeappx pack" { & $makeappx pack /d $stage /p $msix /o }
        Guard @($msix)
        Write-Host ("built {0} ({1:N0} bytes, unsigned — Microsoft Store signs it)" -f $msix, (Get-Item $msix).Length)
        if ($name -eq "DeskPals.Placeholder") { Write-Warning "MSIX identity is a placeholder — set MSIX_IDENTITY_NAME / MSIX_PUBLISHER / MSIX_PUBLISHER_DISPLAY_NAME from Partner Center before uploading (see PUBLISHING.md)" }
    }
}
