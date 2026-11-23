#!/bin/sh
# Collects the Miami server's live configuration into /tmp/mia-live.tgz with secrets removed,
# so it can be kept in the g7-infra repository under mia/live/.
# Run on Miami as root (see mia/README.md, "Refreshing the live copy"). Changes nothing on the
# server except writing /tmp/mia-live.tgz.
set -u
[ "$(id -u)" = 0 ] || { echo "mia-capture: run with sudo" >&2; exit 1; }

OUT=$(mktemp -d) || exit 1
L="$OUT/live"
mkdir -p "$L/etc/ssh/sshd_config.d" "$L/etc/wireguard" "$L/etc/sysctl.d" \
         "$L/etc/apt/apt.conf.d" "$L/etc/ufw" "$L/etc/default" \
         "$L/etc/systemd/system/restic-rest-server.service.d" "$L/state"

# WireGuard private and preshared keys never leave the server.
redact_wg() { sed -E 's/^([[:space:]]*(PrivateKey|PresharedKey)[[:space:]]*=).*/\1 <REDACTED>/'; }
# The Healthchecks ping address works like a password for that one check.
redact_hc() { sed -E 's#(hc-ping\.com/)[A-Za-z0-9/_-]+#\1<REDACTED>#g'; }

# --- SSH
cp /etc/ssh/sshd_config "$L/etc/ssh/sshd_config" 2>/dev/null
for f in /etc/ssh/sshd_config.d/*.conf; do
  [ -e "$f" ] && cp "$f" "$L/etc/ssh/sshd_config.d/"
done
sshd -T 2>/dev/null | grep -Ei '^(port|permitrootlogin|passwordauthentication|kbdinteractiveauthentication|pubkeyauthentication|allowusers|allowgroups|subsystem) ' \
  > "$L/state/sshd-effective.txt"
for u in $(getent passwd | awk -F: '$3>=1000 && $3<65000 {print $1}'); do
  h=$(getent passwd "$u" | cut -d: -f6)
  [ -s "$h/.ssh/authorized_keys" ] && cp "$h/.ssh/authorized_keys" "$L/state/authorized_keys-$u.txt"
done

# --- WireGuard (interface configs only; nothing from /etc/wireguard/clients, no *.key files)
for f in /etc/wireguard/*.conf; do
  [ -e "$f" ] && redact_wg < "$f" > "$L/etc/wireguard/$(basename "$f")"
done
[ -e /etc/wireguard/server.pub ] && cp /etc/wireguard/server.pub "$L/etc/wireguard/server.pub"
ls /etc/wireguard/clients 2>/dev/null | sed -n 's/\.pub$//p' > "$L/state/vpn-clients.txt"

# --- Firewall, forwarding, names
ufw status verbose > "$L/state/ufw-status.txt" 2>&1
ufw show added > "$L/state/ufw-added.txt" 2>&1
for f in user.rules user6.rules; do [ -e "/etc/ufw/$f" ] && cp "/etc/ufw/$f" "$L/etc/ufw/$f"; done
for f in /etc/sysctl.d/*.conf; do [ -e "$f" ] && cp "$f" "$L/etc/sysctl.d/"; done
cp /etc/hosts "$L/etc/hosts" 2>/dev/null
cp /etc/hostname "$L/etc/hostname" 2>/dev/null

# --- Backup target: the REST server's settings and drop-in. Of the login file only the user
# names; the password hashes stay on the server.
[ -e /etc/default/restic-rest-server ] && cp /etc/default/restic-rest-server "$L/etc/default/"
for f in /etc/systemd/system/restic-rest-server.service.d/*.conf; do
  [ -e "$f" ] && cp "$f" "$L/etc/systemd/system/restic-rest-server.service.d/"
done
[ -e /etc/restic-rest-server/users.htpasswd ] \
  && cut -d: -f1 /etc/restic-rest-server/users.htpasswd > "$L/state/rest-server-users.txt"

# --- Scheduled jobs and updates
for u in root $(getent passwd | awk -F: '$3>=1000 && $3<65000 {print $1}'); do
  crontab -l -u "$u" 2>/dev/null | grep -v '^#' | grep -v '^$' | redact_hc > "$L/state/crontab-$u.txt"
  [ -s "$L/state/crontab-$u.txt" ] || rm -f "$L/state/crontab-$u.txt"
done
for f in 20auto-upgrades 50unattended-upgrades; do
  [ -e "/etc/apt/apt.conf.d/$f" ] && cp "/etc/apt/apt.conf.d/$f" "$L/etc/apt/apt.conf.d/$f"
done

# --- SkipOS (mia/skipos): the files that make it run, and its state. NEVER the stack's .env
# (two secrets) and never a Healthchecks address: of both, only the names are recorded.
mkdir -p "$L/etc/caddy" "$L/etc/docker" "$L/etc/systemd/system"
[ -e /etc/caddy/Caddyfile ] && cp /etc/caddy/Caddyfile "$L/etc/caddy/Caddyfile"
[ -e /etc/docker/daemon.json ] && cp /etc/docker/daemon.json "$L/etc/docker/daemon.json"
for f in skipos.service skipos-backup.service skipos-backup.timer skipos-gates.service skipos-gates.timer; do
  [ -e "/etc/systemd/system/$f" ] && cp "/etc/systemd/system/$f" "$L/etc/systemd/system/$f"
done
for d in caddy.service.d wg-quick@wg0.service.d; do
  for f in /etc/systemd/system/$d/*.conf; do
    [ -e "$f" ] || continue
    mkdir -p "$L/etc/systemd/system/$d"
    cp "$f" "$L/etc/systemd/system/$d/"
  done
done
if [ -d /opt/skipos ] || command -v docker >/dev/null 2>&1; then
  {
    echo "== checkout"
    # As the checkout's owner: root's git refuses a repository owned by someone else.
    sudo -u skipos git -C /opt/skipos log -1 --format='%H %s' 2>/dev/null || echo "(no /opt/skipos checkout)"
    echo
    echo "== settings in /opt/skipos/infra/docker/.env (names only, never values)"
    sed -n 's/^\([A-Z_][A-Z0-9_]*\)=.*/\1/p' /opt/skipos/infra/docker/.env 2>/dev/null
    echo
    echo "== files in /etc/skipos (names only)"
    ls -1 /etc/skipos 2>/dev/null
    echo
    echo "== containers (name, state)"
    docker ps -a --format '{{.Names}} {{.State}}' 2>/dev/null | sort
    echo
    echo "== volumes"
    docker volume ls --format '{{.Name}}' 2>/dev/null | sort
    echo
    echo "== DOCKER-USER (the VPN's rules ahead of Docker's)"
    iptables -S DOCKER-USER 2>/dev/null
    echo
    echo "== versions"
    docker --version 2>/dev/null
    docker compose version 2>/dev/null
    caddy version 2>/dev/null
    /opt/node24/bin/node -v 2>/dev/null
    echo
    echo "== newest backup"
    ls -1d /srv/skipos-backups/20* 2>/dev/null | sort | tail -n 1
  } > "$L/state/skipos.txt" 2>&1
