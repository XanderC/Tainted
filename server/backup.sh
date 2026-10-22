#!/bin/sh
# Off-host backup of the Tainted World's characters: once a day (tainted-backup.timer) the accounts
# and the bans/mutes are packed into one archive on the NAS (mounted on the host at /storage), and
# archives older than KEEP_DAYS are deleted. The server's own daily copies stay on the host
# (/appdata/estate/tainted/backups, 7 days); these survive the host's disk.
SRC=/appdata/estate/tainted
DEST=/storage/Tainted/server-backups
KEEP_DAYS=30
set -e
mountpoint -q /storage || { echo "The NAS isn't mounted at /storage: no backup today." >&2; exit 1; }
mkdir -p "$DEST"
out="$DEST/tainted-$(date +%F).tar.gz"
files="accounts"
[ -f "$SRC/moderation.json" ] && files="$files moderation.json"
# shellcheck disable=SC2086
timeout 600 tar czf "$out.tmp" -C "$SRC" $files
mv "$out.tmp" "$out"
find "$DEST" -maxdepth 1 -name 'tainted-*.tar.gz' -mtime +"$KEEP_DAYS" -delete
echo "Backed up to $out ($(du -h "$out" | cut -f1))"
