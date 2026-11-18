# G7 (buttserver): network, WireGuard, firewall and Docker

Snapshot taken **2026-11-18 14:25 PST** from the live server (`g7-netdump.txt` in this folder is
the raw source). No private keys, preshared keys, Wi-Fi passwords or tokens are in this file,
only where they live on G7. The overview of G7, Miami and the home network together is
[INFRA.md](INFRA.md).

To refresh this snapshot later, from `D:\g7-infra`:

    scp g7-netdump.sh g7:/tmp/g7-netdump.sh
    ssh -t g7 "sudo bash /tmp/g7-netdump.sh > /tmp/g7-netdump.txt; sudo chmod 644 /tmp/g7-netdump.txt"
    scp g7:/tmp/g7-netdump.txt g7-netdump.txt
    ssh -t g7 "sudo rm -f /tmp/g7-netdump.sh /tmp/g7-netdump.txt"

---

## 1. Host

| | |
|---|---|
| Hostname | `buttserver` (G7) |
| OS | Debian 13 (trixie), kernel 6.12.113+deb13-amd64 |
| Admin user | `buttmud` (sudo with password) |
| Network manager | **ifupdown** (`/etc/network/interfaces`), not systemd-networkd or NetworkManager |
| Public DNS name | `buttmud.duckdns.org`, kept current by G7's `duckdns.timer` (every 2 minutes; token in `/etc/duckdns.conf`) |
| Out-of-band | PiKVM at 192.168.0.100 (keyboard, screen, power); SSH also reachable on port **1337** through it |

## 2. Interfaces and addresses

| Interface | Address | Role |
|---|---|---|
| `enp59s0` (wired, MAC 3c:2c:30:c6:15:e7) | **192.168.0.6/24**, gateway and DNS 192.168.0.1 | Uplink to the home router; everything leaves G7 here |
| `wlp0s20f3` (Wi-Fi, MAC 98:3b:8f:01:84:a7) | **192.168.4.1/24** | Access point **CrackCookingKitchen** |
| `wg0` | **10.77.0.1/24** | G7 VPN server |
| `wg-mia` | **10.78.0.2/32** | Private link to Miami (10.78.0.1) |
| `docker0` | 172.17.0.1/16 (no containers, link down) | Docker default bridge |
| `br-0218e6ba6111` | 172.18.0.1/16 | Docker network `taxglasses_default` |
| `br-0cf6f2132494` | 172.19.0.1/16 | Docker network `ntfy_default` |
| `br-caffe30fae00` | 172.30.77.1/24 | Docker network `vaultwarden_net` |

IPv6: link-local addresses only, forwarding off.

### `/etc/network/interfaces`
```
source /etc/network/interfaces.d/*

auto lo
iface lo inet loopback

# Wired uplink — takes over 192.168.0.6
auto enp59s0
iface enp59s0 inet static
    address 192.168.0.6/24
    gateway 192.168.0.1
    dns-nameservers 192.168.0.1

# Wifi as access point — static, no DHCP client
auto wlp0s20f3
iface wlp0s20f3 inet static
    address 192.168.4.1/24
```
`/etc/network/interfaces.d/` is empty.

### Routes
```
default via 192.168.0.1 dev enp59s0 onlink
10.77.0.0/24    dev wg0              src 10.77.0.1
10.78.0.0/24    dev wg-mia
172.17.0.0/16   dev docker0          src 172.17.0.1 linkdown
172.18.0.0/16   dev br-0218e6ba6111  src 172.18.0.1
172.19.0.0/16   dev br-0cf6f2132494  src 172.19.0.1
172.30.77.0/24  dev br-caffe30fae00  src 172.30.77.1
192.168.0.0/24  dev enp59s0          src 192.168.0.6
192.168.4.0/24  dev wlp0s20f3        src 192.168.4.1
```
No policy routing: only the standard `local`, `main` and `default` rules.

### DNS (`/etc/resolv.conf`)
Static, written by `persist-g7.sh`: `nameserver 192.168.0.1`, then `nameserver 127.0.0.1`.

### Kernel settings (`/etc/sysctl.d/`)
| File | Setting |
|---|---|
| `90-wireguard-forwarding.conf` | `net.ipv4.ip_forward = 1` |
| `99-ap-forward.conf` | `net.ipv4.ip_forward=1` (duplicate, harmless) |
| `90-nonlocal-bind.conf` | `net.ipv4.ip_nonlocal_bind=1`: lets Docker bind to 10.77.0.1 before wg0 is up at boot |

