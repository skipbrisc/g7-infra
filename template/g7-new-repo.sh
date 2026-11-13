#!/usr/bin/env bash
# g7-new-repo.sh: put a new project on G7 the same way as the others.
#   * bare repository /srv/git/repos/<RepoName>.git (you push to remote g7)
#   * GitHub mirror service and timer (G7 is the only thing that pushes to GitHub)
#   * Healthchecks.io ping after each successful mirror push (slug <slug>-mirror)
#   * a read-only SSH key for Jenkins, locked to this one repository
# Run as root on G7:
#   bash g7-new-repo.sh <RepoName> <github-owner>/<repo> [--dry-run]
# Idempotent: re-running skips what is already done. Touches no other project.
set -euo pipefail

[[ $# -ge 2 ]] || { echo "usage: $0 <RepoName> <github-owner>/<repo> [--dry-run]" >&2; exit 1; }
NAME=$1; GITHUB=$2; DRY=0; [[ "${3:-}" == "--dry-run" ]] && DRY=1
[[ "$NAME" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "bad repository name: $NAME" >&2; exit 1; }
[[ "$GITHUB" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || { echo "bad GitHub path: $GITHUB" >&2; exit 1; }
SLUG=$(printf '%s' "$NAME" | tr 'A-Z' 'a-z' | tr -c 'a-z0-9\n' '-' | sed 's/-\+/-/g; s/^-//; s/-$//')

GIT_USER=git
GIT_HOME=/srv/git
BARE=$GIT_HOME/repos/$NAME.git
KEYDIR=/root/g7-sites-keys
UNIT=/etc/systemd/system/$SLUG-mirror

say()  { printf '\n==> %s\n' "$*"; }
note() { printf '    %s\n' "$*"; }
run()  { if (( DRY )); then note "would run: $*"; else "$@"; fi; }
asgit(){ if (( DRY )); then note "would run as $GIT_USER: $*"; else sudo -u "$GIT_USER" -H "$@"; fi; }
write_file() {  # write_file <path> <content>
  if [[ -f "$1" ]] && [[ "$(cat "$1")" == "$2" ]]; then note "$1 already correct"; return; fi
  if (( DRY )); then note "would write $1:"; printf '%s\n' "$2" | sed 's/^/      /'; return; fi
  printf '%s\n' "$2" > "$1"; chmod 644 "$1"; note "wrote $1"
}

[[ $EUID -eq 0 ]] || { echo "run as root (sudo bash $0 ...)" >&2; exit 1; }
id "$GIT_USER" >/dev/null 2>&1 || { echo "user $GIT_USER missing" >&2; exit 1; }
(( DRY )) && echo "DRY RUN: nothing will be changed"

say "Bare repository $BARE"
if [[ -d "$BARE" ]]; then note "already exists"; else asgit git init --bare -b main "$BARE"; fi

say "GitHub remote git@github.com:$GITHUB.git"
if [[ -d "$BARE" ]] && sudo -u "$GIT_USER" -H git -C "$BARE" remote get-url github >/dev/null 2>&1; then
  note "remote already set: $(sudo -u "$GIT_USER" -H git -C "$BARE" remote get-url github)"
else
  asgit git -C "$BARE" remote add github "git@github.com:$GITHUB.git"
fi

say "Mirror service and timer ($SLUG-mirror)"
write_file "$UNIT.service" "[Unit]
Description=Sync $NAME to GitHub
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
User=$GIT_USER
Group=$GIT_USER
WorkingDirectory=$BARE
Environment=\"GIT_SSH_COMMAND=/usr/bin/ssh -o BatchMode=yes -o ConnectTimeout=15\"
ExecStart=/usr/bin/git push github --all
ExecStart=/usr/bin/git push github --tags
TimeoutStartSec=120"
write_file "$UNIT.timer" "[Unit]
Description=Sync $NAME to GitHub every minute

[Timer]
OnBootSec=1min
OnUnitInactiveSec=1min
Unit=$SLUG-mirror.service

[Install]
WantedBy=timers.target"
run mkdir -p "$UNIT.service.d"
write_file "$UNIT.service.d/healthchecks.conf" "# Runs only when the push to GitHub succeeded. \"+\" runs it as root so it can read the ping key.
[Service]
ExecStartPost=+/usr/local/sbin/g7-hc-ping $SLUG-mirror"
run systemctl daemon-reload
run systemctl enable --now "$SLUG-mirror.timer"

say "Jenkins read-only key, locked to this repository"
JKEY=$KEYDIR/$SLUG-jenkins
if (( DRY )); then
  note "would create $JKEY and authorize it for git-upload-pack on $BARE only"
else
  mkdir -p -m 700 "$KEYDIR"
  [[ -f "$JKEY" ]] || { ssh-keygen -q -t ed25519 -N '' -C "jenkins-$SLUG" -f "$JKEY"; note "generated $JKEY"; }
  AUTH=$GIT_HOME/.ssh/authorized_keys
  if grep -q "jenkins-$SLUG\$" "$AUTH" 2>/dev/null; then
    note "key already authorized"
  else
    printf 'restrict,command="git-upload-pack '"'"'%s'"'"'" %s\n' "$BARE" "$(cat "$JKEY.pub")" >> "$AUTH"
    chown "$GIT_USER:$GIT_USER" "$AUTH"; chmod 600 "$AUTH"
    note "authorized jenkins-$SLUG (read-only, $NAME only)"
  fi
fi

say "Left to do by hand"
cat <<TXT
    1. GitHub: the empty private repository $GITHUB must exist. The mirror starts working on
       its own once it does and something has been pushed to G7. Check with:
         journalctl -u $SLUG-mirror.service -n 5 --no-pager
    2. Healthchecks.io: create a check with slug  $SLUG-mirror  (period 5 minutes, grace 30).
    3. Jenkins: add a credential (SSH Username with private key, username 'git',
       id g7-git-$SLUG) with the private key from:   sudo cat $JKEY
       Then create the Pipeline job from SCM with the repository URL
         ssh://git@127.0.0.1:3333$BARE
    4. On the PC:  git remote add g7 ssh://git@192.168.0.6:3333$BARE
    5. Copy the three unit files into the g7-infra repository (systemd/) and commit.
TXT
