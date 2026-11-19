<#
setup-all.ps1 - walk through the 2026-11-18 move of work from this PC to G7, step by step.
It runs the commands from agent/README.md, g7/pc-backup/README.md and pc/README.md in order,
and stops wherever you are needed: G7's sudo password, the Claude login in the browser, the
backup passwords, Healthchecks.io and GitHub in the browser.

Run it in a normal (not admin) PowerShell from D:\g7-infra:

    powershell -NoProfile -ExecutionPolicy Bypass -File pc\setup-all.ps1
    powershell -NoProfile -ExecutionPolicy Bypass -File pc\setup-all.ps1 -From 5     # resume at step 5

  1  commit and push g7-infra             5  PC backup: G7 side (sudo), Healthchecks checks
  2  G7 agent: this PC's side             6  PC backup: this PC's side (admin window)
  3  G7 agent: G7's side (sudo)           7  repositories onto G7 (GitHub, sudo, push)
  4  Claude login for G7, doctor          8  record the new mirror units in g7-infra

Before each step it says what it will do. Enter goes on, S skips the step, Q stops.
After a failure, fix the cause and re-run with -From <that step>.
Left for later: once the long TaxGlasses workflow has finished, run
pc\repos-to-g7.ps1 -Apply -TaxGlassesBranches, then pc\prune-worktrees.ps1.
#>
param([int]$From = 1)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root
$utf8 = New-Object System.Text.UTF8Encoding($false)
$script:step = 0

function Step([int]$n, [string]$title, [string]$what) {
    $script:step = $n
    if ($n -lt $From) { return $false }
    Write-Host ""
    Write-Host "=== Step $n of 8: $title" -ForegroundColor Cyan
    Write-Host $what
    $a = Read-Host "Enter to go on, S to skip, Q to stop"
    if ($a -match '^[Qq]') { Write-Host "Stopped. Resume with: -From $n"; exit 0 }
    return -not ($a -match '^[Ss]')
}
function Run([string]$exe) {  # Run <exe> <args...>: stop on failure
    & $exe @args
    if ($LASTEXITCODE -ne 0) { throw "'$exe $($args -join ' ')' failed (exit $LASTEXITCODE). Fix it, then re-run with -From $script:step" }
}
function Ask([string]$q) { return ((Read-Host "$q (y/n)") -match '^[Yy]') }
function Read-Secret([string]$prompt) {
    $s = Read-Host -AsSecureString $prompt
    $b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b).Trim() } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b) }
}
function Commit-And-Push([string]$message, [string[]]$paths) {
    Run git add @paths
    & git diff --cached --quiet
    if ($LASTEXITCODE -ne 0) {
        $msgFile = Join-Path $env:TEMP 'g7-infra-commit-msg.txt'
        [IO.File]::WriteAllText($msgFile, $message, $utf8)
        Run git commit -F $msgFile
        Remove-Item $msgFile
    } else { Write-Host "   nothing new to commit" }
    Run git push g7 main
}

Write-Host "Checking: this is D:\g7-infra on main, and 'ssh g7' works without a password..."
if ((& git rev-parse --abbrev-ref HEAD) -ne 'main') { throw "g7-infra is not on main" }
& ssh -o BatchMode=yes -o ConnectTimeout=10 g7 true
if ($LASTEXITCODE -ne 0) { throw "ssh g7 does not work from here (key ~/.ssh/g7_skip). Fix that first." }
Write-Host "ok"

# ------------------------------------------------------------------------------------------
if (Step 1 'commit and push g7-infra' @'
Commits the new folders (agent/, g7/pc-backup/, pc/) and the INFRA.md and MAP changes, and
pushes to G7, so the nightly drift check agrees with what gets installed next.
'@) {
    & git status --short
    Commit-And-Push @'
G7 agent, PC backup to G7, repos onto G7

- agent/: Claude Code jobs on G7 for the PC (ssh g7-agent), in tmux inside a sandboxed,
  memory-capped service; Git access limited to agent repos; pre-receive hook refuses the
  release branch, tags and deletions from the agent
- g7/pc-backup/: append-only restic REST server for the PC on 192.168.0.6:8000, nightly
  prune and copy to Miami, alarm when the PC's newest backup is over 3 days old
- pc/: PC-side scripts (backup task, repos-to-g7, prune-worktrees, setup-all)
- MAP and INFRA.md updated

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QGwe7Bd3zQ24ZmHmSAE56P
'@ @('agent', 'g7/pc-backup', 'pc', 'INFRA.md', 'g7/drift/MAP')
}

# ------------------------------------------------------------------------------------------
if (Step 2 'G7 agent: this PC' @'
Creates the SSH key ~/.ssh/g7_agent (press Enter twice when asked: no passphrase), adds
"Host g7-agent" to ~/.ssh/config, installs the g7-offload skill for Claude Code and allows
it to run "ssh g7-agent ...".
'@) {
    & (Join-Path $root 'agent\pc\setup-pc.ps1')
}

