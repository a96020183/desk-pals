param([string]$PipeName = "desk-pals", [string]$Pet = "spidey", [string]$Lineup = "")   #@fan
# <public> param([string]$PipeName = "desk-pals", [string]$Pet = "duoduo", [string]$Lineup = "")
# Desk Pals (figure shelf) desktop overlay launcher: compiles DeskPals.cs (UTF-8) and runs it.
$ErrorActionPreference = "Stop"
try {
    $src = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot "DeskPals.cs"), [System.Text.Encoding]::UTF8)
    # Extra partial files (DeskPals.*.cs, e.g. DeskPals.Pikmin.cs) are appended; their usings live inside the namespace
    foreach ($f in (Get-ChildItem -Path $PSScriptRoot -Filter "DeskPals.*.cs" | Sort-Object Name)) { $src += "`n" + [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8) }
    Add-Type -TypeDefinition $src -ReferencedAssemblies System.Windows.Forms, System.Drawing, System.Web.Extensions
    [DeskPals.SqAssets]::Root = (Join-Path $PSScriptRoot "pals")   # 續命小隊的圖（Add-Type 的組件沒有實體路徑）
    [DeskPals.App]::Run($PipeName, $Pet, $Lineup)   # Lineup: classic / teletubbies; empty = last used (startup shortcut)
} catch {
    Add-Content -Path (Join-Path $env:TEMP "desk-pals.log") -Value ("{0} ps1: {1}" -f (Get-Date -Format s), $_)
}
