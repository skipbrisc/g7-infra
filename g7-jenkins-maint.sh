#!/usr/bin/env bash
# G7 helper for the TaxGlasses CI host (Debian 13). Run as root:
#   sudo bash g7-jenkins-maint.sh inventory   read-only report, secrets redacted (default)
#   sudo bash g7-jenkins-maint.sh upgrade     back up JENKINS_HOME, Java 25 for controller and agent,
#                                             Jenkins LTS 2.580.2, restart both, verify
#   sudo bash g7-jenkins-maint.sh sudoers     let buttmud restart jenkins.service and jenkins-agent.service
#                                             without a password (/etc/sudoers.d/taxglasses-ci)
# Never runs apt-get upgrade/dist-upgrade, never reboots, never touches MemeSniper.
set -uo pipefail
MODE="${1:-inventory}"
JH=/var/lib/jenkins
BARE=/srv/git/repos/TaxGlasses.git
TARGET_CORE=2.580.2
J21=/usr/lib/jvm/java-21-openjdk-amd64
J25=/usr/lib/jvm/java-25-openjdk-amd64
TS=$(date +%Y%m%d-%H%M%S)
BK=/var/backups/jenkins/$TS
SUDOERS_FILE=/etc/sudoers.d/taxglasses-ci
SUDOERS_RULE='buttmud ALL=(root) NOPASSWD: /usr/bin/systemctl restart jenkins.service, /usr/bin/systemctl restart jenkins-agent.service'

[ "$(id -u)" -eq 0 ] || { echo "Run as root: sudo bash $0 $MODE"; exit 1; }

red() {
  sed -E \
    -e 's/(-secret[ =])[^ ]+/\1<REDACTED>/g' \
    -e 's/\b[0-9a-f]{64}\b/<REDACTED-HEX64>/g' \
    -e 's#(https?://)[^/@ ]+@#\1<REDACTED>@#g' \
    -e 's/(gh[pousr]_)[A-Za-z0-9_]{20,}/\1<REDACTED>/g' \
    -e 's/((TOKEN|SECRET|PASSWORD|PASSWD|API_?KEY)[A-Za-z_]*[=:][ ]*)[^ "]+/\1<REDACTED>/Ig'
}
sec() { printf '\n=== %s ===\n' "$*"; }
g() { git -c safe.directory="$BARE" -C "$BARE" "$@"; }
http_head() {  # HEAD request to the local controller without curl/wget; subshell keeps fd 3 and stderr local
  ( exec 3<>/dev/tcp/127.0.0.1/8080 || exit 1
    printf 'HEAD %s HTTP/1.0\r\nHost: 127.0.0.1\r\n\r\n' "$1" >&3
    timeout 5 cat <&3 | tr -d '\r' ) 2>/dev/null
}

