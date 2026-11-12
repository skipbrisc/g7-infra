# Healthchecks.io: is G7 alive, and did the jobs run?

Uptime Kuma runs on G7, so it can't report G7 itself going down, and it can't see a job
that silently stopped running. Healthchecks.io (hosted, free plan) waits for pings from G7
and alerts when one doesn't arrive.

| Check (slug) | Pinged by | Period | Grace | Means when it alerts |
| --- | --- | --- | --- | --- |
| `g7-heartbeat` | `g7-heartbeat.timer`, every 5 minutes | 5 minutes | 10 minutes | G7 is off, frozen, or has no internet |
| `g7-backup` | `g7-backup.service`, after a successful run | 1 day | 3 hours | last night's backup failed or never ran |
| `taxglasses-mirror` | `taxglasses-mirror.service`, after a successful push | 5 minutes | 30 minutes | the GitHub mirror stopped |

Pings go to `https://hc-ping.com/<ping key>/<slug>`. The ping key (Project > Settings >
Ping key) is in `/root/.healthchecks-ping-key` on G7 and in Vaultwarden, nowhere else.
`g7-hc-ping` never fails its caller.

## Install (root, once)

Create the three checks on healthchecks.io first, with exactly these slugs. Then from
`D:\TaxGlasses-ops` in PowerShell, one command at a time:

    ssh g7-taxglasses "rm -rf /tmp/g7-healthchecks && mkdir /tmp/g7-healthchecks"

    scp g7/healthchecks/g7-hc-ping g7/healthchecks/g7-heartbeat.service g7/healthchecks/g7-heartbeat.timer g7/healthchecks/ping-backup.conf g7/healthchecks/ping-mirror.conf g7/healthchecks/install.sh g7-taxglasses:/tmp/g7-healthchecks/

    ssh -t g7-taxglasses "sudo sh /tmp/g7-healthchecks/install.sh"

The installer asks for the ping key (typed or pasted, not shown), then tests all three
checks and prints OK or NOT FOUND for each.

## Add another job

Create a check with a new slug, then add `ExecStartPost=+/usr/local/sbin/g7-hc-ping <slug>`
to the job's service (a drop-in under `/etc/systemd/system/<name>.service.d/`), or call
`g7-hc-ping <slug>` at the end of a script.
