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
`/var/backups/jenkins`, user crontabs, the Docker named volumes (Caddy's certificates and
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

From `D:\TaxGlasses-ops`, one command at a time:

    scp -r g7/backup g7-taxglasses:/tmp/g7-backup
    ssh -t g7-taxglasses "sudo sh /tmp/g7-backup/install.sh"

It prints the repository password once at the end: put it in Vaultwarden. Then give the
script the ntfy token Jenkins uses (from Vaultwarden, `tk_...`):

    ssh -t g7-taxglasses "sudo sh -c 'umask 077; cat > /root/.ntfy-g7-token'"

(paste the token, Enter, then Ctrl-D). First backup by hand, which takes a while (~42 GB):

    ssh -t g7-taxglasses "sudo systemctl start g7-backup.service; sudo journalctl -u g7-backup.service -n 5 --no-pager"

## Restore

    sudo -i
    export RESTIC_REPOSITORY=/mnt/data/G7-backups/restic RESTIC_PASSWORD_FILE=/root/.restic-g7
    restic snapshots
    restic restore latest --target /tmp/restore --include /srv/git/repos/TaxGlasses.git

Restore to a scratch folder and copy back what you need; never restore over a running service.
