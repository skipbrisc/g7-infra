# Runbook: MemeSniper on G7

This page covers the G7 side only. Day-to-day operation of the bot, studies and the local
workspace is Codex's, in `D:\memesniper\RUNBOOK.md` and `STATUS.md`. Main is paper. No live
mode, real orders, transfers or signing are authorized; see
[MEMESNIPER-GO-LIVE-GATES.md](MEMESNIPER-GO-LIVE-GATES.md).

## What runs on G7
| Thing | What it is | State on 2026-11-14 |
|---|---|---|
| `memesniper.service` | Paper monitor dashboard, `http://10.77.0.1:8765` over WireGuard, monitor-only | Running |
| `memesniper-tier2-20261110.service` | Tier 2 unsigned buy compatibility study | Finished and inactive. Next start runs the app in `/opt/memesniper-runtime-node24-20261113` with Node at `/opt/node24/bin/node` |
| `memesniper-tier2-20261110-source.service` | Tier 2's source relay | Unchanged |
| `memesniper-study-watchdog.timer` | Watches a running study | See Codex's notes |
| Jenkins job MemeSniper-CI | Runs the tests for every pushed commit. The test stages run with the network off; checkout, install and the security audit use it | Never deploys or restarts anything |
| `/var/lib/memesniper-signer/live-keypair.json` | The live wallet. The only key; there is no seed phrase | Not in use. Balance not verified here |

Code: `/opt/memesniper` (app and venv). State: `/var/lib/memesniper`. System Node
(`/usr/bin/node`, 20 today) serves everything except Tier 2. `/opt/node24` is shared with
CI and the website pipelines, so do not reinstall or upgrade it without requalifying Tier 2.

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

Either way Tier 2 goes back to the application in `/opt/memesniper-tier2-20261110`, which
looks up the system Node at `/usr/bin/node`. That is Node 20 today; a Debian update could
change it. Nothing is started and no study state changes.

## Logs
- Paper monitor: `ssh -t g7 "sudo journalctl -u memesniper.service -n 50 --no-pager"`.
- CI: the MemeSniper-CI job in Jenkins.
- Node 24 release evidence: `/root/memesniper-node24-plan-20261113/` on G7, copies in
  `D:\memesniper-state\`.

## Restart
Ask Codex first. Do not restart or start any MemeSniper unit while a study is running, and
do not start a stopped study or worker because a page, a deadline or a STOP file seems to
say so. Restarting never resets risk windows, loss history or budgets, and must not be
used to try.

**Emergency exception.** If something is plainly wrong (orders you did not expect, runaway
errors, a suspected break-in), stopping is always allowed:
`ssh -t g7 "sudo systemctl stop <unit>"`. Write down the time and what you saw, tell Codex,
and do not start it again yourself.

## Secrets and config
| What | Where it lives | How to rotate |
|---|---|---|
| Live keypair | `/var/lib/memesniper-signer/live-keypair.json`, owned by `memesniper-signer`, mode 0600 (root can also read it). Never print, move or regenerate it | Cannot be rotated without a new wallet |
| Encrypted keypair copy | `memesniper-live-keypair.json.enc`, kept off the server; passphrase on paper | Re-encrypt with a new passphrase |
| Keypair check | SHA-256 `338c18faee6ea23d1b788907c9c2ee51c8a28ed00abe1e54596eef5f4d509520` | - |
| Live RPC credentials | `/etc/memesniper-live/rpc.env` | Helius dashboard. Never rotate a key to get around a quota refusal |
| Dashboard control token | `/var/lib/memesniper/secrets/control-token.txt` | Codex's procedure |

Restore the keypair during a rebuild only, never over an existing key. As root, into a
fresh private folder, then check the hash before it goes anywhere (passphrase on paper):

    umask 077
    d=$(mktemp -d)
    openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 -in memesniper-live-keypair.json.enc -out "$d/live-keypair.json"
    sha256sum "$d/live-keypair.json"

The hash must be the one in the table. Then confirm the public address matches your
records, and install it as `memesniper-signer`, mode 0600, by Codex's procedure.

## Common failures
| Symptom | Likely cause | Fix |
|---|---|---|
| MemeSniper-CI red | A test failed, or the SDK artifact could not be used | Read the console. "SDK SOURCE: npm ci FALLBACK" means the production SDK artifact under `/var/lib/jenkins-agent/artifacts/` is missing, or it or its helper failed the hash check |
| MemeSniper-CI yellow | `pip-audit` found an advisory | Tell Codex; it updates `requirements.lock` |
| HTTP 429 "max usage reached" from Solana (research feed) | Provider quota | Wait. Leave the cooldown in place; a paced `getSlot` over HTTP must succeed before the research feed reopens websockets. The live prototype is HTTP-only and does not use `getSlot` |
| Dashboard does not load | WireGuard off, or the service stopped | Turn WireGuard on; check `is-active` |
| Someone reinstalled `/opt/node24` | Tier 2 would run an unqualified Node | Check `sha256sum /opt/node24/bin/node` is `a7ec1b37e6ff9d187e4198c5b6df9a4eb1c74dd31804fb3bac55cc4ceca1ac01`; if not, roll back Tier 2 and requalify |

## Who to ask
Codex owns the MemeSniper tree: one editing CLI at a time in `D:\memesniper`. You approve
and run anything on G7.
