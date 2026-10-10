# Boots an ADF in FS-UAE as a stock machine, the same way ADAM's "Build and play" does.
# Usage:  powershell -File tools\run_adf.ps1 -Adf path\game.adf [-Model A600|A1200] [-FsUae path\fs-uae.exe] [-Kick path\kick.rom]
param(
    [Parameter(Mandatory=$true)][string]$Adf,
    [string]$Model = "A600",
    [string]$FsUae = "",
    [string]$Kick = ""
)
if ($FsUae -eq "") {
    $cands = @(
        "$env:LOCALAPPDATA\ADAM\fs-uae\FS-UAE\Windows\x86-64\fs-uae.exe",
        "C:\Program Files\FS-UAE\Windows\x86-64\fs-uae.exe",
        "C:\Program Files (x86)\FS-UAE\Windows\x86-64\fs-uae.exe",
        "$env:USERPROFILE\Documents\FS-UAE\Windows\x86-64\fs-uae.exe"
    )
    foreach ($c in $cands) { if (Test-Path $c) { $FsUae = $c; break } }
}
if ($FsUae -eq "" -or -not (Test-Path $FsUae)) { Write-Error "fs-uae.exe not found - pass -FsUae"; exit 1 }
$chip = 1024
if ($Model -eq "A1200") { $chip = 2048 }
$fsargs = @("--amiga_model=$Model", "--chip_memory=$chip", "--slow_memory=0", "--fast_memory=0",
          "--floppy_drive_0=$Adf", "--floppy_drive_speed=0", "--fullscreen=0",
          "--automatic_input_grab=0", "--initial_input_grab=0")
if ($Kick -ne "") { $fsargs += "--kickstart_file=$Kick" }
Get-Process fs-uae -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Process -FilePath $FsUae -ArgumentList $fsargs -WorkingDirectory (Split-Path $FsUae)
