# Runbook: aeraphimcpa.com

## What it is
The Aeraphim CPA public website. Live at `https://aeraphimcpa.com`. A static site built by
`node tools/build-site.mjs` and hosted on Vercel (project `aeraphim`, Node 24.x). It collects
no client tax data. Source: `D:\Aeraphim`. Full detail: `DEPLOYMENT.md` there.

## Is it up?
- Uptime Kuma: monitors "Aeraphim CPA" (also warns before the certificate expires) and "Aeraphim contact".
- By hand: `curl -sIL https://www.aeraphimcpa.com/` ends with `200`.

## Deploy
Commit, push to G7, and Jenkins job Aeraphim-Deploy tests and deploys to Vercel:

    git push g7 main

To start it by hand, from `D:\Aeraphim` in PowerShell:

    & "C:\Program Files\Git\bin\bash.exe" deploy/g7.sh deploy
    & "C:\Program Files\Git\bin\bash.exe" deploy/g7.sh status

The job runs the secret scan and the site's tests, deploys a new Vercel deployment, checks
it, and puts the previous one back by itself if the check fails. A good deploy: `status`
shows `"result":"SUCCESS"`.

## Roll back
    & "C:\Program Files\Git\bin\bash.exe" deploy/g7.sh rollback

Puts the previous production deployment back. You can also promote any earlier deployment
from the Vercel dashboard.

## Logs
- `& "C:\Program Files\Git\bin\bash.exe" deploy/g7.sh log` (last 80 lines of the Jenkins build).
- Runtime and build logs: the Vercel dashboard, project `aeraphim`.

## Restart
Nothing to restart; it is static files on Vercel. To force a fresh build, run `deploy` again.

## Secrets and config
| What | Where it lives | How to rotate |
|---|---|---|
| Jenkins deploy-bot user and token (`G7_JENKINS_USER`, `G7_JENKINS_TOKEN`) | Your PC's environment; Vaultwarden | New API token in Jenkins |
| Vercel token used by the Jenkins job | Jenkins credential `vercel-token` | New token in Vercel, update the credential |
| Vercel project settings | `deploy/vercel.env` and the Vercel dashboard | Edit and commit |
| Example environment | `.env.example` | Keep in step with the real settings |

## Common failures
| Symptom | Likely cause | Fix |
|---|---|---|
| Build fails at the secret scan | gitleaks found something new | Remove the secret and rotate it. A false positive goes in `.gitleaksignore` |
| Build fails at a test | A page, link, CSP or SEO check broke | `deploy/g7.sh log`, fix, push again |
| `deploy/g7.sh` says "set G7_JENKINS_USER" | The two variables are not set in this shell | Set them from Vaultwarden |
| `bash` is not recognized | PowerShell has no bash on its path | Use the full `& "C:\Program Files\Git\bin\bash.exe"` form above |
| Contact form or booking frame stops working | Formspree or Google Calendar, or a CSP change | Check the browser console for CSP errors; see `DEPLOYMENT.md` |
| GitHub copy is behind | Mirror timer | `deploy/g7.sh mirror` |

## Who to ask
You. Vendors: Vercel (hosting), Formspree (contact form), Google Calendar (booking).
