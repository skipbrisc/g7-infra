#!/bin/sh
# Install (or update) the G7 drift check. Run as root from the folder holding these files:
#   sudo sh install.sh
# Installs the script and its units. It does NOT enable the timer: do that after a clean run
# (README.md, step 4). Changes nothing else on G7.
set -eu
[ "$(id -u)" = 0 ] || { echo "run as root" >&2; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
/usr/bin/python3 -IS -c 'import sys; src = open(sys.argv[1]).read(); compile(src, sys.argv[1], "exec")' "$HERE/g7-drift"
install -o root -g root -m 0700 "$HERE/g7-drift" /usr/local/sbin/g7-drift
install -o root -g root -m 0644 "$HERE/g7-drift.service" "$HERE/g7-drift.timer" /etc/systemd/system/
install -d -o root -g root -m 0700 /var/log/g7-drift
systemctl daemon-reload
echo "Installed /usr/local/sbin/g7-drift and g7-drift.service/.timer (timer not enabled)."
echo "Next: sudo g7-drift  (prints the report; changes nothing)"
