# SkipOS' backup, off the Miami server

SkipOS runs on Miami (`mia/skipos/`). Its nightly backup is written there, which covers a bad
change but not losing the server. G7 copies it home every night. Written 2026-11-23. The
scripts have been syntax-checked and linted here. Run the first pull by hand and read it.

    Miami 02:10 Eastern: skipos-backup ──▶ restic, encrypted ──▶ REST server 10.78.0.1:8000 /skipos/
                                                                        (append-only)
    G7 00:40 Pacific: g7-skipos-pull ── restic copy over wg-mia ──▶ /mnt/data/skipos-backups/restic

## Why it is built this way

- **G7 pulls; Miami never dials G7.** The link stays as it was: only G7 opens connections, to
  the one port it already used. No firewall rule changed on either side.
- **Encrypted before it leaves the stack's own folders.** The backup holds SkipOS' secrets
  (the root escrow passphrase among them). The repository is encrypted with a password that
  lives on Miami, on G7 and in Vaultwarden.
- **Append-only on Miami.** The `skipos` login can add snapshots and read them, never delete
  or rewrite. Pruning happens only on G7's copy.
- **G7 watches Miami.** If the newest snapshot is more than 30 hours old the pull fails and
  sends ntfy topic `g7` (high). Miami's own `skipos-health` also reports a stale local backup.
- **No Healthchecks.io check.** The free plan was full. A successful pull sends a low-priority
  ntfy line instead; a silent night is the thing to notice.

Kept on G7: 30 daily, 12 weekly, 24 monthly. The data is small (a few hundred KB a night).

## Install

1. **Miami first.** From `D:\g7-infra` in PowerShell:

       scp mia/skipos/08-offsite.sh mia/skipos/skipos-backup mia/skipos/skipos-restore-drill mia:/tmp/skipos-setup/
       ssh -t mia "sudo sh /tmp/skipos-setup/08-offsite.sh"

   It prints two secrets once: the repository password and the REST login. **Put both in
   Vaultwarden.** Keep the window open for step 2.

2. **G7.** It asks for those two secrets; type or paste each, nothing is shown.

       ssh g7 "rm -rf /tmp/g7-skipos-backup"
       scp -r g7/skipos-backup g7:/tmp/g7-skipos-backup
       ssh -t g7 "sudo sh /tmp/g7-skipos-backup/install.sh"
       ssh -t g7 "sudo /usr/local/sbin/g7-skipos-pull"

   The last line should read `g7-skipos-pull: newest snapshot ... copied from Miami`.

## Checking a backup

On Miami, `sudo skipos-restore-drill` restores the newest snapshot from the encrypted
repository, loads the database into a throwaway Postgres and checks what a restored instance
must have. It proves the backup reads back. It does not prove a whole stack comes up from it
on a new server; that has never been done.

## Restoring for real

Not rehearsed. The outline, to be turned into a tested runbook before it is needed:

1. A server prepared as in `mia/skipos/README.md` up to step 4, with the stack NOT started.
2. `restic restore latest` from either copy into a scratch folder.
3. Put `env` back as `/opt/skipos/infra/docker/.env`; recreate the four volumes from the
   `volume-*.tgz` files; start only `postgres`; load `pg_dumpall.sql.gz`; then start the rest.

The database, its rotated credentials (`dbcreds`) and the root escrow belong together: restore
all of them from the SAME night or none.

## Secrets (none are in this repository)

| What | Where it lives | If lost |
|---|---|---|
| Repository password | Miami `/etc/skipos/restic-repo-pass`, G7 `/root/.restic-skipos`, Vaultwarden | Both copies become unreadable. New repositories from then on |
| REST login `skipos` | Miami `/etc/skipos/restic-rest-env` (hash in `users.htpasswd`), G7 `/root/.restic-mia-skipos-rest`, Vaultwarden | New password and hash on Miami, the same on G7 |
