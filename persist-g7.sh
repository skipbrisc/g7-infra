#!/usr/bin/env bash
# persist-g7.sh — make G7's current network/firewall/service setup survive a reboot.
#
#   sudo bash persist-g7.sh --dry-run    report what's persistent today and what would change; touches nothing
#   sudo bash persist-g7.sh              apply
#   sudo bash persist-g7.sh --no-firewall  skip step 1 (firewall already persisted by another unit)
#   sudo bash persist-g7.sh --ap-nat     also give CrackCookingKitchen Wi-Fi clients internet (NAT 192.168.4.0/24)
#
# What it does:
#   1. Installs /usr/local/sbin/g7-firewall.sh — rebuilds the Will / Frank / tg1-tg2 restrictions and the VPN
#      forwarding rules in the right order. Safe to re-run any time.
#   2. Runs it at boot, every time WireGuard comes up, and every time Docker restarts (Docker rebuilds its
#      own chains but keeps DOCKER-USER, and this re-checks the order).
#   3. Fixes the empty /etc/resolv.conf so it isn't regenerated empty.
#   4. Enables every service that is running now but wouldn't start on boot.
#   5. Sets the TaxGlasses containers to restart automatically.
# It does not touch wg0.conf, the peers, or any keys. Backups of every file it changes go to /root/g7-persist-backup-<time>/.

set -euo pipefail
DRY=0; AP_NAT=0; NO_FW=0
for a in "$@"; do case "$a" in --dry-run) DRY=1;; --ap-nat) AP_NAT=1;; --no-firewall) NO_FW=1;; *) echo "unknown option $a" >&2; exit 1;; esac; done
[[ $EUID -eq 0 ]] || { echo "run with sudo" >&2; exit 1; }
say(){ printf '\n==> %s\n' "$*"; }; note(){ printf '    %s\n' "$*"; }
BK="/root/g7-persist-backup-$(date +%Y%m%d-%H%M%S)"
backup(){ (( DRY )) && return; mkdir -p "$BK"; [[ -e "$1" ]] && cp -a --parents "$1" "$BK/"; }
(( DRY )) && echo "DRY RUN — nothing will be changed"

say "Are the peer restrictions already saved anywhere?"
found="$(grep -rl -E 'WG-WILL|WG-FRANK|TG-WG' /etc /usr/local /root 2>/dev/null | grep -v -E "g7-persist-backup|/usr/local/sbin/g7-firewall.sh|g7-netdump" || true)"
if [[ -n "$found" ]]; then note "found in:"; printf '      %s\n' $found; note "(left as is; g7-firewall.sh rebuilds the same rules, so both agree)"
else note "NOT saved anywhere — they exist only in memory and would be lost on reboot"; fi
iptables-save > /root/iptables-before-persist-$(date +%Y%m%d-%H%M%S).rules 2>/dev/null || true

