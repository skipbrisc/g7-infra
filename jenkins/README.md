# Jenkins jobs kept in g7-infra

Inline pipelines whose source of truth is this folder (the TaxGlasses jobs live in TaxGlasses'
`ops/jenkins/`, the website jobs in each site's `Jenkinsfile`). `g7-drift` compares each job with
its file through the `job` lines in `g7/drift/MAP`.

| Job | File | Runs on | What it does |
|---|---|---|---|
| SkipOS-CI | `SkipOS-CI.Jenkinsfile` | `g7-worker`, Node 24 from `/opt/node24` | polls `SkipOS.git` `main` every 2 minutes: `npm ci`, `npm run typecheck`, `npm run test:unit` (Vitest capped at 3 workers). Alerts to ntfy `sites` on failure and recovery |

SkipOS-CI clones with the Jenkins credential `g7-git-skipos`, the read-only key that
`template/g7-new-repo.sh` made for SkipOS (`/root/g7-sites-keys/skipos-jenkins` on G7).
There's no deploy job: SkipOS isn't a running service yet.

## Changing a job

Edit the file here, then replace the `<script>` of the live job with it through the Jenkins CLI
(`get-job`, swap the script, `update-job`), as TaxGlasses' `scripts/jenkins-jobs.ps1` does. A new
job must be built once by hand: Jenkins registers the `pollSCM` trigger only after a run.

## SkipOS: what was left out, and what it would need

First green build: #2 on 2026-11-23, 252 test files, 3,999 tests, about 1 minute in all.

`npm ci` needs `ONNXRUNTIME_NODE_INSTALL_CUDA=skip`. Otherwise `onnxruntime-node` 1.21.0 tries to
download its CUDA build on linux-x64, which returns 404. G7 has no GPU, so nothing is lost.

**Integration and e2e tests.** That's 121 `*.integration.test.ts` and 3 `*.e2e.test.ts` files.
**`validate:*` gates.** 41 of the 42 `scripts/validate-*.mjs` scripts bring up the Docker Compose
stack in `infra/docker/` (only `validate-citations.mjs` doesn't). Both groups would need:

- **Docker access for `jenkins-agent`.** It isn't in the `docker` group today. That group is
  root-equivalent on G7, which also runs TaxGlasses' live containers and Vaultwarden. A separate
  agent user or a rootless Docker would be safer than adding `jenkins-agent` to the group. Needs sudo.
- **Memory.** The full stack is about 20 services: Postgres with pgvector (pg17), two Redis,
  Temporal, auth, PDP, embedder, API, orchestrator, the Node, Python and Claude workers, and the
  agent. The three Python workers alone have limits of 0.5, 1 and 1.5 GB. G7 has 7.5 GiB in all
  and about 3.7 GiB available with TaxGlasses, MemeSniper and Jenkins running. The full stack won't
  fit beside them, so at most one gate at a time, on the smaller compose files
  (`docker-compose.gate.yml`, `phase1`, `stage2`), with `disableConcurrentBuilds` and a lock shared
  with the TaxGlasses jobs.
- **Disk.** GitHub Actions clears about 10 GB before these jobs ("free disk space" in
  `.github/workflows/ci.yml`). G7's `/` has 63 GB free (71% used), so a nightly
  `docker image prune` would be needed.
- **Python.** The orchestration and phase5 gates start a real `worker-python` and need its
  requirements, including onnxruntime.
- **The live model key**, only for the live lanes. `validate-agent-claude-e2e.mjs` and the
  `*_LIVE=1` switches read `ANTHROPIC_API_KEY` from `infra/docker/.env`. That file isn't on the PC
  or on G7; without it the gates run on fixtures. If it's ever added, it belongs in a Jenkins
  credential, not a file in the workspace.
