#!/bin/sh
# Installs Docker on the Miami server and makes it coexist with the WireGuard exit, the same
# way G7 does it (g7-infra: etc/wireguard/wg0.conf PostUp rules, systemd/wg-quick@wg0.service.d).
# Run on Miami:  sudo sh 01-docker.sh
# Safe to run again. It does NOT restart WireGuard: the firewall rules are applied live and
# written into wg0.conf for the next boot, so a VPN or SSH session through Miami stays up.
# Written 2026-11-23 from the configs in mia/live. Syntax-checked only; not yet run on Miami.
set -eu
[ "$(id -u)" = 0 ] || { echo "run with sudo" >&2; exit 1; }

WG_CONF=/etc/wireguard/wg0.conf
WG_NET=10.78.0.0/24
UPLINK=$(ip -o -4 route show default | awk '{print $5; exit}')
[ -n "$UPLINK" ] || { echo "could not find the uplink interface" >&2; exit 1; }
grep -q -- "-o $UPLINK -j MASQUERADE" "$WG_CONF" || {
  echo "wg0.conf does not masquerade out of $UPLINK; check the uplink name before going on" >&2; exit 1; }

# --- 1. Docker Engine from Docker's own apt repository -----------------------------------
if ! command -v docker >/dev/null 2>&1; then
  apt-get update
  apt-get install -y ca-certificates curl
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  . /etc/os-release
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $VERSION_CODENAME stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi

# Bounded container logs: the default json-file driver grows without limit.
if [ ! -e /etc/docker/daemon.json ]; then
  mkdir -p /etc/docker
  cat > /etc/docker/daemon.json <<'JSON'
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "20m", "max-file": "5" }
}
JSON
  systemctl restart docker
fi
systemctl enable --now docker

# --- 2. WireGuard after Docker at boot (G7's two drop-ins, as one file) --------------------
# Docker creates the DOCKER-USER chain. wg0's PostUp inserts rules into it, so wg0 must come
# up after Docker or those rules have nowhere to go.
mkdir -p /etc/systemd/system/wg-quick@wg0.service.d
cat > /etc/systemd/system/wg-quick@wg0.service.d/10-docker.conf <<'UNIT'
[Unit]
Wants=docker.service
After=docker.service
UNIT
systemctl daemon-reload

# --- 3. Keep VPN forwarding ahead of Docker's own forward rules ----------------------------
# Docker sets the FORWARD policy to DROP and puts its chains first. These two rules accept the
# VPN's traffic in DOCKER-USER, which Docker evaluates before anything else and never rewrites.
RULE_OUT="-i wg0 -o $UPLINK -s $WG_NET -j ACCEPT"
RULE_IN="-i $UPLINK -o wg0 -d $WG_NET -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT"

# Live, now (idempotent: -C checks, -I inserts only if missing).
iptables -C DOCKER-USER $RULE_OUT 2>/dev/null || iptables -I DOCKER-USER 1 $RULE_OUT
iptables -C DOCKER-USER $RULE_IN  2>/dev/null || iptables -I DOCKER-USER 1 $RULE_IN

# And in wg0.conf, for every later start of wg0.
if ! grep -q 'DOCKER-USER' "$WG_CONF"; then
  cp -p "$WG_CONF" "$WG_CONF.before-docker"
  TMP=$(mktemp)
  awk -v out="$RULE_OUT" -v in_="$RULE_IN" '
    { print }
    /^PostUp = iptables -t nat -A POSTROUTING/ {
      print "PostUp = /usr/sbin/iptables -C DOCKER-USER " out " || /usr/sbin/iptables -I DOCKER-USER 1 " out
      print "PostUp = /usr/sbin/iptables -C DOCKER-USER " in_ " || /usr/sbin/iptables -I DOCKER-USER 1 " in_
    }
    /^PostDown = iptables -t nat -D POSTROUTING/ {
      print "PostDown = /usr/sbin/iptables -D DOCKER-USER " out " || true"
      print "PostDown = /usr/sbin/iptables -D DOCKER-USER " in_ " || true"
    }
  ' "$WG_CONF" > "$TMP"
  grep -q 'DOCKER-USER' "$TMP" || { rm -f "$TMP"; echo "wg0.conf has no PostUp MASQUERADE line to anchor on; nothing written" >&2; exit 1; }
  install -m 0600 -o root -g root "$TMP" "$WG_CONF"
  rm -f "$TMP"
  echo "wg0.conf updated (previous copy: $WG_CONF.before-docker)"
fi

echo
docker --version
docker compose version
echo "DOCKER-USER now:"
iptables -S DOCKER-USER
echo
echo "Check from a VPN device that the internet still works through Miami, then go on."
