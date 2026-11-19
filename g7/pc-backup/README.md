# The PC's backup, on G7 and in Miami

The PC (Windows, `D:\` and the user folders that matter) backs up to G7 every day with restic.
G7 keeps the snapshots on its backup disk, prunes them, and copies them to the Miami server each
night, the same way it copies its own backup. Written 2026-11-18. The scripts have been
syntax-checked and linted here. Run the first backup by hand and look at the output.

    PC ── restic, daily 12:30 ──▶ G7 restic REST server 192.168.0.6:8000 (append-only)
                                        /mnt/data/PC-backups/pc/restic
                                  01:40 g7-pc-backup-offsite: prune, check, copy ──▶ Miami
                                                                   rest:http://10.78.0.1:8000/g7/pc/

## Why it is built this way

- **Append-only, so ransomware on the PC cannot reach the backups.** The PC can add snapshots
  but never delete or change stored ones, even with its password. Pruning happens on G7 itself,
  through the filesystem, by the nightly job.
- **G7 watches the PC.** If the newest PC snapshot is more than 3 days old, the nightly job
  fails. That sends ntfy topic `g7` (high), and the Healthchecks.io check `pc-backup-offsite`
  stops getting pings. So a PC that quietly stopped backing up raises an alarm. No separate
  check on the PC is needed.
- **Off-site.** Miami gets every snapshot, append-only, under G7's existing Miami login
  (`/g7/pc/` beside `/g7/restic/`). Miami keeps everything until it is pruned there by hand
  (`mia/README.md`, "Pruning": the same command with the path `/srv/backups/g7/pc`).
- **The server runs as root without capabilities.** `/mnt/data` is NTFS mounted for root only,
  so the Debian package's own user could not write there. The drop-in runs it as root, but
  with an empty capability set and a sandbox that shows it only `/mnt/data/PC-backups`.
- **The server listens on 192.168.0.6:8000.** That is reachable from the LAN and, through the
  G7 VPN, from the PC when away. Will and Frank are already blocked from G7 itself. Anyone else
  on the LAN needs the login, and could still only add encrypted snapshots.

## What is backed up from the PC

All of `D:\` except `SteamLibrary`, the recycle bin and `System Volume Information`. Plus these
folders in your user folder: Documents, Desktop, Pictures, Videos, Music, Favorites, Contacts,
`.claude`, `.codex`, `.config`, `.gstack`, `.remember`, `.memesniper` and `.jenkins-cli`, and
`.gitconfig`.

Left out everywhere: `node_modules`, `.venv`, `__pycache__`, `.vite`, `.next`, `.turbo`,
`.cache`, `.pytest_cache` and `.mypy_cache` folders, `*.tmp` files, and any folder holding a
`.nobackup` file.

Left out on purpose, as secrets that would not belong on G7:

- `~/.ssh`: the Miami key must not be readable on G7. Keep the SSH keys in Vaultwarden instead.
- Claude Code's `.credentials.json`.
- Codex's `auth.json`.
- The backup's own settings.

OneDrive and AppData are not included (OneDrive is already in the cloud). Downloads is not
included either.

Kept on G7: 14 daily, 8 weekly, 12 monthly. The first backup is large; later ones send only
changes.

## Install

1. **G7**, from `D:\g7-infra` in PowerShell, after this folder is committed and pushed:

       ssh g7 "rm -rf /tmp/g7-pc-backup"
       scp -r g7/pc-backup g7:/tmp/g7-pc-backup
       ssh -t g7 "sudo sh /tmp/g7-pc-backup/install.sh"

   It installs the REST server, makes the repository, sets up the nightly job and the Miami
   copy repository. It prints two secrets once: the repository password and the PC's REST
   login. **Put both in Vaultwarden.** Then create the Healthchecks.io check `pc-backup-offsite`
   (period 1 day, grace 6 hours).

2. **PC**, in an **admin** PowerShell from `D:\g7-infra`:

       powershell -NoProfile -ExecutionPolicy Bypass -File pc\backup\get-restic.ps1   # once
       powershell -NoProfile -ExecutionPolicy Bypass -File pc\backup\install-pc-backup.ps1

   It asks for the two secrets and keeps them in `%USERPROFILE%\.config\pc-backup`, readable
   by your account only. It checks the login, and creates the scheduled task "PC backup to G7"
   (daily 12:30, runs later if the PC was off, elevated so it can copy open files). Start the
   first backup from there, or run `Start-ScheduledTask "PC backup to G7"`. A dry run that
   shows what would be backed up:

       powershell -NoProfile -File pc\backup\pc-backup.ps1 -DryRun

   Logs: `%LOCALAPPDATA%\pc-backup\` (the last 30 days).

## Restore

On the PC, with the same settings loaded (or from any machine with restic and the two secrets):

    $env:RESTIC_REPOSITORY = "rest:http://192.168.0.6:8000/pc/restic/"
    $env:RESTIC_REST_USERNAME = "pc"; $env:RESTIC_REST_PASSWORD = "<REST password>"
    restic snapshots
    restic restore latest --target D:\restore --include "D:\TaxGlasses-wt-fig-al"

On G7 as root: `restic -r /mnt/data/PC-backups/pc/restic --password-file /root/.restic-pc snapshots`.
If G7 is gone: load `/root/.restic-mia-rest` from G7's own backup on Miami, then use the
repository `rest:http://10.78.0.1:8000/g7/pc/`. It has the same password.

## Check it

    ssh -t g7 "sudo systemctl start g7-pc-backup-offsite; sudo journalctl -u g7-pc-backup-offsite -n 5 --no-pager"

Add this repository to `g7-restore-drill` when it is next revised. Until then, restore a folder
by hand every few months.
