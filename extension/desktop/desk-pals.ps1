param([string]$PipeName = "desk-pals", [string]$Pet = "spidey", [string]$Lineup = "")
# Desk Pals (figure shelf) desktop overlay launcher: compiles DeskPals.cs (UTF-8) and runs it.
$ErrorActionPreference = "Stop"
try {
    $src = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot "DeskPals.cs"), [System.Text.Encoding]::UTF8)
    Add-Type -TypeDefinition $src -ReferencedAssemblies System.Windows.Forms, System.Drawing, System.Web.Extensions
    [DeskPals.App]::Run($PipeName, $Pet, $Lineup)   # Lineup: classic / teletubbies; empty = last used (startup shortcut)
} catch {
    Add-Content -Path (Join-Path $env:TEMP "desk-pals.log") -Value ("{0} ps1: {1}" -f (Get-Date -Format s), $_)
}
