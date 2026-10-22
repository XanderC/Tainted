# Runs a dedicated Tainted server (no window): players on the Wi-Fi find it on the online screen.
# Uses the built game (builds\windows\Tainted.exe, see build_windows.ps1) if there is one, else Godot.
# The first time, Windows asks to let it through the firewall: allow it on private networks.
# Usage:  .\run_server.ps1 [-Name "Home"]
param([string]$Name = "$env:COMPUTERNAME")
$exe = Join-Path $PSScriptRoot "builds\windows\Tainted.exe"
if (Test-Path $exe) {
    & $exe --headless -- --server "--name=$Name"
} else {
    & "D:\godot_bin\Godot_v4.4.1-stable_win64_console.exe" --headless --path $PSScriptRoot -- --server "--name=$Name"
}