# ------------------------------------------------------------------------------------------
if (Step 3 'G7 agent: G7 (asks for your sudo password)' @'
Copies agent/ and the new key to G7 and runs its install.sh: user "agent", Claude Code, the
sandboxed tmux service, Git access and hooks. It ends with a self-test inside the sandbox.
'@) {
    Run ssh g7 "rm -rf /tmp/g7-agent-src"
    Run scp -q -r agent g7:/tmp/g7-agent-src
    Run scp -q "$HOME\.ssh\g7_agent.pub" g7:/tmp/g7_agent.pub
    Run ssh -t g7 "sudo sh /tmp/g7-agent-src/install.sh /tmp/g7_agent.pub"
    Write-Host "SKIP lines for repositories that are not on G7 yet are fine: step 7 creates them."
    if (-not (Ask "Did the self-test end with 'selftest: 0 failed'?")) {
        throw "Fix the FAIL lines first (agent/README.md, Troubleshooting), then re-run with -From 3"
    }
}

# ------------------------------------------------------------------------------------------
if (Step 4 'Claude login for G7' @'
Runs "claude setup-token": a browser opens, you approve, and it prints a token (sk-ant-...)
that lasts a year. Copy it; this step then asks for it (hidden) and stores it on G7.
'@) {
    if (-not (Get-Command claude -ErrorAction SilentlyContinue)) { throw "claude (Claude Code) is not on PATH here" }
    & claude setup-token
    $token = Read-Secret "Paste the token"
    $token | & ssh g7-agent set-token
    if ($LASTEXITCODE -ne 0) { throw "storing the token failed; re-run with -From 4" }
    $token = $null
    & ssh g7-agent doctor
    if ($LASTEXITCODE -ne 0) { Write-Host "doctor reported a FAIL line above; see agent/README.md" -ForegroundColor Yellow }
}

# ------------------------------------------------------------------------------------------
if (Step 5 'PC backup: G7 (asks for your sudo password)' @'
Installs the restic REST server for this PC on G7, the backup repository, and the nightly
prune-and-copy-to-Miami job. The first time it prints TWO secrets: put both in Vaultwarden
before going on. Then Healthchecks.io opens to add four checks.
'@) {
    Run ssh g7 "rm -rf /tmp/g7-pc-backup"
    Run scp -q -r g7/pc-backup g7:/tmp/g7-pc-backup
    Run ssh -t g7 "sudo sh /tmp/g7-pc-backup/install.sh"
    Read-Host "Saved the repository password and the REST login in Vaultwarden? Enter to go on" | Out-Null
    Start-Process 'https://healthchecks.io/'
    Write-Host @'
In Healthchecks.io (the project G7 already pings), add these checks. The slug must be exactly
as written (Name and slug: same text):
   pc-backup-offsite         period 1 day      grace 6 hours
   aeraphim-chatbot-mirror   period 5 minutes  grace 30 minutes
   househack-mirror          period 5 minutes  grace 30 minutes
   cryptoagent-mirror        period 5 minutes  grace 30 minutes
'@
    Read-Host "Enter when done" | Out-Null
}

