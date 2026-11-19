#!/bin/sh
# Install (or update) the G7 agent runner. Safe to re-run; it never restarts running jobs.
# Run as root on G7 from the folder holding these files, with the PC's public key:
#   sudo sh /tmp/g7-agent-src/install.sh /tmp/g7_agent.pub
# What it sets up is described in agent/README.md.
set -eu
cd "$(dirname "$0")"
PUB=${1:-}
H=/srv/agent
LIB=/usr/local/lib/g7-agent
SOCK=/run/g7-agent/tmux.sock
SSHD=$H/.config/g7-agent/ssh
say() { printf '\n== %s\n' "$*"; }
die() { echo "install.sh: $*" >&2; exit 1; }
as_agent() { runuser -u agent -- env HOME="$H" PATH=/usr/local/bin:/usr/bin:/bin "$@"; }

[ "$(id -u)" = 0 ] || die "run as root (sudo sh install.sh <key.pub>)"
[ -n "$PUB" ] && [ -r "$PUB" ] || die "usage: sudo sh install.sh <the PC's g7_agent.pub>"
KEY=$(grep -E '^(ssh-ed25519|ecdsa-sha2-nistp[0-9]+|ssh-rsa) [A-Za-z0-9+/=]+( [^"]*)?$' "$PUB" | head -n 1 || true)
[ -n "$KEY" ] || die "$PUB does not hold an SSH public key"
[ -x /opt/node24/bin/node ] || die "Node 24 is missing at /opt/node24 (g7/install-node24.sh)"
id git >/dev/null 2>&1 || die "the git user is missing"
[ -d /srv/git/.ssh ] || die "/srv/git/.ssh is missing"

say "packages"
apt-get install -y tmux git python3 curl ca-certificates openssh-client coreutils >/dev/null

say "user agent: home $H, no password, no sudo, no other groups"
if ! id agent >/dev/null 2>&1; then
  useradd --system --user-group --create-home --home-dir "$H" --shell /bin/bash \
    --comment "G7 agent jobs (Claude Code)" agent
