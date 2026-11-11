# G7 (buttserver) — Network, WireGuard, Firewall & Docker

Snapshot taken **2026-11-05 08:55 PST** from the live server (`g7-netdump.txt` in this folder is the raw source).
No private keys, preshared keys or Wi-Fi passwords are in this file — only where they live on G7. Keep those in your password manager.

To refresh this snapshot later: `sudo bash /tmp/g7-netdump.sh > /tmp/g7-netdump.txt` (script: `g7-netdump.sh` in this folder).

---

## 1. Host

| | |
|---|---|
| Hostname | `buttserver` (G7) |
| OS | Debian 13 (trixie), kernel 6.12.113+deb13-amd64 |
| Admin user | `buttmud` |
| Network manager | **ifupdown** (`/etc/network/interfaces`) — not systemd-networkd, not NetworkManager |
| Public DNS name | `buttmud.duckdns.org` |
| Out-of-band | PiKVM box, SSH also reachable on port **1337** through it |

## 2. Interfaces & addresses

| Interface | Address | Role |
|---|---|---|
| `enp59s0` (wired, MAC 3c:2c:30:c6:15:e7) | **192.168.0.6/24**, gateway 192.168.0.1, DNS 192.168.0.1 | Uplink to home router — everything leaves G7 here |
| `wlp0s20f3` (Wi-Fi, MAC 98:3b:8f:01:84:a7) | **192.168.4.1/24** | Access point **CrackCookingKitchen** |
| `wg0` | **10.77.0.1/24** | WireGuard VPN server |
| `docker0` | 172.17.0.1/16 (no containers, link down) | Docker default bridge |
| `br-0218e6ba6111` | 172.18.0.1/16 | Docker network `taxglasses_default` |

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

### Routes
```
default via 192.168.0.1 dev enp59s0 onlink
10.77.0.0/24    dev wg0              src 10.77.0.1
172.17.0.0/16   dev docker0          src 172.17.0.1 linkdown
172.18.0.0/16   dev br-0218e6ba6111  src 172.18.0.1
192.168.0.0/24  dev enp59s0          src 192.168.0.6
192.168.4.0/24  dev wlp0s20f3        src 192.168.4.1
```

### Kernel settings (`/etc/sysctl.d/`)
| File | Setting |
|---|---|
| `90-wireguard-forwarding.conf` | `net.ipv4.ip_forward = 1` |
| `99-ap-forward.conf` | `net.ipv4.ip_forward=1` (duplicate, harmless) |
| `90-nonlocal-bind.conf` | `net.ipv4.ip_nonlocal_bind=1` — lets Docker bind to 10.77.0.1 before wg0 is up at boot |

IPv6 forwarding is off.

---

## 3. WireGuard (`wg0`)

| | |
|---|---|
| Config | `/etc/wireguard/wg0.conf` |
| Service | `wg-quick@wg0` (enabled) |
| Listen port | **UDP 51820** (router must forward this to 192.168.0.6) |
| Subnet | 10.77.0.0/24, server = 10.77.0.1 |
| Server public key | `tanf/9aIsqo1b1Xm0dydGczTn1yblvG4tDekcPr1+zU=` (also in `/etc/wireguard/server.pub`) |
| Server private key | inside `wg0.conf` `[Interface] PrivateKey` — **back this up**, losing it means re-issuing every client |
| Mode | Full tunnel — clients send all internet traffic through G7, NAT'd out `enp59s0` |

### Peers

| VPN IP | Name (from config comment) | Public key | Access |
|---|---|---|---|
| 10.77.0.2 | Phone | `/+RI8n0Dp7SnzUDUa21aIzJuM/RxSWdOAQ2py9FMdDk=` | Everything (G7, LAN, internet) |
| 10.77.0.3 | Laptop | `yr+gwphzZc/qocxjaTf2Bsnf6Rsk26RddaTHp86Zehk=` | Everything |
| 10.77.0.20 | tg1 – TaxGlasses | `c3ak6I6b01+oRGIUWCShIMTSV0cGoOUip1zzhs6bayw=` | **Only** TaxGlasses at 10.77.0.1:8090 |
| 10.77.0.21 | tg2 – TaxGlasses | `ju0So/hWI4pEbTuIezEl6FHWHYgZCioTb5ecd5k1fgo=` | **Only** TaxGlasses at 10.77.0.1:8090 |
| 10.77.0.31 | Will | `8k7gke0JRt8Pz9rWR7Ese/LNH2/DHyzaUn/RqTKC5w0=` | Home LAN + internet. Blocked from G7 itself (Jenkins, SSH, Git, TaxGlasses, MemeSniper), other VPN clients, and Docker networks |
| 10.77.0.32 | Frank | `+3Li7qmzDw6PftOk22wM/eC79IDqLJE55u812WHB4xI=` | 192.168.0.100 + internet only. Blocked from G7 itself and every other private range |

tg1 and tg2 are the two dedicated TaxGlasses client logins. As of the snapshot, tg2, Will and Frank had never connected (no handshake).

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

