# Runbook: MemeSniper on G7

This page covers the G7 side only. Day-to-day operation of the bot, studies and the local
workspace is Codex's, in `D:\memesniper\RUNBOOK.md` and `STATUS.md`. Main is paper. No live
mode, real orders, transfers or signing are authorized; see
[MEMESNIPER-GO-LIVE-GATES.md](MEMESNIPER-GO-LIVE-GATES.md).

## What runs on G7
| Thing | What it is | State on 2026-11-14 |
|---|---|---|
| `memesniper.service` | Paper monitor dashboard, `http://10.77.0.1:8765` over WireGuard, monitor-only | Running |
| `memesniper-tier2-20261110.service` | Tier 2 unsigned buy compatibility study | Finished and inactive. Next start uses Node 24 from `/opt/memesniper-runtime-node24-20261113` |
| `memesniper-tier2-20261110-source.service` | Tier 2's source relay | Unchanged |
| `memesniper-study-watchdog.timer` | Watches a running study | See Codex's notes |
| Jenkins job MemeSniper-CI | Runs the tests for every pushed commit, network off | Never deploys or restarts anything |
| `/var/lib/memesniper-signer/live-keypair.json` | The live wallet. The only key; there is no seed phrase | Not in use |

Code: `/opt/memesniper` (app and venv). State: `/var/lib/memesniper`. System Node stays 20
for everything except Tier 2.

## Is it up?
- Uptime Kuma: monitor "MemeSniper dashboard". Alerts: ntfy topic `memesniper`.
- By hand: `ssh g7 "systemctl is-active memesniper.service"` prints `active`.
- Tier 2 should print `inactive`: `ssh g7 "systemctl is-active memesniper-tier2-20261110.service"`.

## Deploy
There is no deploy job. Releases are built by Codex as hash-pinned packages, reviewed, and
run by you as root, one step at a time. Pushing a commit only runs CI:

    git push g7 <branch>

A good push: MemeSniper-CI goes green for that commit. The CI pipeline itself lives in
`D:\memesniper-deploy\ci\`; install a change with `scripts\jenkins-job.ps1 -Action Push`.

## Roll back
Tier 2's Node 24 selection, with Tier 2 stopped, as root on G7:

    /bin/bash /root/memesniper-node24-tier2-release-20261113.sh rollback

If that refuses because Debian updated `/usr/bin/node` or `/usr/bin/python3` since staging:

    mv /etc/systemd/system/memesniper-tier2-20261110.service.d/90-node24-20261113.conf /root/memesniper-node24-plan-20261113/
    systemctl daemon-reload

Either way Tier 2 goes back to `/opt/memesniper-tier2-20261110` on Node 20. Nothing is
started and no study state changes.

## Logs
- Paper monitor: `ssh -t g7 "sudo journalctl -u memesniper.service -n 50 --no-pager"`.
- CI: the MemeSniper-CI job in Jenkins.
- Node 24 release evidence: `/root/memesniper-node24-plan-20261113/` on G7, copies in
  `D:\memesniper-state\`.

## Restart
Ask Codex first. Do not restart, stop or start any MemeSniper unit while a study is
running, and do not start a stopped study or worker because a page, a deadline or a STOP
file seems to say so. Restarting never resets risk windows, loss history or budgets, and
must not be used to try.

## Secrets and config
| What | Where it lives | How to rotate |
|---|---|---|
| Live keypair | `/var/lib/memesniper-signer/live-keypair.json` (root-only). Never print, move or regenerate it | Cannot be rotated without a new wallet |
| Encrypted keypair copy | `memesniper-live-keypair.json.enc`, kept off the server; passphrase on paper | Re-encrypt with a new passphrase |
| Keypair check | SHA-256 `338c18faee6ea23d1b788907c9c2ee51c8a28ed00abe1e54596eef5f4d509520` | - |
| Live RPC credentials | `/etc/memesniper-live/rpc.env` | Helius dashboard. Never rotate a key to get around a quota refusal |
| Dashboard control token | `/var/lib/memesniper/secrets/control-token.txt` | Codex's procedure |

Restore the keypair (passphrase on paper), then check the hash:

    openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 -in memesniper-live-keypair.json.enc -out live-keypair.json

## Common failures
| Symptom | Likely cause | Fix |
|---|---|---|
| MemeSniper-CI red | A test failed, or the SDK artifact is missing on the agent | Read the console. "SDK SOURCE: npm ci FALLBACK" means the production SDK artifact under `/var/lib/jenkins-agent/artifacts/` is gone |
| MemeSniper-CI yellow | `pip-audit` found an advisory | Tell Codex; it updates `requirements.lock` |
| HTTP 429 "max usage reached" from Solana | Provider quota | Wait. Leave the cooldown in place; a paced `getSlot` over HTTP must succeed before reopening websockets |
| Dashboard does not load | WireGuard off, or the service stopped | Turn WireGuard on; check `is-active` |
| Someone reinstalled `/opt/node24` | Tier 2 would run an unqualified Node | Check `sha256sum /opt/node24/bin/node` is `a7ec1b37e6ff9d187e4198c5b6df9a4eb1c74dd31804fb3bac55cc4ceca1ac01`; if not, roll back Tier 2 and requalify |

## Who to ask
Codex owns the MemeSniper tree: one editing CLI at a time in `D:\memesniper`. You approve
and run anything on G7.
