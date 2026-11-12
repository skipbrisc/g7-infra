# Uptime Kuma on G7: is everything still up?

Checks each service every minute and alerts through ntfy when one stops answering or a
certificate is about to expire. Page: `http://192.168.0.6:3001` (at home directly, away over
WireGuard). It has its own login. Data lives in `/opt/uptime-kuma/data`.

It runs ON G7, so it cannot tell you G7 itself is down. That is Healthchecks.io's job.

## Install (root, once)

From `D:\TaxGlasses` in PowerShell, one command at a time:

    scp ops/g7/uptime-kuma/docker-compose.yml g7-taxglasses:/tmp/kuma-compose.yml

    ssh -t g7-taxglasses "sudo -v && sudo install -d -m 0755 /opt/uptime-kuma && sudo install -d -m 0750 /opt/uptime-kuma/data && sudo install -m 0644 /tmp/kuma-compose.yml /opt/uptime-kuma/docker-compose.yml && rm -f /tmp/kuma-compose.yml && cd /opt/uptime-kuma && sudo docker compose up -d && sleep 20 && curl -sS -o /dev/null -w '%{http_code}\n' http://192.168.0.6:3001/"

The last line should print `200` or `302`.

Then open `http://192.168.0.6:3001`, choose **SQLite** when asked for a database, and create
the admin account. Keep the password in Vaultwarden.

## ntfy user for alerts

    ssh -t g7-taxglasses "cd /opt/ntfy && sudo docker compose exec ntfy ntfy user add kuma"

    ssh -t g7-taxglasses "cd /opt/ntfy && sudo docker compose exec ntfy ntfy access kuma g7 write-only && sudo docker compose exec ntfy ntfy access kuma taxglasses write-only && sudo docker compose exec ntfy ntfy access kuma sites write-only && sudo docker compose exec ntfy ntfy access kuma memesniper write-only && sudo docker compose exec ntfy ntfy token add kuma"

The first asks for a password twice. The second prints a token starting `tk_`. Paste it only
into Uptime Kuma and Vaultwarden.

In Uptime Kuma: Settings > Notifications > Setup Notification, type **Ntfy**, four times:

| Friendly name | Server URL | Topic | Authentication |
| --- | --- | --- | --- |
| ntfy g7 | `http://127.0.0.1:2586` | `g7` | Access token = the `tk_` token |
| ntfy taxglasses | same | `taxglasses` | same |
| ntfy sites | same | `sites` | same |
| ntfy memesniper | same | `memesniper` | same |

## Monitors

Interval 60 seconds, retries 2 (so one slow answer does not page you), unless noted.

| Name | Type | Target | Alert to |
| --- | --- | --- | --- |
| TaxGlasses (live) | HTTP keyword `revision` | `http://10.77.0.1:8090/api/version` | taxglasses |
| TaxGlasses blue | HTTP | `http://10.77.0.1:8091/api/meta` | taxglasses |
| TaxGlasses green | HTTP | `http://10.77.0.1:8092/api/meta` | taxglasses |
| MemeSniper dashboard | HTTP | `http://10.77.0.1:8765/` | memesniper |
| Aeraphim CPA | HTTP, certificate expiry on | `https://www.aeraphimcpa.com/` | sites |
| Aeraphim contact | HTTP | `https://www.aeraphimcpa.com/contact` | sites |
| Guatemala Hope | HTTP keyword `Guatemala Hope`, certificate expiry on | `https://guatemalahope.org/` | sites |
| Guatemala Hope give | HTTP keyword `Guatemala Hope` | `https://guatemalahope.org/give` | sites |
| Jenkins | HTTP | `http://127.0.0.1:8080/login` | g7 |
| ntfy | HTTP keyword `healthy` | `http://127.0.0.1:2586/v1/health` | g7 |
| Vaultwarden | HTTP, certificate expiry on | `https://buttvault.duckdns.org/alive` (by hostname; its Caddy refuses HTTPS by bare IP) | g7 |
| Git over SSH | TCP port | `192.168.0.6` port `3333` | g7 |
| Internet from G7 | Ping, interval 120 | `1.1.1.1` | g7 |

Blue and green: the idle color is stopped between deploys only if a deploy failed; both
normally answer. During a deploy the idle one restarts, which the 2 retries absorb.

## Update

    ssh -t g7-taxglasses "cd /opt/uptime-kuma && sudo docker compose pull && sudo docker compose up -d"

## Backup

`/opt/uptime-kuma/data` must be in the nightly backup (see `ops/g7/backup/g7-backup`).
