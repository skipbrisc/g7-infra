---
name: g7-offload
description: Hand long-running or parallel coding work to Claude Code on Skip's G7 server, where it runs in tmux and keeps going when this PC sleeps. Use when the user says to offload, run on G7 or run in the background on the server, or when a task will take hours. Every command is `ssh g7-agent ...`.
allowed-tools:
  - Bash(ssh g7-agent *)
---

# Offload work to G7

G7 runs Claude Code jobs for this PC. Each job gets its own git worktree on a branch, cloned from G7's own Git server (remote `g7`), and runs headless in a tmux session. A job pushes its commits back to that branch on G7. You then fetch the branch here, review it and merge it as usual. Source and details: `D:\g7-infra\agent\README.md`.

## Before you start a job

1. **Make sure the starting point is on G7.** The job only sees what is on G7's Git server, not this PC. Push the base branch first, for example `git push g7 master`, or your feature branch if the job should continue it.
2. **Write a self-contained prompt into a file.** The job cannot see this conversation, so include:
   - the goal
   - the relevant files and context
   - the constraints
   - how to check the work (the project's verify or test command)
   - what "done" means
   The job already knows it is on Linux, that it should commit and push often, and that it should finish with a report.
3. **Check there is room.** At most 2 jobs run at once, and G7 has limited memory. `ssh g7-agent list` shows what is running.

## Commands

| Command | What it does |
|---|---|
| `ssh g7-agent repos` | Repositories the agent may use. |
| `ssh g7-agent start <repo> <branch> --name <job> [--base <branch>] < prompt.md` | Start a job. A new branch starts from `--base` (default: the release branch). An existing branch on G7 continues from where it is. Optional: `--model`, `--effort`, `--budget <usd>`. |
| `ssh g7-agent wait <job> --timeout 540` | Wait for a job. Blocks up to 9 minutes. Exit codes: 0 done, 1 failed or stopped, 2 still running. |
| `ssh g7-agent status <job>` | Details, commits and recent output. |
| `ssh g7-agent logs <job> -n 80` | Recent output. Add `--stderr` for errors. |
| `ssh g7-agent result <job>` | The job's final report, branch and commits. |
| `ssh g7-agent resume <job> < followup.md` | Follow-up in the same session and worktree, after the job has ended. |
| `ssh g7-agent stop <job>` | Interrupt a job. Its work is committed and pushed first. |
| `ssh g7-agent clean <job>` | Remove the worktree after the branch is merged. The branch stays on G7. |
| `ssh g7-agent doctor` / `ssh g7-agent mem` | Health and memory. |

Run these from the Bash tool: Git Bash handles `< prompt.md` correctly. `ssh -t g7-agent attach|watch <job>` is for the user in their own terminal. Don't run it yourself.

## While it runs

Don't poll in a tight loop. Either call `wait` (repeat it if it exits 2), or tell the user the job is running and check back with `status` when they ask. Long jobs take hours, and the user can watch with `ssh -t g7-agent watch <job>`.

## When it finishes

1. Read the report: `ssh g7-agent result <job>`.
2. Fetch the branch: `git fetch g7 <branch>`. Then review `git log` and `git diff` against the base.
3. Run the project's checks here, or its CI, as the repository's CLAUDE.md says. Merge only the way that file allows. G7's agent can never push the release branch, so merging is always done from this PC.
4. Once the branch is merged, run `ssh g7-agent clean <job>`.

## Limits to remember

- **The agent cannot reach** the LAN, Jenkins, Vaultwarden or other G7 services, and it has no sudo. Tasks that need them stay on this PC.
- **Exit code 3 from `start` or `resume` means G7 is full.** Wait for a job to finish, or ask the user.
- **Jobs use the user's Claude plan, like sessions here.** Offloading moves the computer work, not the usage limits.
- **MemeSniper and g7-infra are not open to the agent.** Only the repositories that `ssh g7-agent repos` lists are.
