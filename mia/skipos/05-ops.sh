#!/bin/sh
# Installs the SkipOS health check and nightly backup on Miami.
# Run on Miami, from the folder holding these files:  sudo sh 05-ops.sh
# Syntax-checked only; not yet run on Miami.
set -eu
[ "$(id -u)" = 0 ] || { echo "run with sudo" >&2; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
apt-get install -y cron curl >/dev/null

install -m 0755 -o root -g root "$HERE/skipos-health" /usr/local/sbin/skipos-health
install -m 0755 -o root -g root "$HERE/skipos-backup" /usr/local/sbin/skipos-backup
install -m 0644 -o root -g root "$HERE/skipos-backup.service" /etc/systemd/system/skipos-backup.service
install -m 0644 -o root -g root "$HERE/skipos-backup.timer" /etc/systemd/system/skipos-backup.timer
systemctl daemon-reload
systemctl enable --now skipos-backup.timer

# Root's crontab: one more line beside the Miami heartbeat.
LINE='*/5 * * * * /usr/local/sbin/skipos-health >/dev/null 2>&1'
( crontab -l 2>/dev/null | grep -v 'skipos-health' ; echo "$LINE" ) | crontab -

install -d -m 0755 /etc/skipos
echo "Installed. Two Healthchecks.io checks to create, then put each ping address (the whole"
echo "https://hc-ping.com/... line) in a root-only file:"
echo "  skipos-stack   period 5 minutes, grace 15 minutes  ->  /etc/skipos/hc-ping-url"
echo "  skipos-backup  period 1 day, grace 6 hours         ->  /etc/skipos/hc-backup-url"
echo "    sudo sh -c 'umask 077; cat > /etc/skipos/hc-ping-url'     (paste, Enter, Ctrl-D)"
echo "Try them now:  sudo skipos-health    and    sudo systemctl start skipos-backup"