fi
usermod -p '*' agent
[ "$(id -nG agent)" = agent ] || echo "   WARNING: agent is in other groups: $(id -nG agent) (remove them)"
chown agent:agent "$H"; chmod 0750 "$H"
for d in .config .config/g7-agent "$SSHD" repos work jobs .claude .local; do
  case "$d" in /*) p=$d ;; *) p=$H/$d ;; esac
  install -d -o agent -g agent -m 0750 "$p"
done
chmod 0700 "$H/.config/g7-agent" "$SSHD"

say "the PC's key: it may only run g7-agent (forced command)"
install -d -o root -g root -m 0755 "$H/.ssh"
AK=$H/.ssh/authorized_keys
BODY=$(printf '%s\n' "$KEY" | awk '{print $2}')
touch "$AK"
if grep -qF "$BODY" "$AK"; then
  echo "   already authorized"
else
  printf 'restrict,pty,command="/usr/local/bin/g7-agent --ssh" %s\n' "$KEY" >> "$AK"
  echo "   authorized: $(printf '%s' "$KEY" | awk '{print $3}')"
fi
chown root:root "$AK"; chmod 0644 "$AK"

say "programs and settings"
install -o root -g root -m 0755 g7-agent /usr/local/bin/g7-agent
install -d -o root -g root -m 0755 "$LIB"
install -o root -g root -m 0644 pretty.py system-prompt.md tmux.conf resolv.conf "$LIB/"
install -o root -g root -m 0755 pre-receive "$LIB/pre-receive"
install -d -o root -g root -m 0755 /etc/g7-agent
for f in config repos; do
  if [ -f "/etc/g7-agent/$f" ] && ! cmp -s "$f" "/etc/g7-agent/$f"; then
    echo "   /etc/g7-agent/$f differs from Git and was left alone (g7-drift will show the difference)"
  else
    install -o root -g root -m 0644 "$f" "/etc/g7-agent/$f"
  fi
done

say "the agent's Git key: fetch and push through git-shell, only the repositories in /etc/g7-agent/repos"
[ -f "$SSHD/g7_git" ] || as_agent ssh-keygen -q -t ed25519 -N '' -C g7-agent -f "$SSHD/g7_git"
cat > "$SSHD/config" <<EOF
Host 127.0.0.1
    Port 3333
    User git
    IdentityFile $SSHD/g7_git
    IdentitiesOnly yes
    UserKnownHostsFile $SSHD/known_hosts
    StrictHostKeyChecking yes
    BatchMode yes
EOF
ssh-keyscan -p 3333 127.0.0.1 2>/dev/null | grep -v '^#' > "$SSHD/known_hosts.new" || true
[ -s "$SSHD/known_hosts.new" ] || die "could not read G7's SSH host key on 127.0.0.1:3333"
mv "$SSHD/known_hosts.new" "$SSHD/known_hosts"
chown agent:agent "$SSHD/config" "$SSHD/known_hosts"; chmod 0600 "$SSHD/config" "$SSHD/known_hosts"

install -d -o root -g root -m 0755 /srv/git/git-shell-commands
install -o root -g root -m 0755 g7-agent-git no-interactive-login /srv/git/git-shell-commands/
GAK=/srv/git/.ssh/authorized_keys
ABODY=$(awk '{print $2}' "$SSHD/g7_git.pub")
if grep -qF "$ABODY" "$GAK" 2>/dev/null; then
  echo "   agent key already authorized for git"
else
  printf 'restrict,from="127.0.0.1,::1",command="g7-agent-git" %s\n' "$(cat "$SSHD/g7_git.pub")" >> "$GAK"
  echo "   agent key authorized for git (forced command g7-agent-git)"
fi
chown git:git "$GAK"; chmod 0600 "$GAK"

say "pre-receive hook in each repository open to the agent"
grep -v '^[[:space:]]*\(#\|$\)' /etc/g7-agent/repos | while read -r r; do
  B=/srv/git/repos/$r.git
  if [ ! -d "$B" ]; then echo "   $r: not on G7 yet (re-run this after it is)"; continue; fi
  if [ -f "$B/hooks/pre-receive" ] && ! cmp -s "$LIB/pre-receive" "$B/hooks/pre-receive"; then
    echo "   $r: has a pre-receive hook of its own; left alone, so the agent cannot push to $r"
    continue
  fi
  install -o git -g git -m 0755 "$LIB/pre-receive" "$B/hooks/pre-receive"
  echo "   $r: ok"
done

say "Git settings for the agent"
as_agent git config --global user.name "G7 agent"
as_agent git config --global user.email "agent@buttserver"
as_agent git config --global core.sshCommand "ssh -F $SSHD/config"
as_agent git config --global init.defaultBranch main
as_agent git config --global push.autoSetupRemote true
as_agent git config --global fetch.prune true

say "Claude Code for the agent (native installer; it keeps itself up to date)"
if [ ! -x "$H/.local/bin/claude" ]; then
  as_agent sh -c 'curl -fsSL https://claude.ai/install.sh | bash' || die "the Claude Code installer failed"
fi
if [ ! -f "$H/.claude/settings.json" ]; then
  printf '{\n  "autoUpdatesChannel": "stable"\n}\n' > "$H/.claude/settings.json"
  chown agent:agent "$H/.claude/settings.json"
fi
echo "   $(as_agent "$H/.local/bin/claude" --version 2>/dev/null || echo 'claude --version failed')"

say "systemd: g7-agent.slice (memory cap) and g7-agent-tmux.service (sandbox)"
install -o root -g root -m 0644 g7-agent.slice g7-agent-tmux.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable g7-agent-tmux.service >/dev/null 2>&1
JOBS_RUNNING=$(as_agent tmux -S "$SOCK" list-sessions -F '#S' 2>/dev/null | grep -c '^job-' || true)
if [ "${JOBS_RUNNING:-0}" -gt 0 ]; then
  echo "   $JOBS_RUNNING job(s) running: the service was NOT restarted. Restart it later for unit changes:"
  echo "   sudo systemctl restart g7-agent-tmux"
else
  systemctl restart g7-agent-tmux.service
fi
systemctl is-active --quiet g7-agent-tmux.service || die "g7-agent-tmux.service did not start (journalctl -u g7-agent-tmux -n 30)"

say "sandbox self-test (inside the service, as the agent)"
rm -f "$H/.selftest.out"
as_agent tmux -S "$SOCK" kill-session -t =_selftest 2>/dev/null || true
as_agent tmux -S "$SOCK" new-session -d -s _selftest "/usr/local/bin/g7-agent _selftest > $H/.selftest.out 2>&1"
i=0
while as_agent tmux -S "$SOCK" has-session -t =_selftest 2>/dev/null && [ $i -lt 90 ]; do sleep 1; i=$((i + 1)); done
sed 's/^/   /' "$H/.selftest.out" 2>/dev/null || echo "   (no self-test output)"
grep -q '^selftest: 0 failed' "$H/.selftest.out" 2>/dev/null || echo "   SELF-TEST FAILED: fix the FAIL lines before running jobs (agent/README.md, Troubleshooting)"

say "memory"
awk '/^MemTotal|^MemAvailable/ {printf "   %-14s %.1f GiB\n", $1, $2/1048576}' /proc/meminfo
echo "   agent jobs are capped at MemoryMax=$(systemctl show -p MemoryMax --value g7-agent.slice | numfmt --to=iec 2>/dev/null) (g7-agent.slice)"

cat <<'TXT'

Installed. Left to do, from the PC:
  1. A login for Claude Code on G7. In PowerShell:  claude setup-token
     copy the token it prints, then:              ssh g7-agent set-token
     and paste it. (It authenticates with your Claude subscription and lasts a year.)
  2. Check everything:                            ssh g7-agent doctor
  3. Optional phone notifications: agent/README.md, "Notifications".
  4. Commit the agent/ folder and the MAP lines in g7-infra and push, so g7-drift agrees.
TXT
