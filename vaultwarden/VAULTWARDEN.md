# Vaultwarden on G7

Self-hosted Bitwarden server. Use the normal **Bitwarden** apps (Windows, browser extension, phone) pointed at your own server.

| | |
|---|---|
| URL | `https://<name>.duckdns.org` (DuckDNS record → **192.168.0.6**) |
| Reachable from | Home LAN, or anywhere with WireGuard on. **Not** the internet — no router port opened |
| Blocked for | Will, Frank, tg1/tg2 (their firewall chains already drop 172.16.0.0/12, where the containers live) |
| Containers | `vaultwarden` (server) + `vaultwarden-caddy` (HTTPS, real Let's Encrypt cert via DuckDNS DNS challenge) |
| Files on G7 | `/srv/vaultwarden/` — `compose.yml`, `.env`, `caddy.env` (DuckDNS token), `data/`, `backups/` |
| Backups | Nightly 02:41 → `/srv/vaultwarden/backups/`, 14 days. Pulled to `D:\VaultBackups` by your PC (60 days) |
| Admin panel | Off |

## Install

**1. DuckDNS.** Log in at duckdns.org (same account as `buttmud`), add a new subdomain for the vault, e.g. `buttvault`. Leave its IP alone — the script sets it to 192.168.0.6. Copy your token from the top of the page.

**2. Dry run, then install** (from PowerShell):
```powershell
scp -P 3333 D:\TaxGlasses-ops\vaultwarden\setup-vaultwarden.sh buttmud@192.168.0.6:/tmp/
ssh -t -p 3333 buttmud@192.168.0.6 "sudo bash /tmp/setup-vaultwarden.sh --dry-run"
ssh -t -p 3333 buttmud@192.168.0.6 "sudo bash /tmp/setup-vaultwarden.sh"
```
It asks for the subdomain and token (the token is hidden and stored only in `/srv/vaultwarden/caddy.env`, mode 600). First run builds Caddy, which takes a few minutes.

**3. Check DNS from your PC:**
```powershell
nslookup <name>.duckdns.org
```
It should answer `192.168.0.6`. If it answers nothing, your router is blocking private-IP answers ("DNS rebind protection"). Either allow `duckdns.org` in the router's rebind exceptions, or set your WireGuard clients' `DNS = 1.1.1.1`.

**4. Create your account.** Open `https://<name>.duckdns.org` → **Create account**. Use a long master passphrase you'll remember; write it down on paper with the recovery code. Nobody can reset it, including you.

**5. Close signups** so nobody else can create an account:
```powershell
ssh -t -p 3333 buttmud@192.168.0.6 "sudo bash /tmp/setup-vaultwarden.sh --close-signups"
```

**6. Turn on two-step login** in the web vault: Settings → Security → Two-step login → Authenticator app. Save the recovery code with your master passphrase.

## Connect the apps

In every Bitwarden app, **before** logging in, choose the region / server selector → **Self-hosted** → Server URL `https://<name>.duckdns.org`.

- **Windows desktop app** and **browser extension**: as above.
- **Phone**: as above. Your phone must be on home Wi-Fi or WireGuard to sync; when it's not, the app still shows everything from its encrypted local copy, and edits sync next time it connects.

## Off-G7 backup (do this — it's what protects you if G7's disk dies)

**1. Make a read-only backup key on your PC:**
```powershell
ssh-keygen -t ed25519 -N '""' -C vault-backup -f $env:USERPROFILE\.ssh\vault-backup
Get-Content $env:USERPROFILE\.ssh\vault-backup.pub
```
**2. Authorize it on G7** (paste the whole `.pub` line in the quotes):
```powershell
ssh -t -p 3333 buttmud@192.168.0.6 "sudo bash /tmp/setup-vaultwarden.sh --backup-key 'ssh-ed25519 AAAA... vault-backup'"
```
That key can only download `latest.tar.gz` — it can't open a shell or touch anything else.

**3. Test, then schedule daily:**
```powershell
D:\TaxGlasses-ops\vaultwarden\pull-vault-backup.cmd
Register-ScheduledTask -TaskName "Vault backup pull" -Action (New-ScheduledTaskAction -Execute "D:\TaxGlasses-ops\vaultwarden\pull-vault-backup.cmd") -Trigger (New-ScheduledTaskTrigger -Daily -At 9am) -Settings (New-ScheduledTaskSettingsSet -StartWhenAvailable -RunOnlyIfNetworkAvailable)
```
Runs when the PC is on and can reach G7; missed days catch up. Copies older than 60 days are pruned.

The vault items in a backup are encrypted with your master passphrase, but the file also holds the server's keys — keep `D:\VaultBackups` off public shares.

## Everyday commands (on G7)

| Task | Command |
|---|---|
| Status | `cd /srv/vaultwarden && sudo docker compose ps` |
| Logs | `sudo docker logs vaultwarden --tail 50` / `sudo docker logs vaultwarden-caddy --tail 50` |
| Update | `cd /srv/vaultwarden && sudo docker compose pull vaultwarden && sudo docker compose build --pull caddy && sudo docker compose up -d` |
| Backup now | `sudo systemctl start vaultwarden-backup` |
| List backups | `ls -l /srv/vaultwarden/backups` |

## Restore

```bash
cd /srv/vaultwarden && sudo docker compose stop vaultwarden
sudo mv data data.broken-$(date +%F)
sudo tar xzf /path/to/vault-YYYY-MM-DD.tar.gz -C /srv/vaultwarden     # recreates data/
sudo docker compose start vaultwarden
```
On a rebuilt G7: re-run `setup-vaultwarden.sh` first (same subdomain + token), then restore as above.
