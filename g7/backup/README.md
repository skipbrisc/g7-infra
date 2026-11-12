# G7 nightly backup

restic, encrypted and deduplicated, into `/mnt/data/G7-backups/restic` on the second disk
(NTFS, mounted by `/etc/fstab` with `nofail`; the files already on it are not touched).
Nightly at about 03:15 by `g7-backup.timer`; missed runs catch up after a reboot.

Backed up: `/srv/git/repos`, `/srv/vaultwarden` (+ a consistent copy of its database),
`/var/lib/jenkins` (no workspaces or caches), `/opt/taxglasses`, `/opt/ntfy` (+ its user
database), `/opt/uptime-kuma` (+ a copy of its database), `/var/lib/memesniper` (without `incoming/`, `imports/`, `.npm/`, `migration-tools/`,
the Oct 28 transfer copies), `/etc`, `/usr/local/sbin`, `/var/backups/jenkins`.
Kept: 14 daily, 8 weekly, 6 monthly. Sundays also read back 5% of the data (`restic check`).
Alerts: ntfy topic `g7` (subscribe on the phone), low on success, high on failure.

## Install (once)

From `D:\TaxGlasses`, one command at a time:

    scp -r ops/g7/backup g7-taxglasses:/tmp/g7-backup
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
