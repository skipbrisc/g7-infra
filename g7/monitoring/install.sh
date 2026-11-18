#!/bin/sh
# Installs (or brings back to Git's version) G7's monitoring from this folder: the settings of
# Prometheus, its two exporters and Alertmanager (Debian packages, installed beforehand and left
# stopped; README.md, "Install", step 1), Alertmanager's ntfy login, and Grafana in Docker.
# Run as root on G7:
#   sudo sh /tmp/g7-monitoring/install.sh
# Prints Grafana's admin password once, the first time; it is kept in /opt/grafana/admin_password.
set -eu
PATH=/usr/sbin:/usr/bin:/sbin:/bin
D=$(cd "$(dirname "$0")" && pwd)
[ "$(id -u)" = 0 ] || { echo "run as root: sudo sh $0" >&2; exit 1; }
for p in prometheus prometheus-node-exporter prometheus-process-exporter prometheus-alertmanager; do
  dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q 'install ok installed' \
    || { echo "$p is not installed (README.md, Install, step 1)" >&2; exit 1; }
done
command -v docker >/dev/null || { echo "docker is missing" >&2; exit 1; }
if ss -ltnH | awk '{print $4}' | grep -q ':3000$' && ! docker ps --format '{{.Names}}' | grep -qx grafana-grafana-1; then
  echo "something else already listens on port 3000; Grafana needs it" >&2; exit 1
fi

echo "== Alertmanager's ntfy login (write-only to topic g7)"
TOKEN=/etc/prometheus/ntfy-alerts.token
if [ ! -s "$TOKEN" ]; then
  N="docker compose -f /opt/ntfy/docker-compose.yml exec -T"
  if ! $N ntfy ntfy user list 2>&1 | grep -q '^user alertmanager '; then
    NTFY_PASSWORD=$(openssl rand -hex 24) $N -e NTFY_PASSWORD ntfy ntfy user add alertmanager >/dev/null
  fi
  $N ntfy ntfy access alertmanager g7 write-only >/dev/null
  t=$($N ntfy ntfy token add alertmanager 2>&1 | grep -o 'tk_[A-Za-z0-9_-]*' | head -n 1)
  [ -n "$t" ] || { echo "no ntfy token came back for alertmanager" >&2; exit 1; }
  (umask 027; printf '%s\n' "$t" > "$TOKEN"); unset t
fi
chown root:prometheus "$TOKEN"; chmod 0640 "$TOKEN"
echo "token file: $(stat -c '%U:%G %a' "$TOKEN")"

echo "== Prometheus, exporters and Alertmanager"
install -o root -g root -m 0644 "$D/prometheus.yml" /etc/prometheus/prometheus.yml
install -d -o root -g root -m 0755 /etc/prometheus/rules
install -o root -g root -m 0644 "$D/alerts.yml" /etc/prometheus/rules/g7.yml
install -o root -g root -m 0644 "$D/alertmanager.yml" /etc/prometheus/alertmanager.yml
install -o root -g root -m 0644 "$D/prometheus-alertmanager.default" /etc/default/prometheus-alertmanager
install -o root -g root -m 0644 "$D/process-exporter.yml" /etc/prometheus/process-exporter.yml
install -o root -g root -m 0644 "$D/prometheus.default" /etc/default/prometheus
install -o root -g root -m 0644 "$D/prometheus-node-exporter.default" /etc/default/prometheus-node-exporter
install -o root -g root -m 0644 "$D/prometheus-process-exporter.default" /etc/default/prometheus-process-exporter
for u in prometheus-node-exporter prometheus-process-exporter prometheus-alertmanager; do
  install -d -o root -g root -m 0755 "/etc/systemd/system/$u.service.d"
  install -o root -g root -m 0644 "$D/exporter-hardening.conf" "/etc/systemd/system/$u.service.d/hardening.conf"
done
promtool check config /etc/prometheus/prometheus.yml >/dev/null
promtool check rules /etc/prometheus/rules/g7.yml >/dev/null
amtool check-config /etc/prometheus/alertmanager.yml >/dev/null
systemctl daemon-reload
systemctl enable --quiet prometheus prometheus-node-exporter prometheus-process-exporter prometheus-alertmanager
systemctl restart prometheus-node-exporter prometheus-process-exporter prometheus-alertmanager prometheus
sleep 3
for s in prometheus-node-exporter prometheus-process-exporter prometheus-alertmanager prometheus; do
  systemctl is-active --quiet "$s" || { echo "$s did not start:" >&2; journalctl -u "$s" -n 15 --no-pager >&2; exit 1; }
done
wide=$(ss -ltnH | awk '{print $4}' | grep -E ':(9090|9093|9094|9100|9256)$' | grep -v '^127\.0\.0\.1:' || true)
[ -z "$wide" ] || { echo "listening beyond 127.0.0.1: $wide" >&2; exit 1; }
echo "running, listening on 127.0.0.1 only; waiting for the first scrapes"
sleep 35
up=$(curl -fsS 'http://127.0.0.1:9090/api/v1/query?query=up' | python3 -c 'import json,sys; print(" ".join("%s=%s" % (r["metric"]["job"], r["value"][1]) for r in json.load(sys.stdin)["data"]["result"]))')
echo "targets: $up"
case "$up" in *=0*) echo "a target is down" >&2; exit 1 ;; esac
rules=$(curl -fsS http://127.0.0.1:9090/api/v1/rules | python3 -c 'import json,sys; print(sum(len(g["rules"]) for g in json.load(sys.stdin)["data"]["groups"]))')
echo "alert rules loaded: $rules"
end=$(date -u -d '+1 minute' +%Y-%m-%dT%H:%M:%SZ)
amtool --alertmanager.url=http://127.0.0.1:9093 alert add alertname=G7AlertTest severity=default \
  --annotation=summary='Test from the monitoring install: alerts reach your phone' --end="$end"
echo "test alert sent: ntfy topic g7 gets it in about 30 seconds, and a 'resolved' one a few minutes later"

echo "== Grafana"
install -d -o root -g root -m 0700 /opt/grafana
install -o root -g root -m 0644 "$D/grafana/docker-compose.yml" /opt/grafana/docker-compose.yml
for d in datasources dashboards; do
  install -d -o root -g root -m 0755 "/opt/grafana/provisioning/$d"
  for f in "$D/grafana/provisioning/$d"/*; do install -o root -g root -m 0644 "$f" "/opt/grafana/provisioning/$d/"; done
done
NEW=
if [ ! -s /opt/grafana/admin_password ]; then
  (umask 077; openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | cut -c1-24 > /opt/grafana/admin_password)
  NEW=1
fi
chown 472:472 /opt/grafana/admin_password; chmod 0400 /opt/grafana/admin_password
docker compose -f /opt/grafana/docker-compose.yml up -d --quiet-pull
i=0
until curl -fsS -m 3 http://192.168.0.6:3000/api/health >/dev/null 2>&1; do
  i=$((i + 1)); [ "$i" -lt 40 ] || { echo "Grafana did not answer:" >&2; docker compose -f /opt/grafana/docker-compose.yml logs --tail 20 >&2; exit 1; }
  sleep 3
done
echo "Grafana answers at http://192.168.0.6:3000/ (user admin)"
if [ -n "$NEW" ]; then
  echo "Grafana admin password, shown this once (put it in Vaultwarden now): $(cat /opt/grafana/admin_password)"
fi
echo "done"
