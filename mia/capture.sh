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
         "$L/etc/apt/apt.conf.d" "$L/etc/ufw" "$L/state"

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

# --- Scheduled jobs and updates
for u in root $(getent passwd | awk -F: '$3>=1000 && $3<65000 {print $1}'); do
  crontab -l -u "$u" 2>/dev/null | grep -v '^#' | grep -v '^$' | redact_hc > "$L/state/crontab-$u.txt"
  [ -s "$L/state/crontab-$u.txt" ] || rm -f "$L/state/crontab-$u.txt"
done
for f in 20auto-upgrades 50unattended-upgrades; do
  [ -e "/etc/apt/apt.conf.d/$f" ] && cp "/etc/apt/apt.conf.d/$f" "$L/etc/apt/apt.conf.d/$f"
done

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
  for s in ssh ufw wg-quick@wg0 cron unattended-upgrades; do
    echo "$s: $(systemctl is-enabled "$s" 2>/dev/null) / $(systemctl is-active "$s" 2>/dev/null)"
  done
  echo
  echo "== addresses"; ip -br addr
  echo
  echo "== default route"; ip route show default
  echo
  echo "== disks"; lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT
  echo
  echo "== root filesystem"; df -h /
  echo
  echo "== backup folders"; ls -ld /srv/backups /srv/backups/* 2>/dev/null
} > "$L/state/system.txt" 2>&1
getent passwd | awk -F: '$3>=1000 && $3<65000 {print $1 " uid=" $3 " home=" $6 " shell=" $7}' > "$L/state/users.txt"
for u in $(getent passwd | awk -F: '$3>=1000 && $3<65000 {print $1}'); do id "$u"; done >> "$L/state/users.txt" 2>&1
apt-mark showmanual > "$L/state/apt-manual.txt" 2>/dev/null

# --- Refuse to hand over anything that still looks like a private key or a ping address.
if grep -rEq '^[[:space:]]*(PrivateKey|PresharedKey)[[:space:]]*=[[:space:]]*[A-Za-z0-9+/]{43}=' "$L" \
   || grep -rEq 'hc-ping\.com/[0-9a-f]{8}-' "$L" \
   || grep -rlq 'PRIVATE KEY' "$L"; then
  rm -rf "$OUT"
  echo "mia-capture: a secret survived redaction; nothing written" >&2
  exit 1
fi

tar -C "$OUT" -czf /tmp/mia-live.tgz live && chmod 644 /tmp/mia-live.tgz
rm -rf "$OUT"
echo "mia-capture: wrote /tmp/mia-live.tgz"
