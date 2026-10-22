# Builds the standalone Windows game: builds\windows\Tainted.exe (one file, the game packed inside).
# Needs the "Windows Desktop" preset in export_presets.cfg and Godot's 4.4.1 export templates.
# Usage:  .\build_windows.ps1          (add -Run to start it afterwards)
param([switch]$Run)
$godot = "D:\godot_bin\Godot_v4.4.1-stable_win64_console.exe"
$exe = Join-Path $PSScriptRoot "builds\windows\Tainted.exe"
New-Item -ItemType Directory -Force (Split-Path $exe) | Out-Null
Write-Host "Building Windows exe..."
& $godot --headless --path $PSScriptRoot --export-release "Windows Desktop" $exe
if (-not (Test-Path $exe)) {
    Write-Error "Build failed!"
    exit 1
}
Write-Host "Built $exe"
if ($Run) {
    Start-Process $exe
}
