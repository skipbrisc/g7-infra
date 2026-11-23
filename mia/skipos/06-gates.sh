#!/bin/sh
# OPTIONAL. Sets up a nightly run of SkipOS' lane gates on Miami, isolated from the live stack.
# Run on Miami, from the folder holding these files:  sudo sh 06-gates.sh
#
# Why it needs its own Docker. The gates begin by force-removing every container named
# skipos-*, which on this server is the live stack. So they run as their own user,
# skipos-ci, against that user's own ROOTLESS Docker daemon: a separate daemon with its own
# containers, images and networks, which cannot see or touch root's. SkipOS' gates refuse to
# start on this server (the /etc/skipos/live-host marker) unless SKIPOS_GATES_ISOLATED=1 says
# exactly that, and only this user's job sets it.
#
# What runs: the lane gates through scripts/ci-local.mjs, in a private clone of /opt/skipos.
# Left out: the 7 compose phase gates (they publish the live stack's own loopback ports), and
#   redis-agent-isolation  starts compose services on the live stack's ports
#   orchestration, phase5  need Python and the worker requirements
#
# This is the least-proven file here: rootless Docker has not been set up on Miami before and
# nothing below has run. Do it last, and read the first night's log before trusting it.
set -eu
[ "$(id -u)" = 0 ] || { echo "run with sudo" >&2; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
U=skipos-ci
[ -x /opt/node24/bin/node ] || { echo "Node 24 is not at /opt/node24" >&2; exit 1; }
[ -d /opt/skipos/.git ] || { echo "/opt/skipos is not there yet" >&2; exit 1; }

apt-get install -y uidmap dbus-user-session slirp4netns fuse-overlayfs docker-ce-rootless-extras git openssl >/dev/null

id "$U" >/dev/null 2>&1 || useradd --create-home --shell /bin/bash "$U"
grep -q "^$U:" /etc/subuid || usermod --add-subuids 200000-265535 --add-subgids 200000-265535 "$U"
loginctl enable-linger "$U"
UID_N=$(id -u "$U")
RT=/run/user/$UID_N
# Lingering starts the user's systemd; give it a moment to create the runtime directory.
i=0; while [ ! -d "$RT" ] && [ $i -lt 20 ]; do sleep 1; i=$((i+1)); done
[ -d "$RT" ] || { echo "$RT did not appear; log in once as $U, then run this again" >&2; exit 1; }

as_ci() { sudo -u "$U" env HOME="/home/$U" XDG_RUNTIME_DIR="$RT" DBUS_SESSION_BUS_ADDRESS="unix:path=$RT/bus" PATH="/opt/node24/bin:/usr/bin:/bin" "$@"; }

[ -S "$RT/docker.sock" ] || as_ci dockerd-rootless-setuptool.sh install
as_ci systemctl --user enable --now docker
as_ci env DOCKER_HOST="unix://$RT/docker.sock" docker info --format 'rootless daemon: {{.ServerVersion}}, rootless={{.SecurityOptions}}'

# The checkout belongs to another user (skipos); git refuses to read it without this.
as_ci git config --global --get-all safe.directory | grep -qx /opt/skipos || as_ci git config --global --add safe.directory /opt/skipos
as_ci git config --global --get-all safe.directory | grep -qx /opt/skipos/.git || as_ci git config --global --add safe.directory /opt/skipos/.git

# A private clone of the server's checkout: the gates build and write inside their tree.
[ -d "/home/$U/skipos/.git" ] || as_ci git clone /opt/skipos "/home/$U/skipos"

install -m 0755 -o root -g root "$HERE/skipos-gates" /usr/local/bin/skipos-gates
sed "s/@UID@/$UID_N/g" "$HERE/skipos-gates.service" > /etc/systemd/system/skipos-gates.service
install -m 0644 -o root -g root "$HERE/skipos-gates.timer" /etc/systemd/system/skipos-gates.timer
systemctl daemon-reload
systemctl enable --now skipos-gates.timer

echo "Installed. Run it once by hand and read the result:"
echo "  sudo systemctl start skipos-gates ; sudo journalctl -u skipos-gates -n 80 --no-pager"
