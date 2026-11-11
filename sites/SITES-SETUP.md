# guatemalahope.org + Aeraphim on G7

Same pattern as TaxGlasses and MemeSniper: you push to `g7`, G7 mirrors to GitHub, Jenkins on G7 tests every push and does deploys with a health check and automatic rollback. Both sites **stay hosted on Vercel** — Jenkins deploys to Vercel instead of restarting a systemd unit.

| | guatemalahope.org | Aeraphim |
|---|---|---|
| Bare repo | `/srv/git/repos/guatemalahope.org.git` | `/srv/git/repos/Aeraphim.git` |
| Mirror | `guatemalahope-mirror.timer` → github.com/skipbrisc/guatemalahope.org | `aeraphim-mirror.timer` → github.com/skipbrisc/Aeraphim |
| Jenkins job | `GuatemalaHope-Deploy` | `Aeraphim-Deploy` |
| Tests | lint, typecheck, vitest, secret scan | build + SEO tests (+ browser tests with `--with-browsers`) |
| Live check | `https://guatemalahope.org` `/`, `/give` | `https://www.aeraphimcpa.com` pages 200, internal files 404 |
| Local remote | `g7` (already added) | `g7` (already added) |

How a deploy works (`deploy/vercel-deploy.sh`): build on G7 → upload to Vercel **without** touching the live domain → smoke-test that deployment URL → promote → health-check the live domain → if it fails, roll back to the deployment that was live before (exit 2). A failed smoke test never reaches the live site.

## 0. Before anything else — commit what's live

- **Aeraphim:** the live site was deployed from your working tree, and a lot of it is not in Git yet (`services.html`, `tax-preparation-and-planning.html`, `consultation-guide.html`, the font and JS files in `assets/`, several `tools/` scripts). Deploying `main` as it stands would publish an older site. Commit those first. `output/` is not ignored — add it to `.gitignore` unless you want it in the repo.
- **guatemalahope.org:** `main` is 4 commits ahead of GitHub, plus uncommitted edits and `public/media/Updates/`. Commit what you want live.
- Both repos now have new files to commit: `Jenkinsfile`, `deploy/vercel-deploy.sh`, `deploy/vercel.env`, `deploy/g7.sh`, and a G7 section at the end of `CLAUDE.md`.
- Fill in `VERCEL_ORG_ID` and `VERCEL_PROJECT_ID` in each `deploy/vercel.env` (run `npx vercel link` in the repo and copy them from `.vercel/project.json`, or read them from the Vercel dashboard).

## 1. Stop Vercel's own Git deploys (do this before the first push to g7)

Once G7 mirrors to GitHub, Vercel's GitHub integration would also deploy every push — racing Jenkins and skipping the health check. For **each** project in Vercel: Settings → Git → **Disconnect**. Domains, env vars and Web Analytics are unaffected.

## 2. Server setup

```bash
scp -P 3333 D:\TaxGlasses-ops\sites\setup-g7-sites.sh buttmud@192.168.0.6:/tmp/     # from Windows
sudo bash /tmp/setup-g7-sites.sh --dry-run     # on G7: shows every change, touches nothing
sudo bash /tmp/setup-g7-sites.sh               # add --with-browsers to run Aeraphim's Playwright tests too
```

It creates the bare repos, mirror units, a read-only Jenkins key per repo (locked to that repo, like `jenkins-local-git` is to TaxGlasses), and `/etc/sudoers.d/sites-ops` so `buttmud` can force a mirror sync. If the `git` user's existing GitHub key can't reach these repos, it generates a deploy key per repo and prints it: add each on GitHub (repo → Settings → Deploy keys) **with write access**.

Then seed from your PC:

```bash
cd D:\guatemalahope.org && git push g7 --all && git push g7 --tags
cd D:\Aeraphim          && git push g7 --all && git push g7 --tags
```

Within a minute `journalctl -u guatemalahope-mirror -n 5` / `-u aeraphim-mirror` should show the GitHub push.

## 3. Jenkins credentials (Manage Jenkins → Credentials → Global)

| ID | Kind | Value |
|---|---|---|
| `g7-git-guatemalahope` | SSH Username with private key, user `git` | `sudo cat /root/g7-sites-keys/guatemalahope-jenkins` |
| `g7-git-aeraphim` | SSH Username with private key, user `git` | `sudo cat /root/g7-sites-keys/aeraphim-jenkins` |
| `vercel-token` | Secret text | Vercel → Account Settings → Tokens (scope: your team) |
| `vercel-bypass-guatemalahope` / `vercel-bypass-aeraphim` | Secret text, optional | Project → Settings → Deployment Protection → Protection Bypass for Automation. Only needed if protection is on; run deploys with `USE_BYPASS=true`. Without it, the smoke test is skipped and only the post-promote live check runs. |

## 4. Jenkins jobs

For each site: New Item → Pipeline → `GuatemalaHope-Deploy` / `Aeraphim-Deploy` → *Pipeline script from SCM* → Git → `ssh://git@127.0.0.1:3333/srv/git/repos/guatemalahope.org.git` (or `Aeraphim.git`), credential from step 3, branch `*/main`, script path `Jenkinsfile`. Run once by hand to register the parameters and the 2-minute poll. After that, every push to `g7` runs the tests; deploys only happen with `DEPLOY=true`.

## 5. Let Claude Code / Codex drive it

- Add both jobs to the `deploy-bot` user's Job/Build + Job/Read permissions (same token as MemeSniper-Deploy). Agents then use `bash deploy/g7.sh deploy|rollback|test|status|log|push|mirror` with `G7_JENKINS_USER` / `G7_JENKINS_TOKEN` set.
- `mirror` goes over SSH as `buttmud` (your `claude-taxglasses` key works), limited by sudoers to `systemctl start <site>-mirror.service`.
- Claude Code permissions are yours to grant. To allow the helper and block direct GitHub/Vercel pushes, merge this into each repo's `.claude/settings.local.json`:

```json
"permissions": {
  "allow": ["Bash(bash deploy/g7.sh:*)", "Bash(git push g7:*)", "Bash(git fetch g7:*)"],
  "deny":  ["Bash(git push origin:*)", "Bash(vercel deploy:*)", "Bash(npx vercel deploy:*)", "Bash(vercel promote:*)", "Bash(vercel rollback:*)"]
}
```

## 6. Lock out direct GitHub pushes (after the mirror works)

```bash
git -C D:\guatemalahope.org remote set-url --push origin "DISABLED-push-to-g7"
git -C D:\Aeraphim          remote set-url --push origin "DISABLED-push-to-g7"
```

## Rollback by hand

`bash deploy/g7.sh rollback`, or in Jenkins run the job with `ROLLBACK_ONLY=true`, or Vercel dashboard → Deployments → previous → Instant Rollback.
