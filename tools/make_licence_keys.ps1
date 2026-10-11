# Makes ADAM Pro licence keys (ADAM-XXXX-XXXX-XXXX-XXXX) - same check as scr_licence.gml.
#
#   powershell -File tools\make_licence_keys.ps1 -Count 100 -Out D:\POLYTRICITY\ADAM_private\keys.txt
#
# Keys are signed with the private secret (tools\licence_secret.ps1 -New), one per line,
# appended to -Out (existing keys there are never repeated) - ready to upload to itch.io
# as external keys. -Dev makes keys from the public placeholder instead: they only work
# in dev builds (ADAM_DEV_TOOLS true), for testing.
param(
    [int]$Count = 10,
    [string]$Out = "",
    [string]$Private = "D:\POLYTRICITY\ADAM_private\scr_licence_secret.gml",
    [switch]$Dev
)
$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$placeholder = "ADAM-DEV-PLACEHOLDER"
$abc = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"   # LICENCE_ALPHABET

if ($Dev) { $secret = $placeholder }
else {
    if (-not (Test-Path $Private)) { throw "No private secret at $Private (make one with tools\licence_secret.ps1 -New)." }
    $m = [regex]::Match((Get-Content $Private -Raw), '#macro\s+LICENCE_SECRET\s+"([^"]+)"')
    if (-not $m.Success) { throw "No LICENCE_SECRET in $Private" }
    $secret = $m.Groups[1].Value
    if ($secret -eq $placeholder) { throw "That is the public placeholder - keys from it are worthless." }
}

$sha = [Security.Cryptography.SHA1]::Create()
function Sign([string]$serial) {
    $h = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($secret + $serial))
    -join (0..7 | ForEach-Object { $abc[$h[$_] % 32] })
}

$have = @{}
if ($Out -ne "" -and (Test-Path $Out)) { Get-Content $Out | ForEach-Object { $have[$_.Trim()] = $true } }
$rng = [Security.Cryptography.RandomNumberGenerator]::Create()
$keys = @()
while ($keys.Count -lt $Count) {
    $b = New-Object byte[] 8
    $rng.GetBytes($b)
    $serial = -join ($b | ForEach-Object { $abc[$_ % 32] })
    $k = $serial + (Sign $serial)
    $key = "ADAM-" + $k.Substring(0, 4) + "-" + $k.Substring(4, 4) + "-" + $k.Substring(8, 4) + "-" + $k.Substring(12, 4)
    if (-not $have.ContainsKey($key)) { $have[$key] = $true; $keys += $key }
}
if ($Out -ne "") { $keys | Add-Content $Out; Write-Host "$Count keys added to $Out" }
else { $keys }