FW=/usr/local/sbin/g7-firewall.sh
FW_BODY=$(cat <<'EOF'
#!/usr/bin/env bash
# g7-firewall.sh — G7 WireGuard forwarding + per-peer restrictions. Idempotent; installed by persist-g7.sh.
# Runs at boot, after wg0 comes up, and after every Docker restart.
set -eu
IPT=/usr/sbin/iptables
WAN=enp59s0; WG=wg0; VPN=10.77.0.0/24
AP_NAT=__AP_NAT__

rm_rule(){ local t="$1"; shift; local c="$1"; shift; while $IPT -t "$t" -C "$c" "$@" 2>/dev/null; do $IPT -t "$t" -D "$c" "$@"; done; }
chain(){ $IPT -N "$1" 2>/dev/null || true; $IPT -F "$1"; }

# Docker owns DOCKER-USER; create it if Docker isn't up yet (Docker keeps an existing one).
$IPT -N DOCKER-USER 2>/dev/null || true
$IPT -C FORWARD -j DOCKER-USER 2>/dev/null || $IPT -I FORWARD 1 -j DOCKER-USER

# Per-peer chains
chain WG-WILL      # Will 10.77.0.31: LAN + internet; no Docker nets, no other VPN clients
$IPT -A WG-WILL -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
$IPT -A WG-WILL -d 172.16.0.0/12 -j DROP
$IPT -A WG-WILL -d $VPN -j DROP
$IPT -A WG-WILL -o $WAN -j ACCEPT
$IPT -A WG-WILL -j DROP

chain WG-FRANK     # Frank 10.77.0.32: 192.168.0.100 + internet only
$IPT -A WG-FRANK -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
$IPT -A WG-FRANK -d 192.168.0.100/32 -j ACCEPT
for n in 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 169.254.0.0/16 100.64.0.0/10; do $IPT -A WG-FRANK -d $n -j DROP; done
$IPT -A WG-FRANK -o $WAN -j ACCEPT
$IPT -A WG-FRANK -j DROP

chain TG-WG        # tg1/tg2 10.77.0.20-21: TaxGlasses proxy 10.77.0.1:8090 only
$IPT -A TG-WG -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
$IPT -A TG-WG -p tcp -m conntrack --ctorigdst 10.77.0.1 --ctorigdstport 8090 -j ACCEPT
$IPT -A TG-WG -j DROP

# DOCKER-USER, in this exact order (restricted peers must be matched before the general VPN accept)
rm_rule filter DOCKER-USER -s 10.77.0.31/32 -j WG-WILL
rm_rule filter DOCKER-USER -s 10.77.0.32/32 -j WG-FRANK
rm_rule filter DOCKER-USER -s 10.77.0.20/31 -j TG-WG
rm_rule filter DOCKER-USER -d $VPN -i $WAN -o $WG -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
rm_rule filter DOCKER-USER -s $VPN -i $WG -o $WAN -j ACCEPT
$IPT -I DOCKER-USER 1 -s $VPN -i $WG -o $WAN -j ACCEPT
$IPT -I DOCKER-USER 1 -d $VPN -i $WAN -o $WG -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
$IPT -I DOCKER-USER 1 -s 10.77.0.20/31 -j TG-WG
$IPT -I DOCKER-USER 1 -s 10.77.0.32/32 -j WG-FRANK
$IPT -I DOCKER-USER 1 -s 10.77.0.31/32 -j WG-WILL

# Restricted peers can't talk to G7 itself (SSH, Jenkins, Git, MemeSniper dashboard).
# tg1/tg2 still reach TaxGlasses: 10.77.0.1:8090 is DNAT'd to the container, so it goes through FORWARD, not INPUT.
for src in 10.77.0.31/32 10.77.0.32/32 10.77.0.20/31; do
  rm_rule filter INPUT -s $src -i $WG -j DROP
  $IPT -I INPUT 1 -s $src -i $WG -j DROP
done

# NAT for VPN clients (wg0.conf PostUp adds the same rule; -C keeps it to one copy)
$IPT -t nat -C POSTROUTING -s $VPN -o $WAN -j MASQUERADE 2>/dev/null || $IPT -t nat -A POSTROUTING -s $VPN -o $WAN -j MASQUERADE

if [ "$AP_NAT" = 1 ]; then   # CrackCookingKitchen Wi-Fi clients → internet
  $IPT -t nat -C POSTROUTING -s 192.168.4.0/24 -o $WAN -j MASQUERADE 2>/dev/null || $IPT -t nat -A POSTROUTING -s 192.168.4.0/24 -o $WAN -j MASQUERADE
  $IPT -C DOCKER-USER -s 192.168.4.0/24 -i wlp0s20f3 -o $WAN -j ACCEPT 2>/dev/null || $IPT -A DOCKER-USER -s 192.168.4.0/24 -i wlp0s20f3 -o $WAN -j ACCEPT
  $IPT -C DOCKER-USER -d 192.168.4.0/24 -i $WAN -o wlp0s20f3 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || $IPT -A DOCKER-USER -d 192.168.4.0/24 -i $WAN -o wlp0s20f3 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
fi
echo "g7-firewall: rules in place"
EOF
)
FW_BODY="${FW_BODY//__AP_NAT__/$AP_NAT}"

UNIT=/etc/systemd/system/g7-firewall.service
UNIT_BODY="[Unit]
Description=G7 WireGuard peer restrictions and NAT
After=network-online.target docker.service wg-quick@wg0.service
Wants=network-online.target
PartOf=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=$FW

[Install]
WantedBy=multi-user.target docker.service"
WGDROP=/etc/systemd/system/wg-quick@wg0.service.d/g7-firewall.conf
WGDROP_BODY="# Re-apply peer restrictions the moment wg0 comes up, so restricted peers never get a window of full access.
[Service]
ExecStartPost=$FW"

