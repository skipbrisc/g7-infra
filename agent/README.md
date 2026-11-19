# G7 agent: Claude Code jobs on G7, handed over from the PC

Claude Code on the PC can hand a long job to G7, where it runs headless in its own tmux
session. It keeps going when the PC sleeps or reboots. Each job works in its own git worktree,
on a branch cloned from G7's Git server, and pushes its commits back to that branch. You fetch,
review and merge on the PC as usual. Written 2026-11-18. Tested off G7 with a stand-in for
Claude Code (the full flow: start, wait, stop, resume, clean, the push rules); the sandbox is
proven on G7 by the install's self-test.

    PC: Claude Code ── ssh g7-agent start TaxGlasses fig-x < prompt.md ──▶ G7: g7-agent (user agent)
                                                                     │ tmux (g7-agent-tmux.service)
                                                                     ▼
                         git push g7 ◀── job: worktree /srv/agent/work/<job>, claude -p ...
    PC: git fetch g7 fig-x, review, merge

## What runs where

| Piece | On G7 | Source here |
|---|---|---|
| The command (start, list, wait, result, stop, ...) | `/usr/local/bin/g7-agent` | `g7-agent` |
| Its helper files: output formatter, the job's extra instructions, tmux and DNS settings, master copy of the hook | `/usr/local/lib/g7-agent/` | `pretty.py`, `system-prompt.md`, `tmux.conf`, `resolv.conf`, `pre-receive` |
| Settings: jobs at once (2), permission mode, protected branches, ntfy topic | `/etc/g7-agent/config` | `config` |
| Repositories open to the agent | `/etc/g7-agent/repos` | `repos` |
| Memory cap for all jobs together (2.5 GB, 1 GB swap, half CPU weight) | `/etc/systemd/system/g7-agent.slice` | `g7-agent.slice` |
| The tmux server holding the jobs, and the sandbox around them | `/etc/systemd/system/g7-agent-tmux.service` | `g7-agent-tmux.service` |
| Git access for the agent: fetch and push, nothing else | `/srv/git/git-shell-commands/g7-agent-git` and `no-interactive-login` | same names |
| Push rules in each repository: no release branch, tags or deletions from the agent | `/srv/git/repos/<repo>.git/hooks/pre-receive` | `pre-receive` |
| The agent's home: Claude Code, its login, clones, worktrees, job logs | `/srv/agent` (user `agent`) | — |
| Claude Code's skill and SSH setup on the PC | `~/.claude/skills/g7-offload/`, `~/.ssh/config` | `pc/` |

## The guard rails

A job runs without permission prompts (`bypassPermissions`), so the limits come from G7 itself:

- **Memory.** Every job runs in `g7-agent.slice`, capped at 2.5 GB RAM and 1 GB swap together.
  If jobs hit the cap, the kernel ends the biggest process inside the slice, never MemeSniper or
  Jenkins. Agent processes also have a raised OOM score, so if G7 as a whole ever runs out, they
  go first. At most 2 jobs run at once; a third `start` is refused with exit code 3.
- **What it can see.** The sandbox hides `/srv/git`, `/srv/vaultwarden`, `/opt` (except
  `/opt/node24`), `/var/lib` (MemeSniper, Jenkins, Docker), `/mnt/data`, `/root`, `/home`,
  `/etc/taxglasses`, `/etc/memesniper-live` and `/etc/wireguard`. The user `agent` has no
  password, no sudo and no groups, and the sandbox blocks setuid programs.
- **What it can reach.** The internet (Claude, npm, PyPI, GitHub) and G7's own `127.0.0.1`
  (Git over SSH, DNS). Not the LAN, 192.168.0.6, the VPNs or Docker networks, so not Jenkins,
  Vaultwarden, TaxGlasses' live containers or the router. Known gap: services that listen on
  `127.0.0.1` too (Jenkins on all addresses, Prometheus, ntfy) can be reached; they need logins
  for anything that matters.
- **Git.** The agent's key may only fetch and push the repositories in `/etc/g7-agent/repos`.
  Its pushes are marked, and each of those repositories' `pre-receive` hook refuses the release
  branch (the repository's HEAD, so `master` for TaxGlasses), `master`/`main`, tags and
  branch deletions. Your own pushes are untouched. So a job can never trigger TaxGlasses-Deploy
  or a site deploy: those start from the release branch, which only the PC pushes.
- **The PC's key** may only run `g7-agent` (a forced command), not a shell.
- **Not open to the agent:** MemeSniper's repositories (Codex's) and g7-infra (it changes G7).

## Install (once)

1. **On the PC**, from `D:\g7-infra` in PowerShell:

       powershell -NoProfile -ExecutionPolicy Bypass -File agent\pc\setup-pc.ps1

   It makes the key `~/.ssh/g7_agent` (press Enter twice: no passphrase, so Claude Code can use
   it unattended), adds `Host g7-agent` to `~/.ssh/config`, installs the `g7-offload` skill and
   allows `Bash(ssh g7-agent *)` in `~/.claude/settings.json` (a backup is kept beside it).

2. **On G7**, after this folder is committed and pushed:

       ssh g7 "rm -rf /tmp/g7-agent-src"
       scp -r agent g7:/tmp/g7-agent-src
       scp $HOME\.ssh\g7_agent.pub g7:/tmp/g7_agent.pub
       ssh -t g7 "sudo sh /tmp/g7-agent-src/install.sh /tmp/g7_agent.pub"

   It creates the user, installs the files and Claude Code (the native installer, which keeps
   itself updated on the stable channel), sets up Git access and the hooks, starts the service,
   and ends with a **self-test inside the sandbox**. Every line should say PASS. Re-running is
   safe: running jobs are never restarted.

