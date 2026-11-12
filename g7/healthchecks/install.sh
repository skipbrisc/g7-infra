#!/bin/sh
# One-time install of the Healthchecks.io pings. Run as root from the folder holding these files:
#   sudo sh /tmp/g7-healthchecks/install.sh
set -eu
cd "$(dirname "$0")"

echo "== ping key"
if [ ! -s /root/.healthchecks-ping-key ]; then
  printf "Paste the Healthchecks.io ping key and press Enter (it will not be shown): "
  stty -echo 2>/dev/null || true
  read -r KEY
  stty echo 2>/dev/null || true
  echo
  KEY="$(printf '%s' "$KEY" | tr -d '[:space:]')"
  [ -n "$KEY" ] || { echo "No key entered. Nothing installed."; exit 1; }
  ( umask 077; printf '%s\n' "$KEY" > /root/.healthchecks-ping-key )
fi
chmod 600 /root/.healthchecks-ping-key

echo "== script, heartbeat timer"
install -o root -g root -m 0755 g7-hc-ping /usr/local/sbin/g7-hc-ping
install -o root -g root -m 0644 g7-heartbeat.service g7-heartbeat.timer /etc/systemd/system/

echo "== ping after a successful backup and a successful GitHub mirror"
install -d -m 0755 /etc/systemd/system/g7-backup.service.d
install -o root -g root -m 0644 ping-backup.conf /etc/systemd/system/g7-backup.service.d/healthchecks.conf
if systemctl cat taxglasses-mirror.service >/dev/null 2>&1; then
  install -d -m 0755 /etc/systemd/system/taxglasses-mirror.service.d
  install -o root -g root -m 0644 ping-mirror.conf /etc/systemd/system/taxglasses-mirror.service.d/healthchecks.conf
else
  echo "   (taxglasses-mirror.service not found; mirror ping skipped)"
fi
systemctl daemon-reload
systemctl enable --now g7-heartbeat.timer

echo "== test: each address must answer OK"
KEY="$(tr -d '[:space:]' < /root/.healthchecks-ping-key)"
for SLUG in g7-heartbeat g7-backup taxglasses-mirror; do
  CODE="$(curl -sS -m 10 -o /dev/null -w '%{http_code}' "https://hc-ping.com/$KEY/$SLUG/log" -d 'install test' || echo fail)"
  case "$CODE" in
    200) echo "   $SLUG: OK" ;;
    404) echo "   $SLUG: NOT FOUND - no check with this slug in the project, or the key is wrong" ;;
    *)   echo "   $SLUG: problem ($CODE)" ;;
  esac
done
echo
echo "Installed. The heartbeat pings every 5 minutes; backup and mirror ping after each success."
echo "If a line above says NOT FOUND, fix the slug on healthchecks.io, or delete"
echo "/root/.healthchecks-ping-key and run this again to re-enter the key."
