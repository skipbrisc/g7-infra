#!/bin/sh
# Gives the SkipOS backup an encrypted home that G7 can copy off this server.
# Run on Miami, from the folder holding these files:  sudo sh 08-offsite.sh
# Then on G7: g7/skipos-backup/install.sh (g7/skipos-backup/README.md).
#
# What it sets up, all on Miami:
#   - a restic repository at rest:http://10.78.0.1:8000/skipos/restic, behind the SAME
#     append-only REST server G7 already uses for its own backups, under a new login "skipos"
#     that reaches /skipos/ and nothing else. Append-only means a broken or hostile script can
#     add snapshots but never delete or rewrite one.
#   - skipos-backup now adds each night's folder to that repository.
# It prints two secrets ONCE. G7's install asks for both, and both belong in Vaultwarden.
# The firewall needs no change: G7 (10.78.0.2) may already reach port 8000.
# Safe to run again: existing secrets and the repository are kept.
# Syntax-checked only; not yet run on Miami.
set -eu
[ "$(id -u)" = 0 ] || { echo "run with sudo" >&2; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
HT=/etc/restic-rest-server/users.htpasswd
REPO=rest:http://10.78.0.1:8000/skipos/restic
PW=/etc/skipos/restic-repo-pass
ENVF=/etc/skipos/restic-rest-env

[ -e "$HT" ] || { echo "$HT is missing: the REST server is not set up as mia/README.md describes" >&2; exit 1; }
apt-get install -y restic apache2-utils >/dev/null
install -d -m 0755 /etc/skipos

NEWPW=0
if [ ! -s "$PW" ]; then
  (umask 077; head -c 32 /dev/urandom | base64 > "$PW")
  NEWPW=1
fi
chmod 600 "$PW"

NEWREST=""
if ! grep -q '^skipos:' "$HT"; then
  NEWREST=$(head -c 24 /dev/urandom | base64 | tr -d '/+=' | cut -c1-28)
  htpasswd -B -b "$HT" skipos "$NEWREST" >/dev/null 2>&1
  grep -q '^skipos:' "$HT" || { echo "could not add the user skipos to $HT" >&2; exit 1; }
  (umask 077; printf 'RESTIC_REST_USERNAME=skipos\nRESTIC_REST_PASSWORD=%s\n' "$NEWREST" > "$ENVF")
fi
[ -s "$ENVF" ] || { echo "$ENVF is missing but the login exists; remove the skipos line from $HT and run this again" >&2; exit 1; }
chmod 600 "$ENVF"
chown root:restic-rest-server "$HT"; chmod 640 "$HT"

# The server runs as restic-rest-server and cannot create a folder in root's /srv/backups.
install -d -m 0700 -o restic-rest-server -g restic-rest-server /srv/backups/skipos
systemctl restart restic-rest-server
sleep 2
systemctl is-active --quiet restic-rest-server || { echo "restic-rest-server did not start (journalctl -u restic-rest-server -n 30)" >&2; exit 1; }

set -a
# shellcheck source=/dev/null
. "$ENVF"
set +a
export RESTIC_CACHE_DIR=/var/cache/restic-skipos
if restic -r "$REPO" --password-file "$PW" cat config >/dev/null 2>&1; then
  echo "repository exists: $REPO"
else
  restic -r "$REPO" --password-file "$PW" init
fi

install -m 0755 -o root -g root "$HERE/skipos-backup" /usr/local/sbin/skipos-backup
install -m 0755 -o root -g root "$HERE/skipos-restore-drill" /usr/local/sbin/skipos-restore-drill
systemctl start skipos-backup
restic -r "$REPO" --password-file "$PW" snapshots --compact

if [ "$NEWPW" = 1 ] || [ -n "$NEWREST" ]; then
  echo
  echo "=== SAVE THESE IN VAULTWARDEN NOW. G7's install asks for both. Shown once. ==="
  [ "$NEWPW" = 1 ] && echo "SkipOS backup repository password:  $(cat "$PW")"
  [ -n "$NEWREST" ] && echo "SkipOS backup REST login:           user skipos, password $NEWREST"
  echo "Without the repository password the off-server copy cannot be read by anyone."
  echo "==============================================================================="
fi
