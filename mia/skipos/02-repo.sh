#!/bin/sh
# Puts the SkipOS checkout on Miami at /opt/skipos, pulled from GitHub with a read-only
# deploy key. GitHub is G7's mirror, so Miami always gets what was pushed to G7.
# Run on Miami:  sudo sh 02-repo.sh
# First run: it makes the key, prints the public half and stops. Add that key to the GitHub
# repository (Settings > Deploy keys, read-only), then run it again.
# Syntax-checked only; not yet run on Miami.
set -eu
[ "$(id -u)" = 0 ] || { echo "run with sudo" >&2; exit 1; }

REPO=git@github.com:skipbrisc/SkipOS.git
DEST=/opt/skipos
HOME_DIR=/var/lib/skipos
KEY=$HOME_DIR/.ssh/id_ed25519

apt-get install -y git openssh-client >/dev/null

# A login-less account that owns the checkout and the key. It is not in the docker group:
# the stack is started by root (skipos-ctl), never by this account.
id skipos >/dev/null 2>&1 || useradd --system --home-dir "$HOME_DIR" --create-home --shell /usr/sbin/nologin skipos
install -d -m 0700 -o skipos -g skipos "$HOME_DIR/.ssh"

if [ ! -e "$KEY" ]; then
  sudo -u skipos ssh-keygen -q -t ed25519 -N '' -C "skipos@mia deploy key" -f "$KEY"
  echo
  echo "Add this as a READ-ONLY deploy key on github.com/skipbrisc/SkipOS, then run this again:"
  echo
  cat "$KEY.pub"
  echo
  exit 0
fi

GIT_SSH="ssh -i $KEY -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"
install -d -m 0755 -o skipos -g skipos "$DEST"
if [ ! -d "$DEST/.git" ]; then
  sudo -u skipos env GIT_SSH_COMMAND="$GIT_SSH" git clone --branch main "$REPO" "$DEST"
else
  sudo -u skipos env GIT_SSH_COMMAND="$GIT_SSH" git -C "$DEST" pull --ff-only
fi
# Later pulls (skipos-ctl pull) use the same key without the environment variable.
sudo -u skipos git -C "$DEST" config core.sshCommand "$GIT_SSH"

echo "Checkout: $DEST at $(sudo -u skipos git -C "$DEST" log -1 --format='%h %s')"
