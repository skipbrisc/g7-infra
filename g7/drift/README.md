# G7 drift check

`g7-drift` compares G7 with Git every morning and tells you about every difference. It only
reads: nothing on G7 is changed, started or restarted. Phase 1 of the GitOps playbook.

| File | What it is |
|---|---|
| `g7-drift` | The check. Installed as `/usr/local/sbin/g7-drift` (root, 0700) |
| `MAP` | Every file Git describes: its place in Git, its place on G7, owner, mode, and whether Phase 2's `g7-apply` may apply it. Also the Jenkins jobs and the copies that must stay identical |
| `g7-drift.service`, `g7-drift.timer` | Daily at 05:10, after the backup (03:15) and TaxGlasses-Nightly (04:40) |
| `install.sh` | Installs the script and units; does not enable the timer |

## What it compares

- Every `file` line in `MAP`: content (secrets redacted the same way on both sides), owner, mode.
- `g7-infra` files under `systemd/` and `etc/` that `MAP` does not list.
- Files in `/etc/systemd/system`, `/usr/local/sbin` and `/etc/sudoers.d` that `MAP` does not list.
- Jenkins jobs: inline pipelines against their files in Git; jobs that are not in Git.

**Not MemeSniper.** MemeSniper's files on G7 belong to the memesniper-deploy repository and to
Codex. `MAP` ignores them, and the script refuses to read anything under `/opt/memesniper*`,
`/var/lib/memesniper*`, `/etc/memesniper*`, MemeSniper's units, its sudoers file or its Git
hook, even if `MAP` named one. A proposed MemeSniper check is in memesniper-deploy
`proposals/integrity-check/`, for Codex to decide on.

Git is read from the bare repositories in `/srv/git/repos` as the `git` user, at `main`
(`master` for TaxGlasses). The check needs no network or Jenkins token. Contents of `/root`,
`/home` and `/srv/vaultwarden` are never read either, whatever `MAP` says.

## Reading a report

`sudo cat /var/log/g7-drift/latest.txt` (the last 30 are kept). Each difference is one line,
then DETAILS holds the diffs and NOTES lists what was not checked and the live color.

| Difference | What to do |
|---|---|
| `differs` | Someone changed G7 or Git. Keep G7's version: copy it into Git and commit. Keep Git's: put it back on G7 (Phase 2 makes this `g7-apply`) |
| `on G7, not in Git` | Copy it into g7-infra and add a `file` line, or add an `ignore` line with a reason |
| `in Git, not in MAP` | Add a `file` line, or remove the stale copy from Git |
| `Jenkins job differs` / `not in Git` | Compare with `scripts/jenkins-jobs.ps1` in TaxGlasses and decide which side is right |

## Install, first run, switch on

From `D:\g7-infra` in PowerShell, after this folder is committed and pushed:

1. Copy and install:

       ssh g7 "rm -rf /tmp/g7-drift-src"
       scp -r g7/drift g7:/tmp/g7-drift-src
       ssh -t g7 "sudo sh /tmp/g7-drift-src/install.sh"

2. Run the check by hand: `ssh -t g7 "sudo g7-drift"`. Fix each difference and run again
   until it reports `everything matches Git`.
3. On healthchecks.io create a check with slug `g7-drift`: period 1 day, grace 3 hours.
4. Switch it on: `ssh -t g7 "sudo systemctl enable --now g7-drift.timer"`.

To try a changed `MAP` before committing it: copy it to G7 and run `sudo g7-drift --map /tmp/MAP`.

## Undo

`sudo systemctl disable --now g7-drift.timer`. Nothing else on G7 was changed.