---

## 3. WireGuard

### `wg0`: the G7 VPN

| | |
|---|---|
| Config | `/etc/wireguard/wg0.conf` |
| Service | `wg-quick@wg0` (enabled), started after Docker (drop-ins in `systemd/wg-quick@wg0.service.d/`) |
| Listen port | **UDP 51820** (the router forwards it to 192.168.0.6) |
| Subnet | 10.77.0.0/24, server = 10.77.0.1 |
| Server public key | `tanf/9aIsqo1b1Xm0dydGczTn1yblvG4tDekcPr1+zU=` (also in `/etc/wireguard/server.pub`) |
| Server private key | `wg0.conf` `[Interface] PrivateKey`; in the nightly backup. Losing it means re-issuing every client |
| Mode | Full tunnel: clients send all internet traffic through G7, NAT'd out `enp59s0` |

| VPN IP | Name (config comment) | Public key | Access | Last handshake at snapshot |
|---|---|---|---|---|
| 10.77.0.2 | Phone | `/+RI8n0Dp7SnzUDUa21aIzJuM/RxSWdOAQ2py9FMdDk=` | Everything (G7, LAN, internet) | 1 minute ago |
| 10.77.0.3 | Laptop | `yr+gwphzZc/qocxjaTf2Bsnf6Rsk26RddaTHp86Zehk=` | Everything | 15 days ago |
| 10.77.0.20 | tg1 – TaxGlasses | `c3ak6I6b01+oRGIUWCShIMTSV0cGoOUip1zzhs6bayw=` | **Only** TaxGlasses at 10.77.0.1:8090 | 14 days ago |
| 10.77.0.21 | tg2 – TaxGlasses | `ju0So/hWI4pEbTuIezEl6FHWHYgZCioTb5ecd5k1fgo=` | **Only** TaxGlasses at 10.77.0.1:8090 | never |
| 10.77.0.31 | Will | `8k7gke0JRt8Pz9rWR7Ese/LNH2/DHyzaUn/RqTKC5w0=` | Home LAN + internet. Blocked from G7 itself (every service on it), other VPN clients, Docker networks and the Miami link | never |
| 10.77.0.32 | Frank | `+3Li7qmzDw6PftOk22wM/eC79IDqLJE55u812WHB4xI=` | 192.168.0.100 + internet only. Blocked from G7 itself and every other private range | never |

Will and Frank also have Miami VPN logins (10.78.0.31 and .32, see `mia/README.md`).

### `wg0.conf` (private key removed)
```ini
[Interface]
Address = 10.77.0.1/24
ListenPort = 51820
PrivateKey = <in /etc/wireguard/wg0.conf on G7>
PostUp = /usr/sbin/iptables -C DOCKER-USER -i wg0 -o enp59s0 -s 10.77.0.0/24 -j ACCEPT || /usr/sbin/iptables -I DOCKER-USER 1 -i wg0 -o enp59s0 -s 10.77.0.0/24 -j ACCEPT
PostUp = /usr/sbin/iptables -C DOCKER-USER -i enp59s0 -o wg0 -d 10.77.0.0/24 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT || /usr/sbin/iptables -I DOCKER-USER 1 -i enp59s0 -o wg0 -d 10.77.0.0/24 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
PostUp = /usr/sbin/iptables -t nat -C POSTROUTING -s 10.77.0.0/24 -o enp59s0 -j MASQUERADE || /usr/sbin/iptables -t nat -A POSTROUTING -s 10.77.0.0/24 -o enp59s0 -j MASQUERADE

[Peer]
# Phone
PublicKey = /+RI8n0Dp7SnzUDUa21aIzJuM/RxSWdOAQ2py9FMdDk=
AllowedIPs = 10.77.0.2/32

[Peer]
# Laptop
PublicKey = yr+gwphzZc/qocxjaTf2Bsnf6Rsk26RddaTHp86Zehk=
AllowedIPs = 10.77.0.3/32

[Peer]
# tg1 - TaxGlasses
PublicKey = c3ak6I6b01+oRGIUWCShIMTSV0cGoOUip1zzhs6bayw=
AllowedIPs = 10.77.0.20/32

[Peer]
# tg2 - TaxGlasses
PublicKey = ju0So/hWI4pEbTuIezEl6FHWHYgZCioTb5ecd5k1fgo=
AllowedIPs = 10.77.0.21/32

[Peer]
# will - full LAN + internet
PublicKey = 8k7gke0JRt8Pz9rWR7Ese/LNH2/DHyzaUn/RqTKC5w0=
AllowedIPs = 10.77.0.31/32

[Peer]
# frank - 192.168.0.100 only + internet
PublicKey = +3Li7qmzDw6PftOk22wM/eC79IDqLJE55u812WHB4xI=
AllowedIPs = 10.77.0.32/32
```

