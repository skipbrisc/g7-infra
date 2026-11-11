# Vault Checklist

One row = one Bitwarden item. Type the **Item Name** exactly as shown, put it in the **Folder** listed, and pick the **Type** when you click **New**.
No secret values are in this file — only where to get them.

**G7 commands:** run from PowerShell as `ssh -t -p 3333 buttmud@192.168.0.6 "<command>"`
**After copying a value:** paste it straight into Bitwarden, then run `Clear-Host`.
**Never in the vault:** your Vaultwarden master passphrase and 2FA recovery code. Paper only.

**Folders to create first** (Bitwarden → Folders → +): `G7 Server` · `WireGuard` · `SSH Keys` · `Websites` · `MemeSniper` · `Accounts` · `Docs`

| # | Done | Item Name | Folder | Type | Username | URI / Address | Secret goes in | How to get the secret |
|---|---|---|---|---|---|---|---|---|
| 1 | ☐ | G7 – buttmud | G7 Server | Login | `buttmud` | `ssh://192.168.0.6:3333` | Password | You know it |
| 2 | ☐ | G7 – PiKVM | G7 Server | Login | your PiKVM user | PiKVM web address; note SSH port 1337 | Password | You know it |
| 3 | ☐ | G7 – Jenkins admin | G7 Server | Login | `buttmud` | `http://192.168.0.6:8080` | Password | You know it |
| 4 | ☐ | G7 – Jenkins deploy-bot | G7 Server | Login | `deploy-bot` | `http://192.168.0.6:8080` | Password + custom field **API token** (hidden) | Password: set when created. Token: PowerShell `[Environment]::GetEnvironmentVariable("G7_JENKINS_TOKEN","User")` |
| 5 | ☐ | G7 – Jenkins CLI auth | G7 Server | Secure note | — | — | Note body | PowerShell `Get-Content $env:USERPROFILE\.jenkins-cli\auth.txt` |
| 6 | ☐ | G7 – Jenkins agent secret | G7 Server | Secure note | — | — | Note body | G7 `sudo grep -rho -- '-secret [^ ]*' /etc/systemd/system` (optional — can be regenerated) |
| 7 | ☐ | DuckDNS | G7 Server | Login | your DuckDNS sign-in | `https://www.duckdns.org` | Custom field **Token** (hidden); note domains `buttmud`, `buttvault` | G7 `sudo cat /srv/vaultwarden/caddy.env` |
| 8 | ☐ | Home router | G7 Server | Login | router admin user | `http://192.168.0.1` | Password | You know it; note "UDP 51820 → 192.168.0.6" |
| 9 | ☐ | WireGuard – Server (wg0) | WireGuard | Secure note | — | `buttmud.duckdns.org:51820` | Note body: private key + public key `tanf/9aIsqo1b1Xm0dydGczTn1yblvG4tDekcPr1+zU=` | G7 `sudo grep PrivateKey /etc/wireguard/wg0.conf` |
| 10 | ☐ | WireGuard – Phone (10.77.0.2) | WireGuard | Secure note | — | — | Attach the `.conf` | WireGuard app on phone → tunnel → Export |
| 11 | ☐ | WireGuard – Laptop (10.77.0.3) | WireGuard | Secure note | — | — | Attach the `.conf` | WireGuard app on laptop → Export tunnels to zip |
| 12 | ☐ | WireGuard – tg1 (10.77.0.20) | WireGuard | Secure note | — | — | Attach the `.conf` | Find on G7: `sudo find /etc/wireguard /root /home -name '*.conf' ! -name 'wg0.conf*' 2>/dev/null` |
| 13 | ☐ | WireGuard – tg2 (10.77.0.21) | WireGuard | Secure note | — | — | Attach the `.conf` | Same command as #12 |
| 14 | ☐ | WireGuard – Will (10.77.0.31) | WireGuard | Secure note | — | — | Attach the `.conf` | Same command as #12 |
| 15 | ☐ | WireGuard – Frank (10.77.0.32) | WireGuard | Secure note | — | — | Attach the `.conf` | Same command as #12 |
| 16 | ☐ | Wi-Fi – CrackCookingKitchen | WireGuard | Login | — | SSID `CrackCookingKitchen` | Password | G7 `sudo grep wpa_passphrase /etc/hostapd/hostapd.conf` |
| 17 | ☐ | SSH – id_ed25519 (main) | SSH Keys | SSH key | — | — | Import key; put its passphrase in the item's notes or a custom field | File `C:\Users\skip\.ssh\id_ed25519`. Used for site pushes to G7 and SSH |
| 18 | ☐ | SSH – g7_git | SSH Keys | SSH key | — | — | Import key | File `C:\Users\skip\.ssh\g7_git`. Used for TaxGlasses pushes |
| 19 | ☐ | SSH – claude-taxglasses | SSH Keys | SSH key | — | — | Import key | File `C:\Users\skip\.ssh\claude-taxglasses`. Claude Code's access to G7 |
| 20 | ☐ | SSH – vault-backup | SSH Keys | SSH key | — | — | Import key (no passphrase, by design) | File `C:\Users\skip\.ssh\vault-backup`. Daily vault backup pull |
| 21 | ☐ | SSH – config file | SSH Keys | Secure note | — | — | Note body | PowerShell `Get-Content $env:USERPROFILE\.ssh\config` |
| 22 | ☐ | SSH – Jenkins site keys (G7) | SSH Keys | Secure note | — | — | Note body: both keys | G7 `sudo cat /root/g7-sites-keys/guatemalahope-jenkins /root/g7-sites-keys/aeraphim-jenkins` (optional) |
| 23 | ☐ | SSH – G7 GitHub mirror key | SSH Keys | Secure note | — | — | Note body | G7 `sudo ls /srv/git/.ssh/`, then `sudo cat` the private key (optional) |
| 24 | ☐ | GitHub – skipbrisc | Websites | Login | `skipbrisc` | `https://github.com` | Password + TOTP + recovery codes in notes | github.com → Settings → Password and authentication |
| 25 | ☐ | Vercel | Websites | Login | your Vercel sign-in | `https://vercel.com` | Password | You know it |
| 26 | ☐ | Vercel – token g7-jenkins | Websites | Secure note | — | — | Note body | Shown only once. If not saved: make a new token, update Jenkins credential `vercel-token`, delete the old one |
| 27 | ☐ | Vercel – bypass Guatemala Hope | Websites | Secure note | — | — | Note body | Vercel → guatemalahope.org → Settings → Deployment Protection |
| 28 | ☐ | Vercel – bypass Aeraphim | Websites | Secure note | — | — | Note body | Vercel → aeraphim → Settings → Deployment Protection |
| 29 | ☐ | Guatemala Hope – Stripe | Websites | Login | Stripe sign-in | `https://dashboard.stripe.com` | Password + custom fields **Secret key**, **Webhook secret** (hidden) | Stripe → Developers → API keys / Webhooks |
| 30 | ☐ | Guatemala Hope – Resend | Websites | Login | Resend sign-in | `https://resend.com` | Password + custom field **API key** (hidden) | Resend → API Keys (make a new one if not saved) |
| 31 | ☐ | Guatemala Hope – Redis | Websites | Login | provider sign-in | provider dashboard | Password + custom field **REDIS_URL** (hidden) | Your Redis provider's dashboard |
| 32 | ☐ | Guatemala Hope – Turnstile | Websites | Login | Cloudflare sign-in | `https://dash.cloudflare.com` | Password + custom fields **Site key**, **Secret key** | Cloudflare → Turnstile |
| 33 | ☐ | Guatemala Hope – .env.local | Websites | Secure note | — | — | Attach the file | `D:\guatemalahope.org\.env.local` (if it holds real values) |
| 34 | ☐ | Aeraphim – site services | Websites | Login (one per service) | — | — | Password | Booking, contact form, analytics — whatever the site uses |
| 35 | ☐ | Domain registrar | Websites | Login | registrar sign-in | registrar site | Password | For aeraphimcpa.com and guatemalahope.org |
| 36 | ☐ | MemeSniper – control token | MemeSniper | Secure note | — | `http://10.77.0.1:8765` | Note body | G7 `sudo cat /var/lib/memesniper/secrets/control-token.txt` |
| 37 | ☐ | MemeSniper – other secrets | MemeSniper | Secure note | — | — | Note body | G7 `sudo ls -la /var/lib/memesniper/secrets/` — save anything else there |
| 38 | ☐ | Alpha Vantage | MemeSniper | Login | your sign-in | `https://www.alphavantage.co` | Custom field **API key** (hidden) | You have it |
| 39 | ☐ | Robinhood | MemeSniper | Login | your sign-in | `https://robinhood.com` | Password + 2FA backup codes in notes | Robinhood app → Security |
| 40 | ☐ | Claude / Anthropic | Accounts | Login | your email | `https://claude.ai` | Password (+ API keys as custom fields if any) | You know it |
| 41 | ☐ | OpenAI / Codex | Accounts | Login | your email | `https://chatgpt.com` | Password (+ API keys if any) | You know it |
| 42 | ☐ | Email | Accounts | Login | your email | provider site | Password + recovery codes in notes | Provider's security page |
| 43 | ☐ | Doc – G7 Network | Docs | Secure note | — | — | Attach file | `D:\TaxGlasses-ops\G7-NETWORK.md` |
| 44 | ☐ | Doc – Vaultwarden runbook | Docs | Secure note | — | — | Attach file | `D:\TaxGlasses-ops\vaultwarden\VAULTWARDEN.md` |
| 45 | ☐ | Doc – Sites pipeline | Docs | Secure note | — | — | Attach file | `D:\TaxGlasses-ops\sites\SITES-SETUP.md` |
| 46 | ☐ | Doc – MemeSniper deploy | Docs | Secure note | — | — | Attach file | `D:\memesniper-deploy\SETUP.md` |

## Quick reference

**Custom field:** in the item, scroll to **Custom fields** → **New custom field** → choose **Hidden** → name it (e.g. `API token`) → paste the value.

**SSH key item:** New → **SSH key** → **Import key** → choose the file (enter its passphrase if asked).

**Attachment:** open the saved item → **Attachments** → **Choose file** → **Save**.
