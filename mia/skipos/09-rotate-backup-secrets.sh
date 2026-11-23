#!/bin/sh
# Replaces BOTH SkipOS backup secrets on Miami: the repository password and the REST login.
# Run on Miami, from the folder holding these files:  sudo sh 09-rotate-backup-secrets.sh
# Use it when either secret may have been seen by anyone or anything it should not have been.
#
# It starts the encrypted repository again from empty, because a restic repository cannot
# drop its old password through an append-only server. Nothing is lost that matters: the
# dated folders in /srv/skipos-backups are untouched, and tonight's run refills the new one.
# G7's copy made with the old password stays readable only with the old password; remove it
# on G7 if the old password is not to be trusted (the last lines say how).
# Then it runs 08-offsite.sh, which prints the two NEW secrets once.
# Syntax-checked only; not yet run on Miami.
set -eu
[ "$(id -u)" = 0 ] || { echo "run with sudo" >&2; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
HT=/etc/restic-rest-server/users.htpasswd
[ -e "$HT" ] || { echo "$HT is missing" >&2; exit 1; }
[ -e "$HERE/08-offsite.sh" ] || { echo "08-offsite.sh must be in the same folder" >&2; exit 1; }

sed -i '/^skipos:/d' "$HT"
rm -f /etc/skipos/restic-rest-env /etc/skipos/restic-repo-pass
rm -rf /srv/backups/skipos/restic /var/cache/restic-skipos
echo "Old login, old password and old repository removed. Setting up new ones."
sh "$HERE/08-offsite.sh"

echo
echo "On G7, give it the new secrets:   sudo sh /tmp/g7-skipos-backup/install.sh reset"
echo "If G7 already holds a copy made with the old password, remove that first:"
echo "  sudo rm -rf /mnt/data/skipos-backups/restic /var/cache/restic-skipos"
