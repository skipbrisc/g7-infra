#!/usr/bin/env bash
# setup-vaultwarden.sh — Vaultwarden (self-hosted Bitwarden server) on G7.
#
#   sudo bash setup-vaultwarden.sh --dry-run                 check everything, change nothing
#   sudo bash setup-vaultwarden.sh                            install / update (asks for the DuckDNS name + token)
#   sudo bash setup-vaultwarden.sh --close-signups            after you've created your account: no new accounts
#   sudo bash setup-vaultwarden.sh --backup-key "ssh-ed25519 AAAA... vault-backup"
#                                                             authorize your PC's read-only backup-pull key
#
# Layout:
#   https://<name>.duckdns.org  →  DuckDNS record points at 192.168.0.6 (private IP: reachable at home on the LAN,
#                                  or anywhere over WireGuard; NOT from the internet — no router port is opened)
#   192.168.0.6:443  →  Caddy (custom build with DuckDNS DNS plugin, real Let's Encrypt cert)  →  vaultwarden:80
#   Docker network vaultwarden_net 172.30.77.0/24 (inside 172.16.0.0/12, so Will/Frank/tg1/tg2 are already blocked)
#   Data      /srv/vaultwarden/data          Nightly backups  /srv/vaultwarden/backups (14 days)
# Idempotent. Doesn't touch TaxGlasses, MemeSniper, WireGuard or the firewall.

set -euo pipefail
DIR=/srv/vaultwarden
LAN_IP=192.168.0.6
SUBNET=172.30.77.0/24
DRY=0; CLOSE=0; BKEY=""
while (( $# )); do case "$1" in
  --dry-run) DRY=1;; --close-signups) CLOSE=1;;
  --backup-key) BKEY="${2:-}"; shift;;
  *) echo "unknown option $1" >&2; exit 1;; esac; shift; done
[[ $EUID -eq 0 ]] || { echo "run with sudo" >&2; exit 1; }
say(){ printf '\n==> %s\n' "$*"; }; note(){ printf '    %s\n' "$*"; }; die(){ echo "ERROR: $*" >&2; exit 1; }
(( DRY )) && echo "DRY RUN — nothing will be changed"

# ---- backup key only ----------------------------------------------------------------------------
if [[ -n "$BKEY" ]]; then
  [[ "$BKEY" =~ ^ssh-ed25519\ [A-Za-z0-9+/=]+ ]] || die "--backup-key must be an ssh-ed25519 public key"
  AK=/home/buttmud/.ssh/authorized_keys
  LINE="restrict,command=\"cat $DIR/backups/latest.tar.gz\" $BKEY"
  if grep -qF "${BKEY%% vault*}" "$AK" 2>/dev/null; then note "backup key already authorized"
  elif (( DRY )); then note "would add to $AK: $LINE"
  else install -d -m 700 -o buttmud -g buttmud /home/buttmud/.ssh; echo "$LINE" >> "$AK"
       chown buttmud:buttmud "$AK"; chmod 600 "$AK"; note "authorized read-only backup key (can only download latest.tar.gz)"; fi
  exit 0
fi

# ---- close signups only -------------------------------------------------------------------------
if (( CLOSE )); then
  [[ -f $DIR/.env ]] || die "$DIR/.env missing — run setup first"
  if grep -q '^SIGNUPS_ALLOWED=false' $DIR/.env; then note "signups already closed"
  elif (( DRY )); then note "would set SIGNUPS_ALLOWED=false and restart vaultwarden"
  else sed -i 's/^SIGNUPS_ALLOWED=.*/SIGNUPS_ALLOWED=false/' $DIR/.env
       (cd $DIR && docker compose up -d vaultwarden); note "signups closed — only existing accounts can log in"; fi
  exit 0
fi

