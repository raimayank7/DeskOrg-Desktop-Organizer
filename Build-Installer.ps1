# Build-Installer.ps1
# One-click rebuild of the whole DeskOrg package after you edit any script:
#   1. (no exe any more: antivirus programs quarantine script-wrapped exes)
#   2. Sign every script (SHA256 + timestamp)
#   3. Compile DeskOrgSetup.exe from DeskOrg.iss (Inno Setup)
#   4. Sign DeskOrgSetup.exe
# Run it by double-clicking Build-Installer.bat (it runs with Bypass, so this
# file itself is not signed).
# Credits: Nivesh Sahayak | https://niveshsahayak.in

$ErrorActionPreference = 'Stop'
$AppFolder = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$Subject   = 'CN=DeskOrg Code Signing (Nivesh Sahayak)'
$Timestamp = 'http://timestamp.digicert.com'
# Marker that starts a signature block (written in two pieces so this file never matches itself).
$SigMarker = '# SIG # ' + 'Begin signature block'

function Fail($msg) { Write-Host "ERROR: $msg" -ForegroundColor Red; Read-Host "`nPress Enter to close"; exit 1 }

Write-Host "`n=== DeskOrg installer build ===`n" -ForegroundColor Cyan

# Locate the signing certificate
$cert = Get-ChildItem Cert:\CurrentUser\My |
    Where-Object { $_.Subject -eq $Subject -and $_.HasPrivateKey } |
    Sort-Object NotAfter -Descending | Select-Object -First 1
if (-not $cert) { Fail "DeskOrg signing certificate not found ($Subject)." }

# Locate the Inno Setup compiler
$iscc = @(
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $iscc) { Fail "Inno Setup compiler (ISCC.exe) not found. Install it with: winget install JRSoftware.InnoSetup" }

# Helper: sign one file, prefer a timestamp.
# Signing can drop the last character of a script unless a blank line follows it,
# so strip any old signature and end the file with a blank line first.
function Sign-File($path) {
    if ($path -like '*.ps1') {
        $text = [IO.File]::ReadAllText($path)
        $k = $text.IndexOf($SigMarker)
        if ($k -ge 0) { $text = $text.Substring(0, $k) }
        [IO.File]::WriteAllText($path, $text.TrimEnd() + "`r`n`r`n", (New-Object Text.UTF8Encoding($true)))
    }
    try   { Set-AuthenticodeSignature -FilePath $path -Certificate $cert -TimestampServer $Timestamp -HashAlgorithm SHA256 -ErrorAction Stop }
    catch { Set-AuthenticodeSignature -FilePath $path -Certificate $cert -HashAlgorithm SHA256 }
}

# Step 1: no DeskOrg.exe any more; the shortcuts run DeskOrgStart.bat.
Write-Host "Step 1/4  No exe to build (shortcuts run DeskOrgStart.bat)." -ForegroundColor White
if (-not (Test-Path -LiteralPath (Join-Path $AppFolder 'DeskOrgStart.bat'))) { Fail 'DeskOrgStart.bat is missing.' }

# Step 2: sign the scripts (top-level folder only; not this build script, not the Installer output)
Write-Host "Step 2/4  Signing scripts ..." -ForegroundColor White
$toSign = Get-ChildItem -Path (Join-Path $AppFolder '*') -Include *.ps1 -File |
    Where-Object { $_.Name -ne 'Build-Installer.ps1' }
foreach ($f in $toSign) {
    $r = Sign-File $f.FullName
    $c = if ($r.Status -eq 'Valid') { 'Green' } else { 'Yellow' }
    Write-Host ("          {0,-28} {1}" -f $f.Name, $r.Status) -ForegroundColor $c
}

# Step 3: compile the installer from a temporary copy of the .iss whose SrcDir is this
# folder (the .iss itself names the OneDrive path).
Write-Host "Step 3/4  Compiling DeskOrgSetup.exe ..." -ForegroundColor White
$issText = (Get-Content (Join-Path $AppFolder 'DeskOrg.iss') -Raw) -replace '(?m)^#define SrcDir\s+".*"', ('#define SrcDir        "' + $AppFolder + '"')
$issTmp = Join-Path $env:TEMP 'DeskOrg-build.iss'
Set-Content -LiteralPath $issTmp -Value $issText -Encoding UTF8
& $iscc $issTmp | Out-Null
if ($LASTEXITCODE -ne 0) { Fail "Inno Setup compile failed (exit $LASTEXITCODE)." }
$setup = Join-Path $AppFolder 'Installer\DeskOrgSetup.exe'
if (-not (Test-Path $setup)) { Fail "DeskOrgSetup.exe was not produced." }
Write-Host "          Compiled." -ForegroundColor Green

# Step 4: sign the installer
Write-Host "Step 4/4  Signing DeskOrgSetup.exe ..." -ForegroundColor White
$r = Sign-File $setup
Write-Host ("          DeskOrgSetup.exe {0}" -f $r.Status) -ForegroundColor $(if ($r.Status -eq 'Valid') { 'Green' } else { 'Yellow' })

Write-Host "`nDone. Installer: $setup`n" -ForegroundColor Cyan
Read-Host "Press Enter to close"