Older copies on G7 (each holds the private key; root only): `wg0.conf.bak`, `.bak2`–`.bak5`,
`.bak-2026-11-02`, `.bak-2026-11-04`, `.before-nat`.

### `wg-mia`: the private link to Miami

| | |
|---|---|
| Config | `/etc/wireguard/wg-mia.conf` (in Git as `etc/wireguard/wg-mia.conf`, key removed) |
| Service | `wg-quick@wg-mia` (enabled) |
| G7's address | 10.78.0.2/32 |
| G7's public key | `4VsHYGh0a7w+94lAN68DKLmbCx7d5nPE66492l50LQM=` (also in `/etc/wireguard/wg-mia.pub`) |
| Miami | `1nAO0AqhzYKl4Wbey0h9vJlykQc/hbUWiy5hT0MCFmE=` at 38.126.208.251:51820 |
| Routed through it | 10.78.0.0/24 only; G7's own default route stays on `enp59s0` |
| Keepalive | 25 seconds; G7 dials out, so nothing is forwarded at home for it. Its local port is picked at start (52938 at the snapshot) |
| Carries | G7's off-site backup to the restic REST server at 10.78.0.1:8000 |

```ini
[Interface]
PrivateKey = <in /etc/wireguard/wg-mia.conf on G7>
Address = 10.78.0.2/32

[Peer]
PublicKey = 1nAO0AqhzYKl4Wbey0h9vJlykQc/hbUWiy5hT0MCFmE=
Endpoint = 38.126.208.251:51820
AllowedIPs = 10.78.0.0/24
PersistentKeepalive = 25
```

Only G7 itself uses this link. Miami accepts only 10.78.0.2 from G7's key, its firewall forwards
its own VPN clients to the internet and nowhere else (so they cannot reach G7 through it), and
its backup port answers 10.78.0.2 only. G7 VPN clients cannot use it either: Miami drops any
source other than 10.78.0.2.

### Client config template (G7 VPN)
Each client's private key lives only on that device.
```ini
[Interface]
PrivateKey = <client's own private key>
Address = 10.77.0.X/32
DNS = 192.168.0.1

[Peer]
PublicKey = tanf/9aIsqo1b1Xm0dydGczTn1yblvG4tDekcPr1+zU=
Endpoint = buttmud.duckdns.org:51820
AllowedIPs = 0.0.0.0/0          # full tunnel
PersistentKeepalive = 25
```
At home on the LAN, leave WireGuard off and use 192.168.0.6 directly. Away, WireGuard routes
192.168.0.6 too, so the same address works everywhere.

### Adding a peer
```bash
wg genkey | tee client.key | wg pubkey > client.pub      # on the client, or on G7 then move the key
sudo wg set wg0 peer "$(cat client.pub)" allowed-ips 10.77.0.X/32    # live
# then add a matching [Peer] block to /etc/wireguard/wg0.conf so it survives a restart
```
A peer with limited access also needs its own chain in `etc/sbin/taxglasses-fw.sh` (see section 5).
Commit both to g7-infra.

---

## 4. Access point (CrackCookingKitchen)

| | |
|---|---|
| Config | `/etc/hostapd/hostapd.conf` (service `hostapd`, active) |
| SSID | `CrackCookingKitchen` |
| Band / channel | 2.4 GHz (`hw_mode=g`), channel 6, 802.11n HT40- (the card refuses 5 GHz) |
| Security | WPA2-PSK, CCMP, country US |
| Password | `wpa_passphrase` in `hostapd.conf` |
| DHCP + DNS | dnsmasq, `/etc/dnsmasq.d/ap.conf` (service `dnsmasq`, active) |
| DHCP range | 192.168.4.10 – 192.168.4.200, 24h leases |
| Gateway / DNS handed out | 192.168.4.1 |
| Upstream DNS | 192.168.0.1 |
| Internet for its clients | **Not loaded**: no NAT rule for 192.168.4.0/24 (section 8, item 1) |

