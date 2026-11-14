# Runbook: guatemalahope.org

## What it is
The Guatemala Hope public website. Live at `https://guatemalahope.org`. A Next.js site
(Node 24.x) hosted on Vercel. Source: `D:\guatemalahope.org`.

## Is it up?
- Uptime Kuma: monitors "Guatemala Hope" (also warns before the certificate expires) and "Guatemala Hope give".
- By hand: `curl -sI https://guatemalahope.org` answers `200`.

## Deploy
Commit, push to G7, and Jenkins job GuatemalaHope-Deploy tests and deploys to Vercel:

    git push g7 main

To start it by hand, from `D:\guatemalahope.org` in PowerShell:

    & "C:\Program Files\Git\bin\bash.exe" deploy/g7.sh deploy
    & "C:\Program Files\Git\bin\bash.exe" deploy/g7.sh status

The job runs `npm ci`, the dependency audit (`npm audit --omit=dev --audit-level=high`), the
secret scan and the build, deploys a new Vercel deployment, checks it, and puts the previous
one back by itself if the check fails. A good deploy: `status` shows `"result":"SUCCESS"`.

## Roll back
    & "C:\Program Files\Git\bin\bash.exe" deploy/g7.sh rollback

Puts the previous production deployment back. You can also promote any earlier deployment
from the Vercel dashboard.

## Logs
- `& "C:\Program Files\Git\bin\bash.exe" deploy/g7.sh log` (last 80 lines of the Jenkins build).
- Runtime and build logs: the Vercel dashboard.

## Restart
Nothing to restart on G7; Vercel runs it. To force a fresh build, run `deploy` again.

## Secrets and config
| What | Where it lives | How to rotate |
|---|---|---|
| Jenkins deploy-bot user and token (`G7_JENKINS_USER`, `G7_JENKINS_TOKEN`) | Your PC's environment; Vaultwarden | New API token in Jenkins |
| Vercel token used by the Jenkins job | Jenkins credential `vercel-token` | New token in Vercel, update the credential |
| Vercel project settings | `deploy/vercel.env` and the Vercel dashboard | Edit and commit |
| Node version | `.nvmrc` and `"engines"` in `package.json` (24.x) | Change both, and the Vercel project setting |

## Common failures
| Symptom | Likely cause | Fix |
|---|---|---|
| Build fails at `npm audit` | A dependency has a new high or critical advisory | `npm audit`; for `next`, which is pinned exactly: `npm install --save-exact next@<fixed version> eslint-config-next@<same>`; commit and push |
| Build fails at the secret scan | gitleaks found something new | Remove the secret and rotate it |
| `deploy/g7.sh` says "set G7_JENKINS_USER" | The two variables are not set in this shell | Set them from Vaultwarden |
| `bash` is not recognized | PowerShell has no bash on its path | Use the full `& "C:\Program Files\Git\bin\bash.exe"` form above |
| Images missing after a deploy | New media was not committed | `git status`; commit the files under `public/` |
| GitHub copy is behind | Mirror timer | `deploy/g7.sh mirror` |

## Who to ask
You. Vendor: Vercel (hosting).
