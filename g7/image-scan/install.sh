#!/bin/sh
# Weekly vulnerability scan of every container image running on G7 (g7-image-scan).
# Installs a pinned, checksum-verified grype, a locked-down user to run it, and the timer.
# Run: sudo sh /tmp/g7-image-scan/install.sh   (re-run to upgrade after changing VER and SHA)
set -eu
VER=0.121.3
SHA=e9da18cc1429e786722e32161288103600efffd8e483c90761f90485bd1bec85
HERE=$(cd "$(dirname "$0")" && pwd)

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
curl -fsSL -o "$TMP/grype.tgz" "https://github.com/anchore/grype/releases/download/v$VER/grype_${VER}_linux_amd64.tar.gz"
echo "$SHA  $TMP/grype.tgz" | sha256sum -c -
tar -xzf "$TMP/grype.tgz" -C "$TMP" grype
install -o root -g root -m 0755 "$TMP/grype" /usr/local/bin/grype

# The scanner never runs as root and never touches Docker: root exports an image to a file,
# and this user, which owns nothing else and has no shell, reads that file.
id imgscan >/dev/null 2>&1 || useradd --system --home-dir /var/cache/imgscan --shell /usr/sbin/nologin imgscan
install -d -o imgscan -g imgscan -m 0700 /var/cache/imgscan /var/cache/imgscan/db /var/cache/imgscan/tmp

install -o root -g root -m 0700 "$HERE/g7-image-scan" /usr/local/sbin/g7-image-scan
install -o root -g root -m 0644 "$HERE/g7-image-scan.service" "$HERE/g7-image-scan.timer" /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now g7-image-scan.timer
/usr/local/bin/grype version | head -3
echo "Installed. First scan by hand:  sudo systemctl start g7-image-scan.service; sudo cat /var/log/g7-image-scan.txt"
