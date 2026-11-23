#!/bin/sh
# Makes the SkipOS console reachable from the PC over the Miami VPN, and from nowhere else.
# Run on Miami:  sudo sh 04-console.sh
#
# The console container listens on 127.0.0.1:3000 only. Caddy runs on the HOST (not in Docker)
# and forwards http://10.78.0.1:8300 to it. That matters: a port published by Docker bypasses
# ufw, so a Docker-published port on the VPN address would be open to every VPN device,
# Will's and Frank's included. A host process is filtered by ufw like anything else, and the
# rule below lets in the PC (10.78.0.11) alone.
#
# The console has no login. Whoever reaches it acts as the owner. Plain http is used because
# the only path to it is inside the WireGuard tunnel, the same as TaxGlasses on G7.
# Syntax-checked only; not yet run on Miami.
set -eu
[ "$(id -u)" = 0 ] || { echo "run with sudo" >&2; exit 1; }
VPN_ADDR=10.78.0.1
PORT=8300
PC=10.78.0.11

apt-get install -y caddy >/dev/null

[ -e /etc/caddy/Caddyfile ] && [ ! -e /etc/caddy/Caddyfile.dist ] && cp -p /etc/caddy/Caddyfile /etc/caddy/Caddyfile.dist
cat > /etc/caddy/Caddyfile <<CADDY
# /etc/caddy/Caddyfile on Miami. Source: mia/skipos/04-console.sh in g7-infra.
{
	admin localhost:2019
	auto_https off
}
http://$VPN_ADDR:$PORT {
	bind $VPN_ADDR
	# flush_interval -1: the console's live run feed is a server-sent event stream.
	reverse_proxy 127.0.0.1:3000 {
		flush_interval -1
	}
}
CADDY
caddy validate --config /etc/caddy/Caddyfile >/dev/null

# Caddy binds the VPN address, which exists only once wg0 is up.
mkdir -p /etc/systemd/system/caddy.service.d
cat > /etc/systemd/system/caddy.service.d/10-after-wg0.conf <<'UNIT'
[Unit]
Wants=wg-quick@wg0.service
After=wg-quick@wg0.service

[Service]
Restart=on-failure
RestartSec=10
UNIT
systemctl daemon-reload
systemctl enable caddy >/dev/null
systemctl restart caddy

ufw allow in on wg0 from "$PC" to "$VPN_ADDR" port "$PORT" proto tcp comment 'SkipOS console, PC only'

echo "Console: http://$VPN_ADDR:$PORT from the PC with the Miami VPN connected."
echo "From Miami itself, 200 once the stack is up:"
printf '%s\n' "  curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:3000/"