say "Preflight"
docker compose version >/dev/null 2>&1 && note "$(docker compose version)" || die "docker compose plugin missing (apt install docker-compose-plugin)"
command -v sqlite3 >/dev/null || { (( DRY )) && note "sqlite3 missing — would apt install sqlite3 (for safe live DB backups)" || apt-get install -y -qq sqlite3; }
command -v curl >/dev/null || die "curl missing"
if ss -tlnH | awk '{print $4}' | grep -qE "^(0\.0\.0\.0|\[::\]|\*|$LAN_IP):443$"; then
  docker ps --format '{{.Names}} {{.Ports}}' | grep -q 'vaultwarden-caddy.*:443->' && note "443 already used by vaultwarden-caddy (update run)" || die "something else is already listening on 443"
else note "port $LAN_IP:443 free"; fi
docker network ls --format '{{.Name}}' | grep -qx vaultwarden_net || \
  { docker network inspect $(docker network ls -q) --format '{{range .IPAM.Config}}{{.Subnet}} {{end}}' 2>/dev/null | grep -q "172.30.77." && die "$SUBNET already in use"; note "subnet $SUBNET free"; }

# ---- DuckDNS name + token -----------------------------------------------------------------------
say "DuckDNS"
if [[ -f $DIR/caddy.env && -f $DIR/.env ]]; then
  VHOST=$(sed -n 's#^DOMAIN=https://##p' $DIR/.env); note "using existing $VHOST"
