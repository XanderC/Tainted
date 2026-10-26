# A full release: builds the game for PCs and phones and puts both on the NAS (Tainted > builds),
# where the server's "update your game" message sends players:
#   Tainted.exe  (Windows: run it)        Tainted.apk  (Android: open it on the phone to install)
#   version.txt  (the build's number, protocol, date and commit)
# It stamps a new build number (build.json) and keeps each platform's pack as the base later updates
# are made against (builds\base, publish_update.ps1): games installed from this release update
# themselves from then on. Only needed for what an update can't do (Updater: the engine, export
# settings, project settings, the autoloads); otherwise release with publish_update.ps1.
# Usage:  .\publish_builds.ps1 [-Dest Y:\Tainted\builds]
param([string]$Dest = "Y:\Tainted\builds")
# (Godot's log lines come on stderr: no ErrorActionPreference Stop; each step's result is checked)
$godot = "D:\godot_bin\Godot_v4.4.1-stable_win64_console.exe"
$apk = Join-Path $PSScriptRoot "builds\android\Tainted.apk"
$exe = Join-Path $PSScriptRoot "builds\windows\Tainted.exe"

$started = Get-Date
$build = [long](Get-Date -Format "yyyyMMddHHmm")
[IO.File]::WriteAllText((Join-Path $PSScriptRoot "build.json"), "{`n`t`"build`": $build`n}`n")
& (Join-Path $PSScriptRoot "build_windows.ps1") 2>&1 | Out-Null
# The APK holds the game as one pack (Updater: GAME_PACK), exported first (as a .pck: Godot won't
# export to another name)
$gamePack = Join-Path $PSScriptRoot "builds\android\game.pck"
New-Item -ItemType Directory -Force (Join-Path $PSScriptRoot "pack"), (Split-Path $gamePack) | Out-Null
Write-Host "Building Android APK..." -ForegroundColor Cyan
& $godot --headless --path $PSScriptRoot --export-pack "Android Data" $gamePack 2>&1 | Out-Null
if (Test-Path $gamePack) { Copy-Item $gamePack (Join-Path $PSScriptRoot "pack\game.mp4") -Force }
& $godot --headless --path $PSScriptRoot --export-debug "Android" $apk 2>&1 | Out-Null
foreach ($f in $exe, $gamePack, $apk) {
    if (-not (Test-Path $f) -or (Get-Item $f).LastWriteTime -lt $started) { Write-Host "Build failed: $f wasn't made" -ForegroundColor Red; exit 1 }
}
# The bases updates are made against: the exe's pack, and the game pack in the APK
$base = Join-Path $PSScriptRoot "builds\base"
New-Item -ItemType Directory -Force $base | Out-Null
& $godot --headless --path $PSScriptRoot --export-pack "Windows Desktop" (Join-Path $base "windows.pck") 2>&1 | Out-Null
Copy-Item $gamePack (Join-Path $base "android.pck") -Force
[IO.File]::WriteAllText((Join-Path $base "base.json"), "{`n`t`"build`": $build`n}`n")
# Updates made against the last release don't fit this one: none until publish_update.ps1
Remove-Item -Recurse -Force (Join-Path $PSScriptRoot "builds\update") -ErrorAction SilentlyContinue

New-Item -ItemType Directory -Force $Dest | Out-Null
Copy-Item $exe, $apk $Dest -Force
$protocol = (Select-String -Path (Join-Path $PSScriptRoot "scripts\net.gd") -Pattern 'const PROTOCOL := (\d+)').Matches[0].Groups[1].Value
$commit = (git -C $PSScriptRoot log -1 --format="%h %s")
Set-Content -Path (Join-Path $Dest "version.txt") -Encoding utf8 -Value @(
    "Tainted build $build, protocol $protocol",
    "Built $(Get-Date -Format 'yyyy-MM-dd HH:mm')",
    "Commit $commit")
Write-Host "Published build $build to $Dest (protocol $protocol). Deploy the server too: .\deploy_server.ps1" -ForegroundColor Green
