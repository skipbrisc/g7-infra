#!/bin/sh
# Adds one device to the Miami VPN and prints its config as a QR code and as text.
# Usage (on Miami):  sudo sh add-vpn-device.sh <name> <last-octet>
#   e.g.             sudo sh add-vpn-device.sh tablet 12      -> 10.78.0.12
# The same commands were run by hand for phone, pc, will and frank on 2026-11-12; this script
# form has only been syntax-checked.
set -eu
[ "$(id -u)" = 0 ] || { echo "run with sudo" >&2; exit 1; }
NAME=${1:?name, e.g. tablet}
OCTET=${2:?last octet of 10.78.0.x, e.g. 12}
case "$NAME" in *[!a-z0-9-]*|'') echo "name: lowercase letters, digits and - only" >&2; exit 1;; esac
case "$OCTET" in *[!0-9]*|'') echo "octet must be a number" >&2; exit 1;; esac
[ "$OCTET" -ge 3 ] && [ "$OCTET" -le 254 ] || { echo "octet must be 3-254 (1 is Miami, 2 is G7)" >&2; exit 1; }

IP="10.78.0.$OCTET"
DIR=/etc/wireguard/clients
CONF=/etc/wireguard/wg0.conf
ENDPOINT=38.126.208.251:51820

[ -e "$DIR/$NAME.key" ] && { echo "$NAME already exists in $DIR" >&2; exit 1; }
grep -q "AllowedIPs = $IP/32" "$CONF" && { echo "$IP is already assigned in $CONF" >&2; exit 1; }

umask 077
mkdir -p "$DIR"
wg genkey | tee "$DIR/$NAME.key" | wg pubkey > "$DIR/$NAME.pub"
PUB=$(cat "$DIR/$NAME.pub")

printf '\n[Peer]\n# %s\nPublicKey = %s\nAllowedIPs = %s/32\n' "$NAME" "$PUB" "$IP" >> "$CONF"
wg set wg0 peer "$PUB" allowed-ips "$IP/32"

cat > "$DIR/$NAME.conf" <<EOF
[Interface]
PrivateKey = $(cat "$DIR/$NAME.key")
Address = $IP/32
DNS = 1.1.1.1

[Peer]
PublicKey = $(cat /etc/wireguard/server.pub)
Endpoint = $ENDPOINT
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF

echo "Added $NAME at $IP. Config: $DIR/$NAME.conf (contains the device's private key)."
echo
qrencode -t ansiutf8 < "$DIR/$NAME.conf"
