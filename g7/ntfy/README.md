# ntfy on G7: phone alerts

Jenkins posts to the `taxglasses` topic at `http://127.0.0.1:2586`; your phone subscribes at
`http://192.168.0.6:2586` (at home directly, away over WireGuard). Login is required: the
server denies everything by default, so other WireGuard peers can't read or post.

## Install (root, once)

From `D:\TaxGlasses` in PowerShell:

    scp ops/g7/ntfy/docker-compose.yml ops/g7/ntfy/server.yml g7-taxglasses:/tmp/
    ssh -t g7-taxglasses "sudo -v && sudo install -d -m 0755 /opt/ntfy /opt/ntfy/etc && sudo install -d -m 0750 /opt/ntfy/lib && sudo install -m 0644 /tmp/docker-compose.yml /opt/ntfy/docker-compose.yml && sudo install -m 0644 /tmp/server.yml /opt/ntfy/etc/server.yml && rm -f /tmp/docker-compose.yml /tmp/server.yml && cd /opt/ntfy && sudo docker compose up -d && sleep 3 && curl -fsS http://127.0.0.1:2586/v1/health"

The last line should print `{"healthy":true}`.

## Users and the Jenkins token

    ssh -t g7-taxglasses "cd /opt/ntfy && sudo docker compose exec ntfy ntfy user add --role=admin skip"
    ssh -t g7-taxglasses "cd /opt/ntfy && sudo docker compose exec ntfy ntfy user add jenkins && sudo docker compose exec ntfy ntfy access jenkins taxglasses write-only && sudo docker compose exec ntfy ntfy token add jenkins"

Each `user add` asks for a password twice. The last command prints a token starting `tk_`.
In Jenkins: Manage Jenkins > Credentials > System > Global credentials > Add Credentials,
kind *Secret text*, ID `ntfy-token`, secret = the `tk_` token. Keep the token and both
passwords in Vaultwarden.

## Phone

Install the ntfy app. Settings > Default server (or "Add subscription" > "Use another server"):
`http://192.168.0.6:2586`, sign in as `skip`, subscribe to `taxglasses`. On an iPhone, also
uncomment `upstream-base-url` in `server.yml` and reinstall it, or alerts arrive only when the
app is open.

## Test

    ssh g7-taxglasses "curl -s -u skip -d 'Test from G7' http://127.0.0.1:2586/taxglasses"
