#!/bin/sh
# Node.js 24 for the Jenkins pipelines on G7, installed beside the system Node at /opt/node24.
# The system "node" (Debian package) is left alone: MemeSniper's live executor calls plain
# "node" and must not change runtime without its own validation.
# Pipelines opt in by putting /opt/node24/bin first on PATH.
# Run: sudo sh /tmp/install-node24.sh   (re-run to move to the newest 24.x patch release)
set -eu
BASE=https://nodejs.org/dist/latest-v24.x
DEST=/opt/node24
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cd "$TMP"
curl -fsSL -o SHASUMS256.txt "$BASE/SHASUMS256.txt"
TARBALL=$(grep -oE 'node-v24\.[0-9]+\.[0-9]+-linux-x64\.tar\.xz' SHASUMS256.txt | head -1)
[ -n "$TARBALL" ] || { echo "no linux-x64 tarball listed at $BASE" >&2; exit 1; }
curl -fsSL -o "$TARBALL" "$BASE/$TARBALL"
grep " $TARBALL\$" SHASUMS256.txt | sha256sum -c -
rm -rf "$DEST.new"; mkdir -p "$DEST.new"
# --no-same-owner: as root, tar would otherwise keep the user and group IDs recorded in the
# archive, leaving the binary owned (and writable) by whichever local account has that ID.
tar -xJf "$TARBALL" -C "$DEST.new" --strip-components=1 --no-same-owner
chown -R root:root "$DEST.new"
chmod -R go-w "$DEST.new"
rm -rf "$DEST.old"; [ -d "$DEST" ] && mv "$DEST" "$DEST.old"
mv "$DEST.new" "$DEST"; rm -rf "$DEST.old"
chmod -R a+rX "$DEST"
echo "Installed: $("$DEST/bin/node" -v), npm $("$DEST/bin/npm" -v) in $DEST"
echo "System node is unchanged: $(node -v 2>/dev/null || echo none)"
echo "As jenkins-agent: $(sudo -u jenkins-agent env PATH="$DEST/bin:/usr/bin:/bin" node -v)"