elif (( DRY )); then VHOST="<name>.duckdns.org"; note "would ask for a DuckDNS subdomain + token, and point it at $LAN_IP"
else
  read -rp "    DuckDNS subdomain for the vault (just the name, e.g. buttvault): " SUB
  [[ "$SUB" =~ ^[a-z0-9-]+$ ]] || die "letters, digits and dashes only"
  read -rsp "    DuckDNS token (hidden): " TOKEN; echo
  [[ ${#TOKEN} -ge 30 ]] || die "that doesn't look like a DuckDNS token"
  r=$(curl -fsS "https://www.duckdns.org/update?domains=$SUB&token=$TOKEN&ip=$LAN_IP") || die "DuckDNS unreachable"
  [[ "$r" == OK ]] || die "DuckDNS said '$r' — create '$SUB' in your duckdns.org dashboard first, and check the token"
  note "$SUB.duckdns.org → $LAN_IP"
  VHOST="$SUB.duckdns.org"
  install -d -m 700 $DIR
  umask 077; printf 'DUCKDNS_TOKEN=%s\n' "$TOKEN" > $DIR/caddy.env; umask 022
  unset TOKEN
fi

# ---- files --------------------------------------------------------------------------------------
write(){ # path mode content
  if [[ -f "$1" && "$(cat "$1")" == "$3" ]]; then note "$1 unchanged"; return; fi
  if (( DRY )); then note "would write $1"; return; fi
  install -d "$(dirname "$1")"; printf '%s\n' "$3" > "$1"; chmod "$2" "$1"; note "wrote $1"; }

say "Files in $DIR"
(( DRY )) || install -d -m 700 $DIR $DIR/data $DIR/caddy
(( DRY )) || { install -d -m 750 -o root -g buttmud $DIR/backups; }

[[ -f $DIR/.env ]] && grep -q '^SIGNUPS_ALLOWED=false' $DIR/.env && SIGN=false || SIGN=true
write $DIR/.env 600 "DOMAIN=https://$VHOST
SIGNUPS_ALLOWED=$SIGN
INVITATIONS_ALLOWED=false
SHOW_PASSWORD_HINT=false
# no ADMIN_TOKEN → /admin panel disabled"

write $DIR/caddy/Dockerfile 644 'FROM caddy:2-builder AS build
RUN xcaddy build --with github.com/caddy-dns/duckdns
FROM caddy:2-alpine
COPY --from=build /usr/bin/caddy /usr/bin/caddy'

write $DIR/caddy/Caddyfile 644 "{
	admin off
}

$VHOST {
	tls {
		dns duckdns {env.DUCKDNS_TOKEN}
		resolvers 1.1.1.1
	}
	encode zstd gzip
	header Strict-Transport-Security \"max-age=31536000\"
	reverse_proxy vaultwarden:80
}"

write $DIR/compose.yml 644 "name: vaultwarden
services:
  vaultwarden:
    image: vaultwarden/server:latest
    container_name: vaultwarden
    restart: unless-stopped
    env_file: .env
    volumes:
      - ./data:/data
    networks: [net]

  caddy:
    build: ./caddy
    image: vaultwarden-caddy:local
    container_name: vaultwarden-caddy
    restart: unless-stopped
    env_file: caddy.env
    ports:
      - \"$LAN_IP:443:443\"
    volumes:
      - ./caddy/Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy-data:/data
      - caddy-config:/config
    depends_on: [vaultwarden]
    networks: [net]

networks:
  net:
    name: vaultwarden_net
    ipam:
      config:
        - subnet: $SUBNET

volumes:
  caddy-data:
  caddy-config:"

write /usr/local/sbin/vaultwarden-backup.sh 755 '#!/bin/sh
# Nightly Vaultwarden backup: consistent SQLite copy + keys/attachments. Keeps 14 days.
set -eu
D=/srv/vaultwarden; B=$D/backups; T=$(date +%F-%H%M); tmp=$(mktemp -d)
trap "rm -rf $tmp" EXIT
sqlite3 "$D/data/db.sqlite3" ".backup '"'"'$tmp/db.sqlite3'"'"'"
mkdir -p "$tmp/data"; cp -a "$D/data/." "$tmp/data/"
rm -f "$tmp/data/db.sqlite3" "$tmp/data/db.sqlite3-wal" "$tmp/data/db.sqlite3-shm"; rm -rf "$tmp/data/icon_cache"
mv "$tmp/db.sqlite3" "$tmp/data/db.sqlite3"
tar czf "$B/vault-$T.tar.gz" -C "$tmp" data
chown root:buttmud "$B/vault-$T.tar.gz"; chmod 640 "$B/vault-$T.tar.gz"
ln -sfn "vault-$T.tar.gz" "$B/latest.tar.gz"
find "$B" -name "vault-*.tar.gz" -mtime +14 -delete
echo "backup: $B/vault-$T.tar.gz"'

write /etc/systemd/system/vaultwarden-backup.service 644 "[Unit]
Description=Vaultwarden nightly backup
After=docker.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/vaultwarden-backup.sh"

write /etc/systemd/system/vaultwarden-backup.timer 644 "[Unit]
Description=Vaultwarden nightly backup

[Timer]
OnCalendar=*-*-* 02:41
Persistent=true

[Install]
WantedBy=timers.target"

say "Start"
if (( DRY )); then
  note "would: docker compose build caddy, docker compose up -d, enable vaultwarden-backup.timer"
  note "re-run without --dry-run to apply"; exit 0
fi
cd $DIR
docker compose build --pull caddy
docker compose up -d
systemctl daemon-reload
systemctl enable --now vaultwarden-backup.timer >/dev/null
note "waiting for the certificate (DuckDNS DNS challenge, up to ~2 min)..."
ok=0
for i in $(seq 1 30); do
  if curl -fsS --max-time 5 --resolve "$VHOST:443:$LAN_IP" "https://$VHOST/alive" >/dev/null 2>&1; then ok=1; break; fi
  sleep 5
done
if (( ok )); then note "https://$VHOST is up with a valid certificate"
else note "not answering yet — check: docker logs vaultwarden-caddy --tail 40"; fi
/usr/local/sbin/vaultwarden-backup.sh >/dev/null && note "first backup written"

say "Done"
note "1. Open https://$VHOST from your PC (on the LAN, or with WireGuard on) and create your account."
note "2. Then close signups:  sudo bash $0 --close-signups"
note "signups are currently: $(sed -n 's/^SIGNUPS_ALLOWED=//p' $DIR/.env)"
