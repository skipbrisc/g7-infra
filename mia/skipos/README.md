# SkipOS on the Miami server

SkipOS (the governed multi-agent stack, `D:\SkipOS`) runs on Miami as a Docker Compose stack:
about 20 containers, with the operator console reachable from the PC over the Miami VPN.
Written 2026-11-23. **Every script here has been syntax-checked and linted, and none has been
run on Miami yet.** Run them one at a time and read the output before the next.

    PC ── Miami VPN (10.78.0.11) ──▶ Caddy on Miami 10.78.0.1:8300 ──▶ console 127.0.0.1:3000
                                                                          │ mTLS
    G7 ── mirror ──▶ GitHub ──▶ deploy key ──▶ /opt/skipos ──▶ docker compose (project "skipos")

## Why it is built this way

- **Miami, not G7 or the PC.** The stack wants 6 to 8 GB of RAM. Miami has 31 GB and was idle;
  G7 has 7.5 GB and is full; the PC has no Docker.
- **Every container port stays on 127.0.0.1.** A port that Docker publishes bypasses ufw. If
  the console were published on the VPN address, Will and Frank could open it. So Caddy runs on
  the host, where ufw applies, and one rule lets in the PC alone.
- **The console has no login.** Whoever reaches it acts as the owner. The ufw rule is the lock.
- **Miami pulls from GitHub with a read-only deploy key.** No new path between G7 and Miami,
  and Miami can never push. It gets whatever G7 has mirrored.
- **Nothing deploys by itself.** `skipos-ctl pull` updates the files and stops. `skipos-ctl
  build` is the deploy.
- **Fresh instance.** The old stack's `.env` and volumes are gone, so this is a new database
  with new secrets and a governance bootstrap. The code is the same.

Miami was "not backed up anywhere, on purpose". That stops being true the moment SkipOS holds
anything you would miss. See "Backup" below: it is half done.

## Before you start

1. The SkipOS patches are applied and pushed to `g7`, and the GitHub mirror has caught up.
   `03-install.sh` checks for `infra/docker/.env.example` and stops if the patch is missing.
2. You can afford a few minutes of care on Miami. `01-docker.sh` does not restart WireGuard, but
   it does change firewall rules on the server that is your VPN exit. Keep the provider console
   (`console-mia.serverroom.net:11477`) open in a browser tab as the way back in.

## Install

From `D:\g7-infra` in PowerShell, one command at a time. Copy the folder over first:

    ssh mia "rm -rf /tmp/skipos-setup"
    scp -r mia/skipos mia:/tmp/skipos-setup
    scp g7/install-node24.sh mia:/tmp/skipos-setup/

**1. Docker, and WireGuard's rules for it.**

    ssh -t mia "sudo sh /tmp/skipos-setup/01-docker.sh"

Then, from a phone or the PC on the Miami VPN, load any website. If the internet is gone, the
old `wg0.conf` is beside the new one as `wg0.conf.before-docker`.

**2. Node 24**, for the governance bootstrap, which runs on the host. Its last line mentions
`jenkins-agent`, which does not exist on Miami; ignore that line.

    ssh -t mia "sudo sh /tmp/skipos-setup/install-node24.sh"

**3. The repository.** The first run prints a public key and stops.

    ssh -t mia "sudo sh /tmp/skipos-setup/02-repo.sh"

On GitHub: `skipbrisc/SkipOS` > Settings > Deploy keys > Add deploy key. Paste the key, leave
"Allow write access" unticked. Then run the same command again; it clones to `/opt/skipos`.

**4. The environment file, the marker, the control script.** It prints two secrets once.
**Put both in Vaultwarden before you do anything else.**

    ssh -t mia "sudo sh /tmp/skipos-setup/03-install.sh"

**5. First start.** About 20 images are built; allow 15 to 30 minutes.

    ssh -t mia "sudo skipos-ctl build"
    ssh -t mia "sudo skipos-ctl ps"

In `ps`, the setup containers (`provision-db-certs`, `migrate`, `provision-root`,
`ca-bootstrap`, `seed`, `export-host-certs`, `creds-bootstrap`) show as exited with code 0.
So does `worker-claude`: it stops by design until it is armed with `CLAUDE_AGENT_LIVE=1`.
Everything else should be running. If one is not: `sudo skipos-ctl logs <service>`.
(First run on Miami, 2026-11-23: 19 images built in about 4 minutes, 14 containers up.)

**6. Governance bootstrap.** A fresh database has no constitution and denies every run until
this is done (`docs/operations/governance-bootstrap.md` in SkipOS). It installs the repo's
packages on the host the first time, so it is slow once.

    ssh -t mia "sudo skipos-ctl bootstrap"
    ssh -t mia "sudo skipos-ctl bootstrap-check"

**7. The console.**

    ssh -t mia "sudo sh /tmp/skipos-setup/04-console.sh"

On the PC, connect the Miami VPN and open `http://10.78.0.1:8300`.

**8. Health check and backup.**

    ssh -t mia "sudo sh /tmp/skipos-setup/05-ops.sh"

