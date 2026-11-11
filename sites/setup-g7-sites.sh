#!/usr/bin/env bash
# setup-g7-sites.sh — put guatemalahope.org and Aeraphim on G7 the same way as TaxGlasses/MemeSniper:
#   * bare repo under /srv/git/repos (you push to remote g7)
#   * GitHub mirror timer (G7 is the only thing that pushes to GitHub)
#   * a read-only, repo-locked SSH key per site for Jenkins
#   * sudoers rule so buttmud (you, or Claude Code over SSH) can force a mirror sync
# Both sites stay hosted on Vercel; the Jenkins jobs test and deploy there (see SITES-SETUP.md).
#
# Run as root on buttserver:
#   bash setup-g7-sites.sh --dry-run          shows every change, touches nothing
#   bash setup-g7-sites.sh                    applies it
#   bash setup-g7-sites.sh --with-browsers    also installs Playwright+Chromium for Aeraphim's browser tests
# Idempotent: re-running skips anything already done. Never touches TaxGlasses, MemeSniper or Jenkins itself.

set -euo pipefail

GIT_USER=git
GIT_HOME=/srv/git
REPOS=$GIT_HOME/repos
SSH_DIR=$GIT_HOME/.ssh
KEYDIR=/root/g7-sites-keys
SUDOERS=/etc/sudoers.d/sites-ops
CI_ROOT=/opt/sites-ci
# slug | bare repo name | GitHub owner/repo
SITES=(
  "guatemalahope|guatemalahope.org|skipbrisc/guatemalahope.org"
  "aeraphim|Aeraphim|skipbrisc/Aeraphim"
)

DRY=0; BROWSERS=0
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    --with-browsers) BROWSERS=1 ;;
    *) echo "unknown option: $a" >&2; exit 1 ;;
  esac
done

