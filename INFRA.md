# How it all fits together: G7, Miami and the home network

The one-page map. Each section points to the page that holds the detail. Written 2026-11-18 from
this repository, a fresh capture of G7 (`g7-netdump.txt`), Miami's capture (`mia/live/`) and the
work done in chat since October. Fix it the moment it is wrong.

**The rule that holds everything together:** this repository is the record of how G7 and Miami
should look. A change starts as a commit here, reaches G7 through `g7-apply` (or by hand for the
files too risky to apply automatically), and the drift check at 05:10 every night reports anything
on G7 that no longer matches. See `REBUILD.md`, "Changing G7".

## The machines

| Machine | Where | What it does | Reach it |
|---|---|---|---|
| **G7** (`buttserver`) | Home. Debian 13, 12 CPU threads, 7.5 GiB RAM + 7.7 GiB swap; system disk `sdb` (226 GB), backup disk `sda` (932 GB NTFS, `/mnt/data`) | Git server, Jenkins, TaxGlasses, MemeSniper, Vaultwarden, ntfy, Uptime Kuma, Prometheus + Grafana, the Wi-Fi access point, the home VPN, the nightly backup | `ssh g7` (192.168.0.6:3333, key `~/.ssh/g7_skip`, user `buttmud`); sudo needs your password |
| **Miami** (`mia`) | Server Room, Miami. Debian 13, 864 GB NVMe, public 38.126.208.251 | VPN exit for your devices, private link to G7, off-site backup (append-only) | `ssh mia` (port 3333, key `~/.ssh/mia_skip`); provider console as fallback (`mia/README.md`) |
| **PiKVM** | Home LAN, 192.168.0.100 (DHCP reservation on the router) | Out-of-band keyboard, screen and power for G7 | `https://192.168.0.100`; SSH to G7 through it on port 1337 |
| **Home router** | 192.168.0.1 | Your internet connection, LAN DHCP and DNS | Forwards UDP 51820 to G7 (the VPN) and the PiKVM's web page; see "Facing the internet" |
| **PC** | Home (Windows) | Where the repositories are edited (`D:\`), Claude Code and Codex run, and the daily Vaultwarden backup copy lands (`D:\VaultBackups`). Hands long Claude Code jobs to G7 (`ssh g7-agent`) and backs itself up to G7 daily | |

Outside services: **GitHub** (`skipbrisc/*`, a mirror only, never pushed to by hand),
**Vercel** (hosts aeraphimcpa.com and guatemalahope.org), **Healthchecks.io** (outside alarm for
anything that stops running), **DuckDNS** (`buttmud.duckdns.org` for the VPN, `buttvault.duckdns.org`
for Vaultwarden; G7's `duckdns.timer` keeps them current).

## The networks

| Network | Range | Who is on it | Its traffic leaves through |
|---|---|---|---|
| Home LAN | 192.168.0.0/24 | router .1, G7 .6, PiKVM .100, your other devices | your home connection |
| G7 Wi-Fi "CrackCookingKitchen" | 192.168.4.0/24 | anything on G7's own access point (G7 is .1, hands out .10–.200) | nowhere: no internet, on purpose; it reaches G7 only and is kept for a later Wi-Fi project (`G7-NETWORK.md`, section 8) |
| G7 VPN (`wg0` on G7) | 10.77.0.0/24 | phone .2, laptop .3, TaxGlasses logins tg1 .20 and tg2 .21, Will .31, Frank .32 | G7, then your home connection |
| Miami VPN (`wg0` on Miami) | 10.78.0.0/24 | phone .10, PC .11, Will .31, Frank .32; G7 .2 as a private link only | Miami (38.126.208.251) |
| Docker on G7 | 172.16.0.0/12 | containers | G7 |

What each VPN login may reach, the firewall rules that enforce it and every address on G7 are in
`G7-NETWORK.md`. Miami's side is in `mia/README.md`. The two VPNs never chain: G7 VPN traffic
exits at home, Miami VPN traffic exits in Miami, and the G7 to Miami link carries only G7's own
traffic (the off-site backup).

At home, leave WireGuard off and use 192.168.0.6. Away, the G7 VPN routes 192.168.0.6 too, so
every address below works the same from anywhere.

## What runs where

| Service | Address | Who can reach it | Detail |
|---|---|---|---|
| Git | `ssh://git@192.168.0.6:3333/srv/git/repos/<name>.git` (remote `g7`) | you (keys) | each repository mirrors to GitHub about once a minute |
| Jenkins | `http://192.168.0.6:8080` | LAN and your VPN devices | jobs below |
| TaxGlasses | `http://192.168.0.6:8090` and `http://10.77.0.1:8090` | LAN, your VPN devices; tg1/tg2 reach `10.77.0.1:8090` and nothing else | `runbooks/taxglasses.md` |
| MemeSniper | systemd services; monitor on `10.77.0.1:8765` | your VPN devices | memesniper-deploy (Codex's) |
| Vaultwarden | `https://buttvault.duckdns.org` (points to 192.168.0.6) | LAN and your VPN devices, never the internet | `vaultwarden/VAULTWARDEN.md` |
| ntfy | `http://192.168.0.6:2586` | the phone app and G7's jobs | `g7/ntfy/README.md` |
| Uptime Kuma | `http://192.168.0.6:3001` | LAN and your VPN devices | `g7/uptime-kuma/` |
| Grafana | `http://192.168.0.6:3000` | LAN and your VPN devices (login) | `g7/monitoring/README.md` |
| Prometheus, exporters, Alertmanager | `127.0.0.1` on G7 only | G7 itself | `g7/monitoring/README.md` |
| Off-site backup (restic REST, append-only) | `10.78.0.1:8000` on Miami | G7 only | `mia/README.md`, "Backup target" |
| PC backup (restic REST, append-only) | `http://192.168.0.6:8000` on G7 | the PC (login `pc`) | `g7/pc-backup/README.md` |
| G7 agent: Claude Code jobs for the PC | tmux on G7 (`g7-agent-tmux.service`), as user `agent`; `ssh g7-agent <command>` | the PC's `g7_agent` key, forced to `g7-agent` | `agent/README.md` |
| Websites | aeraphimcpa.com, guatemalahope.org | everyone | Vercel; deployed by Jenkins on G7 (`sites/SITES-SETUP.md`) |

## The projects

| Project | Repository | Runs on | Pipeline | Owner |
|---|---|---|---|---|
| TaxGlasses | `D:\TaxGlasses` → `TaxGlasses.git` | G7, Docker blue/green in `/opt/taxglasses` | push → TaxGlasses-CI → TaxGlasses-Deploy (stage on the idle color, compare answers, approve if figures change, promote, `live-` tag) → TaxGlasses-Nightly checks live every night at 04:40 | Claude Code |
| MemeSniper | `D:\memesniper` → `memesniper.git`, plus `memesniper-deploy` | G7, systemd services | MemeSniper-CI; releases by your own root steps | Codex |
| aeraphimcpa.com | `D:\Aeraphim` → `Aeraphim.git` | Vercel | push → Aeraphim-Deploy (test, upload, smoke test, promote, health check, roll back on failure) | Claude Code |
| guatemalahope.org | `guatemalahope.org.git` | Vercel | push → GuatemalaHope-Deploy (same) | Claude Code |
| G7 and Miami themselves | `D:\g7-infra` → `g7-infra.git` | | commit → `g7-apply`, or by hand for `no` files; `g7-drift` every night | you |
| Aeraphim-Chatbot, househack, cryptoagent | `D:\<name>` → `<name>.git` (from 2026-11-18, `pc/repos-to-g7.ps1`) | | none yet; GitHub mirror only | Claude Code |
| SkipOS | `D:\SkipOS` → `SkipOS.git` (from 2026-11-23, `template/g7-new-repo.sh`) | not a running service yet | push → SkipOS-CI (unit lane only, pipeline in `jenkins/` here); no deploy job | Claude Code |

TaxGlasses' Jenkins pipelines live in `D:\TaxGlasses\ops\jenkins\` and are installed with
`scripts/jenkins-jobs.ps1 -Action Push` (only you run it). The websites' pipelines are the
`Jenkinsfile` in each repository. MemeSniper is kept separate on purpose: its units, sudoers,
runbook and go-live gates are in memesniper-deploy, and nothing in this repository changes or
reads it.

## Backups

| What | When | Where | Detail |
|---|---|---|---|
| G7's state (Git, Jenkins, `/etc`, `/root`, Docker volumes, Vaultwarden, MemeSniper folders incl. the wallet key, media masters, ...) | nightly 03:15 | restic on `/mnt/data`, then copied to Miami | `g7/backup/README.md` |
| Off-site copy | right after | Miami, append-only: G7 can add snapshots but never delete or change them | `mia/README.md`, "Backup target" |
| Vaultwarden | nightly 02:41 | `/srv/vaultwarden/backups`, pulled to `D:\VaultBackups` daily | `vaultwarden/VAULTWARDEN.md` |
| The PC (`D:\` without Steam, and the user folders that matter) | daily 12:30 from the PC; nightly 01:40 G7 prunes and copies | restic on `/mnt/data/PC-backups`, then Miami (`/g7/pc/`), both append-only for the PC | `g7/pc-backup/README.md` |
| Proof it restores | every three months, and after any backup change | `sudo g7-restore-drill` | `g7/backup/README.md`, "Restore drill" |

Kept on G7: 14 daily, 8 weekly, 6 monthly. Miami keeps everything until pruned by hand there.
Two secrets live on paper because the backup holds the vault that would otherwise store them: the
restic repository password and the wallet key's encryption passphrase. The 2026-11-18 drill proved
both, and that both copies restore.

## Monitoring and alerts

Your phone's ntfy app (server `http://192.168.0.6:2586`) has four topics: `g7` (the server),
`taxglasses`, `sites` and `memesniper`.

| Layer | Answers | Where |
|---|---|---|
| Uptime Kuma | Is each service answering right now? | `http://192.168.0.6:3001` → ntfy |
| Healthchecks.io | Did each scheduled job run, and is each server alive at all? (works when G7 is down) | `g7-heartbeat` and "Miami heartbeat" every 5 min, `g7-backup`, `g7-drift`, `taxglasses-mirror`, `taxglasses-nightly`, `pc-backup-offsite` (also fails when the PC's newest backup is over 3 days old); `memesniper-integrity` (Codex's, paused) |
| Prometheus + Grafana | What was happening, per service, over time | `http://192.168.0.6:3000` |
| Alertmanager | Disk nearly full, memory short, heavy swapping, a failed service, monitoring blind | → ntfy `g7` |
| Jenkins | Build, deploy and nightly-check results | → ntfy `taxglasses`, `sites` |
| `g7-drift` | Does G7 still match this repository? | 05:10 → ntfy `g7` |
| `g7-image-scan` | Do running containers have fixable high or critical vulnerabilities? | Mondays 04:30 → ntfy `g7` |

**A G7 night:** 01:40 PC backup care (prune, copy to Miami), 02:41 Vaultwarden backup, 03:15 backup and copy to Miami, 04:40 TaxGlasses
nightly check, 05:10 drift check (Mondays also 04:30 image scan).

## Facing the internet

| Machine | Open to the internet | Everything else |
|---|---|---|
| G7 (through the router) | UDP 51820, the G7 VPN | LAN, G7's Wi-Fi and VPN only |
| PiKVM (through the router) | its HTTPS web page, for remote keyboard, screen and power control of G7 (wanted; confirmed 2026-11-18) | LAN |
| Miami | TCP 3333 (SSH, key only), UDP 51820 (Miami VPN) | the backup server answers only G7, on the tunnel |

SSH on both servers accepts keys only (password logins off). Miami refuses root entirely; G7 allows
root by key only. sudo needs your password on both. The
private keys, tokens and passwords are not in this repository: `REBUILD.md` lists where each one
lives and how to get it back.

## Plans, not built yet

- **An isolated 192.168.1.x network at home** whose traffic all enters and leaves through Miami,
  routed by G7 with a USB Ethernet adapter and its own switch (talking stage, 2026-11-14).
- **A Wi-Fi project on CrackCookingKitchen**, G7's access point, which has no internet until then.
- **A new home router** with more control (the GL.iNet Flint 2 came out on top); G7 stays behind it
  rather than becoming the edge router.
- **Bitcoin Core on G7** (decided 2026-11-11; the backup already includes its data folder if one
  exists).
- **Automatic `g7-apply`**: decide on 2026-12-19, after 30 clean nights of drift checks.
- **Codex on G7.** Claude Code there is the G7 agent (`agent/README.md`, written 2026-11-18): jobs
  handed over from the PC, capped at 2.5 GB together. Codex is not set up there yet.
- **More off-site sites** (Dallas as the main backup host, NYC and Denver as VPN exits) were the
  first idea; Miami took the backup and VPN roles instead.
