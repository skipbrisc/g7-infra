#!/bin/sh
# Install the G7 side of SkipOS' off-server backup (g7/skipos-backup/README.md). Run as root
# from the folder holding these files:   sudo sh /tmp/g7-skipos-backup/install.sh
# Run mia/skipos/08-offsite.sh on Miami FIRST: it prints the two secrets this asks for.
# Safe to re-run: stored secrets and the repository are kept.
#   sudo sh install.sh reset    forget the two stored secrets first and ask for them again
#                               (after a mistyped paste, or after Miami's 09-rotate script)
# Syntax-checked only; not yet run on G7.
set -eu
cd "$(dirname "$0")"
REPO=/mnt/data/skipos-backups/restic
PW=/root/.restic-skipos
LOGIN=/root/.restic-mia-skipos-rest
SOURCE=rest:http://10.78.0.1:8000/skipos/restic
say() { printf '\n== %s\n' "$*"; }
die() { echo "install.sh: $*" >&2; exit 1; }
[ "$(id -u)" = 0 ] || die "run as root"

ask_secret() { # prompt -> stdout, typed without echo
  printf '%s: ' "$1" >&2
  stty -echo 2>/dev/null || true
  IFS= read -r REPLY || REPLY=""
  stty echo 2>/dev/null || true
  printf '\n' >&2
  printf '%s' "$REPLY"
}

if [ "${1:-}" = reset ]; then
  rm -f "$PW" "$LOGIN"
  echo "Stored secrets removed; they will be asked for again."
fi

say "packages"
apt-get install -y restic python3 curl >/dev/null

say "backup disk"
mountpoint -q /mnt/data || mount /mnt/data || die "/mnt/data is not mounted"
mkdir -p /mnt/data/skipos-backups

say "the two secrets from Miami (mia/skipos/08-offsite.sh printed them)"
if [ ! -s "$PW" ]; then
  V=$(ask_secret "SkipOS backup repository password")
  [ -n "$V" ] || die "no repository password given"
  echo "   got ${#V} characters (Miami prints 44)"
  (umask 077; printf '%s\n' "$V" > "$PW")
fi
chmod 600 "$PW"
if [ ! -s "$LOGIN" ]; then
  V=$(ask_secret "SkipOS backup REST password (user skipos)")
  [ -n "$V" ] || die "no REST password given"
  echo "   got ${#V} characters (Miami prints 28; the password only, not the words before it)"
  (umask 077; printf 'RESTIC_REST_USERNAME=skipos\nRESTIC_REST_PASSWORD=%s\n' "$V" > "$LOGIN")
fi
chmod 600 "$LOGIN"

say "can G7 read Miami's repository?"
set -a
# shellcheck source=/dev/null
. "$LOGIN"
set +a
export RESTIC_CACHE_DIR=/var/cache/restic-skipos
CODE=$(curl -s -m 10 -o /dev/null -w '%{http_code}' "http://10.78.0.1:8000/skipos/restic/config" || true)
case "$CODE" in
  401) echo "   Miami answers on the link (401 without a login: ok)" ;;
  000) die "no answer from 10.78.0.1:8000. Is the link up? (ping 10.78.0.1; systemctl status wg-quick@wg-mia)" ;;
  *)   echo "   note: expected 401 from Miami without a login, got $CODE" ;;
esac
CODE=$(curl -s -m 10 -o /dev/null -w '%{http_code}' -u "$RESTIC_REST_USERNAME:$RESTIC_REST_PASSWORD" "http://10.78.0.1:8000/skipos/restic/config" || true)
[ "$CODE" = 200 ] || die "Miami refused the REST login (HTTP $CODE): the REST password is wrong. Run:  sudo sh install.sh reset"
echo "   the REST login is accepted"
if ! ERR=$(restic -r "$SOURCE" --password-file "$PW" cat config 2>&1 >/dev/null); then
  echo "$ERR" | tail -n 3 >&2
  die "the REST login works but the repository will not open: the repository password is wrong. Run:  sudo sh install.sh reset"
fi
echo "   the repository opens"

say "G7's copy (same password, same chunking, so copies stay small)"
if [ -f "$REPO/config" ]; then
  echo "   repository exists: $REPO"
else
  restic -r "$REPO" --password-file "$PW" init --from-repo "$SOURCE" --from-password-file "$PW" --copy-chunker-params
fi

say "the nightly job"
install -o root -g root -m 0700 g7-skipos-pull /usr/local/sbin/g7-skipos-pull
install -o root -g root -m 0644 g7-skipos-pull.service g7-skipos-pull.timer /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now g7-skipos-pull.timer >/dev/null 2>&1

echo
echo "Installed. Next run: $(systemctl list-timers g7-skipos-pull.timer --no-pager | awk 'NR==2{print $1, $2, $3}')"
echo "Run it once now and read the result:"
echo "  sudo /usr/local/sbin/g7-skipos-pull"