say()  { printf '\n==> %s\n' "$*"; }
note() { printf '    %s\n' "$*"; }
run()  { if (( DRY )); then note "would run: $*"; else "$@"; fi; }
asgit(){ if (( DRY )); then note "would run as $GIT_USER: $*"; else sudo -u "$GIT_USER" -H "$@"; fi; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
write_file() {  # write_file <path> <mode> <owner> <content>
  local path="$1" mode="$2" owner="$3" content="$4"
  if [[ -f "$path" ]] && [[ "$(cat "$path")" == "$content" ]]; then note "$path already correct"; return; fi
  if (( DRY )); then note "would write $path:"; printf '%s\n' "$content" | sed 's/^/      /'; return; fi
  local tmp; tmp="$(mktemp)"; printf '%s\n' "$content" > "$tmp"
  install -m "$mode" -o "${owner%:*}" -g "${owner#*:}" "$tmp" "$path"; rm -f "$tmp"
  note "wrote $path"
}

[[ $EUID -eq 0 ]] || die "run as root (sudo bash $0)"
(( DRY )) && echo "DRY RUN — nothing will be changed"

say "Preflight"
id "$GIT_USER" >/dev/null 2>&1 || die "user $GIT_USER missing"
[[ -d "$REPOS" ]] || die "$REPOS missing"
command -v git >/dev/null || die "git missing"
command -v node >/dev/null && note "node $(node -v), npm $(npm -v 2>/dev/null)" || die "node missing (Jenkins needs it for both sites)"
command -v python3 >/dev/null && note "$(python3 -V)" || die "python3 missing (Aeraphim tests need it)"
command -v curl >/dev/null || note "WARNING: curl missing — Jenkins health checks need it (apt install curl)"
[[ -f /etc/systemd/system/taxglasses-mirror.service ]] && note "taxglasses-mirror.service found — using it as the template" \
  || note "taxglasses-mirror.service not found — writing mirror units from scratch"
[[ -d "$SSH_DIR" ]] || run install -d -m 700 -o "$GIT_USER" -g "$GIT_USER" "$SSH_DIR"
(( DRY )) || install -d -m 700 -o root -g root "$KEYDIR"

DEPLOY_KEYS_TO_ADD=()

for entry in "${SITES[@]}"; do
  IFS='|' read -r slug repo gh <<<"$entry"
  bare="$REPOS/${repo}.git"
  say "Site: $slug  ($bare  <->  github.com/$gh)"

  # 1. bare repo -----------------------------------------------------------------
  if [[ -d "$bare" ]]; then
    note "bare repo exists ($(git -C "$bare" -c safe.directory="$bare" rev-parse --verify -q refs/heads/main >/dev/null && echo 'has main' || echo 'empty — push from your PC to seed it'))"
  else
    asgit git init -q --bare -b main "$bare"
    note "created $bare"
  fi

  # 2. GitHub remote + push credential --------------------------------------------
  url="git@github.com:${gh}.git"
  if (( DRY )); then
    note "would test GitHub write access as $GIT_USER with the key TaxGlasses already uses; if it fails, generate deploy key $SSH_DIR/github_$slug"
  elif sudo -u "$GIT_USER" -H env GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=15 -o StrictHostKeyChecking=accept-new" \
         git ls-remote "$url" HEAD >/dev/null 2>&1; then
    note "existing $GIT_USER GitHub key can reach $gh — reusing it"
  else
    alias_host="github-$slug"
    key="$SSH_DIR/github_$slug"
    if [[ ! -f "$key" ]]; then
      sudo -u "$GIT_USER" -H ssh-keygen -q -t ed25519 -N '' -C "g7-mirror-$slug" -f "$key"
      note "generated deploy key $key"
    fi
    if ! grep -q "^Host $alias_host\$" "$SSH_DIR/config" 2>/dev/null; then
      printf '\nHost %s\n  HostName github.com\n  User git\n  IdentityFile %s\n  IdentitiesOnly yes\n  StrictHostKeyChecking accept-new\n' \
        "$alias_host" "$key" >> "$SSH_DIR/config"
      chown "$GIT_USER:$GIT_USER" "$SSH_DIR/config"; chmod 600 "$SSH_DIR/config"
      note "added Host $alias_host to $SSH_DIR/config"
    fi
    url="git@${alias_host}:${gh}.git"
    DEPLOY_KEYS_TO_ADD+=("$gh|$(cat "$key.pub")")
  fi
  if (( ! DRY )); then
    if git -C "$bare" -c safe.directory="$bare" remote get-url github >/dev/null 2>&1; then
      sudo -u "$GIT_USER" git -C "$bare" remote set-url github "$url"
    else
      sudo -u "$GIT_USER" git -C "$bare" remote add github "$url"
    fi
    note "remote github -> $url"
  fi

  # 3. mirror units ----------------------------------------------------------------
  write_file "/etc/systemd/system/${slug}-mirror.service" 644 root:root "[Unit]
Description=Sync ${repo} to GitHub
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
User=${GIT_USER}
Group=${GIT_USER}
WorkingDirectory=${bare}
Environment=\"GIT_SSH_COMMAND=/usr/bin/ssh -o BatchMode=yes -o ConnectTimeout=15\"
ExecStart=/usr/bin/git push github --all
ExecStart=/usr/bin/git push github --tags
TimeoutStartSec=120"
  write_file "/etc/systemd/system/${slug}-mirror.timer" 644 root:root "[Unit]
Description=Sync ${repo} to GitHub every minute

[Timer]
OnBootSec=1min
OnUnitInactiveSec=1min
Unit=${slug}-mirror.service

[Install]
WantedBy=timers.target"

  # 4. Jenkins read-only key, locked to this one repo --------------------------------
  jkey="$KEYDIR/${slug}-jenkins"
  if (( DRY )); then
    note "would create $jkey (if missing) and add it to $SSH_DIR/authorized_keys restricted to git-upload-pack '$bare'"
  else
    [[ -f "$jkey" ]] || { ssh-keygen -q -t ed25519 -N '' -C "jenkins-$slug" -f "$jkey"; note "generated $jkey"; }
    if grep -q "jenkins-$slug\$" "$SSH_DIR/authorized_keys" 2>/dev/null; then
      note "Jenkins key already authorized"
    else
      printf 'restrict,command="git-upload-pack '"'"'%s'"'"'" %s\n' "$bare" "$(cat "$jkey.pub")" >> "$SSH_DIR/authorized_keys"
      chown "$GIT_USER:$GIT_USER" "$SSH_DIR/authorized_keys"; chmod 600 "$SSH_DIR/authorized_keys"
      note "authorized jenkins-$slug (read-only, $repo only)"
    fi
  fi
done

say "systemd"
run systemctl daemon-reload
for entry in "${SITES[@]}"; do
  IFS='|' read -r slug _ _ <<<"$entry"
  run systemctl enable --now "${slug}-mirror.timer"
done

say "Sudoers: $SUDOERS"
SUDO_LINE="buttmud ALL=(root) NOPASSWD:"
first=1
for entry in "${SITES[@]}"; do
  IFS='|' read -r slug _ _ <<<"$entry"
  (( first )) || SUDO_LINE+=","
  SUDO_LINE+=" /usr/bin/systemctl start ${slug}-mirror.service"
  first=0
done
SUDOERS_CONTENT="# buttmud (you, Claude Code, Codex over SSH) may force an immediate GitHub mirror sync for the sites.
# Deploys and rollbacks go through Jenkins (deploy-bot token), not sudo.
$SUDO_LINE"
if [[ -f "$SUDOERS" ]] && [[ "$(cat "$SUDOERS")" == "$SUDOERS_CONTENT" ]]; then
  note "already in place"
elif (( DRY )); then
  note "would write:"; printf '%s\n' "$SUDOERS_CONTENT" | sed 's/^/      /'
else
  tmp="$(mktemp)"; printf '%s\n' "$SUDOERS_CONTENT" > "$tmp"
  visudo -cf "$tmp" >/dev/null || die "generated sudoers failed visudo check"
  install -m 0440 -o root -g root "$tmp" "$SUDOERS"; rm -f "$tmp"
  note "written and validated"
fi

if (( BROWSERS )); then
  say "Playwright for Aeraphim browser tests ($CI_ROOT)"
  run apt-get install -y python3-venv
  [[ -x "$CI_ROOT/venv/bin/python" ]] || run python3 -m venv "$CI_ROOT/venv"
  run "$CI_ROOT/venv/bin/pip" install -q --upgrade pip playwright pypdf
  run env PLAYWRIGHT_BROWSERS_PATH="$CI_ROOT/browsers" "$CI_ROOT/venv/bin/playwright" install --with-deps chromium
  run chmod -R a+rX "$CI_ROOT"
fi

say "Done"
if (( DRY )); then note "re-run without --dry-run to apply"; exit 0; fi
for entry in "${SITES[@]}"; do
  IFS='|' read -r slug _ _ <<<"$entry"
  note "${slug}-mirror.timer: $(systemctl is-active "${slug}-mirror.timer")"
done
if (( ${#DEPLOY_KEYS_TO_ADD[@]} )); then
  echo
  echo "ACTION NEEDED — add these as deploy keys WITH WRITE ACCESS on GitHub (repo → Settings → Deploy keys):"
  for k in "${DEPLOY_KEYS_TO_ADD[@]}"; do echo "  github.com/${k%%|*}:"; echo "    ${k#*|}"; done
fi
echo
echo "Jenkins credentials (SSH Username with private key, username 'git') — paste the private key from:"
for entry in "${SITES[@]}"; do IFS='|' read -r slug _ _ <<<"$entry"; echo "  sudo cat $KEYDIR/${slug}-jenkins      → credential id: g7-git-${slug}"; done
echo
echo "Next: push from your PC (git push g7 --all), then SITES-SETUP.md steps 3–6."
