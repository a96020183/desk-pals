# CI only (GitHub runner — never run this on your own PC: it installs, creates shortcuts and uninstalls).
# Checks the Inno Setup installer end to end, including taking over from the VS Code extension's PowerShell copy:
#   1. fake the extension: runtime copy in %LOCALAPPDATA%\DeskPals, Startup shortcut → powershell desk-pals.ps1, running
#   2. silent install (autostart + desktop icon) → extension copy quit, Startup shortcut now → DeskPals.exe, marker, registry
#   3. start the installed exe (offscreen) → answers on the default pipe
#   4. silent install again (upgrade in place) while it runs → succeeds, running copy was closed
#   5. silent uninstall → program, shortcuts, marker, registry gone; user data kept
param([Parameter(Mandatory = $true)][string]$Setup)
$ErrorActionPreference = "Stop"
$env:DESKPALS_OFFSCREEN = "1"; $env:DESKPALS_ISOLATED = "1"
$dir = Join-Path $env:RUNNER_TEMP "dp-install"
$data = Join-Path $env:LOCALAPPDATA "DeskPals"
$startup = [Environment]::GetFolderPath("Startup")
$programs = [Environment]::GetFolderPath("Programs")
$lnkName = "公仔櫃 Desk Pals.lnk"
$pipe = "desk-pals-" + ($env:USERNAME -replace '[^A-Za-z0-9_.-]', '_')
$sh = New-Object -ComObject WScript.Shell
# WScript.Shell can't save/load a shortcut whose path has characters outside the ANSI code page (the runner is cp1252):
# go through an ASCII temp name
function New-Lnk([string]$path, [string]$target, [string]$arguments) {
    $tmp = Join-Path $env:RUNNER_TEMP "tmp-shortcut.lnk"
    $l = $sh.CreateShortcut($tmp); $l.TargetPath = $target; $l.Arguments = $arguments; $l.Save()
    Move-Item -LiteralPath $tmp $path -Force
}
function Lnk-Target([string]$path) {
    $tmp = Join-Path $env:RUNNER_TEMP "tmp-read.lnk"
    Copy-Item -LiteralPath $path $tmp -Force
    return $sh.CreateShortcut($tmp).TargetPath
}
function Check([bool]$ok, [string]$what) { if ($ok) { Write-Host "PASS  $what" } else { throw "FAIL  $what" } }
function Install([string]$log) {
    $p = Start-Process $Setup -ArgumentList "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /TASKS=autostart,desktopicon /DIR=`"$dir`" /LOG=`"$log`"" -PassThru -Wait
    if ($p.ExitCode -ne 0) { Get-Content $log | Select-Object -Last 40; throw "installer exit $($p.ExitCode)" }
}

# 1. the extension's copy
New-Item -ItemType Directory -Force $data | Out-Null
Copy-Item extension\desktop\DeskPals*.cs, extension\desktop\desk-pals.ps1 $data
New-Lnk (Join-Path $startup $lnkName) "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" "-NoProfile -WindowStyle Hidden -File `"$data\desk-pals.ps1`" -PipeName $pipe"
$ps = Start-Process powershell.exe -ArgumentList "-NoProfile -File `"$data\desk-pals.ps1`" -PipeName $pipe -Pet po" -PassThru
node .github/ping.js $pipe
Check ($LASTEXITCODE -eq 0) "extension's PowerShell copy is running on $pipe"

# 2. install
Install (Join-Path $env:RUNNER_TEMP "install1.log")
Start-Sleep -Seconds 2
Check $ps.HasExited "installer closed the extension's running copy (--quit)"
$exe = Join-Path $dir "DeskPals.exe"
Check (Test-Path $exe) "DeskPals.exe installed"
Check ((Test-Path "$dir\claude-hook.js") -and (Test-Path "$data\claude-hook.js")) "claude-hook.js in the app folder and in %LOCALAPPDATA%\DeskPals"
$t = Lnk-Target (Join-Path $startup $lnkName)
Check ($t -eq $exe) "Startup shortcut now points at DeskPals.exe ($t)"
Check (Test-Path (Join-Path $programs "公仔櫃 Desk Pals.lnk")) "Start menu shortcut"
Check (Test-Path (Join-Path ([Environment]::GetFolderPath("Desktop")) "公仔櫃 Desk Pals.lnk")) "desktop shortcut (task ticked)"
$marker = Get-Content "$data\standalone.json" -Raw -Encoding UTF8 | ConvertFrom-Json
Check (($marker.kind -eq "installer") -and ($marker.exe -eq $exe)) "standalone.json → $($marker.exe)"
$reg = Get-ItemProperty "HKCU:\Software\DeskPals"
Check ($reg.InstallDir -eq $dir) "HKCU\Software\DeskPals InstallDir"
$uninst = Get-ChildItem "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall" | Where-Object { $_.PSChildName -like "*63CF3CC4*" }
Check ($null -ne $uninst) "per-user uninstall entry (Apps & features)"
$vi = (Get-Item $exe).VersionInfo
Write-Host "exe version: $($vi.ProductVersion) / $($vi.FileVersion) — $($vi.ProductName)"

# 3. run the installed exe (no args = autostart path, default pipe)
$app = Start-Process $exe -PassThru
node .github/ping.js $pipe
Check ($LASTEXITCODE -eq 0) "installed exe answers on $pipe"
$second = Start-Process $exe -PassThru -Wait
Check (($second.ExitCode -eq 0) -and -not $app.HasExited) "second launch just says hi and exits (single instance)"

# 4. upgrade in place while running
Install (Join-Path $env:RUNNER_TEMP "install2.log")
Start-Sleep -Seconds 2
Check $app.HasExited "upgrade closed the running copy first"
Check (Test-Path $exe) "upgrade in place kept DeskPals.exe"

# 5. uninstall
$app = Start-Process $exe -PassThru
node .github/ping.js $pipe
$un = Get-ChildItem $dir -Filter "unins*.exe" | Select-Object -First 1
Start-Process $un.FullName -ArgumentList "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART" -Wait
for ($i = 0; $i -lt 60 -and (Test-Path $exe); $i++) { Start-Sleep -Seconds 1 }   # the uninstaller re-launches itself from %TEMP%
Start-Sleep -Seconds 2
Check $app.HasExited "uninstall closed the running app"
Check (-not (Test-Path $exe)) "program removed"
Check (-not (Test-Path (Join-Path $startup $lnkName))) "Startup shortcut removed"
Check (-not (Test-Path (Join-Path $programs "公仔櫃 Desk Pals.lnk"))) "Start menu shortcut removed"
Check (-not (Test-Path "$data\standalone.json")) "standalone.json removed (extension goes back to its own copy)"
Check (-not (Test-Path "HKCU:\Software\DeskPals")) "registry key removed"
Check ((Test-Path "$data\claude-hook.js") -and ((Get-ChildItem $data -Filter *.txt).Count -gt 0)) "user data kept (silent uninstall = keep)"
Write-Host "installer test OK"
