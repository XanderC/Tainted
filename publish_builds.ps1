# Builds the game for PCs and phones and puts both on the NAS (Tainted > builds), where the server's
# "update your game" message sends players:
#   Tainted.exe  (Windows: run it)        Tainted.apk  (Android: open it on the phone to install)
#   version.txt  (the build's protocol, date and commit)
# Usage:  .\publish_builds.ps1 [-Dest Y:\Tainted\builds]
param([string]$Dest = "Y:\Tainted\builds")
# (Godot's log lines come on stderr: no ErrorActionPreference Stop; each step's result is checked)
$godot = "D:\godot_bin\Godot_v4.4.1-stable_win64_console.exe"
$apk = Join-Path $PSScriptRoot "builds\android\Tainted.apk"
$exe = Join-Path $PSScriptRoot "builds\windows\Tainted.exe"

$started = Get-Date
& (Join-Path $PSScriptRoot "build_windows.ps1") 2>&1 | Out-Null
Write-Host "Building Android APK..." -ForegroundColor Cyan
& $godot --headless --path $PSScriptRoot --export-debug "Android" $apk 2>&1 | Out-Null
foreach ($f in $exe, $apk) {
    if (-not (Test-Path $f) -or (Get-Item $f).LastWriteTime -lt $started) { Write-Host "Build failed: $f wasn't made" -ForegroundColor Red; exit 1 }
}

New-Item -ItemType Directory -Force $Dest | Out-Null
Copy-Item $exe, $apk $Dest -Force
$protocol = (Select-String -Path (Join-Path $PSScriptRoot "scripts\net.gd") -Pattern 'const PROTOCOL := (\d+)').Matches[0].Groups[1].Value
$commit = (git -C $PSScriptRoot log -1 --format="%h %s")
Set-Content -Path (Join-Path $Dest "version.txt") -Encoding utf8 -Value @(
    "Tainted, protocol $protocol",
    "Built $(Get-Date -Format 'yyyy-MM-dd HH:mm')",
    "Commit $commit")
Write-Host "Published to $Dest (protocol $protocol)" -ForegroundColor Green
