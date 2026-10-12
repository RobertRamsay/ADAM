# Builds one ADAM release for Windows: ADAM_V<version>_LITE|PRO.zip and _Setup.exe (NSIS).
#   powershell -File tools\release_build.ps1 -Ed 0|1 -Out D:\POLYTRICITY\ADAM_builds [-FsUae <folder>]
#   -Ed      0 = ADAM Lite, 1 = ADAM Pro
#   -FsUae   folder holding the unpacked official FS-UAE Windows release (the folder that
#            contains FS-UAE\Windows\x86-64\fs-uae.exe). It is copied next to ADAM.exe, so
#            Build and play works with nothing else installed. Leave it out for no FS-UAE.
# For the build only: ADAM_PRO = Ed, ADAM_DEV_TOOLS false, display / exe name from
# ADAM_VERSION, FS-UAE added to the included files. Every source file it touches is
# restored byte for byte afterwards (see docs/RELEASE.md).
param([int]$Ed, [string]$Out, [string]$FsUae = "")
$repo = Split-Path -Parent $PSScriptRoot
$about = [IO.File]::ReadAllText("$repo\scripts\scr_about\scr_about.gml")
if ($about -notmatch '#macro ADAM_VERSION "([0-9.]+)"') { throw "ADAM_VERSION not found in scr_about" }
$ver = $Matches[1]
$ver4 = $ver; while (($ver4.Split(".")).Count -lt 4) { $ver4 += ".0" }
$tag = "LITE"; if ($Ed -eq 1) { $tag = "PRO" }
$name = "ADAM_V$ver4`_$tag"
$fsdir = "$repo\datafiles\FS-UAE"
if ($FsUae -ne "")
{
    if (-not (Test-Path "$FsUae\FS-UAE\Windows\x86-64\fs-uae.exe")) { throw "No FS-UAE\Windows\x86-64\fs-uae.exe in $FsUae" }
    if (Test-Path $fsdir) { throw "$fsdir is already there - remove it first" }
}
if (Get-Process | Where-Object { $_.ProcessName -match "^GameMaker" })
{
    "NOTE: GameMaker is open. It will see the project change while this builds and ask"
    "      'Reload or Save?' - click Reload (the files are back as they were by then)."
    "      Closing GameMaker first avoids the question."
}
$files = @("$repo\scripts\scr_licence\scr_licence.gml", "$repo\scripts\scr_adf\scr_adf.gml", "$repo\options\windows\options_windows.yy", "$repo\ADAM.yyp")
$orig = @{}
foreach ($f in $files) { $orig[$f] = [IO.File]::ReadAllBytes($f) }
try {
    $t = [IO.File]::ReadAllText($files[0]); [IO.File]::WriteAllText($files[0], ($t -replace "#macro ADAM_PRO [01]", "#macro ADAM_PRO $Ed"))
    $t = [IO.File]::ReadAllText($files[1]); [IO.File]::WriteAllText($files[1], $t.Replace("#macro ADAM_DEV_TOOLS true", "#macro ADAM_DEV_TOOLS false"))
    $t = [IO.File]::ReadAllText($files[2])
    $t = $t -replace '"option_windows_display_name":"[^"]*"', ('"option_windows_display_name":"' + $name + '"')
    $t = $t -replace '"option_windows_executable_name":"[^"]*"', ('"option_windows_executable_name":"' + $name + '.exe"')
    [IO.File]::WriteAllText($files[2], $t)
    if ($FsUae -ne "")
    {
        # FS-UAE goes in as Windows-only included files (CopyToMask 64), in datafiles\FS-UAE
        Copy-Item -Recurse "$FsUae\FS-UAE" $fsdir
        $t = [IO.File]::ReadAllText($files[3])
        $nl = "`n"; if ($t.Contains("`r`n")) { $nl = "`r`n" }
        $sb = New-Object System.Text.StringBuilder
        Get-ChildItem -Recurse -File $fsdir | ForEach-Object {
            $rel = $_.DirectoryName.Substring($repo.Length + 1).Replace("\", "/")
            [void]$sb.Append('    {"$GMIncludedFile":"","%Name":"' + $_.Name + '","CopyToMask":-1,"filePath":"' + $rel + '","name":"' + $_.Name + '","resourceType":"GMIncludedFile","resourceVersion":"2.0",},' + $nl)
        }
        $key = '"IncludedFiles":[' + $nl
        if (-not $t.Contains($key)) { throw "IncludedFiles not found in ADAM.yyp" }
        $t = $t.Replace($key, $key + $sb.ToString())
        [IO.File]::WriteAllText($files[3], $t)
        "--- FS-UAE added: " + (Get-ChildItem -Recurse -File $fsdir).Count + " files"
    }
    "--- release check ($tag, version $ver)"
    & powershell -File "$repo\tools\release_check.ps1"
    # Igor zips the parent of --of, so keep its temp, cache and the log out of there
    $tmp = Join-Path $env:TEMP "adam_rel_$tag"
    $work = Join-Path $env:TEMP "adam_relwork_$tag"
    $rt = (Get-ChildItem "C:\ProgramData\GameMakerStudio2-LTS2026\Cache\runtimes" -Directory | Sort-Object Name | Select-Object -Last 1).FullName
    $user = (Get-ChildItem "$env:APPDATA\GameMakerStudio2-LTS2026" -Directory | Where-Object { $_.Name -match "_\d+$" } | Select-Object -First 1).FullName
    New-Item -ItemType Directory $Out -Force | Out-Null
    foreach ($target in "PackageZip", "PackageNsis")
    {
        foreach ($dd in $tmp, $work) { if (Test-Path $dd) { Remove-Item -Recurse -Force $dd } }
        New-Item -ItemType Directory "$tmp\out" | Out-Null
        New-Item -ItemType Directory $work | Out-Null
        $file = "$Out\$name.zip"
        if ($target -eq "PackageNsis") { $file = "$Out\${name}_Setup.exe" }
        if (Test-Path $file) { Remove-Item -Force $file }
        $log = "$work\$name.$target.log"
        & "$rt\bin\igor\windows\x64\Igor.exe" -j=8 --project="$repo\ADAM.yyp" --user="$user" --runtimePath="$rt" --temp="$work\tmp" --cache="$work\cache" --of="$tmp\out" --tf="$file" --runtime=VM -- Windows $target > $log 2>&1
        Copy-Item $log "$env:TEMP\$name.$target.log" -Force
        "--- $target errors: " + (Select-String -Path $log -Pattern "(?i)\berror\b" | Measure-Object).Count
        if (-not (Test-Path $file)) { "NOT MADE: $file"; Get-Content $log -Tail 15; continue }
        if ($target -eq "PackageZip")
        {
            # Igor leaves an empty out/ folder in the zip
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $z = [IO.Compression.ZipFile]::Open($file, "Update")
            @($z.Entries | Where-Object { $_.FullName -eq "out/" }) | ForEach-Object { $_.Delete() }
            $z.Dispose()
        }
        "made: $file  " + [math]::Round((Get-Item $file).Length / 1MB, 1) + " MB"
    }
    foreach ($dd in $tmp, $work) { if (Test-Path $dd) { Remove-Item -Recurse -Force $dd } }
}
finally {
    foreach ($f in $files) { [IO.File]::WriteAllBytes($f, $orig[$f]) }
    if ($FsUae -ne "" -and (Test-Path $fsdir)) { Remove-Item -Recurse -Force $fsdir }
    $c = "$repo\cache"; if (Test-Path $c) { Remove-Item -Recurse -Force $c }
}
