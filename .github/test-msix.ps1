# CI only (GitHub runner). Best-effort check that the MSIX really installs and runs:
# sign a copy with a throw-away self-signed certificate whose subject = the manifest's Publisher, trust it,
# Add-AppxPackage, start it through its execution alias (offscreen), check it answers on the pipe and wrote
# standalone.json into the real %LOCALAPPDATA%\DeskPals (= unvirtualizedResources works), then remove it.
# The real Store package is NOT signed by us — Microsoft signs it at submission.
param([Parameter(Mandatory = $true)][string]$Msix)
$ErrorActionPreference = "Stop"
$env:DESKPALS_OFFSCREEN = "1"; $env:DESKPALS_ISOLATED = "1"
function Check([bool]$ok, [string]$what) { if ($ok) { Write-Host "PASS  $what" } else { throw "FAIL  $what" } }
$work = Join-Path $env:RUNNER_TEMP "msix-test"
New-Item -ItemType Directory -Force $work | Out-Null
$signed = Join-Path $work "DeskPals-test.msix"
Copy-Item $Msix $signed

$makeappx = Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits\10\bin\10.*\x64\makeappx.exe" | Sort-Object FullName -Descending | Select-Object -First 1
$signtool = Join-Path $makeappx.DirectoryName "signtool.exe"
& $makeappx.FullName unpack /p $signed /d (Join-Path $work "x") /o | Out-Null
[xml]$m = Get-Content (Join-Path $work "x\AppxManifest.xml") -Raw
$publisher = $m.Package.Identity.Publisher
$name = $m.Package.Identity.Name
Write-Host "identity: $name / $publisher / $($m.Package.Identity.Version)"

$cert = New-SelfSignedCertificate -Type Custom -Subject $publisher -KeyUsage DigitalSignature -FriendlyName "Desk Pals CI test" `
    -CertStoreLocation "Cert:\CurrentUser\My" -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.3", "2.5.29.19={text}")
$pfx = Join-Path $work "test.pfx"
$pw = ConvertTo-SecureString -String "ci-test" -Force -AsPlainText
Export-PfxCertificate -Cert $cert -FilePath $pfx -Password $pw | Out-Null
Import-PfxCertificate -FilePath $pfx -CertStoreLocation "Cert:\LocalMachine\TrustedPeople" -Password $pw | Out-Null
& $signtool sign /fd sha256 /f $pfx /p ci-test $signed
Check ($LASTEXITCODE -eq 0) "test-signed the msix"

Add-AppxPackage -Path $signed
$pkg = Get-AppxPackage -Name $name
Check ($null -ne $pkg) "installed: $($pkg.PackageFullName)"
$alias = Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps\DeskPals.exe"
for ($i = 0; $i -lt 20 -and -not (Test-Path $alias); $i++) { Start-Sleep -Milliseconds 500 }
Check (Test-Path $alias) "execution alias $alias"
$pipe = "desk-pals-msix"
Start-Process $alias -ArgumentList "--pipe $pipe"
node .github/ping.js $pipe quit
Check ($LASTEXITCODE -eq 0) "packaged app answers on the pipe"
$marker = Join-Path $env:LOCALAPPDATA "DeskPals\standalone.json"
Check (Test-Path $marker) "packaged app wrote the real %LOCALAPPDATA%\DeskPals\standalone.json (unvirtualized)"
Get-Content $marker
Remove-AppxPackage -Package $pkg.PackageFullName
Remove-Item $marker -Force
Write-Host "msix test OK"
