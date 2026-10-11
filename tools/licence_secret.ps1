# ADAM Pro licence secret - kept OUTSIDE the (public) repo.
#
#   powershell -File tools\licence_secret.ps1 -New       makes the private secret file (once, ever)
#   powershell -File tools\licence_secret.ps1 -Install   copies it into the project, for a release build
#   powershell -File tools\licence_secret.ps1 -Remove    puts the public placeholder back (do this before committing)
#
# Keys sold on itch.io are made from this secret (tools\make_licence_keys.ps1).
# Back the private file up: if it is lost, keys already sold can't be checked by new builds.
param(
    [switch]$New,
    [switch]$Install,
    [switch]$Remove,
    [string]$Private = "D:\POLYTRICITY\ADAM_private\scr_licence_secret.gml"
)
$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$inProject = Join-Path $repo "scripts\scr_licence_secret\scr_licence_secret.gml"
$placeholderText = @'
/// ADAM Pro licence secret - PUBLIC PLACEHOLDER, never commit the real one.
///
/// The repository is public, so this file only holds a placeholder. Keys made
/// with it work in dev builds (ADAM_DEV_TOOLS true) and are refused by public
/// builds. For a release, tools/licence_secret.ps1 -Install copies the real
/// secret over this file from outside the repo; -Remove puts this back.
#macro LICENCE_SECRET "ADAM-DEV-PLACEHOLDER"

'@

# git hook (local to this PC): refuses a commit while the real secret is in the project
function Install-Guard {
    $hook = Join-Path $repo ".git\hooks\pre-commit"
    $mark = "ADAM licence secret guard"
    if ((Test-Path $hook) -and ((Get-Content $hook -Raw) -match $mark)) { return }
    if (Test-Path $hook) { Write-Host "Note: $hook already exists - add the secret check to it by hand."; return }
    $sh = "#!/bin/sh`n# $mark (tools/licence_secret.ps1)`n" +
          "f=scripts/scr_licence_secret/scr_licence_secret.gml`n" +
          "if git cat-file -e :`$f 2>/dev/null && ! git show :`$f | grep -q 'ADAM-DEV-PLACEHOLDER'; then`n" +
          "  echo 'The real ADAM Pro licence secret is staged - run: powershell -File tools\licence_secret.ps1 -Remove'`n" +
          "  exit 1`nfi`n"
    [IO.File]::WriteAllText($hook, $sh.Replace("`r", ""))
}

if ($New) {
    if (Test-Path $Private) { throw "$Private already exists - keep it, keys depend on it." }
    New-Item -ItemType Directory -Force (Split-Path -Parent $Private) | Out-Null
    $abc = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789abcdefghijkmnpqrstuvwxyz"
    $bytes = New-Object byte[] 40
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $secret = -join ($bytes | ForEach-Object { $abc[$_ % $abc.Length] })
    $text = "/// ADAM Pro licence secret - PRIVATE. Never commit this; back it up.`r`n" +
            "/// tools\licence_secret.ps1 -Install copies it into the project for a release build.`r`n" +
            "#macro LICENCE_SECRET `"$secret`"`r`n"
    [IO.File]::WriteAllText($Private, $text)
    Write-Host "Made $Private - back this file up somewhere safe."
}
elseif ($Install) {
    if (-not (Test-Path $Private)) { throw "No private secret at $Private (make one with -New)." }
    Install-Guard
    Copy-Item $Private $inProject -Force
    Write-Host "Real secret installed. Build the release now, then run -Remove before any commit."
}
elseif ($Remove) {
    [IO.File]::WriteAllText($inProject, $placeholderText.Replace("`r", ""))
    Install-Guard
    Write-Host "Public placeholder back in the project."
}
else {
    Write-Host "Use -New, -Install or -Remove (see the top of this script)."
}
