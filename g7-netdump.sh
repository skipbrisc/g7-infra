#!/usr/bin/env bash
# g7-netdump.sh — read-only snapshot of G7's network, WireGuard, firewall and Docker setup.
# Private keys, preshared keys, Wi-Fi passphrases and DuckDNS tokens are replaced with <REDACTED>.
# Run: sudo bash g7-netdump.sh > /tmp/g7-netdump.txt
redact() { sed -E \
  -e 's/^([[:space:]]*(PrivateKey|PresharedKey)[[:space:]]*=[[:space:]]*).*/\1<REDACTED>/I' \
  -e 's/^([[:space:]]*(wpa_passphrase|wpa_psk|sae_password)[[:space:]]*=).*/\1<REDACTED>/I' \
  -e 's/(token=)[A-Za-z0-9-]+/\1<REDACTED>/Ig' \
  -e 's/(preshared key: ).*/\1<REDACTED>/I'; }
sec() { printf '\n===== %s =====\n' "$*"; }
showfiles() { for f in "$@"; do [ -f "$f" ] && { echo "--- $f"; redact < "$f"; }; done; }

sec "host";            hostnamectl 2>/dev/null | grep -E 'hostname|Operating|Kernel'; date -Is
sec "interfaces";      ip -br addr
sec "links";           ip -br link
sec "routes";          ip route; ip -6 route 2>/dev/null | head -20
sec "policy rules";    ip rule
sec "/etc/network";    showfiles /etc/network/interfaces /etc/network/interfaces.d/*
sec "resolv";          showfiles /etc/resolv.conf
sec "sysctl";          sysctl net.ipv4.ip_forward net.ipv6.conf.all.forwarding 2>/dev/null; showfiles /etc/sysctl.d/*.conf
sec "wireguard live";  wg show all 2>/dev/null | redact
sec "wireguard conf";  showfiles /etc/wireguard/*.conf
sec "wireguard other"; find /etc/wireguard -maxdepth 3 -type f ! -name '*.conf' 2>/dev/null | grep -v -i -E 'priv|key$' ; \
                       for f in $(find /etc/wireguard -mindepth 2 -maxdepth 3 -name '*.conf' 2>/dev/null); do echo "--- $f"; redact < "$f"; done
sec "wg services";     systemctl list-units --all --no-pager 'wg-quick@*' 2>/dev/null; systemctl is-enabled wg-quick@wg0 2>/dev/null
sec "access point";    showfiles /etc/hostapd/hostapd.conf /etc/default/hostapd; systemctl is-active hostapd 2>/dev/null
sec "dhcp/dns";        showfiles /etc/dnsmasq.conf /etc/dnsmasq.d/* /etc/dhcp/dhcpd.conf /etc/default/isc-dhcp-server; \
                       for s in dnsmasq isc-dhcp-server; do printf '%s: %s\n' "$s" "$(systemctl is-active $s 2>/dev/null)"; done
sec "duckdns";         crontab -l 2>/dev/null | redact; ls /etc/cron.d 2>/dev/null; showfiles /etc/cron.d/*duck* /opt/duckdns/*.sh /root/duckdns/*.sh
sec "nftables conf";   showfiles /etc/nftables.conf /etc/nftables.d/*
sec "nft ruleset";     nft list ruleset 2>/dev/null
sec "iptables-save";   iptables-save 2>/dev/null
sec "ip6tables-save";  ip6tables-save 2>/dev/null | head -60
sec "ufw";             ufw status verbose 2>/dev/null || echo "ufw not installed"
sec "firewalld";       systemctl is-active firewalld 2>/dev/null || true
sec "docker daemon";   showfiles /etc/docker/daemon.json; docker version --format 'docker {{.Server.Version}}' 2>/dev/null
sec "docker networks"; docker network ls 2>/dev/null; for n in $(docker network ls -q 2>/dev/null); do \
                         docker network inspect "$n" --format '{{.Name}} driver={{.Driver}} subnet={{range .IPAM.Config}}{{.Subnet}} gw={{.Gateway}} {{end}}containers={{range .Containers}}{{.Name}}:{{.IPv4Address}} {{end}}'; done
sec "docker containers"; docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null
sec "listening ports"; ss -tlnup | sed -E 's/users:.*\(\("([^"]+)".*/\1/'
sec "sshd";            sshd -T 2>/dev/null | grep -E '^(port|listenaddress|passwordauthentication|permitrootlogin|pubkeyauthentication|allowusers) '
