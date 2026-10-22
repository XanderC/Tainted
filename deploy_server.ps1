# Deploys the Tainted World server to the main host (192.168.86.18), in Docker beside the estate:
#   1. exports the game as a pack (builds\server\tainted.pck) with the "Linux Server" export preset
#      (added to export_presets.cfg the first time; that file is not in git)
#   2. copies it with the server\ files (Dockerfile, compose file, start and admin scripts, the NAS
#      backup and its timer) to /opt/projects/Tainted/server
#   3. rebuilds and restarts the container there (the old one warns its players and saves first),
#      waits until it is healthy, and installs the daily backup timer
# Clients and server must be the same build: redeploy whenever the game changes.
# Usage:  .\deploy_server.ps1 [-HostName root@192.168.86.18]
param([string]$HostName = "root@192.168.86.18")
$ErrorActionPreference = "Stop"
$godot = "D:\godot_bin\Godot_v4.4.1-stable_win64_console.exe"
$key = Join-Path $env:USERPROFILE ".ssh\id_ed25519_estate"
$ssh = @("-i", $key, "-o", "BatchMode=yes", "-o", "ConnectTimeout=10")
$remote = "/opt/projects/Tainted/server"
$pck = Join-Path $PSScriptRoot "builds\server\tainted.pck"
$presets = Join-Path $PSScriptRoot "export_presets.cfg"

# 1. The export preset, then the pack
if (-not (Select-String -Path $presets -Pattern 'name="Linux Server"' -Quiet)) {
    $n = ([regex]::Matches((Get-Content $presets -Raw), '(?m)^\[preset\.(\d+)\]$') | ForEach-Object { [int]$_.Groups[1].Value } | Measure-Object -Maximum).Maximum + 1
    Write-Host "Adding the Linux Server export preset (preset.$n)..." -ForegroundColor Cyan
    $block = @"

[preset.$n]

name="Linux Server"
platform="Linux"
runnable=false
advanced_options=false
dedicated_server=false
custom_features=""
export_filter="all_resources"
include_filter="*.json"
exclude_filter="scratch/*, tools/*, builds/*"
export_path="./builds/server/tainted.pck"
encryption_include_filters=""
encryption_exclude_filters=""
encrypt_pck=false
encrypt_directory=false

[preset.$n.options]

custom_template/debug=""
custom_template/release=""
debug/export_console_wrapper=0
binary_format/embed_pck=false
texture_format/s3tc_bptc=true
texture_format/etc2_astc=false
binary_format/architecture="x86_64"
"@
    [IO.File]::AppendAllText($presets, $block.Replace("`r`n", "`n"))
}
New-Item -ItemType Directory -Force (Split-Path $pck) | Out-Null
Remove-Item $pck -ErrorAction SilentlyContinue
Write-Host "Exporting the server pack..." -ForegroundColor Cyan
& $godot --headless --path $PSScriptRoot --export-pack "Linux Server" $pck 2>&1 | Out-Null
if (-not (Test-Path $pck)) { Write-Error "Export failed: no $pck" }
Write-Host ("Pack: {0:N0} MB" -f ((Get-Item $pck).Length / 1MB))

# 2. Copy it over
Write-Host "Copying to $HostName`:$remote..." -ForegroundColor Cyan
& ssh @ssh $HostName "mkdir -p $remote"
$files = "Dockerfile", "docker-compose.yml", "entrypoint.sh", "tainted-admin", "backup.sh", "tainted-backup.service", "tainted-backup.timer" |
    ForEach-Object { Join-Path $PSScriptRoot "server\$_" }
& scp @ssh -q @files $pck "$HostName`:$remote/"
if ($LASTEXITCODE -ne 0) { Write-Error "Copy failed" }

# 3. Rebuild, restart, wait for healthy
Write-Host "Building and starting the container..." -ForegroundColor Cyan
& ssh @ssh $HostName @"
set -e
mkdir -p /appdata/estate/tainted && chown 1000:1000 /appdata/estate/tainted  # the characters (uid of the container's user)
cd $remote
docker compose up -d --build 2>&1 | tail -3
for i in `$(seq 1 30); do
  s=`$(docker inspect -f '{{.State.Health.Status}}' tainted 2>/dev/null || echo missing)
  [ "`$s" = healthy ] && break
  sleep 2
done
echo "health: `$s"
docker logs --tail 5 tainted 2>&1
# The daily backup to the NAS (backup.sh), as a systemd timer on the host
sed -i 's/\r`$//' backup.sh tainted-backup.service tainted-backup.timer
cp tainted-backup.service tainted-backup.timer /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now tainted-backup.timer >/dev/null 2>&1
echo "backup timer: `$(systemctl is-active tainted-backup.timer), next `$(systemctl show tainted-backup.timer -p NextElapseUSecRealtime --value)"
"@
if ($LASTEXITCODE -ne 0) { Write-Error "Deploy failed" }
Write-Host "Done: games on the home network join ws://192.168.86.18:24601" -ForegroundColor Green
