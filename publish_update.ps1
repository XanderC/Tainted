# Releases an update: players' games download it from the Tainted World by themselves (Updater) the
# next time they connect, and restart into it; no reinstalling.
#   1. stamps a new build number (build.json)
#   2. exports a patch for Windows and for Android: just the files changed since the last full release
#      (builds\base, made by publish_builds.ps1), into builds\update with update.json (build, base,
#      each patch's size and SHA-256)
#   3. deploys the server with it (deploy_server.ps1), which offers it to every game older than it
# An update can't change the engine, export settings, project settings or the autoloads: those need a
# full release (publish_builds.ps1), which players install once.
# Usage:  .\publish_update.ps1 [-NoDeploy]
param([switch]$NoDeploy)
$godot = "D:\godot_bin\Godot_v4.4.1-stable_win64_console.exe"
$base = Join-Path $PSScriptRoot "builds\base"
$update = Join-Path $PSScriptRoot "builds\update"
$baseJson = Join-Path $base "base.json"
if (-not (Test-Path $baseJson)) { Write-Host "No base release in builds\base: run .\publish_builds.ps1 first" -ForegroundColor Red; exit 1 }
$baseBuild = [long]((Get-Content $baseJson -Raw | ConvertFrom-Json).build)

$build = [long](Get-Date -Format "yyyyMMddHHmm")
[IO.File]::WriteAllText((Join-Path $PSScriptRoot "build.json"), "{`n`t`"build`": $build`n}`n")
Remove-Item -Recurse -Force $update -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $update | Out-Null

$files = [ordered]@{}
foreach ($p in @(@("windows", "Windows Desktop"), @("android", "Android Data"))) {
    $plat, $preset = $p
    $out = Join-Path $update "$plat.pck"
    Write-Host "Exporting the $plat patch (against build $baseBuild)..." -ForegroundColor Cyan
    & $godot --headless --path $PSScriptRoot --export-patch $preset $out --patches (Join-Path $base "$plat.pck") 2>&1 | Out-Null
    if (-not (Test-Path $out)) { Write-Host "Export failed: no $out" -ForegroundColor Red; exit 1 }
    $files[$plat] = [ordered]@{ file = "$plat.pck"; size = (Get-Item $out).Length; sha256 = (Get-FileHash $out -Algorithm SHA256).Hash.ToLower() }
    Write-Host ("  {0:N1} MB" -f ((Get-Item $out).Length / 1MB))
}
$meta = [ordered]@{ build = $build; base = $baseBuild; files = $files } | ConvertTo-Json -Depth 4
[IO.File]::WriteAllText((Join-Path $update "update.json"), $meta)
Write-Host "Update $build ready in builds\update" -ForegroundColor Green
if (-not $NoDeploy) { & (Join-Path $PSScriptRoot "deploy_server.ps1") }
