# G7 nightly backup

restic, encrypted and deduplicated, into `/mnt/data/G7-backups/restic` on the second disk
(NTFS, mounted by `/etc/fstab` with `nofail`; the files already on it are not touched).
Nightly at about 03:15 by `g7-backup.timer`; missed runs catch up after a reboot.

Backed up: `/srv/git` (the repositories and the `git` user's SSH keys), `/srv/vaultwarden`
(+ a consistent copy of its database), `/var/lib/jenkins` and `/var/lib/jenkins-agent` (no
workspaces or caches), `/opt/taxglasses`, `/opt/ntfy` (+ its user database), `/opt/uptime-kuma`
(+ a copy of its database), every `/opt/memesniper*` and `/var/lib/memesniper*` folder (so the
signer's live keypair and the Tier 2 folders are included; `/var/lib/memesniper` goes without
`incoming/`, `imports/`, `.npm/`, `migration-tools/`), `/root` (the restic, ntfy and
Healthchecks secrets and the Miami backup key), `/home/buttmud`, `/etc`, `/usr/local/sbin`,
`/var/backups/jenkins`, `/srv/media-masters` (raw footage and promotions work copied up
from the PC, which Git does not hold), user crontabs, the Docker named volumes (Caddy's certificates and
state), and the list of installed packages. A Bitcoin Core data folder is
included if one exists, without the block chain itself.

Off-site: after the local snapshot, the script copies every snapshot Miami does not have to
a second restic repository, `sftp:mia-backup:/srv/backups/g7/restic` (the Miami server,
reached over the wg-mia tunnel as the file-transfer-only user `g7backup`; same password and
retention as the local repository). If the copy fails the local snapshot is still saved and
the alert says so. Restore from Miami by using that repository path in the commands below.
Kept: 14 daily, 8 weekly, 6 monthly. Sundays also read back 5% of the data (`restic check`).
Alerts: ntfy topic `g7` (subscribe on the phone), low on success, high on failure.

## Install (once)

From `D:\g7-infra`, one command at a time:

    scp -r g7/backup g7-taxglasses:/tmp/g7-backup
    ssh -t g7-taxglasses "sudo sh /tmp/g7-backup/install.sh"

It prints the repository password once at the end: put it in Vaultwarden. Then give the
script the ntfy token Jenkins uses (from Vaultwarden, `tk_...`):

    ssh -t g7-taxglasses "sudo sh -c 'umask 077; cat > /root/.ntfy-g7-token'"

(paste the token, Enter, then Ctrl-D). First backup by hand, which takes a while (~42 GB):

    ssh -t g7-taxglasses "sudo systemctl start g7-backup.service; sudo journalctl -u g7-backup.service -n 5 --no-pager"

## Restore drill

`sudo g7-restore-drill` proves the backup can be restored, from both copies, without touching
anything live. It restores a sample of the newest snapshot from G7's disk and from Miami into a
private scratch folder in `/var/tmp` (both Git repositories that matter most, the database
copies, Jenkins' configuration and a few files from `/etc`), checks each part (`git fsck`,
SQLite integrity, the job configs read), compares Miami's sample with G7's file for file, and
deletes the folder. It also runs `restic check` on both repositories and checks the MemeSniper
wallet key in each by its SHA-256, streamed from the backup into `sha256sum` so no copy of the
key is written. Last, at a terminal, it asks for the two secrets kept on paper: the restic
password (it must open the Miami repository) and the wallet key's encryption passphrase (it
must decrypt the encrypted copy in the backup to the right key). `--no-paper` skips those.

Each line is PASS, WARN or FAIL. WARN means something changed on G7 since the snapshot (an
item added to Vaultwarden, a new Jenkins job), which is expected during the day. Exit 0 when
nothing failed. Reports, without secrets, are kept in `/var/log/g7-restore-drill/` (the last 20).
It needs 10 GB free in `/var/tmp` and takes a few minutes, most of it Miami's `restic check`.
Run it every three months, after any change to the backup, and before relying on the backup
for anything risky.

If `restic check` "could not run: another restic process holds a lock", a restic run was cut
off and left its lock file behind, or one is still running. In a root shell on G7:

    R="restic -r sftp:mia-backup:/srv/backups/g7/restic --password-file /root/.restic-g7"
    for l in $($R list locks --no-lock); do $R cat lock "$l" --no-lock; done
    pgrep -a restic

Each lock shows its host, PID and time. `$R unlock` removes only stale locks (a PID that no
longer runs on this host, or older than 30 minutes) and leaves a running one alone. Use the
local repository path instead for a lock on G7's own copy. Never `unlock --remove-all`.

## Restore

    sudo -i
    export RESTIC_REPOSITORY=/mnt/data/G7-backups/restic RESTIC_PASSWORD_FILE=/root/.restic-g7
    restic snapshots
    restic restore latest --target /tmp/restore --include /srv/git/repos/TaxGlasses.git

Restore to a scratch folder and copy back what you need; never restore over a running service.
