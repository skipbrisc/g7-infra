#!/bin/sh
# Lets G7's Uptime Kuma watch SkipOS on Miami, with no Healthchecks.io check.
# Run on Miami, from the folder holding these files:  sudo sh 07-status.sh
# Needs 04-console.sh (Caddy) and 05-ops.sh (skipos-health) to have run.
#
# skipos-health writes one line every 5 minutes, "skipos ok" or "skipos DOWN: <what>", to
# /var/lib/skipos-status/index.txt. Caddy serves that one folder at http://10.78.0.1:8301,
# and ufw lets in G7 (10.78.0.2, the wg link) and nobody else. Uptime Kuma on G7 fetches the
# page and alerts through ntfy when the words "skipos ok" are not there: the stack is down,
# the backup is stale, Caddy is down, or Miami is unreachable.
#
# What it cannot see: a stopped cron on Miami would leave the last "skipos ok" in place.
# The existing "Miami heartbeat" check on Healthchecks.io is pinged by the same cron, so
# that case already alerts there.
# Syntax-checked only; not yet run on Miami.
set -eu
[ "$(id -u)" = 0 ] || { echo "run with sudo" >&2; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
VPN_ADDR=10.78.0.1
PORT=8301
G7=10.78.0.2
DIR=/var/lib/skipos-status

command -v caddy >/dev/null 2>&1 || { echo "Caddy is not installed: run 04-console.sh first" >&2; exit 1; }
[ -e /etc/caddy/Caddyfile ] || { echo "/etc/caddy/Caddyfile is missing: run 04-console.sh first" >&2; exit 1; }

install -d -m 0755 -o root -g root "$DIR"
install -m 0755 -o root -g root "$HERE/skipos-health" /usr/local/sbin/skipos-health
/usr/local/sbin/skipos-health

if ! grep -q ":$PORT" /etc/caddy/Caddyfile; then
  cp -p /etc/caddy/Caddyfile /etc/caddy/Caddyfile.before-status
  cat >> /etc/caddy/Caddyfile <<CADDY

# SkipOS status line for G7's Uptime Kuma. Source: mia/skipos/07-status.sh in g7-infra.
http://$VPN_ADDR:$PORT {
	bind $VPN_ADDR
	root * $DIR
	rewrite * /index.txt
	header Content-Type "text/plain; charset=utf-8"
	header Cache-Control "no-store"
	file_server
}
CADDY
  if ! caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1; then
    cp -p /etc/caddy/Caddyfile.before-status /etc/caddy/Caddyfile
    echo "The new Caddyfile did not validate; the old one is back in place. Nothing changed." >&2
    exit 1
  fi
  systemctl reload caddy
fi

ufw allow in on wg0 from "$G7" to "$VPN_ADDR" port "$PORT" proto tcp comment 'SkipOS status, G7 only'

sleep 1
echo "The page, as G7 will see it:"
curl -s -m 5 "http://$VPN_ADDR:$PORT/" || echo "(no answer yet)"
echo
echo "In Uptime Kuma on G7, add one monitor:"
echo "  Type: HTTP(s) - Keyword    URL: http://$VPN_ADDR:$PORT/    Keyword: skipos ok"
echo "  Interval 300 seconds, retries 2, notification: ntfy g7"
