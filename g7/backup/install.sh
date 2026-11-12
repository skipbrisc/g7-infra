#!/bin/sh
# One-time install of the G7 backup. Run as root from the folder holding these files:
#   sudo sh /tmp/g7-backup/install.sh
set -eu
cd "$(dirname "$0")"
UUID=14FE49A1FE497BCC

echo "== packages"
apt-get install -y restic sqlite3 >/dev/null

echo "== second disk at /mnt/data (existing files untouched)"
mkdir -p /mnt/data
if ! grep -q "$UUID" /etc/fstab; then
  cp /etc/fstab /etc/fstab.before-g7-backup
  echo "UUID=$UUID /mnt/data ntfs3 rw,noatime,uid=0,gid=0,umask=077,nofail 0 0" >> /etc/fstab
  systemctl daemon-reload
fi
mountpoint -q /mnt/data || mount /mnt/data
mkdir -p /mnt/data/G7-backups

echo "== repository password"
if [ ! -s /root/.restic-g7 ]; then
  umask 077; head -c 32 /dev/urandom | base64 > /root/.restic-g7
  NEWPW=1
fi
chmod 600 /root/.restic-g7
export RESTIC_REPOSITORY=/mnt/data/G7-backups/restic RESTIC_PASSWORD_FILE=/root/.restic-g7
[ -f "$RESTIC_REPOSITORY/config" ] || restic init

echo "== script and timer"
install -o root -g root -m 0700 g7-backup /usr/local/sbin/g7-backup
install -o root -g root -m 0644 g7-backup.service g7-backup.timer /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now g7-backup.timer

echo "== ntfy: let the jenkins token also post to topic g7"
( cd /opt/ntfy && docker compose exec -T ntfy ntfy access jenkins g7 write-only ) || echo "(ntfy access not changed)"
if [ ! -s /root/.ntfy-g7-token ]; then
  echo "   Put the jenkins ntfy token (tk_...) in /root/.ntfy-g7-token to get backup alerts."
fi

echo
echo "Installed. Next backup: $(systemctl list-timers g7-backup.timer --no-pager | awk 'NR==2{print $1, $2, $3}')"
if [ "${NEWPW:-0}" = 1 ]; then
  echo
  echo "SAVE THIS REPOSITORY PASSWORD IN VAULTWARDEN NOW (without it the backups cannot be read):"
  cat /root/.restic-g7
fi
