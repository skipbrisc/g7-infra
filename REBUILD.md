# Rebuilding G7

This repository holds the configuration, scripts and notes needed to rebuild G7 (buttserver,
Debian 13, 192.168.0.6). It holds no secrets and no data. Written 2026-11-12 from the files
here; the procedure has not been tested end to end.

## What you need besides this repository

1. **The latest backup.** restic, nightly, in `/mnt/data/G7-backups/restic` on G7's second
   disk (`g7/backup/README.md` lists what is in it and how to restore). The same snapshots are
   copied each night to a second repository on the Miami server
   (`sftp:mia-backup:/srv/backups/g7/restic`, reached from G7 over the wg-mia tunnel).
2. **The restic repository password.** It is in Vaultwarden, but Vaultwarden's own data is
   inside the backup, so also keep it on paper.
3. **The secrets below.** They all come back with the backup (`/etc`, `/root` and the
   MemeSniper signer folder are in it); the last column is the fallback if it does not.

| File on G7 | What it is | Where to get it |
|---|---|---|
| `/root/.restic-g7` | restic repository password | Vaultwarden, or paper |
| `/root/.ntfy-g7-token` | ntfy token for alerts | Vaultwarden |
| `/root/.healthchecks-ping-key` | Healthchecks.io ping key | Healthchecks.io project settings |
| `/etc/duckdns.conf` | DuckDNS token (curl config) | `/etc` backup, or duckdns.org |
| `/etc/wireguard/wg0.conf` (PrivateKey) | VPN server key | `/etc` backup. A new key means reissuing every client config |
| `/etc/hostapd/hostapd.conf` (wpa_passphrase) | Wi-Fi access point passphrase | `/etc` backup |
| `/etc/memesniper-live/rpc.env` | MemeSniper live RPC credentials | `/etc` backup, or the Helius dashboard |
| `/etc/taxglasses/jenkins-hook.env` | Credential the Git hook uses to start Jenkins jobs | `/etc` backup |
| `jenkins-agent.service` (`-secret`) | Jenkins agent secret, redacted here | `/etc` backup, or the node's page in Jenkins |
| `/var/lib/memesniper-signer/live-keypair.json` | MemeSniper live wallet. The only key; there is no seed phrase | In the backup. Also kept separately as the encrypted file `memesniper-live-keypair.json.enc` |

Keypair restore (passphrase is on paper):

    openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 -in memesniper-live-keypair.json.enc -out live-keypair.json

Its SHA-256 must be `338c18faee6ea23d1b788907c9c2ee51c8a28ed00abe1e54596eef5f4d509520`.

## Order

1. **Base system.** Debian 13, user `buttmud`, SSH on port 3333, key-only
   (`etc/ssh/00-key-only.conf`). Install your public key before turning passwords off.
2. **Network.** `etc/network/interfaces`, `etc/hostapd/`, `etc/sbin/ap-firewall.sh`.
   `G7-NETWORK.md` explains the layout; `persist-g7.sh` makes it survive reboots.
3. **VPN.** `etc/wireguard/wg0.conf`, the drop-ins in `systemd/wg-quick@wg0.service.d/`,
   and the `duckdns` units.
4. **Data.** Install Docker and restic, restore the backup to a scratch folder, and copy
   back `/srv/git/repos`, `/srv/vaultwarden`, `/var/lib/jenkins`, `/opt/taxglasses`,
   `/opt/ntfy`, `/opt/uptime-kuma` and `/var/lib/memesniper`. Never restore over a running
   service.
5. **Git server.** The `git` user, the bare repositories, the hooks (`g7/hooks/`; MemeSniper's
   is in the memesniper-deploy repository), and the `*-mirror` units. The `git` user's GitHub
   key may need regenerating and adding to GitHub.
6. **Supporting services.** Vaultwarden (`vaultwarden/`), ntfy (`g7/ntfy/`), Uptime Kuma
   (`g7/uptime-kuma/`).
7. **Jenkins.** Controller and agent (`g7-jenkins-maint.sh`, `g7-upgrade.txt`),
   `g7/51unattended-upgrades-java`, `g7/install-gitleaks.sh`, `g7/install-sites-ci.sh`. The
   job pipelines live with their projects: TaxGlasses `ops/jenkins/`, memesniper-deploy
   `ci/`, and the `Jenkinsfile` in each website repository.
8. **Privileges and scripts.** `etc/sudoers.d/` and `etc/sbin/` (to `/usr/local/sbin`).
9. **TaxGlasses.** `etc/taxglasses/` (compose file and Caddy config) in `/opt/taxglasses`,
   `g7/taxglasses-deploy`, `etc/sbin/taxglasses-fw.sh`. Deploy with the TaxGlasses-Deploy job.
10. **MemeSniper.** Units are in `systemd/`. Restore the keypair as above. Starting any
    study or live service follows MemeSniper's own release procedure, not this document.
11. **Backup and monitoring.** `g7/backup/`, `g7/healthchecks/`, then enable every timer in
    `systemd/`. Done when Uptime Kuma is green and Healthchecks.io shows fresh pings.

## Layout

| Path | Contents |
|---|---|
| `systemd/` | Unit files, timers and drop-ins as they are on G7 (secrets redacted) |
| `etc/` | Live configs and `/usr/local/sbin` scripts as they are on G7 (keys redacted) |
| `g7/` | Install scripts and READMEs for backup, Healthchecks, ntfy, Uptime Kuma, CI tools |
| `runbooks/` | One page per service: check, deploy, roll back, logs, restart. Plus the MemeSniper go-live gates |
| `sites/`, `vaultwarden/` | Setup scripts and notes for the websites' pipelines and Vaultwarden |
| `G7-NETWORK.md`, `VAULT-CHECKLIST.md` | Network layout and the Vaultwarden contents checklist |

`systemd/` and `etc/` are snapshots. After changing anything on G7, copy the changed file
here and commit, or this repository drifts from the server.