# ------------------------------------------------------------------------------------------
if (Step 6 'PC backup: this PC (opens an admin window)' @'
Installs restic if it is missing (pc\backup\get-restic.ps1), then opens an admin PowerShell running
pc\backup\install-pc-backup.ps1: it asks for the two secrets from step 5 and creates the
daily task "PC backup to G7". Close that window when it says Done.
'@) {
    $have = (Test-Path (Join-Path $env:LOCALAPPDATA 'Programs\restic\restic.exe')) -or (Get-Command restic -ErrorAction SilentlyContinue)
    if (-not $have) { & (Join-Path $root 'pc\backup\get-restic.ps1') }
    $installer = Join-Path $root 'pc\backup\install-pc-backup.ps1'
    Start-Process powershell.exe -Verb RunAs -Wait -ArgumentList "-NoProfile -ExecutionPolicy Bypass -NoExit -File `"$installer`""
    if (Get-ScheduledTask -TaskName 'PC backup to G7' -ErrorAction SilentlyContinue) {
        if (Ask "Start the first backup now? It runs in the background and takes a while") {
            Start-ScheduledTask -TaskName 'PC backup to G7'
            Write-Host "   started; log in $env:LOCALAPPDATA\pc-backup\"
        }
    } else {
        throw "the task 'PC backup to G7' was not created; see the admin window's message, then re-run with -From 6"
    }
}

# ------------------------------------------------------------------------------------------
if (Step 7 'repositories onto G7 (GitHub in the browser, then sudo)' @'
GitHub opens to create the empty private repository "cryptoagent" (no README). Then, in one
G7 session (one sudo password): the bare repositories and GitHub mirrors for Aeraphim-Chatbot,
househack and cryptoagent, and the agent install again so they get its push hook. Then
pc\repos-to-g7.ps1 shows what it would push, and pushes after you say yes.
'@) {
    Start-Process 'https://github.com/new?name=cryptoagent&visibility=private'
    Read-Host "Create it as Private, with no README, .gitignore or license. Enter when done" | Out-Null
    Run scp -q template/g7-new-repo.sh g7:/tmp/g7-new-repo.sh
    Run ssh g7 "rm -rf /tmp/g7-agent-src"
    Run scp -q -r agent g7:/tmp/g7-agent-src
    Run scp -q "$HOME\.ssh\g7_agent.pub" g7:/tmp/g7_agent.pub
    Run ssh -t g7 ("sudo bash /tmp/g7-new-repo.sh Aeraphim-Chatbot skipbrisc/Aeraphim-Chatbot --mirror-only" +
        " && sudo bash /tmp/g7-new-repo.sh househack skipbrisc/house-hack --mirror-only" +
        " && sudo bash /tmp/g7-new-repo.sh cryptoagent skipbrisc/cryptoagent --mirror-only" +
        " && sudo sh /tmp/g7-agent-src/install.sh /tmp/g7_agent.pub")
    & (Join-Path $root 'pc\repos-to-g7.ps1')
    if (Ask "Push these to G7 now?") { & (Join-Path $root 'pc\repos-to-g7.ps1') -Apply }
}

# ------------------------------------------------------------------------------------------
if (Step 8 'record the new mirror units in g7-infra' @'
Copies the three new mirror units from G7 into systemd/, lists them and the three new hooks
in g7/drift/MAP, and commits and pushes, so g7-drift agrees with G7.
'@) {
    $map = Join-Path $root 'g7\drift\MAP'
    $text = [IO.File]::ReadAllText($map)
    $lines = @()
    foreach ($slug in 'aeraphim-chatbot', 'househack', 'cryptoagent') {
        New-Item -ItemType Directory -Force -Path "systemd\$slug-mirror.service.d" | Out-Null
        # One file per scp: Windows' scp drops the connection when one call names several remote files.
        foreach ($f in "$slug-mirror.service", "$slug-mirror.timer", "$slug-mirror.service.d/healthchecks.conf") {
            Run scp -q "g7:/etc/systemd/system/$f" "systemd/$f"
        }
        foreach ($f in "$slug-mirror.service", "$slug-mirror.service.d/healthchecks.conf", "$slug-mirror.timer") {
            $line = "file  g7-infra:systemd/$f  /etc/systemd/system/$f  root:root  0644  yes"
            if (-not $text.Contains($line)) { $lines += $line }
        }
    }
    if ($lines.Count -gt 0) {
        $block = "# --- GitHub mirrors added 2026-11-18 (pc/repos-to-g7.ps1)`n" + ($lines -join "`n") + "`n`n"
        $text = $text.Replace('# --- G7 agent (agent/)', $block + '# --- G7 agent (agent/)')
    }
    $text = $text.Replace("# Uncomment once pc/repos-to-g7.ps1 has put these on G7 and agent/install.sh has run again:`n", '')
    foreach ($r in 'Aeraphim-Chatbot', 'househack', 'cryptoagent') {
        $text = $text.Replace("# file  g7-infra:agent/pre-receive  /srv/git/repos/$r.git/hooks/pre-receive", "file  g7-infra:agent/pre-receive  /srv/git/repos/$r.git/hooks/pre-receive")
    }
    [IO.File]::WriteAllText($map, $text, $utf8)
    Commit-And-Push @'
Record the GitHub mirrors of Aeraphim-Chatbot, househack and cryptoagent, and the agent hooks

g7-agent: repositories not on G7 yet are SKIP in the self-test and info in doctor, not FAIL.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QGwe7Bd3zQ24ZmHmSAE56P
'@ @('systemd', 'g7/drift/MAP', 'agent', 'pc')
    Write-Host "To confirm: ssh -t g7 `"sudo g7-drift`" should report everything matches Git."
}

Write-Host ""
Write-Host "All steps done." -ForegroundColor Green
Write-Host "Later, once the long TaxGlasses workflow has finished:"
Write-Host "   powershell -NoProfile -ExecutionPolicy Bypass -File pc\repos-to-g7.ps1 -Apply -TaxGlassesBranches"
Write-Host "   powershell -NoProfile -ExecutionPolicy Bypass -File pc\prune-worktrees.ps1      (then again with -Apply)"
Write-Host "Optional: phone notifications for agent jobs (agent/README.md, Notifications)."