`/etc/dnsmasq.d/ap.conf`:
```
interface=wlp0s20f3
bind-interfaces
dhcp-range=192.168.4.10,192.168.4.200,255.255.255.0,24h
dhcp-option=3,192.168.4.1
dhcp-option=6,192.168.4.1
server=192.168.0.1
```

---

## 5. Firewall

Everything is in **iptables (nf_tables backend)**. There is no ufw, no firewalld, and
`/etc/nftables.conf` is empty. Three sources write the rules:

1. **Docker**: its own `DOCKER*` chains, port publishing and NAT.
2. **`wg0.conf` PostUp**: VPN forwarding and NAT (shown above).
3. **`/usr/local/sbin/taxglasses-fw.sh`**, run by `taxglasses-fw.service` (enabled;
   `After=docker.service wg-quick@wg0.service`, re-runs whenever wg0 restarts): builds the per-peer
   chains `WG-WILL`, `WG-FRANK` and `TG-WG`, pins their jumps to the top of `DOCKER-USER`, and adds
   the `INPUT` drops.

`/usr/local/sbin/ap-firewall.sh` (the access point's NAT) is installed and matches Git, but nothing
runs it, and its rules are not loaded (section 8, item 1).

All policies are ACCEPT; the restrictions are explicit DROP rules. The VPN rules live in Docker's
`DOCKER-USER` chain, because Docker evaluates it first on forwarded traffic.

### Filter table
```
INPUT  (traffic to G7 itself)
  -s 10.77.0.31   -i wg0 -j DROP      Will    → nothing on G7
  -s 10.77.0.32   -i wg0 -j DROP      Frank   → nothing on G7
  -s 10.77.0.20/31 -i wg0 -j DROP     tg1/tg2 → nothing on G7 directly

FORWARD
  -j DOCKER-USER
  -j DOCKER-FORWARD

DOCKER-USER
  -s 10.77.0.31     -j WG-WILL
  -s 10.77.0.32     -j WG-FRANK
  -s 10.77.0.20/31  -j TG-WG
  -d 10.77.0.0/24 -i enp59s0 -o wg0 ESTABLISHED,RELATED -j ACCEPT    replies back to VPN clients
  -s 10.77.0.0/24 -i wg0 -o enp59s0 -j ACCEPT                         VPN clients out to LAN/internet

TG-WG   (tg1, tg2)
  ESTABLISHED,RELATED -j ACCEPT
  tcp, original destination 10.77.0.1:8090 -j ACCEPT                 TaxGlasses proxy only
  -j DROP

WG-WILL
  ESTABLISHED,RELATED -j ACCEPT
  -d 172.16.0.0/12 -j DROP                                            Docker networks
  -d 10.77.0.0/24  -j DROP                                            other VPN clients
  -o enp59s0       -j ACCEPT                                          LAN + internet
  -j DROP                                                             anything else, incl. wg-mia

WG-FRANK
  ESTABLISHED,RELATED -j ACCEPT
  -d 192.168.0.100 -j ACCEPT
  -d 10.0.0.0/8 / 172.16.0.0/12 / 192.168.0.0/16 / 169.254.0.0/16 / 100.64.0.0/10 -j DROP
  -o enp59s0       -j ACCEPT                                          internet
  -j DROP
```

Docker-published ports are reached by forwarding to a 172.x container address after Docker's
redirect, so the 172.16.0.0/12 drops are what keep Will and Frank out of TaxGlasses, Vaultwarden
and ntfy even on 192.168.0.6.

### NAT table
```
POSTROUTING
  -s 10.77.0.0/24   -o enp59s0                -j MASQUERADE   G7 VPN clients → internet (wg0 PostUp)
  -s 172.17.0.0/16  ! -o docker0              -j MASQUERADE   Docker default bridge
  -s 172.18.0.0/16  ! -o br-0218e6ba6111      -j MASQUERADE   taxglasses_default
  -s 172.19.0.0/16  ! -o br-0cf6f2132494      -j MASQUERADE   ntfy_default
  -s 172.30.77.0/24 ! -o br-caffe30fae00      -j MASQUERADE   vaultwarden_net

DOCKER (port publishing)
  127.0.0.1:2586   → 172.19.0.2:80      ntfy (G7's own jobs)
  192.168.0.6:2586 → 172.19.0.2:80      ntfy (phone app)
  192.168.0.6:443  → 172.30.77.3:443    vaultwarden-caddy (Vaultwarden over HTTPS)
  10.77.0.1:8090   → 172.18.0.3:8090    taxglasses-proxy-1 (Caddy, VPN)
  192.168.0.6:8090 → 172.18.0.3:8090    taxglasses-proxy-1 (Caddy, LAN)
  10.77.0.1:8091   → 172.18.0.2:8090    taxglasses-blue-1
  10.77.0.1:8092   → 172.18.0.4:8090    taxglasses-green-1
```

Docker also adds `raw` PREROUTING drops so the container addresses (172.18.0.2–.4, 172.19.0.2,
172.30.77.2–.3) and 127.0.0.1:2586 can't be hit directly from outside their bridge.

### Router (192.168.0.1)
- UDP **51820** forwarded to 192.168.0.6 (G7 VPN).
- The PiKVM's HTTPS page forwarded to 192.168.0.100 (remote keyboard, screen and power).
- DHCP reservation: PiKVM at 192.168.0.100. G7's 192.168.0.6 is set on G7 itself.
- Nothing else should be forwarded. SSH, Jenkins and every other G7 service are LAN/VPN only.

---

## 6. Docker

| | |
|---|---|
| Version | Docker 29.9.2 |
| `/etc/docker/daemon.json` | none (defaults; Docker manages iptables) |

| Network | Subnet | Containers |
|---|---|---|
| `bridge` (docker0) | 172.17.0.0/16 | none |
| `taxglasses_default` (br-0218e6ba6111) | 172.18.0.0/16 | blue 172.18.0.2, proxy 172.18.0.3, green 172.18.0.4 |
| `ntfy_default` (br-0cf6f2132494) | 172.19.0.0/16 | ntfy 172.19.0.2 |
| `vaultwarden_net` (br-caffe30fae00) | 172.30.77.0/24 | vaultwarden 172.30.77.2, vaultwarden-caddy 172.30.77.3 |
| `host` | G7's own addresses | grafana, uptime-kuma |

| Container | Image | Published on | Role |
|---|---|---|---|
| `taxglasses-proxy-1` | `caddy:2-alpine` | 10.77.0.1:8090, 192.168.0.6:8090 | TaxGlasses front door; switches blue/green |
| `taxglasses-blue-1` | `taxglasses:blue` | 10.77.0.1:8091 | Blue slot |
| `taxglasses-green-1` | `taxglasses:green` | 10.77.0.1:8092 | Green slot |
| `vaultwarden` | `vaultwarden/server:latest` | not published | Vaultwarden server (`/srv/vaultwarden`) |
| `vaultwarden-caddy` | `vaultwarden-caddy:local` | 192.168.0.6:443 | HTTPS for `buttvault.duckdns.org` (Let's Encrypt via DuckDNS) |
| `ntfy-ntfy-1` | `binwiederhier/ntfy` | 127.0.0.1:2586, 192.168.0.6:2586 | Phone alerts (`/opt/ntfy`) |
| `uptime-kuma-uptime-kuma-1` | `louislam/uptime-kuma:2` | host network, 192.168.0.6:3001 | Service checks (`/opt/uptime-kuma`) |
| `grafana-grafana-1` | `grafana/grafana:13.3.1` | host network, 192.168.0.6:3000 | Dashboards (`g7/monitoring/grafana/`) |
| `vibrant_mahavira` | `hello-world` | — | Leftover test container, exited; safe to remove |

Prometheus, Alertmanager and the two exporters are Debian packages, not containers (section 7).

---

## 7. Listening services

| Port | Bound to | Service | Who can reach it |
|---|---|---|---|
| UDP 51820 | all | WireGuard `wg0` | Internet (router forward) |
| UDP 52938 | all | WireGuard `wg-mia` (G7's end of the Miami link; port picked at start) | Miami replies only |
| TCP 3333 | all (v4 + v6) | sshd | LAN, AP Wi-Fi, phone and laptop on the VPN |
| TCP 8080 | all | Jenkins | LAN, AP Wi-Fi, phone and laptop |
| TCP 443 | 192.168.0.6 | Vaultwarden (`https://buttvault.duckdns.org`) | LAN, AP Wi-Fi, phone and laptop |
| TCP 2586 | 192.168.0.6, 127.0.0.1 | ntfy | LAN, AP Wi-Fi, phone and laptop; G7's own jobs |
| TCP 3000 | 192.168.0.6 | Grafana | LAN, AP Wi-Fi, phone and laptop |
| TCP 3001 | 192.168.0.6 | Uptime Kuma | LAN, AP Wi-Fi, phone and laptop |
| TCP 8090 | 10.77.0.1, 192.168.0.6 | TaxGlasses (Caddy proxy) | LAN, AP Wi-Fi, phone and laptop; tg1/tg2 on 10.77.0.1 only |
| TCP 8091 / 8092 | 10.77.0.1 | TaxGlasses blue / green direct | Phone and laptop |
| TCP 8765 | 10.77.0.1 | MemeSniper monitor dashboard (python) | Phone and laptop |
| TCP 9090 | 127.0.0.1 | Prometheus | G7 only |
| TCP 9093 | 127.0.0.1 | Alertmanager (no cluster port) | G7 only |
| TCP 9100 | 127.0.0.1 | node exporter | G7 only |
| TCP 9256 | 127.0.0.1 | process exporter | G7 only |
| 53 TCP/UDP | 127.0.0.1, ::1, 192.168.4.1 | dnsmasq DNS | G7 itself, AP Wi-Fi |
| UDP 67 | wlp0s20f3 | dnsmasq DHCP | AP Wi-Fi |

Will, Frank, tg1 and tg2 reach none of these except tg1/tg2 to 10.77.0.1:8090. Anything bound to
192.168.0.6 is also reachable from the AP Wi-Fi, because G7 answers on any of its addresses
whichever interface a packet arrives on.

### SSH (`sshd -T`)
```
port 3333
listenaddress 0.0.0.0:3333 / [::]:3333
pubkeyauthentication yes
passwordauthentication no          (key-only since 2026-11-12, etc/ssh/00-key-only.conf)
permitrootlogin without-password   (root by key only)
```
The `git` account has no usable password and accepts keys only (`/srv/git/.ssh/authorized_keys`).

---

## 8. Things worth knowing / fixing

1. **AP Wi-Fi clients probably have no internet.** There is no MASQUERADE rule for 192.168.4.0/24
   out `enp59s0`. `ap-firewall.sh` would add it, and `persist-g7.sh --ap-nat` would have made it
   permanent, but neither is run at boot, so the rule has been missing since at least 2026-11-05.
   Phones on CrackCookingKitchen can reach G7 but, unless the router has a static route for
   192.168.4.0/24 → 192.168.0.6, not the internet. Fine if that Wi-Fi is only for reaching G7;
   otherwise it needs a boot-time unit like `taxglasses-fw.service`.
2. **AP Wi-Fi clients can reach SSH, Jenkins and every 192.168.0.6 service.** Nothing restricts
   192.168.4.0/24. Fine if only you use that Wi-Fi; otherwise add INPUT drops for it.
3. **Root can log in by key.** `permitrootlogin without-password`. If nothing logs in as root
   directly (your access is `buttmud` + sudo), `PermitRootLogin no` closes it.
4. **Leftover container** `vibrant_mahavira` (hello-world, exited): `sudo docker rm vibrant_mahavira`.
5. Resolved since the 2026-11-05 snapshot: peer restrictions persist at boot
   (`taxglasses-fw.service`); `/etc/resolv.conf` is static; SSH passwords are off (2026-11-12);
   DuckDNS is updated by G7's `duckdns.timer`.

---

## 9. Backup and rebuild

The nightly backup (`g7/backup/`) holds all of `/etc`, including the WireGuard private keys, the
Wi-Fi password and the DuckDNS token, on G7's backup disk and on Miami. Everything here except
those secrets is in this repository under `etc/` and `systemd/`, and the drift check compares it
with G7 every night.

To rebuild G7's network on a fresh Debian install, follow `REBUILD.md`: steps 1–3 are the
interfaces file, hostapd and dnsmasq, `wg0.conf` and `wg-mia.conf` (private keys from the
backup), the `wg-quick@wg0` drop-ins and the `duckdns` units; Docker and the containers come in
steps 4 and 6, and `taxglasses-fw.sh` with its service in step 9. Then check `sudo wg show` (both handshakes), `ss -tlnup`, and a
VPN client from outside.
