# Miami server (mia)

Off-site dedicated server rented directly from Server Room (serverroom.net), in their Miami
facility. Set up 2026-11-12. It does three jobs:

- **VPN exit.** Devices on its WireGuard network send all their internet traffic out through
  Miami.
- **Private link to G7.** G7 dials out to it over a second tunnel (`wg-mia` on G7). Only G7
  itself uses the link; nothing else on the home network or on G7's own VPN can reach Miami
  through it.
- **Off-site backup target.** G7 copies its nightly restic snapshots to
  `/srv/backups/g7/restic` here. That side is documented in `g7/backup/README.md`.

This folder holds no secrets. Private keys, device configs and the Healthchecks ping address
stay on the server.

## Facts

| | |
|---|---|
| Public address | `38.126.208.251` |
| Provider console | `console-mia.serverroom.net:11477` (root and password; the fallback if SSH is lost) |
| System | Debian 13 (trixie), one NVMe drive, about 864 GB, no mirror |
| Hostname | `mia` (was `server-bpbfbq`) |
| Admin login | `ssh mia` from the PC: user `buttmud`, port 3333, key `~/.ssh/mia_skip` |
| SSH | Key-only. Root and password logins are off |
| Firewall | ufw: deny incoming, allow 3333/tcp and 51820/udp, forward VPN traffic out to the internet only |
| Updates | unattended-upgrades |

### VPN addresses (`wg0`, 10.78.0.0/24, UDP 51820)

| Address | Who | Notes |
|---|---|---|
| 10.78.0.1 | Miami | Server public key `1nAO0AqhzYKl4Wbey0h9vJlykQc/hbUWiy5hT0MCFmE=` |
| 10.78.0.2 | G7 | Link only (`etc/wireguard/wg-mia.conf` in this repository), not an internet exit |
| 10.78.0.10 | phone | Full tunnel |
| 10.78.0.11 | pc | Full tunnel |
| 10.78.0.31 | will | Full tunnel, internet only |
| 10.78.0.32 | frank | Full tunnel, internet only |

G7's own VPN is 10.77.0.0/24 and is separate. Devices on the Miami VPN get the internet and
nothing else: the firewall forwards `wg0` out to the uplink only, so they cannot reach each
other, G7 or the home network.

### Monitoring

- Uptime Kuma on G7: a Ping monitor on `10.78.0.1` (server and link) and a TCP monitor on
  `38.126.208.251:3333` (reachable from the internet), both alerting to ntfy topic `g7`.
- Healthchecks.io check "Miami heartbeat": root's crontab on Miami pings it every 5 minutes.
  This is the one that still works when G7 is down.

## What is in this folder

- `capture.sh` collects the live configuration from Miami with secrets removed.
- `live/` is what `capture.sh` last collected: `live/etc/` are the server's files, `live/state/`
  are command outputs (firewall rules, users, packages, services). **Treat `live/` as the
  record of how the server is configured**; this README is the explanation. If `live/` is
  missing, the capture has not been run yet.
- `add-vpn-device.sh` adds a device to the VPN.

## Refreshing the live copy

From `D:\TaxGlasses-ops` in PowerShell, one command at a time:

    scp mia/capture.sh mia:/tmp/mia-capture.sh
    ssh -t mia "sudo sh /tmp/mia-capture.sh; rm -f /tmp/mia-capture.sh"
    scp mia:/tmp/mia-live.tgz mia-live.tgz
    tar -xzf mia-live.tgz -C mia
    ssh -t mia "sudo rm -f /tmp/mia-live.tgz"
    del mia-live.tgz

The script refuses to write the archive if anything that looks like a private key or a ping
address is still in it. Read `git diff mia/live` before committing. Run it again after any
change on Miami.

## Adding a VPN device

    scp mia/add-vpn-device.sh mia:/tmp/
    ssh -t mia "sudo sh /tmp/add-vpn-device.sh tablet 12; rm -f /tmp/add-vpn-device.sh"

It prints a QR code for a phone. For a computer, `sudo cat /etc/wireguard/clients/tablet.conf`
on Miami and paste the text into the WireGuard app. The config contains the device's private
key: hand it over in person or over an encrypted channel.

On Windows, a full-tunnel config turns on "Block untunneled traffic", which also blocks the
home network. Untick it to keep reaching 192.168.0.x while connected.

## Rebuilding

Miami is not backed up anywhere. That is deliberate: it holds a copy of G7's backups and VPN
keys that can be regenerated. Losing it costs a re-upload of the backups and new configs for
every VPN device.

1. **Base system.** Debian 13 from the provider. In the web console as root: `apt update &&
   apt full-upgrade -y`, `apt install -y sudo`, `adduser buttmud`, `usermod -aG sudo buttmud`.
   Set passwords with letters and digits only until SSH works; the web console keyboard
   changes some symbols.
2. **SSH.** Install the PC's public key for `buttmud` and confirm key login and `sudo` work
   **before** copying `live/etc/ssh/sshd_config.d/` into place. Then `sshd -t && systemctl
   restart ssh`, and test from a second window before closing the first.
3. **Firewall.** `apt install -y ufw`, then the rules in `live/state/ufw-added.txt`, then
   `ufw enable`.
4. **Updates.** `apt install -y unattended-upgrades`, `dpkg-reconfigure -plow
   unattended-upgrades`.
5. **WireGuard.** `apt install -y wireguard qrencode`; generate a server key
   (`wg genkey | tee /etc/wireguard/server.key | wg pubkey > /etc/wireguard/server.pub`,
   umask 077); copy `live/etc/sysctl.d/` and `live/etc/wireguard/wg0.conf` into place and
   put the new private key in `wg0.conf`; `systemctl enable --now wg-quick@wg0`. A new server
   key means every device needs a new config (`add-vpn-device.sh`, after removing the old
   `[Peer]` blocks) and G7's `wg-mia.conf` needs the new public key. If the uplink interface
   has a different name, change it in the `PostUp`/`PostDown` lines and in the ufw route rule.
6. **G7 link.** On Miami, the `[Peer]` block for G7 (10.78.0.2) with G7's `wg-mia` public key.
   On G7, `systemctl enable --now wg-quick@wg-mia`, then `ping 10.78.0.1`.
7. **Backup target.** The `g7backup` user and `/srv/backups/g7`; see `g7/backup/README.md`.
8. **Monitoring.** `apt install -y cron curl`; root's crontab line is in
   `live/state/crontab-root.txt` with the ping address removed (copy the address from the
   check's page on Healthchecks.io). The Uptime Kuma monitors live on G7 and need no change
   unless the address changes.

## Secrets (none are in this repository)

| What | Where it lives | If lost |
|---|---|---|
| Root password (provider console) | Your password manager | Reset through Server Room |
| `buttmud` password (sudo) | Your password manager | Reset from the console as root: `passwd buttmud` |
| PC login key `~/.ssh/mia_skip` | The PC | Make a new key and add it through the console |
| VPN server key `/etc/wireguard/server.key` | Miami only | New key; reissue every device config |
| Device configs `/etc/wireguard/clients/` | Miami only, and on each device | Remove the peer and add the device again |
| Healthchecks ping address | Root's crontab on Miami | Copy it from the check's page |
| Backup user's login key | G7 (`g7/backup/README.md`) | See that file |