install_file(){ # path mode content
  if [[ -f "$1" && "$(cat "$1")" == "$3" ]]; then note "$1 already correct"; return; fi
  if (( DRY )); then note "would write $1"; return; fi
  backup "$1"; mkdir -p "$(dirname "$1")"; printf '%s\n' "$3" > "$1"; chmod "$2" "$1"; note "wrote $1"
}

say "1. Firewall script + boot hooks"
if (( NO_FW )); then note "skipped (--no-firewall)"; else
install_file "$FW" 755 "$FW_BODY"
install_file "$UNIT" 644 "$UNIT_BODY"
install_file "$WGDROP" 644 "$WGDROP_BODY"
(( AP_NAT )) && note "AP NAT for 192.168.4.0/24 included" || note "AP NAT not included (add --ap-nat if Wi-Fi clients need internet)"
if (( ! DRY )); then
  bash -n "$FW"
  systemctl daemon-reload
  systemctl enable g7-firewall.service >/dev/null
  "$FW"
  systemctl start g7-firewall.service
fi
fi

say "2. DNS (/etc/resolv.conf)"
if grep -q '^nameserver' /etc/resolv.conf 2>/dev/null; then note "already has a nameserver"
elif (( DRY )); then note "would write 'nameserver 192.168.0.1' and stop dhcpcd from overwriting it"
else
  backup /etc/resolv.conf
  [[ -L /etc/resolv.conf ]] && rm -f /etc/resolv.conf
  printf '# Static — managed by hand (persist-g7.sh)\nnameserver 192.168.0.1\nnameserver 127.0.0.1\n' > /etc/resolv.conf
  note "wrote /etc/resolv.conf"
fi
if [[ -f /etc/dhcpcd.conf ]] && ! grep -q '^nohook resolv.conf' /etc/dhcpcd.conf; then
  if (( DRY )); then note "would add 'nohook resolv.conf' to /etc/dhcpcd.conf"
  else backup /etc/dhcpcd.conf; echo 'nohook resolv.conf' >> /etc/dhcpcd.conf; note "dhcpcd will no longer rewrite resolv.conf"; fi
fi

say "3. Services that should start on boot"
for u in wg-quick@wg0.service hostapd dnsmasq docker containerd ssh jenkins memesniper \
         guatemalahope-mirror.timer aeraphim-mirror.timer taxglasses-mirror.timer; do
  systemctl cat "$u" >/dev/null 2>&1 || { note "$u: not installed (skip)"; continue; }
  act=$(systemctl is-active "$u" 2>/dev/null || true); en=$(systemctl is-enabled "$u" 2>/dev/null || true)
  if [[ "$act" == active && "$en" != enabled && "$en" != static && "$en" != alias ]]; then
    if [[ "$en" == masked ]]; then (( DRY )) && note "$u: running but MASKED — would unmask + enable" || { systemctl unmask "$u"; systemctl enable "$u" >/dev/null; note "$u: unmasked + enabled"; }
    else (( DRY )) && note "$u: running but $en — would enable" || { systemctl enable "$u" >/dev/null; note "$u: enabled"; }; fi
  else note "$u: $act / $en"; fi
done

say "4. TaxGlasses containers restart on boot"
for c in taxglasses-proxy-1 taxglasses-blue-1 taxglasses-green-1; do
  pol=$(docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' "$c" 2>/dev/null || echo missing)
  case "$pol" in
    always|unless-stopped) note "$c: $pol" ;;
    missing) note "$c: not found" ;;
    *) (( DRY )) && note "$c: restart=$pol — would set unless-stopped" || { docker update --restart unless-stopped "$c" >/dev/null; note "$c: set to unless-stopped"; } ;;
  esac
done
note "Also set 'restart: unless-stopped' in TaxGlasses' docker-compose file, or a future 'compose up' will undo this."

say "Done"
if (( DRY )); then note "re-run without --dry-run to apply"; exit 0; fi
note "backups of changed files: $BK"
note "check: sudo iptables -S DOCKER-USER   (WG-WILL, WG-FRANK, TG-WG must be the first three lines)"
note "then reboot with the PiKVM handy, and run: sudo systemctl status g7-firewall; sudo wg show; sudo iptables -S DOCKER-USER"
