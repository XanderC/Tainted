param(
    [string]$Device = "192.168.86.210:41129"
)

$adb = "D:\Android\Sdk\platform-tools\adb.exe"
$godot = "D:\godot_bin\Godot_v4.4.1-stable_win64_console.exe"
$apk = "$PSScriptRoot\builds\android\Tainted.apk"

Write-Host "Building Android APK..." -ForegroundColor Cyan
& $godot --headless --export-debug "Android" $apk
if ($LASTEXITCODE -ne 0) {
    Write-Error "Build failed!"
    exit 1
}

Write-Host "Connecting to $Device..." -ForegroundColor Cyan
& $adb connect $Device

Write-Host "Installing $apk..." -ForegroundColor Cyan
& $adb -s $Device install -r $apk

Write-Host "Launching Tainted..." -ForegroundColor Cyan
& $adb -s $Device shell monkey -p org.godotengine.tainted -c android.intent.category.LAUNCHER 1

Write-Host "Done!" -ForegroundColor Green
