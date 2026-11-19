# Scripts that run on the PC

Written 2026-11-18, when work moved from the laptop to G7. They run in PowerShell from
`D:\g7-infra`. Each one does nothing until you add `-Apply`, except the backup's setup.

| Script | What it does | When |
|---|---|---|
| `setup-all.ps1` | Walks through all of the below in order (and G7's side of each), stopping where you are needed; `-From <n>` resumes | Once |
| `repos-to-g7.ps1` | Puts Aeraphim-Chatbot, househack and cryptoagent on G7 (remote `g7`, G7 mirrors to GitHub), like the other repositories. With `-TaxGlassesBranches`, also pushes the TaxGlasses branches that exist only on this PC | Once. Create the G7 repositories first (the commands are at the top of the script) |
| `prune-worktrees.ps1` | Lists TaxGlasses worktrees and removes the ones already merged into master that have no uncommitted files | When no Claude Code session is working in them |
| `backup/install-pc-backup.ps1` | Sets up the daily backup of this PC to G7 (scheduled task "PC backup to G7") | Once, in an admin PowerShell, after `g7/pc-backup` is installed on G7 |
| `backup/pc-backup.ps1` | The backup itself; `-DryRun` shows what it would take | Run by the task |
| `../agent/pc/setup-pc.ps1` | Lets Claude Code hand jobs to G7 (`ssh g7-agent ...`) | Once, before installing `agent/` on G7 |

`vaultwarden/pull-vault-backup.cmd` also runs on the PC. It is the "Vault backup pull" task,
which keeps a daily copy of the vault in `D:\VaultBackups`.

## Order, the first time

`setup-all.ps1` does steps 1 to 3 for you. By hand:

1. `agent/pc/setup-pc.ps1`, then install `agent/` on G7 (`agent/README.md`).
2. Install `g7/pc-backup` on G7, then `backup/install-pc-backup.ps1` here
   (`g7/pc-backup/README.md`). After the first backup, every branch and worktree on this PC
   also has a copy on G7 and in Miami.
3. Create the three repositories on G7, then `repos-to-g7.ps1 -Apply`. Then re-run the agent's
   `install.sh`, so the new repositories get its push hook.
4. Once the long Claude Code workflow on TaxGlasses has finished:
   `repos-to-g7.ps1 -Apply -TaxGlassesBranches`, then `prune-worktrees.ps1`, and with `-Apply`
   once the list looks right.