Create the two Healthchecks.io checks it names and store their ping addresses as it says.

**9. Record it.** Refresh `mia/live` ("Refreshing the live copy" in `mia/README.md`), read the
diff, commit. Update the SkipOS row in `INFRA.md`: it still says "not a running service yet".

**Optional, last: nightly gates.** `06-gates.sh`. Read its header first.

    ssh -t mia "sudo sh /tmp/skipos-setup/06-gates.sh"

## Day to day

| To do this | Run on Miami |
|---|---|
| See what is running | `sudo skipos-ctl ps` |
| Read a service's log | `sudo skipos-ctl logs api` |
| Get the newest code | `sudo skipos-ctl pull` (changes nothing that is running) |
| Deploy it | `sudo skipos-ctl build` |
| Stop everything, keep the data | `sudo skipos-ctl down` |
| Start it again | `sudo skipos-ctl up` |

After a reboot `skipos.service` starts the stack by itself.

**Never run `docker compose down -v` here**, and never run a `validate-*` gate as root. `-v`
deletes the database, its credentials and the root escrow. The gates force-remove every
container named `skipos-*`. `/etc/skipos/live-host` makes the gates refuse; nothing stops a
hand-typed `down -v`.

## What is where on Miami

| Piece | Where |
|---|---|
| Checkout | `/opt/skipos`, owned by `skipos` (a login-less account, not in the `docker` group) |
| Deploy key | `/var/lib/skipos/.ssh/id_ed25519` |
| Stack secrets and settings | `/opt/skipos/infra/docker/.env`, root 0600 |
| Data | Docker volumes `skipos_pgdata`, `skipos_dbcreds`, `skipos_root-escrow`, `skipos_certs` and others |
| Control script | `/usr/local/sbin/skipos-ctl` |
| Boot unit | `/etc/systemd/system/skipos.service` |
| Live-host marker | `/etc/skipos/live-host` |
| Console proxy | `/etc/caddy/Caddyfile`, drop-in `caddy.service.d/10-after-wg0.conf` |
| Firewall | ufw: 8300/tcp on `wg0` from 10.78.0.11 only |
| Health check | `/usr/local/sbin/skipos-health`, root's crontab, every 5 minutes |
| Backup | `/usr/local/sbin/skipos-backup`, `skipos-backup.timer` at 02:10, into `/srv/skipos-backups` |

## Backup: half done

`skipos-backup` writes a nightly database dump, the small volumes and `.env` to
`/srv/skipos-backups`, and keeps 14 days. Two things are missing:

1. **It is on the same disk as the stack.** It covers a bad change or a wiped volume. It does
   not cover losing the server. An off-server copy needs a decision: G7 has 63 GB free and
   already runs a restic REST server for the PC, but that listens on the home LAN address,
   which Miami cannot reach.
2. **A restore has never been tried.** Do a drill before relying on it.

## Not done

- **Claude Code hooks from the PC.** SkipOS' hook expects the API on `127.0.0.1` and a governed
  folder on the same machine as the stack. With the stack on Miami, a tunnel
  (`ssh -L 7300:127.0.0.1:7300 -L 7303:127.0.0.1:7303 mia`) covers the first half only: files
  the hook governs on the PC would not exist in Miami's governed folder. This needs a design
  decision in SkipOS, not a config change.
- **The Python specialist workers** (stats, vision, audio). Off by default. To turn them on:
  `COMPOSE_PROFILES=console,specialists` in `.env`, then `sudo skipos-ctl build`.
- **The live model seams.** Everything runs on fixtures until `CLAUDE_AGENT_LIVE=1` or
  `ADVISOR_LIVE=1` and an `ANTHROPIC_API_KEY` are added to `.env`
  (`docs/operations/agent-claude-live-arming.md` and `advisor-live-arming.md` in SkipOS).

## Dates to know

- **About 90 days after the first start**, the initiative plane's standing delegation expires
  and that plane stops minting runs (it fails closed and says so on the console's
  `/initiative` page). Renewal is a ceremony:
  `docs/operations/initiative-delegation-renewal.md` in SkipOS.

## Secrets (none are in this repository)

| What | Where it lives | If lost |
|---|---|---|
| `AGE_ROOT_PASSPHRASE` | `.env` on Miami, and Vaultwarden | The root escrow cannot be unsealed. Fresh instance. |
| `AUTH_JWT_SECRET` | `.env` on Miami, and Vaultwarden | Generate a new one and restart; every session is logged out |
| Deploy key | Miami only | Delete it on GitHub, remove the file, run `02-repo.sh` again |
| Healthchecks ping addresses | `/etc/skipos/hc-*-url` on Miami | Copy them from each check's page |

## Removing it

    sudo systemctl disable --now skipos.service skipos-backup.timer
    sudo skipos-ctl down
    sudo ufw delete allow in on wg0 from 10.78.0.11 to 10.78.0.1 port 8300 proto tcp

That keeps the volumes. Deleting the data as well is `docker volume rm` on each `skipos_*`
volume, and cannot be undone.
