# g7-apply

Makes G7 match g7-infra, one change at a time, after you have read the diff and typed `yes`.
Phase 2 of the GitOps playbook. With it, a change to G7 starts as a commit here.

    ssh -t g7 "sudo g7-apply --dry-run"     what main would change; changes nothing
    ssh -t g7 "sudo g7-apply"               the same, then asks; only "yes" applies

## What it does

1. Reads `main` of g7-infra from G7's own Git server, and the same `MAP` as `g7-drift`.
2. For every `MAP` line marked `yes`, compares Git with G7: content, owner and mode.
3. Prints the commit, every file it would create, update or re-permission, what follows
   (reload systemd; enable a timer it creates), and the diff of each.
4. Asks. Anything but `yes` stops with nothing changed.
5. Keeps each file it replaces in `/var/backups/g7-apply/<time>-<commit>/`, writes the new one
   atomically, reloads systemd if a unit changed, writes a receipt to `/var/log/g7-apply/`
   (with the exact commands to undo it), sends one ntfy note on topic `g7`, and runs `g7-drift`.

It never deletes a file, never restarts a service (every unit it may change is a one-shot job
that picks up the change at its next run), and never reads or writes anything `g7-drift`
protects: MemeSniper's paths, `/root`, `/home`, `/srv/vaultwarden`, SSH host keys.

## What it may apply

Only `MAP` lines marked `yes`: the GitHub mirror units and their Healthchecks drop-ins, backup,
heartbeat, image-scan and drift units and scripts, `g7-hc-ping`, `duckdns`,
`vaultwarden-backup`, `taxglasses-deploy` and the apt Java hold.

Checked only, never applied (`no`): SSH and sudoers (lock-out risk), network, WireGuard, hostapd
and the TaxGlasses firewall (could cut G7 off), anything holding a redacted secret such as
`jenkins-agent.service`, the TaxGlasses compose and Caddy files (the deploy owns them), and
`g7-apply` itself. Change those by hand; the plan lists any that differ from Git.

## It refuses, and then applies nothing

- A file changed on G7 by hand: its contents match no version in that file's Git history.
  Read both versions, then rerun with `--overwrite <path>` if Git should win.
- A Git copy holding `<REDACTED>`, a protected path, a path through a symlink, a missing folder
  (it only creates `*.service.d` folders), or an owner that does not exist on G7.
- A script that does not parse (`sh -n`, `bash -n`, or Python compile).
- `taxglasses-deploy` while a TaxGlasses deploy is running.
- Anything, when not run in a terminal (it must be able to ask).

## Undo

Normally: revert the commit, push, and run `g7-apply` again. If `g7-apply` itself went wrong, the
receipt ends with the exact `install`/`rm`/`systemctl` commands that put the old files back.

## Install

From `D:\g7-infra` in PowerShell, after this folder is committed and pushed:

    ssh g7 "rm -rf /tmp/g7-apply-src"
    scp -r g7/apply g7:/tmp/g7-apply-src
    ssh -t g7 "sudo sh /tmp/g7-apply-src/install.sh && sudo g7-apply --dry-run"

Installing and `--dry-run` change nothing. The dry run should say there is nothing to apply.

## Tests (Phase 2 is done when all pass)

1. With nothing changed in Git, `--dry-run` says nothing to apply.
2. Add a comment line to `systemd/g7-infra-mirror.service.d/healthchecks.conf` and to
   `etc/ssh/00-key-only.conf`, commit, push, `sudo g7-apply`. It updates the drop-in, lists the
   SSH file as checked only and leaves it alone, writes a receipt; `g7-drift` then reports only
   the SSH file.
3. `git revert HEAD`, push, `sudo g7-apply`. G7 is back as before and `g7-drift` is clean.
4. On G7, add a line to the live drop-in by hand. Commit a different change to the same file and
   push. `g7-apply` refuses that file. Then remove the hand edit, revert the commit, push, and
   `--dry-run` says nothing to apply.
5. The receipt from test 2 names the commit and holds working undo commands.

## Later, and only if wanted: automatic apply

Not built. It needs 30 days of clean drift checks and several manual applies with no surprises,
commits signed with a key that lives only on the PC and verified on G7, only `yes` files, and
an alert with the diff after every apply. Until then you run `g7-apply`.
