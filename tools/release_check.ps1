# Pre-release checks for a public (itch.io) build of ADAM. See docs/RELEASE.md.
# Usage:  powershell -File tools\release_check.ps1 [-Zip path\ADAM.zip]
# Exits 1 if anything would make the build unfit to publish.
param(
    [string]$Zip = ""
)
$root = Split-Path -Parent $PSScriptRoot
$fail = 0
function Bad($msg) { Write-Host "FAIL  $msg" -ForegroundColor Red; $script:fail = 1 }
function Ok($msg)  { Write-Host "ok    $msg" -ForegroundColor Green }

# version (single source: ADAM_VERSION in scripts/scr_about)
$about = Get-Content -Raw "$root\scripts\scr_about\scr_about.gml"
$ver = ""
if ($about -match '#macro\s+ADAM_VERSION\s+"([^"]+)"') { $ver = $Matches[1] }
if ($ver -eq "") { Bad "ADAM_VERSION not found in scr_about.gml" } else { Write-Host "ADAM version $ver" }

# ADAM_DEV_TOOLS must be false for public builds
$adf = Get-Content -Raw "$root\scripts\scr_adf\scr_adf.gml"
if ($adf -match '#macro\s+ADAM_DEV_TOOLS\s+(\w+)') {
    if ($Matches[1] -eq "false") { Ok "ADAM_DEV_TOOLS is false" }
    else { Bad "ADAM_DEV_TOOLS is $($Matches[1]) in scr_adf.gml - set it to false for the public build" }
} else { Bad "ADAM_DEV_TOOLS macro not found in scr_adf.gml" }

# which edition this build makes (ADAM_PRO in scripts/scr_licence)
$lic = Get-Content -Raw "$root\scripts\scr_licence\scr_licence.gml"
if ($lic -match '#macro\s+ADAM_PRO\s+(\d+)') {
    if ($Matches[1] -eq "1") { Write-Host "Edition: PRO  (ADAM_PRO 1) - name the zip ..._PRO" -ForegroundColor Yellow }
    elseif ($Matches[1] -eq "0") { Write-Host "Edition: LITE (ADAM_PRO 0) - name the zip ..._LITE" -ForegroundColor Yellow }
    else { Bad "ADAM_PRO is $($Matches[1]) in scr_licence.gml - it must be 0 (Lite) or 1 (Pro)" }
} else { Bad "ADAM_PRO macro not found in scr_licence.gml" }

# Windows options must carry the same version
$opt = Get-Content -Raw "$root\options\windows\options_windows.yy"
if ($opt -match '"option_windows_display_name":"([^"]*)"') {
    $dn = $Matches[1]
    if ($ver -ne "" -and $dn.Contains($ver)) { Ok "display name '$dn'" } else { Bad "option_windows_display_name '$dn' does not contain $ver" }
}
if ($opt -match '"option_windows_version":"([^"]*)"') {
    $wv = $Matches[1]
    if ($ver -ne "" -and $wv.StartsWith($ver)) { Ok "exe version $wv" } else { Bad "option_windows_version '$wv' does not start with $ver" }
}

# licence files that must ship next to ADAM.exe
$need = @("LICENCES.txt", "fonts\OFL.txt", "fonts\Poppins-OFL.txt")
foreach ($f in $need) {
    if (Test-Path "$root\datafiles\$f") { Ok "datafiles\$f" } else { Bad "datafiles\$f is missing" }
    if (-not (Select-String -Quiet -SimpleMatch -Path "$root\ADAM.yyp" -Pattern ('"name":"' + (Split-Path -Leaf $f) + '"'))) {
        Bad "$f is not registered in ADAM.yyp IncludedFiles"
    }
}

# optional: look inside the built zip
if ($Zip -ne "") {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $z = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path $Zip))
    $names = $z.Entries | ForEach-Object { $_.FullName.Replace('\', '/') }
    $z.Dispose()
    $want = @("ADAM.exe", "data.win", "LICENCES.txt", "fonts/OFL.txt", "fonts/Poppins-OFL.txt",
              "fonts/Poppins-Regular.ttf", "fonts/Poppins-Medium.ttf", "fonts/Poppins-Bold.ttf",
              "engine/engine.bin", "engine/boot.bin", "examples/gem_hunter.adam")
    foreach ($w in $want) {
        if ($names -contains $w) { Ok "zip has $w" } else { Bad "zip is missing $w" }
    }
}

if ($fail -ne 0) { Write-Host "NOT READY to release" -ForegroundColor Red; exit 1 }
Write-Host "Ready to release ADAM $ver" -ForegroundColor Green
exit 0
