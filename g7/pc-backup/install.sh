#!/bin/sh
# Install the G7 side of the PC's backup (g7/pc-backup/README.md). Run as root from the folder
# holding these files:   sudo sh /tmp/g7-pc-backup/install.sh
# Safe to re-run: existing passwords and repositories are kept. Prints the two secrets the PC
# needs the first time only; put them in Vaultwarden.
set -eu
cd "$(dirname "$0")"
REPO=/mnt/data/PC-backups/pc/restic
PW=/root/.restic-pc
HT=/etc/restic-rest-server/users.htpasswd
OFFSITE=rest:http://10.78.0.1:8000/g7/pc/
say() { printf '\n== %s\n' "$*"; }
die() { echo "install.sh: $*" >&2; exit 1; }
[ "$(id -u)" = 0 ] || die "run as root"

say "packages"
apt-get install -y restic restic-rest-server apache2-utils python3 >/dev/null

say "backup disk"
mountpoint -q /mnt/data || mount /mnt/data || die "/mnt/data is not mounted"
mkdir -p /mnt/data/PC-backups/pc

say "repository password (G7 keeps it to prune and copy; the PC needs it to back up)"
NEWPW=0
if [ ! -s "$PW" ]; then
  (umask 077; head -c 32 /dev/urandom | base64 > "$PW")
  NEWPW=1
fi
chmod 600 "$PW"
if [ -f "$REPO/config" ]; then
  echo "   repository exists: $REPO"
else
  restic init -r "$REPO" --password-file "$PW" --cache-dir /var/cache/restic-pc
fi

say "REST login for the PC (user pc)"
NEWREST=""
grep -q '^pc:' "$HT" 2>/dev/null || {
  NEWREST=$(head -c 24 /dev/urandom | base64 | tr -d '/+=' | cut -c1-28)
  htpasswd -B -b "$HT" pc "$NEWREST" >/dev/null 2>&1
}
grep -q '^pc:' "$HT" || die "could not add the user pc to $HT"
chown root:restic-rest-server "$HT" 2>/dev/null || true
chmod 640 "$HT"

say "REST server on 192.168.0.6:8000 (append-only, sandboxed)"
install -o root -g root -m 0644 restic-rest-server.default /etc/default/restic-rest-server
install -d -o root -g root -m 0755 /etc/systemd/system/restic-rest-server.service.d
install -o root -g root -m 0644 restic-rest-server-g7.conf /etc/systemd/system/restic-rest-server.service.d/g7.conf
systemctl daemon-reload
systemctl enable restic-rest-server >/dev/null 2>&1
systemctl restart restic-rest-server
sleep 2
systemctl is-active --quiet restic-rest-server || die "restic-rest-server did not start (journalctl -u restic-rest-server -n 30)"
CODE=$(curl -s -o /dev/null -w '%{http_code}' http://192.168.0.6:8000/pc/restic/config || true)
[ "$CODE" = 401 ] && echo "   answers, and wants a login (401): ok" || echo "   WARNING: expected 401 from the server, got $CODE"

say "the daily job: prune, check, copy to Miami"
install -o root -g root -m 0700 g7-pc-backup-offsite /usr/local/sbin/g7-pc-backup-offsite
install -o root -g root -m 0644 g7-pc-backup-offsite.service g7-pc-backup-offsite.timer /etc/systemd/system/
install -d -o root -g root -m 0755 /etc/systemd/system/g7-pc-backup-offsite.service.d
install -o root -g root -m 0644 healthchecks.conf /etc/systemd/system/g7-pc-backup-offsite.service.d/healthchecks.conf
systemctl daemon-reload
systemctl enable --now g7-pc-backup-offsite.timer >/dev/null 2>&1

say "Miami copy repository (same password, same chunking, so copies stay small)"
if [ -r /root/.restic-mia-rest ]; then
  set -a
  # shellcheck source=/dev/null
  . /root/.restic-mia-rest
  set +a
  if restic -r "$OFFSITE" --password-file "$PW" cat config >/dev/null 2>&1; then
    echo "   exists"
  else
    restic -r "$OFFSITE" init --password-file "$PW" --from-repo "$REPO" --from-password-file "$PW" --copy-chunker-params \
      || echo "   WARNING: could not create $OFFSITE (mia/README.md: create it on Miami by hand)"
  fi
else
  echo "   WARNING: no /root/.restic-mia-rest; the off-site copy will fail until it exists"
fi

echo
echo "Installed. Next run: $(systemctl list-timers g7-pc-backup-offsite.timer --no-pager | awk 'NR==2{print $1, $2, $3}')"
if [ "$NEWPW" = 1 ] || [ -n "$NEWREST" ]; then
  echo
  echo "SAVE THESE IN VAULTWARDEN NOW (the PC's install-pc-backup.ps1 asks for both):"
  [ "$NEWPW" = 1 ] && echo "  repository password:  $(cat "$PW")"
  [ -n "$NEWREST" ] && echo "  REST login:           user pc, password $NEWREST"
fi
cat <<'TXT'

Left to do:
  1. Healthchecks.io: create a check with slug  pc-backup-offsite  (period 1 day, grace 6 hours).
  2. On the PC (admin PowerShell, from D:\g7-infra):  pc\backup\install-pc-backup.ps1
TXT