3. **Claude login for G7.** On the PC, run `claude setup-token`. It opens the browser and prints
   a token that lasts a year and uses your subscription. Then:

       ssh g7-agent set-token

   and paste the token. `ssh g7-agent doctor` warns when it is close to a year old.

4. **Check:** `ssh g7-agent doctor` should say ok on every line.

5. **Record it:** the files are listed in `g7/drift/MAP` (see "Drift" below). Commit and
   push g7-infra before installing, so the nightly drift check agrees with G7.

## Use

Ask Claude Code on the PC to "run this on G7" or "offload it"; the `g7-offload` skill tells it
the steps. By hand:

    git push g7 master                                    # the job sees only what is on G7
    ssh g7-agent start TaxGlasses fig-wa-credit --name wa < prompt.md
    ssh g7-agent wait wa --timeout 540                     # exit 2: still running, call again
    ssh -t g7-agent watch wa                               # read-only view; Ctrl-b d to leave
    ssh g7-agent result wa                                 # its report, branch and commits
    git fetch g7 fig-wa-credit                             # then review and merge as usual
    ssh g7-agent clean wa                                  # after merging

`ssh g7-agent help` lists everything. `--interactive` starts the normal Claude Code screen
instead of a headless run. Attach with `ssh -t g7-agent attach <job>` to steer it; the first
time, it asks you to accept the bypass-permissions warning.

When a job ends, any uncommitted changes are committed as a "WIP" commit and the branch is pushed,
so nothing is lost on G7. A job that was running when G7 rebooted shows as `lost`.
`ssh g7-agent resume <job> < followup.md` continues it in the same session and worktree.

## Notifications (optional)

To get a phone notification when a job ends, give the agent its own ntfy login, which may only
post to the topic `agent`. Run this on G7:

    cd /opt/ntfy && sudo docker compose exec ntfy ntfy user add agent
    cd /opt/ntfy && sudo docker compose exec -T ntfy ntfy access agent agent write-only
    cd /opt/ntfy && sudo docker compose exec -T ntfy ntfy token add agent

Then, on the PC: `ssh g7-agent set-ntfy-token` and paste the `tk_...` token. Subscribe to the
topic `agent` in the phone's ntfy app.

## Memory: before raising the cap

G7 has 7.5 GiB. The cap leaves about 5 GB for everything else, including MemeSniper's live
services, Jenkins builds, Prometheus and Grafana. `ssh g7-agent mem` shows what the jobs use now.
G7's Grafana dashboard (`http://192.168.0.6:3000`) shows memory over time. Raise
`MemoryHigh`/`MemoryMax` in `g7-agent.slice` and `MAX_JOBS` in `config` only if both show
headroom. Then commit, `sudo g7-apply` (the slice is a `yes` file), and
`sudo systemctl restart g7-agent-tmux` once no job is running.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `g7-agent-tmux` does not start, with a mount error about `resolv.conf` | G7's `/etc/resolv.conf` is a symlink systemd will not bind over: remove the `resolv.conf` entry from `BindReadOnlyPaths` and add the router to `IPAddressAllow` (`localhost 192.168.0.1`) |
| Self-test `FAIL cannot write /srv/agent` | systemd kept the home read-only: add `ReadWritePaths=/srv/agent` under `[Service]` in the unit, then `daemon-reload` and restart |
| Self-test `FAIL DNS` | dnsmasq is not answering on 127.0.0.1: either fix that, or add the router to `IPAddressAllow` (`localhost 192.168.0.1`) and drop the resolv.conf line |
| Self-test `FAIL Git fetch from X` | `sudo -u agent ssh -F /srv/agent/.config/g7-agent/ssh/config 127.0.0.1` shows why (key, host key or forced command) |
| `start` says the base is not on G7 | push it from the PC: `git push g7 <branch>` |
| A job's push was rejected | someone else pushed to that branch meanwhile; the commits are in `/srv/agent/work/<job>`: `sudo -u agent git -C /srv/agent/work/<job> log` |
| Exit code 3 | G7 is already running `MAX_JOBS` jobs |

## Undo

    sudo systemctl disable --now g7-agent-tmux
    sudo rm /etc/systemd/system/g7-agent-tmux.service /etc/systemd/system/g7-agent.slice && sudo systemctl daemon-reload
    sudo sed -i '/ g7-agent$/d' /srv/git/.ssh/authorized_keys
    sudo rm -r /srv/git/git-shell-commands /usr/local/lib/g7-agent /etc/g7-agent /usr/local/bin/g7-agent
    for r in TaxGlasses Aeraphim guatemalahope.org Aeraphim-Chatbot househack cryptoagent; do sudo rm -f /srv/git/repos/$r.git/hooks/pre-receive; done
    sudo userdel -r agent

The branches the agent pushed stay in the repositories.

## Drift

Every file above that lives under `/usr/local`, `/etc` or `/srv/git` is listed in
`g7/drift/MAP` (section "G7 agent"), so `g7-drift` compares it with Git each night. The
programs, their helper files and the slice are `yes` files (`g7-apply` may update them). The
service (long-running: it holds the jobs), the Git side, the hooks and `/etc/g7-agent/*` are
`no` files: change those by hand. `/srv/agent` is
the agent's own, like a home folder, and is not compared.
