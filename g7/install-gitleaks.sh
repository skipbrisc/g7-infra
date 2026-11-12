#!/bin/sh
# Installs a pinned, checksum-verified gitleaks at /usr/local/bin/gitleaks on G7 for the CI
# "Security checks" stage. Run: sudo sh /tmp/install-gitleaks.sh
set -eu
VER=8.30.1
SHA=551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb
TMP=$(mktemp -d)
cd "$TMP"
curl -fsSL -o gl.tgz "https://github.com/gitleaks/gitleaks/releases/download/v$VER/gitleaks_${VER}_linux_x64.tar.gz"
echo "$SHA  gl.tgz" | sha256sum -c -
tar xzf gl.tgz gitleaks
install -o root -g root -m 0755 gitleaks /usr/local/bin/gitleaks
cd /; rm -rf "$TMP"
/usr/local/bin/gitleaks version
sudo -u jenkins-agent /usr/local/bin/gitleaks version >/dev/null && echo "jenkins-agent can run it"
