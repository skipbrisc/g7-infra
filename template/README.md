# New project on G7

Everything a new project needs to match TaxGlasses, MemeSniper, Aeraphim and guatemalahope.org:
its own repository on G7, a GitHub mirror, a Jenkins job that scans and tests every push,
monitoring, and pinned runtimes. Written 2026-11-13. `g7-new-repo.sh` has been syntax-checked
only; use `--dry-run` the first time.

## Checklist

1. **Start the project folder.** Copy what applies from `files/` into it (they are dotfiles;
   in PowerShell use `Copy-Item -Force template\files\* <project>` and check with `dir -Force`):
   `.gitignore`, `.gitattributes`, `.gitleaksignore`, `.env.example`, `RUNBOOK.md`, `AGENTS.md`,
   and `.nvmrc` (Node) or `.python-version` (Python). Copy `Jenkinsfile.node` or
   `Jenkinsfile.python` to the project root as `Jenkinsfile` and set `NTFY_TOPIC` in it.
2. **Create an empty private repository on GitHub** with the project's name (no README).
3. **Create the G7 side** (bare repository, GitHub mirror timer, Healthchecks ping, Jenkins key):

       scp template/g7-new-repo.sh g7:/tmp/
       ssh -t g7 "sudo bash /tmp/g7-new-repo.sh <RepoName> <github-owner>/<repo> --dry-run"
       ssh -t g7 "sudo bash /tmp/g7-new-repo.sh <RepoName> <github-owner>/<repo>"

   It prints the remaining manual steps, including the Healthchecks slug to create.
4. **Push from the PC.** G7 is the only remote you push to; it publishes to GitHub.

       git init -b main
       git remote add g7 ssh://git@192.168.0.6:3333/srv/git/repos/<RepoName>.git
       git add -A; git commit -m "Initial commit"; git push -u g7 main

5. **Create the Jenkins job** (Pipeline, "Pipeline script from SCM", the G7 repository URL
   `ssh://git@127.0.0.1:3333/srv/git/repos/<RepoName>.git`, credential `g7-git-<slug>`,
   script path `Jenkinsfile`). Add the credential first from the key the script printed.
6. **Add monitoring.** Uptime Kuma: one monitor for the live URL or port
   (`g7/uptime-kuma/README.md`). Healthchecks.io: create the `<slug>-mirror` check (5 minute
   period, 30 minute grace).
7. **Add the project to the backup** only if it keeps state on G7 outside `/srv/git`,
   `/etc`, `/opt/memesniper*` and `/var/lib/memesniper*` (see `g7/backup/g7-backup`).
8. **Deploys.** The starter Jenkinsfiles only scan and test. Copy the pattern that fits:
   Vercel blue/green with rollback from Aeraphim or guatemalahope.org (`deploy/`), or
   containers with a compare-then-promote step from TaxGlasses (`ops/jenkins/`, and
   `g7/taxglasses-deploy` here).
9. **Record it.** Add the project's units and any new files under `/etc` or
   `/usr/local/sbin` to this repository (`systemd/`, `etc/`), and fill in its `RUNBOOK.md`.

## Rules every project follows

- Push to `g7`, never to GitHub. Merge to the release branch only on a green build.
- No secrets in Git. Secrets live in Vaultwarden and in root-only files on G7 or in the
  host's own settings (Vercel, Jenkins credentials). `.env.example` lists names, not values.
- The build fails on a leaked secret (gitleaks, whole history) and on a high or critical
  advisory in runtime dependencies. Reviewed exceptions go in `.gitleaksignore`.
- Runtimes are pinned in the repository: Node 24 (`/opt/node24` on G7), Python 3.13.
