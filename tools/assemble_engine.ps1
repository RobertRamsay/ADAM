# Rebuilds datafiles/engine/engine.bin and boot.bin with vasm (Motorola syntax, 68k).
# Get vasm from http://sun.hasenbraten.de/vasm/ (vasmm68k_mot.exe) and put it on PATH or pass -Vasm.
param([string]$Vasm = "vasmm68k_mot.exe")
$dir = Join-Path $PSScriptRoot "..\datafiles\engine"
Push-Location $dir
& $Vasm -Fbin -pic -m68000 -no-opt -o engine.bin engine.s
if ($LASTEXITCODE -ne 0) { Pop-Location; exit 1 }
& $Vasm -Fbin -pic -m68000 -no-opt -o boot.bin boot.s
$e = $LASTEXITCODE
Pop-Location
exit $e