inventory() {
  echo "G7 inventory $(date -Is)"
  sec "host"
  echo "$(hostname); $(. /etc/os-release; echo "$PRETTY_NAME"); kernel $(uname -r); up since $(uptime -s)"

  sec "accounts"
  for u in buttmud git jenkins jenkins-agent memesniper taxglasses; do
    getent passwd "$u" | cut -d: -f1,6,7 || echo "$u: (none)"
  done
  for u in buttmud git jenkins-agent; do id "$u" 2>/dev/null; done

  sec "sudo rights"
  sudo -l -U buttmud 2>&1 | sed -n '/may run the following/,$p'
  sudo -l -U jenkins-agent 2>&1 | tail -n 2

  sec "authorized_keys (fingerprints and option prefixes only)"
  for h in $(getent passwd buttmud git jenkins-agent root | cut -d: -f6 | sort -u); do
    f="$h/.ssh/authorized_keys"; [ -f "$f" ] || continue
    echo "-- $f ($(stat -c '%U:%G %a' "$f"))"
    ssh-keygen -lf "$f" 2>&1
    grep -nE '^[^ ]*(command=|from=|restrict|no-)' "$f" | cut -c1-100
  done

  sec "sshd (effective)"
  sshd -T 2>/dev/null | grep -E '^(port|listenaddress|passwordauthentication|kbdinteractiveauthentication|pubkeyauthentication|permitrootlogin|allowusers|allowgroups|authorizedkeysfile) '

  sec "packages"
  dpkg-query -W -f='${db:Status-Abbrev} ${Package} ${Version}\n' jenkins nodejs npm needrestart unattended-upgrades 'openjdk-*' 2>/dev/null | grep '^ii'
  apt-cache policy jenkins openjdk-25-jre-headless 2>/dev/null | grep -E '^[a-z]|Installed|Candidate'
  update-alternatives --query java 2>/dev/null | grep -E '^(Value|Alternative):'
  echo "java processes:"; pgrep -a java | red | cut -c1-200

  sec "apt history (jenkins / openjdk)"
  zgrep -hE '^(Start-Date|Commandline|Requested-By|Install|Upgrade):' /var/log/apt/history.log* 2>/dev/null \
    | grep -B2 -E 'jenkins|openjdk' | grep -v '^--$' | tail -24 | cut -c1-220

  sec "unattended-upgrades"
  systemctl is-enabled unattended-upgrades.service apt-daily-upgrade.timer 2>&1 | paste -sd' '
  apt-config dump 2>/dev/null | grep -E '^Unattended-Upgrade::(Origins-Pattern|Allowed-Origins|Package-Blacklist|Automatic-Reboot) ' | head -12

  sec "services"
  for s in jenkins jenkins-agent taxglasses-mirror.service taxglasses-mirror.timer; do
    printf '%-26s ' "$s"
    systemctl show "$s" -p ActiveState -p SubState -p MainPID -p ExecMainStartTimestamp -p Result 2>/dev/null | paste -sd' '
  done
  for s in jenkins jenkins-agent; do
    pid=$(systemctl show -p MainPID --value "$s"); [ "${pid:-0}" -gt 0 ] && echo "$s pid $pid runs $(readlink /proc/"$pid"/exe)"
  done

  sec "unit files (agent secret redacted)"
  systemctl cat jenkins 2>/dev/null | grep -E '^# /|^\[|Environment|ExecStart|^User|^Group|Restart|JAVA' | red | head -30
  grep -E '^[^#]*JAVA' /etc/default/jenkins 2>/dev/null | red
  systemctl cat jenkins-agent 2>/dev/null | red

  sec "JENKINS_HOME and space"
  ls -ld "$JH" "$JH/secrets"
  du -sh --exclude=workspace --exclude=caches --exclude=war "$JH" 2>/dev/null
  df -h /var/lib /var/backups | sed 1d

  sec "existing Jenkins backups"
  ls -la /var/backups/jenkins 2>/dev/null || echo "/var/backups/jenkins: none"
  find / -xdev -maxdepth 4 \( -iname '*jenkins*backup*' -o -iname 'jenkins_home*.t*' -o -iname 'thinBackup*' \) 2>/dev/null | head -10
  systemctl list-timers --all 2>/dev/null | grep -iE 'backup|jenkins' || echo "no backup timers"

  sec "GitHub mirror"
  systemctl cat taxglasses-mirror.service taxglasses-mirror.timer 2>/dev/null | red
  systemctl list-timers --all 2>/dev/null | grep -i mirror
  for s in $(systemctl cat taxglasses-mirror.service 2>/dev/null | sed -nE 's/^ExecStart=[-@:+!]*([^ ]+).*/\1/p'); do
    [ -f "$s" ] && grep -qI . "$s" && { echo "-- $s"; red < "$s"; }
  done
  echo "-- runs, last 2 days"
  journalctl -u taxglasses-mirror.service --since '-2 days' --no-pager -o short-iso 2>/dev/null | red | tail -40
  echo "-- warnings and errors, last 14 days"
  journalctl -u taxglasses-mirror.service --since '-14 days' --no-pager -p warning -o short-iso 2>/dev/null | red | tail -15

  sec "bare repository"
  g config --list --show-origin 2>&1 | red
  echo "HEAD -> $(g symbolic-ref HEAD 2>&1)"
  ls -la "$BARE/hooks" | grep -v '\.sample$'
  for h in "$BARE"/hooks/*; do
    case "$h" in *.sample) ;; *) [ -f "$h" ] && { echo "-- $h"; red < "$h"; } ;; esac
  done
  g for-each-ref --count=8 --sort=-committerdate --format='%(objectname:short) %(committerdate:iso) %(refname)'
  echo "refs: $(g for-each-ref | wc -l)  tags: $(g tag | wc -l)"

  sec "TaxGlasses runtime / deployment"
  systemctl list-unit-files 2>/dev/null | grep -i tax || true
  ls -d /srv/* /opt/* /var/www/* 2>/dev/null
  ss -ltnp 2>/dev/null | awk 'NR>1 {print $4, $6}' | grep -vE ':(3333|8080|51820) ' | head -20

  sec "WireGuard (private keys hidden)"
  wg show 2>/dev/null | grep -viE 'private key|preshared'
  ip -br addr | grep -E 'wg|192\.168\.0\.'
  echo "ip_forward=$(sysctl -n net.ipv4.ip_forward)"

  sec "firewall"
  command -v nft >/dev/null && nft list ruleset 2>/dev/null | grep -nE 'policy|dport|iifname|oifname' | head -40
  iptables -S 2>/dev/null | head -30
  echo; echo "inventory finished"
}

fail() {
  echo "FAILED: $*"
  echo "Nothing after this step ran. Rollback steps: $BK/ROLLBACK.txt"
  exit 1
}

upgrade() {
  echo "G7 upgrade $(date -Is)"
  sec "preflight"
  if pgrep -u jenkins-agent -x 'sh|bash|node|npm|git' >/dev/null; then
    echo "A build is running on g7-worker (child processes of jenkins-agent). Wait for it to finish, then re-run."
    exit 1
  fi
  others=$(pgrep -a java | grep -vE '(jenkins\.war|agent\.jar)( |$)' || true)
  if [ -n "$others" ]; then
    echo "Other Java processes run on this host, so the system 'java' default will not be switched:"
    echo "$others" | red | cut -c1-160
    exit 1
  fi
  apt-get update -qq || { echo "apt-get update failed; nothing was changed."; exit 1; }
  old_core=$(dpkg-query -W -f='${Version}' jenkins)
  cand_core=$(apt-cache policy jenkins | awk '/Candidate:/ {print $2}')
  cand_j25=$(apt-cache policy openjdk-25-jre-headless | awk '/Candidate:/ {print $2}')
  echo "jenkins installed $old_core, candidate $cand_core; openjdk-25-jre-headless candidate $cand_j25"
  [ "$cand_core" = "$TARGET_CORE" ] || { echo "Expected jenkins candidate $TARGET_CORE. Stopping before any change."; exit 1; }
  { [ -n "$cand_j25" ] && [ "$cand_j25" != "(none)" ]; } || { echo "openjdk-25-jre-headless is not available. Stopping before any change."; exit 1; }
  need=$(du -sk --exclude=workspace --exclude=caches --exclude=war "$JH" | awk '{print $1}')
  free=$(df -Pk /var/backups | awk 'NR==2 {print $4}')
  echo "JENKINS_HOME to back up: ${need} KiB; free in /var/backups: ${free} KiB"
  [ "$free" -gt $((need * 2)) ] || { echo "Not enough space for the backup. Stopping before any change."; exit 1; }

  sec "record the current state in $BK"
  umask 077
  mkdir -p "$BK" && chmod 700 /var/backups/jenkins "$BK" || fail "mkdir $BK"
  dpkg-query -W -f='${Package} ${Version}\n' jenkins 'openjdk-*' 2>/dev/null > "$BK/packages-before.txt"
  update-alternatives --query java > "$BK/java-alternatives-before.txt"
  cp -a /etc/systemd/system/jenkins-agent.service "$BK/"   # contains the agent secret: root-only copy
  ls "$JH/plugins" | grep -E '\.(jpi|hpi)$' > "$BK/plugins-before.txt"
  cp -a /var/cache/apt/archives/jenkins_"${old_core}"_all.deb "$BK/" 2>/dev/null || true
  cat > "$BK/ROLLBACK.txt" <<EOF
Rollback for the $TS Jenkins/Java maintenance (run as root on G7):
  systemctl stop jenkins-agent jenkins
  update-alternatives --set java $J21/bin/java
  apt-get install -y --allow-downgrades jenkins=$old_core      # or: dpkg -i $BK/jenkins_${old_core}_all.deb if it was saved
  # Only if JENKINS_HOME itself must be restored:
  #   mv $JH $JH.failed-$TS && tar -C $(dirname "$JH") -xzf $BK/jenkins_home.tgz
  systemctl start jenkins
  systemctl start jenkins-agent
EOF
  echo "prior jenkins $old_core; prior java $(readlink -f /usr/bin/java)"

  sec "stop agent, then controller"
  systemctl stop jenkins-agent || fail "stop jenkins-agent"
  systemctl stop jenkins || fail "stop jenkins"

  sec "back up JENKINS_HOME (excluding workspace, caches, war)"
  b=$(basename "$JH")
  tar -C "$(dirname "$JH")" --exclude="$b/workspace" --exclude="$b/caches" --exclude="$b/war" \
      -czf "$BK/jenkins_home.tgz" "$b" || { systemctl start jenkins; systemctl start jenkins-agent; fail "backup tar"; }
  tar -tzf "$BK/jenkins_home.tgz" > "$BK/backup-contents.txt" || { systemctl start jenkins; systemctl start jenkins-agent; fail "backup listing"; }
  if ! grep -qxE "$b/config\.xml" "$BK/backup-contents.txt" || ! grep -qxE "$b/secrets/master\.key" "$BK/backup-contents.txt"; then
    systemctl start jenkins; systemctl start jenkins-agent
    fail "backup is missing config.xml or secrets/master.key; services restarted unchanged"
  fi
  ls -la "$BK"

  sec "install Java 25 and make it the system default"
  DEBIAN_FRONTEND=noninteractive apt-get install -y -q openjdk-25-jre-headless || fail "install openjdk-25-jre-headless"
  [ -x "$J25/bin/java" ] || fail "$J25/bin/java missing"
  update-alternatives --set java "$J25/bin/java" || fail "update-alternatives --set java"
  echo "/usr/bin/java -> $(readlink -f /usr/bin/java)"; java -version 2>&1 | head -1

  sec "upgrade the jenkins package only"
  DEBIAN_FRONTEND=noninteractive apt-get install -y -q --only-upgrade -o Dpkg::Options::=--force-confold jenkins \
    || fail "jenkins package upgrade"
  echo "jenkins now $(dpkg-query -W -f='${Version}' jenkins)"

  sec "start controller, then agent"
  systemctl start jenkins || fail "start jenkins"
  status=""
  for _ in $(seq 1 60); do
    status=$(http_head /login | head -1)
    case "$status" in *" 200"*|*" 403"*) break ;; esac
    sleep 3
  done
  echo "controller: $status; $(http_head /login | grep -i '^x-jenkins:')"
  systemctl start jenkins-agent || fail "start jenkins-agent"
  sleep 20

  sec "verify"
  for s in jenkins jenkins-agent; do
    pid=$(systemctl show -p MainPID --value "$s")
    echo "$s: $(systemctl is-active "$s"), pid $pid runs $(readlink /proc/"$pid"/exe)"
  done
  journalctl -u jenkins --since "-5 min" --no-pager 2>/dev/null | grep -iE 'SEVERE|Failed to load|unsupported class' | red | tail -15
  journalctl -u jenkins-agent --since "-3 min" --no-pager 2>/dev/null | grep -iE 'Connected|SEVERE|refused' | red | tail -8
  echo
  echo "Backup and rollback steps: $BK (ROLLBACK.txt). Backup is root-only (mode 700)."
}

install_sudoers() {
  echo "G7 sudoers $(date -Is)"
  [ -x /usr/bin/systemctl ] || { echo "/usr/bin/systemctl not found; nothing changed."; exit 1; }
  getent passwd buttmud >/dev/null || { echo "No user buttmud; nothing changed."; exit 1; }
  # @includedir skips names containing a dot, so the candidate cannot affect sudo before it is checked.
  local tmp=/etc/sudoers.d/.taxglasses-ci.new backup=""
  umask 077
  printf '%s\n%s\n' '# TaxGlasses CI: buttmud (Claude Code over g7-taxglasses) may restart the Jenkins services.' "$SUDOERS_RULE" > "$tmp"
  chown root:root "$tmp" && chmod 0440 "$tmp"
  if ! visudo -cf "$tmp"; then rm -f "$tmp"; echo "The rule failed the syntax check; nothing changed."; exit 1; fi
  if [ -f "$SUDOERS_FILE" ] && cmp -s "$tmp" "$SUDOERS_FILE"; then
    rm -f "$tmp"; echo "$SUDOERS_FILE already holds this rule."
  else
    if [ -f "$SUDOERS_FILE" ]; then backup="/root/taxglasses-ci.sudoers.$TS"; cp -a "$SUDOERS_FILE" "$backup"; fi
    mv -f "$tmp" "$SUDOERS_FILE"
  fi
  if ! visudo -c >/dev/null 2>&1; then
    if [ -n "$backup" ]; then mv -f "$backup" "$SUDOERS_FILE"; else rm -f "$SUDOERS_FILE"; fi
    echo "The full sudoers check failed with the new file, so it was undone:"; visudo -c; exit 1
  fi
  echo "Installed $SUDOERS_FILE ($(stat -c '%U:%G %a' "$SUDOERS_FILE")):"
  cat "$SUDOERS_FILE"
  echo; sudo -l -U buttmud | sed -n '/may run the following/,$p'
}

case "$MODE" in
  inventory) inventory ;;
  upgrade)   upgrade ;;
  sudoers)   install_sudoers ;;
  *) echo "usage: sudo bash $0 [inventory|upgrade|sudoers]"; exit 2 ;;
esac
