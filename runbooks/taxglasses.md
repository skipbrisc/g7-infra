# Runbook: TaxGlasses

## What it is
The tax web form. Live at `http://10.77.0.1:8090`, reachable only over WireGuard. Runs on G7
as two containers, blue and green, behind a Caddy proxy; one is live and the other is where
the next release is staged. Previews: blue `:8091`, green `:8092`. Everything is root's, in
`/opt/taxglasses`. Full detail: `D:\TaxGlasses\docs\deploy.md`.

## Is it up?
- Uptime Kuma: monitors "TaxGlasses (live)", "TaxGlasses blue" and "TaxGlasses green". Alerts: ntfy topic `taxglasses`.
- By hand, over WireGuard: `curl -s http://10.77.0.1:8090/api/meta` answers JSON, and
  `curl -s http://10.77.0.1:8090/api/version` shows the live revision.
- Containers: `ssh -t g7 "sudo docker ps --filter name=taxglasses"` shows proxy, blue and
  green, each `healthy`.

## Deploy
Commit, then from `D:\TaxGlasses`:

    powershell.exe -NoProfile -File ./scripts/ci-remote.ps1

It pushes to G7 and runs TaxGlasses-CI (about 3.5 minutes; do not interrupt it). A green
build on `master` starts TaxGlasses-Deploy, which stages the release on the idle color and
compares its answers with live.

| Compare result | What happens |
|---|---|
| Identical | Promotes by itself |
| Answers differ | Waits for you in Jenkins for up to 2 days. Read the diff: every `[money]` line must match a commit that says it moves that figure. Then Promote or Abort |
| Error | Fails. Live is untouched |

A good deploy: the Deploy job is green and `/api/version` shows the new SHA.

## Roll back
    ssh -t g7 "sudo /usr/local/sbin/taxglasses-deploy rollback"

Points the proxy back at the previous release in seconds. It only works until the next
stage, and refuses while a candidate is staged. To go back further, deploy the older commit
through the normal flow.

## Logs
- Build and deploy: Jenkins jobs TaxGlasses-CI, TaxGlasses-Deploy, TaxGlasses-Nightly.
- The app: `ssh -t g7 "sudo docker logs --tail 100 taxglasses-blue-1"` (or `-green-1`, `-proxy-1`).

## Restart
- One app container: `ssh -t g7 "sudo docker restart taxglasses-blue-1"`. Safe any time for
  the idle color; for the live color users see a few seconds of errors.
- Jenkins or its agent, from `D:\TaxGlasses`:
  `powershell.exe -NoProfile -File ./scripts/g7-restart.ps1 -Service all`. It refuses while
  a build is running.

## Secrets and config
| What | Where it lives | How to rotate |
|---|---|---|
| Credential the Git hook uses to start Jenkins | `/etc/taxglasses/jenkins-hook.env` on G7 | New Jenkins API token, replace the file |
| Jenkins API token for the PC scripts | `~/.jenkins-cli` on the PC | New token in Jenkins, replace the file |
| Jenkins agent secret | `jenkins-agent.service` on G7 | From the node's page in Jenkins |
| Compose file and Caddy config | `/opt/taxglasses`; copies in g7-infra `etc/taxglasses/` | Edit, copy back, commit |

## Common failures
| Symptom | Likely cause | Fix |
|---|---|---|
| ntfy "nightly check FAILED" | Live no longer answers a fixture as it did at promotion | Read the Nightly console log, `[money]` lines first; check whether the container restarted. See `docs/deploy.md`, "On a FAILED alert" |
| ntfy "baseline not recorded" | The post-deploy recording step failed | Nothing to do; the first nightly run records one |
| Deploy waits forever | The compare found differences | Open TaxGlasses-Deploy in Jenkins and Promote or Abort |
| Builds fail in seconds, "spawn helper" | Java updated under Jenkins | `g7-restart.ps1 -Service all` |
| No nightly alert at all and the job shows aborted | The agent was offline at 04:40 | `g7-status.ps1`, then restart the agent |
| Page does not load, containers healthy | WireGuard is off on your device | Turn it on |

## Who to ask
You. Jenkins pipelines are in `D:\TaxGlasses\ops\jenkins\`; the deploy script's source is
g7-infra `g7/taxglasses-deploy`.
