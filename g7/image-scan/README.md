# Container image scan

Every Monday at 04:30, `g7-image-scan` checks the image of each running container on G7
(TaxGlasses blue and green, Caddy, Vaultwarden, ntfy, Uptime Kuma and anything added later)
for known vulnerabilities that already have a fix, and sends a phone alert (ntfy topic `g7`)
when any is high or critical. The report is `/var/log/g7-image-scan.txt` (root only).

It is report only. It changes no container and blocks no deploy. Written 2026-11-13;
syntax-checked, not yet run on G7.

## How it is kept safe

A scanner is new code running on a server that holds a wallet key, so it gets as little
access as possible:

- grype is pinned to one version and its download is checked against a recorded SHA-256
  (`install.sh`). Change both lines together to upgrade; take the hash from the release's
  `checksums.txt` on GitHub.
- It never runs as root and never talks to Docker. Root exports an image to a file with
  `docker save`; the scan runs as `imgscan`, a system user with no shell that owns only
  `/var/cache/imgscan`.
- It needs the network only to download the vulnerability database.

## Install (root, once)

From `D:\TaxGlasses-ops` in PowerShell:

    ssh g7 "rm -rf /tmp/g7-image-scan && mkdir /tmp/g7-image-scan"
    scp g7/image-scan/install.sh g7/image-scan/g7-image-scan g7/image-scan/g7-image-scan.service g7/image-scan/g7-image-scan.timer g7:/tmp/g7-image-scan/
    ssh -t g7 "sudo sh /tmp/g7-image-scan/install.sh"

First scan by hand (downloads the database, so it takes a few minutes):

    ssh -t g7 "sudo systemctl start g7-image-scan.service; sudo cat /var/log/g7-image-scan.txt"

## When it alerts

The fix is almost always a newer image, not a code change.

- **TaxGlasses (`taxglasses:blue` / `taxglasses:green`)**: redeploy. `taxglasses-deploy`
  builds with `--pull`, so a deploy picks up the current `node:24-bookworm-slim` base image.
  If the finding is in an npm package, it is a dependency bump in the TaxGlasses repository.
- **Third-party images** (Caddy, Vaultwarden, ntfy, Uptime Kuma): in that service's folder,
  `docker compose pull && docker compose up -d`. Take a backup first for Vaultwarden.
- A finding with no newer image yet: wait for the next scan. Nothing here is urgent enough
  to patch by hand inside a container.

## Limits

- It reports known, published vulnerabilities with a fix. It does not find misconfiguration
  or anything unpublished.
- It scans running containers only. An image that is built and not running is not checked.
