# G7 monitoring: Prometheus and Grafana

Metrics over time for G7 itself and for each service on it, so a slow night, a full disk or a
service that crowds out another can be seen after the fact. Uptime Kuma (is it answering?)
and Healthchecks.io (did the job run?) stay as they are; this answers "what was happening".

Open **http://192.168.0.6:3000/** (at home directly; away, over WireGuard), user `admin`,
password in Vaultwarden (and in `/opt/grafana/admin_password` on G7, root only). The
dashboard is **G7** in the folder G7.

## What runs

| Piece | From | Listens on | Keeps |
|---|---|---|---|
| Prometheus 2.53 | Debian `prometheus`, user `prometheus` | 127.0.0.1:9090 | `/var/lib/prometheus/metrics2`, 400 days or 5 GB, whichever comes first |
| node_exporter 1.9 | Debian `prometheus-node-exporter`, user `prometheus` | 127.0.0.1:9100 | nothing: CPU, memory, swap, disks, network, systemd unit states |
| process-exporter 0.8 | Debian `prometheus-process-exporter`, user `prometheus` | 127.0.0.1:9256 | nothing: CPU, memory and swap per user |
| Grafana 13.3 | Docker `grafana/grafana`, `/opt/grafana` | 192.168.0.6:3000 | the named volume `grafana_grafana_data` (in the nightly backup) |

Everything is scraped every 30 seconds. Together they use roughly 300 to 500 MB of memory.

**Per service.** process-exporter puts every process in a group named after the user it runs
as. On G7 each service runs as its own user, so the groups are services: `jenkins` (the Jenkins
controller), `jenkins-agent` (every CI build and deploy), `git`, `prometheus`, the MemeSniper
users, `root` (system services and most containers), and numbers for container users that have
no name on the host. It reads what `ps` shows (CPU, memory, swap per process) and no files.

**What it does not do, on purpose.** No container gets the Docker socket or G7's filesystem
(the usual Docker recipes for cAdvisor and node_exporter mount `/` or the socket, which would put
the MemeSniper wallet key or root within a container's reach). Prometheus and the exporters are
Debian packages, so unattended-upgrades keeps them patched; the weekly image scan covers
Grafana. Nothing listens beyond G7 except Grafana's page, which needs the admin login.

## The dashboard

Top row: CPU busy, memory available, swap in use, free space on both disks, failed services.
Then CPU and load, memory and swap, swapping activity, disk space, disk reads and writes and
network; then CPU, memory and swap for the 10 largest services, and the failed units by name.

The dashboard is `grafana/provisioning/dashboards/g7.json` in this folder. Grafana refuses
edits in the browser; change the JSON here instead (or build a panel in the browser on a copy,
export it, and paste it into the file).

## Changing it

Edit the file here, commit, `git push g7 main`, `ssh -t g7 "sudo g7-apply"`. g7-apply installs
the Prometheus and exporter settings and Grafana's provisioning files, but restarts nothing:

    sudo systemctl restart prometheus                 # prometheus.yml or prometheus.default
    sudo systemctl restart prometheus-node-exporter   # its .default
    sudo systemctl restart prometheus-process-exporter
    # Grafana reads dashboard changes by itself within a minute.

Check `prometheus.yml` first with `promtool check config /etc/prometheus/prometheus.yml`. The
compose file is check-only (like the other compose files): change it by hand on G7, then
`cd /opt/grafana && sudo docker compose up -d`. To update Grafana, change the image tag there.

## Install (once, root)

1. Install the three Debian packages without letting them start with Debian's defaults
   (which listen on every address):

       printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d && chmod 755 /usr/sbin/policy-rc.d
       apt-get install -y --no-install-recommends prometheus prometheus-node-exporter prometheus-process-exporter
       rm -f /usr/sbin/policy-rc.d

2. From `D:\g7-infra`:

       ssh g7 "rm -rf /tmp/g7-monitoring"
       scp -r g7/monitoring g7:/tmp/g7-monitoring
       ssh -t g7 "sudo sh /tmp/g7-monitoring/install.sh"

   It installs the settings, starts the three services, checks they listen on 127.0.0.1 only
   and are scraped, starts Grafana and waits for it. The first time it prints Grafana's admin
   password once: put it in Vaultwarden.

Undo: `cd /opt/grafana && sudo docker compose down`, then
`sudo systemctl disable --now prometheus prometheus-node-exporter prometheus-process-exporter`.
