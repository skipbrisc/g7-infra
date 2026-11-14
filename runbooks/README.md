# Runbooks

One page per service: how to tell it is up, deploy it, roll it back, read its logs and
restart it. Written 2026-11-14 from the repositories and from what was verified on G7 that
week. Fix a page the moment you find it wrong.

| Page | Service | Where it runs |
|---|---|---|
| [taxglasses.md](taxglasses.md) | TaxGlasses web form | G7, blue/green containers |
| [memesniper.md](memesniper.md) | MemeSniper on G7 (paper monitor, Tier 2, CI) | G7, systemd services |
| [aeraphim.md](aeraphim.md) | aeraphimcpa.com | Vercel, deployed by Jenkins on G7 |
| [guatemalahope.md](guatemalahope.md) | guatemalahope.org | Vercel, deployed by Jenkins on G7 |
| [MEMESNIPER-GO-LIVE-GATES.md](MEMESNIPER-GO-LIVE-GATES.md) | What must be true before MemeSniper trades real money | Draft |

Rebuilding G7 from nothing is [../REBUILD.md](../REBUILD.md).

## G7 itself

**Reach it.** `ssh g7` (192.168.0.6, port 3333, key-only). Away from home, turn WireGuard on
first. Root work: `sudo -i` and your password.

**Is everything up?**

| Look at | What it tells you |
|---|---|
| Uptime Kuma, `http://192.168.0.6:3001` | Each service answering, checked every minute |
| healthchecks.io | G7 alive (`g7-heartbeat`), last night's backup ran (`g7-backup`), mirrors pushing |
| ntfy on your phone (topics `g7`, `taxglasses`, `sites`, `memesniper`) | Alerts from all of the above and from Jenkins |
| Jenkins, `http://192.168.0.6:8080` | Build and deploy results |

One command, read-only, from `D:\TaxGlasses`:

    powershell.exe -NoProfile -File ./scripts/g7-status.ps1

**Common failures**

| Symptom | Likely cause | Fix |
|---|---|---|
| Every Jenkins build fails in seconds with "Failed to exec spawn helper" | Java was updated under the running services | From `D:\TaxGlasses`, once no build is running: `powershell.exe -NoProfile -File ./scripts/g7-restart.ps1 -Service all` |
| healthchecks.io says `g7-heartbeat` is down | G7 is off, frozen or has no internet | Check power and network; it comes back by itself after a reboot |
| ntfy "backup FAILED" or `g7-backup` check down | Backup disk full or unmounted, or Miami unreachable | `ssh -t g7 "sudo journalctl -u g7-backup.service -n 40 --no-pager; df -h /mnt/data"` |
| A GitHub mirror check is down | GitHub key or repository problem | `ssh -t g7 "sudo journalctl -u <name>-mirror.service -n 10 --no-pager"` |
| Weekly image scan alert | A container image has new known vulnerabilities | Read the report it names; rebuild or redeploy that container |
| `ssh g7` asks for a password or is refused | Wrong key, or WireGuard off while away | `ssh -v g7`; the key is `~/.ssh/g7_skip` |

**Restore a file from backup** (root on G7; use the Miami path if the local disk is gone):

    export RESTIC_REPOSITORY=/mnt/data/G7-backups/restic RESTIC_PASSWORD_FILE=/root/.restic-g7
    restic snapshots
    restic restore latest --target /tmp/restore --include <path>

Miami copy: `RESTIC_REPOSITORY=sftp:mia-backup:/srv/backups/g7/restic`. Restore to a scratch
folder and copy back; never restore over a running service.

**Secrets.** All in Vaultwarden. The restic password and the MemeSniper keypair passphrase
are also on paper, because Vaultwarden's own data is inside the backup they unlock.
