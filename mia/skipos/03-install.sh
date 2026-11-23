#!/bin/sh
# Prepares SkipOS to run on Miami: the environment file with fresh secrets, the live-host
# marker, skipos-ctl and the boot unit. It does not start anything.
# Run on Miami, from the folder holding these files:  sudo sh 03-install.sh
# Needs: 01-docker.sh, 02-repo.sh, and Node 24 at /opt/node24 (g7/install-node24.sh).
# Syntax-checked only; not yet run on Miami.
set -eu
[ "$(id -u)" = 0 ] || { echo "run with sudo" >&2; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
DIR=/opt/skipos
ENV_FILE=$DIR/infra/docker/.env

[ -d "$DIR/.git" ] || { echo "$DIR is not there yet: run 02-repo.sh" >&2; exit 1; }
[ -f "$DIR/infra/docker/.env.example" ] || {
  echo "$DIR has no infra/docker/.env.example: the lane 2 patch is not on main yet" >&2; exit 1; }
[ -x /opt/node24/bin/node ] || { echo "Node 24 is not at /opt/node24: run g7/install-node24.sh" >&2; exit 1; }
command -v docker >/dev/null 2>&1 || { echo "Docker is not installed: run 01-docker.sh" >&2; exit 1; }
apt-get install -y openssl >/dev/null

# --- the environment file -------------------------------------------------------------------
if [ -e "$ENV_FILE" ]; then
  echo "$ENV_FILE already exists; left alone."
else
  AGE=$(openssl rand -hex 32)
  JWT=$(openssl rand -hex 32)
  umask 077
  cat > "$ENV_FILE" <<ENV
# SkipOS on Miami. Written by mia/skipos/03-install.sh on $(date -u +%Y-%m-%d). Root only.
AGE_ROOT_PASSPHRASE=$AGE
AUTH_JWT_SECRET=$JWT
HOOK_GOVERNED_ROOT_HOST=$DIR/infra/docker/runtime/governed
HOOK_CERTS_ROOT_HOST=$DIR/infra/docker/runtime/certs
COMPOSE_PROFILES=console
ENV
  chown root:root "$ENV_FILE"; chmod 0600 "$ENV_FILE"
  echo
  echo "=== PUT THESE TWO IN VAULTWARDEN NOW. They are shown once. ==="
  echo "SkipOS Miami AGE_ROOT_PASSPHRASE: $AGE"
  echo "SkipOS Miami AUTH_JWT_SECRET:     $JWT"
  echo "Without AGE_ROOT_PASSPHRASE the root escrow cannot be unsealed, ever."
  echo "==============================================================="
  echo
fi

# --- the live-host marker ---------------------------------------------------------------------
# With this file present the repo's validate-* gates refuse to start here. They force-remove
# every container named skipos-* and the phase gates delete the volumes
# (scripts/lib/live-host-guard.mjs in SkipOS).
install -d -m 0755 /etc/skipos
[ -e /etc/skipos/live-host ] || echo "SkipOS live stack. Set up $(date -u +%Y-%m-%d). See mia/skipos in g7-infra." > /etc/skipos/live-host

# --- the control script and the boot unit ---------------------------------------------------
install -m 0755 -o root -g root "$HERE/skipos-ctl" /usr/local/sbin/skipos-ctl
install -m 0644 -o root -g root "$HERE/skipos.service" /etc/systemd/system/skipos.service
systemctl daemon-reload
systemctl enable skipos.service

echo "Ready. Nothing is running yet. Next:"
echo "  sudo skipos-ctl build       first start: builds about 20 images, allow 15-30 minutes"
echo "  sudo skipos-ctl ps          every long-running service should be 'running'"
echo "  sudo skipos-ctl bootstrap   loads the constitution into the fresh database"
