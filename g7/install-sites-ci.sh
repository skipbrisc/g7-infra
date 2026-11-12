#!/bin/sh
# Browser-test toolchain for the website pipelines on G7, at /opt/sites-ci:
#   venv/      Python Playwright + pypdf (Aeraphim's tools/test_*.py; its Jenkinsfile looks here)
#   browsers/  Chromium builds for that venv and for Guatemala Hope's @playwright/test
# Run: sudo sh /tmp/install-sites-ci.sh   (re-run to upgrade; versions are pinned below)
set -eu
PY_PLAYWRIGHT=1.64.1
PYPDF=7.0.0
NODE_PLAYWRIGHT=1.61.1          # guatemalahope.org package.json's @playwright/test
BASE=/opt/sites-ci
export PLAYWRIGHT_BROWSERS_PATH=$BASE/browsers

apt-get install -y python3-venv >/dev/null
mkdir -p "$BASE" "$PLAYWRIGHT_BROWSERS_PATH"
[ -x "$BASE/venv/bin/python" ] || python3 -m venv "$BASE/venv"
"$BASE/venv/bin/pip" install -q --upgrade pip
"$BASE/venv/bin/pip" install -q "playwright==$PY_PLAYWRIGHT" "pypdf==$PYPDF"

# Chromium plus the system libraries it needs (apt), for the Python package...
"$BASE/venv/bin/playwright" install --with-deps chromium
# ...and the build Guatemala Hope's Node test runner expects.
npx -y "playwright@$NODE_PLAYWRIGHT" install chromium

chmod -R a+rX "$BASE"
echo
echo "Installed in $BASE:"
"$BASE/venv/bin/python" -c "import playwright, pypdf; print('  python playwright', '$PY_PLAYWRIGHT', '| pypdf', pypdf.__version__)"
ls "$PLAYWRIGHT_BROWSERS_PATH" | sed 's/^/  /'
echo
echo "Smoke test as jenkins-agent:"
sudo -u jenkins-agent env PLAYWRIGHT_BROWSERS_PATH="$PLAYWRIGHT_BROWSERS_PATH" "$BASE/venv/bin/python" -c "
from playwright.sync_api import sync_playwright
with sync_playwright() as p:
    b = p.chromium.launch(); pg = b.new_page(); pg.set_content('<title>ok</title>'); print('  chromium launches:', pg.title()); b.close()"
