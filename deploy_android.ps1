param(
    # ip:port of the phone. Leave empty to auto-discover it (wireless debugging changes the port often).
    [string]$Device = "",
    [string]$PhoneIp = "192.168.86.210"
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

if (-not $Device) {
    # Wireless debugging advertises its port over mDNS, but stale ports can linger in the list,
    # so try every advertised port for the phone's IP until one connects.
    # A freshly started adb daemon needs a few seconds to discover devices, so retry briefly.
    & $adb start-server | Out-Null
    # The phone doesn't always advertise itself, so first retry the last address that worked
    $lastFile = "$PSScriptRoot/builds/android/last_device.txt"
    if (Test-Path $lastFile) {
        $last = (Get-Content $lastFile -Raw).Trim()
        if ($last) {
            Write-Host "Trying last device $last..." -ForegroundColor Cyan
            if ((& $adb connect $last) -match "connected to") { $Device = $last }
        }
    }
    $pattern = "_adb-tls-connect\._tcp\s+($([regex]::Escape($PhoneIp)):\d+)"
    for ($try = 0; $try -lt 8 -and -not $Device; $try++) {
        if ($try -gt 0) { Start-Sleep -Seconds 2 }
        if ($try -eq 3) {
            # adb can hold on to stale ports and miss the new one: restart it and look again
            Write-Host "Restarting adb to look for the phone again..." -ForegroundColor Cyan
            & $adb kill-server | Out-Null
            & $adb start-server | Out-Null
            Start-Sleep -Seconds 4
        }
        $candidates = & $adb mdns services | Select-String $pattern | ForEach-Object { $_.Matches[0].Groups[1].Value }
        foreach ($c in $candidates) {
            Write-Host "Trying $c..." -ForegroundColor Cyan
            if ((& $adb connect $c) -match "connected to") { $Device = $c; break }
        }
    }
    if (-not $Device) {
        Write-Error "Phone $PhoneIp not found. Is Wireless debugging on? (or pass -Device ip:port)"
        exit 1
    }
} else {
    Write-Host "Connecting to $Device..." -ForegroundColor Cyan
    & $adb connect $Device
}

Write-Host "Installing $apk..." -ForegroundColor Cyan
& $adb -s $Device install -r $apk
if ($LASTEXITCODE -ne 0) {
    Write-Error "Install failed!"
    exit 1
}

Set-Content -Path "$PSScriptRoot/builds/android/last_device.txt" -Value $Device

Write-Host "Launching Tainted..." -ForegroundColor Cyan
& $adb -s $Device shell monkey -p org.godotengine.tainted -c android.intent.category.LAUNCHER 1

Write-Host "Done!" -ForegroundColor Green
