#!/bin/sh
# Nightly Vaultwarden backup: consistent SQLite copy + keys/attachments. Keeps 14 days.
set -eu
D=/srv/vaultwarden; B=$D/backups; T=$(date +%F-%H%M); tmp=$(mktemp -d)
trap "rm -rf $tmp" EXIT
sqlite3 "$D/data/db.sqlite3" ".backup '$tmp/db.sqlite3'"
mkdir -p "$tmp/data"; cp -a "$D/data/." "$tmp/data/"
rm -f "$tmp/data/db.sqlite3" "$tmp/data/db.sqlite3-wal" "$tmp/data/db.sqlite3-shm"; rm -rf "$tmp/data/icon_cache"
mv "$tmp/db.sqlite3" "$tmp/data/db.sqlite3"
tar czf "$B/vault-$T.tar.gz" -C "$tmp" data
chown root:buttmud "$B/vault-$T.tar.gz"; chmod 640 "$B/vault-$T.tar.gz"
ln -sfn "vault-$T.tar.gz" "$B/latest.tar.gz"
find "$B" -name "vault-*.tar.gz" -mtime +14 -delete
echo "backup: $B/vault-$T.tar.gz"