Older copies on G7: `wg0.conf.bak`, `.bak2`–`.bak5`, `.bak-2026-11-02`, `.bak-2026-11-04`, `.before-nat`.

### Client config template
Each client's private key lives only on that device. To rebuild a client:
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
At home on the LAN, leave WireGuard off and use 192.168.0.6 directly. Away, WireGuard routes 192.168.0.6 too, so the same address works everywhere.

### Adding a new peer
```bash
wg genkey | tee client.key | wg pubkey > client.pub      # on the client, or on G7 then move the key
sudo wg set wg0 peer "$(cat client.pub)" allowed-ips 10.77.0.X/32    # live
# then add a matching [Peer] block to /etc/wireguard/wg0.conf so it survives a restart
```

---

## 4. Access point (CrackCookingKitchen)

| | |
|---|---|
| Config | `/etc/hostapd/hostapd.conf` (service `hostapd`, active) |
| SSID | `CrackCookingKitchen` |
| Band / channel | 2.4 GHz (`hw_mode=g`), channel 6, 802.11n HT40- |
| Security | WPA2-PSK, CCMP, country US |
| Password | `wpa_passphrase` in `hostapd.conf` |
| DHCP + DNS | dnsmasq, `/etc/dnsmasq.d/ap.conf` |
| DHCP range | 192.168.4.10 – 192.168.4.200, 24h leases |
| Gateway / DNS handed out | 192.168.4.1 |
| Upstream DNS | 192.168.0.1 |

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

Everything is in **iptables (nf_tables backend)**. There is no ufw, no firewalld, and `/etc/nftables.conf` is empty. Three sources write the rules:

1. **Docker** — its own `DOCKER*` chains and NAT.
2. **wg0.conf PostUp** — VPN forwarding + NAT (shown above).
3. **`/usr/local/sbin/taxglasses-fw.sh`**, run by `taxglasses-fw.service` (enabled; `After=docker.service wg-quick@wg0.service`, re-runs whenever wg0 restarts) — builds the per-peer chains `WG-WILL`, `WG-FRANK`, `TG-WG`, pins their jumps to the top of `DOCKER-USER`, and adds the `INPUT` drops.

All policies are ACCEPT; the restrictions are explicit DROP rules. Docker's `DOCKER-USER` chain is where the VPN rules go, because Docker evaluates it first on forwarded traffic.

### Filter table
```
INPUT  (traffic to G7 itself)
  -s 10.77.0.31 -i wg0 -j DROP        Will   → nothing on G7
  -s 10.77.0.32 -i wg0 -j DROP        Frank  → nothing on G7
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
  -j DROP

WG-FRANK
  ESTABLISHED,RELATED -j ACCEPT
  -d 192.168.0.100 -j ACCEPT
  -d 10.0.0.0/8 / 172.16.0.0/12 / 192.168.0.0/16 / 169.254.0.0/16 / 100.64.0.0/10 -j DROP
  -o enp59s0       -j ACCEPT                                          internet
  -j DROP
```

### NAT table
```
POSTROUTING
  -s 10.77.0.0/24  -o enp59s0          -j MASQUERADE   VPN clients → internet (from wg0 PostUp)
  -s 172.17.0.0/16 ! -o docker0        -j MASQUERADE   Docker default bridge
  -s 172.18.0.0/16 ! -o br-0218e6ba6111 -j MASQUERADE  taxglasses_default

DOCKER (port publishing, VPN address only)
  10.77.0.1:8090 → 172.18.0.3:8090   taxglasses-proxy-1 (Caddy)
  10.77.0.1:8091 → 172.18.0.2:8090   taxglasses-blue-1
  10.77.0.1:8092 → 172.18.0.4:8090   taxglasses-green-1
```

Docker also adds `raw` PREROUTING drops so the container IPs can't be hit directly from outside their bridge.

### Router (192.168.0.1)
- UDP **51820** forwarded to 192.168.0.6 (WireGuard).
- Nothing else should be forwarded. SSH 3333 and Jenkins 8080 are LAN/VPN only.

---

## 6. Docker

| | |
|---|---|
| Version | Docker 29.9.2 |
| `/etc/docker/daemon.json` | none (defaults; Docker manages iptables) |

| Network | Subnet | Gateway | Containers |
|---|---|---|---|
| `bridge` (docker0) | 172.17.0.0/16 | 172.17.0.1 | none |
| `taxglasses_default` (br-0218e6ba6111) | 172.18.0.0/16 | 172.18.0.1 | blue 172.18.0.2, proxy 172.18.0.3, green 172.18.0.4 |

| Container | Image | Published on | Role |
|---|---|---|---|
| `taxglasses-proxy-1` | `caddy:2-alpine` | 10.77.0.1:8090 → 8090 | Front door; switches blue/green |
| `taxglasses-blue-1` | `taxglasses:blue` | 10.77.0.1:8091 → 8090 | Blue slot |
| `taxglasses-green-1` | `taxglasses:green` | 10.77.0.1:8092 → 8090 | Green slot |
| `vibrant_mahavira` | `hello-world` | — | Leftover test container, exited — safe to `docker rm` |