fi

# --- What the machine is
{
  echo "captured: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "hostname: $(hostname)"
  grep -E '^(PRETTY_NAME|VERSION_ID)=' /etc/os-release
  echo "kernel: $(uname -r)"
  echo "timezone: $(timedatectl show -p Timezone --value 2>/dev/null)"
  echo "ntp-synchronized: $(timedatectl show -p NTPSynchronized --value 2>/dev/null)"
  echo
  echo "== services (is-enabled / is-active)"
  for s in ssh ufw wg-quick@wg0 restic-rest-server cron unattended-upgrades docker caddy skipos skipos-backup.timer; do
    echo "$s: $(systemctl is-enabled "$s" 2>/dev/null) / $(systemctl is-active "$s" 2>/dev/null)"
  done
  echo
  # Docker's bridges and per-container veth pairs are renamed on every container restart;
  # listing them would change this file on every capture and say nothing.
  echo "== addresses"; ip -br addr | grep -Ev '^(veth|br-|docker0)'
  echo
  echo "== default route"; ip route show default
  echo
  echo "== disks"; lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT
  echo
  echo "== root filesystem"; df -h /
  echo
  echo "== backup folders"; ls -ld /srv/backups /srv/backups/* /srv/backups/*/* 2>/dev/null
} > "$L/state/system.txt" 2>&1
getent passwd | awk -F: '$3>=1000 && $3<65000 {print $1 " uid=" $3 " home=" $6 " shell=" $7}' > "$L/state/users.txt"
for u in $(getent passwd | awk -F: '$3>=1000 && $3<65000 {print $1}'); do id "$u"; done >> "$L/state/users.txt" 2>&1
apt-mark showmanual > "$L/state/apt-manual.txt" 2>/dev/null

# --- Refuse to hand over anything that still looks like a private key, a ping address, a
# password hash, or a 64-character hex string (the shape of SkipOS' two stack secrets).
if grep -rEq '^[[:space:]]*(PrivateKey|PresharedKey)[[:space:]]*=[[:space:]]*[A-Za-z0-9+/]{43}=' "$L" \
   || grep -rEq 'hc-ping\.com/[0-9a-f]{8}-' "$L" \
   || grep -rlq 'PRIVATE KEY' "$L" \
   || grep -rEq '\$2[aby]\$[0-9]{2}\$' "$L" \
   || grep -rEq '(^|[^0-9a-f])[0-9a-f]{64}([^0-9a-f]|$)' "$L"; then
  rm -rf "$OUT"
  echo "mia-capture: a secret survived redaction; nothing written" >&2
  exit 1
fi

tar -C "$OUT" -czf /tmp/mia-live.tgz live && chmod 644 /tmp/mia-live.tgz
rm -rf "$OUT"
echo "mia-capture: wrote /tmp/mia-live.tgz"
