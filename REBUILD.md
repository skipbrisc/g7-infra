# Rebuilding G7

This repository holds the configuration, scripts and notes needed to rebuild G7 (buttserver,
Debian 13, 192.168.0.6). It holds no secrets and no data. Written 2026-11-12 from the files
here; the procedure has not been tested end to end.

Since 2026-11-18 this repository is the source for G7's configuration and G7 follows it: a
change starts as a commit here ("Changing G7", at the end).

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
| `/etc/memesniper-integrity/ntfy.token`, `healthchecks.url` | MemeSniper integrity auditor's ntfy publisher token and Healthchecks ping URL | `/etc` backup, or a new token and the check's page (`g7/ntfy/README.md`) |
| `/var/lib/jenkins-agent/agent.secret` | Jenkins agent secret (`jenkins-agent:jenkins-agent` 0600; the unit passes only its path, `-secret @<file>`) | The backup, or the node's page in Jenkins |
| `/var/lib/memesniper-signer/live-keypair.json` | MemeSniper live wallet. The only key; there is no seed phrase | In the backup. Also kept separately as the encrypted file `memesniper-live-keypair.json.enc` |

Keypair restore (passphrase is on paper):

    umask 077
    d=$(mktemp -d)
    openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 -in memesniper-live-keypair.json.enc -out "$d/live-keypair.json"
    sha256sum "$d/live-keypair.json"

Its SHA-256 must be `338c18faee6ea23d1b788907c9c2ee51c8a28ed00abe1e54596eef5f4d509520`. Check the
public address too, then install it owned by `memesniper-signer`, mode 0600. Never restore
over an existing key.

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
10. **MemeSniper.** Its units, drop-ins and sudoers file are in the memesniper-deploy
    repository (`g7/`), with its G7 runbook and go-live gates (`docs/`). Restore the keypair
    as above. Starting any study or live service follows MemeSniper's own release procedure,
    not this document.
11. **Backup and monitoring.** `g7/backup/`, `g7/healthchecks/`, then enable every timer in
    `systemd/`. Done when Uptime Kuma is green and Healthchecks.io shows fresh pings.
12. **Drift check and apply.** `g7/drift/`, then `g7/apply/` (their READMEs). The drift
    check's first run lists everything that still differs from this repository; `g7-apply`
    puts back the files it may change, and the rest are copied by hand. The rebuild is done
    when the drift check reports `everything matches Git`.

## Layout

| Path | Contents |
|---|---|
| `systemd/` | Unit files, timers and drop-ins as G7 should have them (secrets redacted) |
| `etc/` | Configs and `/usr/local/sbin` scripts as G7 should have them (keys redacted) |
| `g7/` | Install scripts and READMEs for backup, Healthchecks, ntfy, Uptime Kuma, CI tools, `taxglasses-deploy`, the drift check (`g7/drift/`, whose `MAP` says where every file here lives on G7) and `g7-apply` (`g7/apply/`) |
| `runbooks/` | One page per service: check, deploy, roll back, logs, restart. MemeSniper's are in memesniper-deploy `docs/` |
| `sites/`, `vaultwarden/` | Setup scripts and notes for the websites' pipelines and Vaultwarden |
| `G7-NETWORK.md`, `VAULT-CHECKLIST.md` | Network layout and the Vaultwarden contents checklist |

## Changing G7

Git is the source and G7 follows it. For any file listed in `g7/drift/MAP`:

1. Change it here, commit, and `git push g7 main`.
2. If its `MAP` line says `yes` (such as the mirror, backup, heartbeat, image-scan, drift and
   DuckDNS units and scripts, `g7-hc-ping`, `taxglasses-deploy` and the Java hold):
   `ssh -t g7 "sudo g7-apply"` shows the diff and applies it when you type `yes`
   (`g7/apply/README.md`). To undo, revert the commit, push and apply again.
3. If it says `no` (SSH, sudoers, network, WireGuard, hostapd, the firewall, the compose files
   and configs of TaxGlasses, ntfy and Uptime Kuma, the TaxGlasses Git hook, any file with a
   redacted secret, and `g7-apply` itself): make the same change on G7 by hand in a root shell.
   A mistake in most of these could lock you out or cut G7 off, so they are never applied from Git.

Every night at 05:10 the drift check reports anything on G7 that differs from Git, with the
diff (ntfy topic `g7`, report in `/var/log/g7-drift/latest.txt`). A change made on G7 first,
such as an emergency fix, shows up there the next morning: commit it here, or apply Git over it.
MemeSniper's own units, sudoers file and state are not in this repository (memesniper-deploy has
them) and are never checked or applied from here.