All TaxGlasses ports are bound to **10.77.0.1 only**, so TaxGlasses is reachable only over WireGuard.

---

## 7. Listening services

| Port | Bound to | Service | Who can reach it |
|---|---|---|---|
| UDP 51820 | all | WireGuard | Internet (via router forward) |
| TCP 3333 | all (v4 + v6) | sshd | LAN, AP Wi-Fi, full VPN peers |
| TCP 1337 | — | SSH via PiKVM | LAN |
| TCP 8080 | all | Jenkins | LAN, AP Wi-Fi, full VPN peers |
| TCP 8765 | 10.77.0.1 | MemeSniper monitor dashboard (python) | Full VPN peers |
| TCP 8090 | 10.77.0.1 | TaxGlasses (Caddy proxy) | Full VPN peers + tg1/tg2 |
| TCP 8091 / 8092 | 10.77.0.1 | TaxGlasses blue / green direct | Full VPN peers |
| 53 TCP/UDP | 127.0.0.1, 192.168.4.1 | dnsmasq DNS | G7 itself, AP Wi-Fi |
| UDP 67 | wlp0s20f3 | dnsmasq DHCP | AP Wi-Fi |

"Full VPN peers" = Phone (10.77.0.2) and Laptop (10.77.0.3).

### SSH (`sshd -T`)
```
port 3333
listenaddress 0.0.0.0:3333 / [::]:3333
pubkeyauthentication yes
passwordauthentication yes
permitrootlogin without-password    (root by key only)
```
The `git` account has no usable password and accepts keys only (see `/srv/git/.ssh/authorized_keys`).

---

## 8. Things worth knowing / fixing

1. ~~Peer restrictions not persisted~~ — **resolved 2026-11-05:** they are rebuilt at boot by `taxglasses-fw.service` (see section 5), and the boot order is correct.
2. **AP Wi-Fi clients may not have internet.** There's no MASQUERADE rule for 192.168.4.0/24 going out `enp59s0`. Unless the router has a static route for 192.168.4.0/24 → 192.168.0.6, phones on CrackCookingKitchen can reach G7 but not the internet. Fix: `iptables -t nat -A POSTROUTING -s 192.168.4.0/24 -o enp59s0 -j MASQUERADE` (and persist it).
3. **AP Wi-Fi clients can reach SSH and Jenkins.** Both listen on all interfaces, and nothing restricts 192.168.4.0/24. Fine if only you use that Wi-Fi; otherwise add INPUT drops for 192.168.4.0/24 to ports 3333 and 8080.
4. **SSH password login is on.** `passwordauthentication yes`. Since everything you use now has keys, consider setting it to `no` (keep the PiKVM path as a fallback before you do).
5. ~~Empty `/etc/resolv.conf`~~ — **fixed 2026-11-05** by `persist-g7.sh`: static `nameserver 192.168.0.1` + `127.0.0.1`, and `nohook resolv.conf` in `/etc/dhcpcd.conf`. Original backed up in `/root/g7-persist-backup-20261105-090600/`.
6. **No DuckDNS updater found on G7.** No cron entry or script. If `buttmud.duckdns.org` stays current, the router or another device is updating it — note which, so it isn't lost.

---

## 9. Backup & restore

### Back up (contains private keys — store encrypted, not in Git)
```bash
sudo tar czf /root/g7-net-$(date +%F).tgz \
  /etc/wireguard /etc/network/interfaces /etc/network/interfaces.d \
  /etc/hostapd/hostapd.conf /etc/default/hostapd /etc/dnsmasq.d /etc/dnsmasq.conf \
  /etc/sysctl.d /etc/ssh/sshd_config /etc/ssh/sshd_config.d \
  /usr/local/sbin/taxglasses-fw.sh /etc/systemd/system/taxglasses-fw.service /etc/resolv.conf /etc/dhcpcd.conf
sudo iptables-save > /root/iptables-$(date +%F).rules
```
Copy the `.tgz` to your password manager's file vault or an encrypted drive.

### Restore on a fresh Debian install
1. `apt install wireguard wireguard-tools hostapd dnsmasq docker.io` (or Docker's repo).
2. Extract the backup over `/etc`.
3. `sudo sysctl --system`
4. `sudo systemctl enable --now wg-quick@wg0 hostapd dnsmasq`
5. Restore `/usr/local/sbin/taxglasses-fw.sh` and `/etc/systemd/system/taxglasses-fw.service`, then `systemctl enable --now taxglasses-fw` — or restore the rules file: `sudo iptables-restore < /root/iptables-<date>.rules`, then restart Docker so it re-adds its own chains.
6. Bring TaxGlasses back: `docker compose up -d` in its project dir (blue, green, Caddy proxy on 10.77.0.1:8090–8092).
7. Router: forward UDP 51820 → 192.168.0.6.
8. Test: `sudo wg show` (handshakes), `ss -tlnup`, and connect a VPN client.
