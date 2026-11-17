#!/bin/sh
# Install or update g7-apply. It never installs or updates itself. Run as root from this folder:
#   sudo sh install.sh
# Installing changes nothing else on G7 and runs nothing; only "sudo g7-apply" (and typing yes) does.
set -eu
[ "$(id -u)" = 0 ] || { echo "run as root" >&2; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
[ -f /usr/local/sbin/g7-drift ] || { echo "install g7-drift first (g7/drift): g7-apply uses its MAP reader" >&2; exit 1; }
/usr/bin/python3 -ISB -c 'import sys; compile(open(sys.argv[1]).read(), sys.argv[1], "exec")' "$HERE/g7-apply"
install -o root -g root -m 0700 "$HERE/g7-apply" /usr/local/sbin/g7-apply
install -d -o root -g root -m 0700 /var/backups/g7-apply /var/log/g7-apply
echo "Installed /usr/local/sbin/g7-apply. Next: sudo g7-apply --dry-run  (reads only)"
