# Runbook: <project>

One page. Fill it in when the project first goes live, and fix it whenever it is wrong.

## What it is
<one sentence>. Live at <URL or host:port>. Runs on <Vercel / G7 service / G7 container>.

## Is it up?
- Uptime Kuma monitor: <name>
- By hand: `<curl or command that proves it works>`

## Deploy
`<command>`. What a good deploy looks like: <alert text or log line>.

## Roll back
`<command>`. Rolls back to: <the previous deployment / the other color / the last release dir>.

## Logs
`<command or URL>`

## Restart
`<command>`. Safe to do when: <condition>.

## Secrets and config
| What | Where it lives | How to rotate |
|---|---|---|
| <name> | <Vaultwarden entry, file on G7, Vercel setting> | <steps> |

## Common failures
| Symptom | Likely cause | Fix |
|---|---|---|
| <what you see> | <why> | <what to do> |

## Who to ask
<you, plus any vendor support links>
