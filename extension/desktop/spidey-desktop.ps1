param([string]$PipeName = "spidey-pet")
# Spidey desktop overlay launcher: compiles SpideyDesktop.cs (UTF-8) and runs it.
$ErrorActionPreference = "Stop"
try {
    $src = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot "SpideyDesktop.cs"), [System.Text.Encoding]::UTF8)
    Add-Type -TypeDefinition $src -ReferencedAssemblies System.Windows.Forms, System.Drawing, System.Web.Extensions
    [SpideyDesktop.App]::Run($PipeName)
} catch {
    Add-Content -Path (Join-Path $env:TEMP "spidey-desktop.log") -Value ("{0} ps1: {1}" -f (Get-Date -Format s), $_)
}
