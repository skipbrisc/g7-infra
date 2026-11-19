<#
setup-pc.ps1 - set up this PC so Claude Code can hand jobs to G7 (g7-infra agent/README.md).
Run once in PowerShell from D:\g7-infra (no admin needed):

    powershell -NoProfile -ExecutionPolicy Bypass -File agent\pc\setup-pc.ps1

It creates the SSH key ~/.ssh/g7_agent (press Enter twice when asked: no passphrase, so Claude
Code can use it unattended), adds "Host g7-agent" to ~/.ssh/config, installs the g7-offload
skill for Claude Code, and lets Claude Code run "ssh g7-agent ..." without asking. Safe to re-run.
#>
$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$sshDir = Join-Path $HOME '.ssh'
$key = Join-Path $sshDir 'g7_agent'

if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) { throw 'OpenSSH (ssh.exe) is not installed.' }
New-Item -ItemType Directory -Force -Path $sshDir | Out-Null

# 1. Key
if (Test-Path $key) {
    Write-Host "== key $key already exists"
} else {
    Write-Host "== creating $key  (press Enter twice: no passphrase)"
    & ssh-keygen -t ed25519 -f $key -C "skip-pc-g7-agent"
    if ($LASTEXITCODE -ne 0) { throw 'ssh-keygen failed' }
}

# 2. SSH config entry
$cfg = Join-Path $sshDir 'config'
$block = @"

Host g7-agent
    HostName 192.168.0.6
    Port 3333
    User agent
    IdentityFile ~/.ssh/g7_agent
    IdentitiesOnly yes
    ServerAliveInterval 30
"@
$existing = if (Test-Path $cfg) { [IO.File]::ReadAllText($cfg) } else { '' }
if ($existing -match '(?m)^\s*Host\s+g7-agent\s*$') {
    Write-Host "== ~/.ssh/config already has Host g7-agent"
} else {
    [IO.File]::AppendAllText($cfg, ($block -replace "`r`n", "`n") + "`n", $utf8)
    Write-Host "== added Host g7-agent to ~/.ssh/config"
}

# 3. Skill for Claude Code
$skillDir = Join-Path $HOME '.claude\skills\g7-offload'
New-Item -ItemType Directory -Force -Path $skillDir | Out-Null
Copy-Item -Force (Join-Path $PSScriptRoot 'SKILL.md') (Join-Path $skillDir 'SKILL.md')
Write-Host "== installed the g7-offload skill in $skillDir"

# 4. Permission: Claude Code may run "ssh g7-agent ..." without asking
$settings = Join-Path $HOME '.claude\settings.json'
$rule = 'Bash(ssh g7-agent *)'
if (Test-Path $settings) {
    $raw = [IO.File]::ReadAllText($settings)
    if ($raw.Contains($rule)) {
        Write-Host "== Claude Code already allows $rule"
    } else {
        Copy-Item $settings "$settings.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
        $json = $raw | ConvertFrom-Json
        if (-not $json.PSObject.Properties['permissions']) {
            $json | Add-Member -NotePropertyName permissions -NotePropertyValue ([pscustomobject]@{})
        }
        if (-not $json.permissions.PSObject.Properties['allow']) {
            $json.permissions | Add-Member -NotePropertyName allow -NotePropertyValue @()
        }
        $json.permissions.allow = @($json.permissions.allow) + $rule
        [IO.File]::WriteAllText($settings, ($json | ConvertTo-Json -Depth 50), $utf8)
        Write-Host "== allowed $rule in $settings (backup kept next to it)"
    }
} else {
    New-Item -ItemType Directory -Force -Path (Split-Path $settings) | Out-Null
    [IO.File]::WriteAllText($settings, "{`n  `"permissions`": {`n    `"allow`": [`"$rule`"]`n  }`n}`n", $utf8)
    Write-Host "== created $settings allowing $rule"
}

Write-Host ""
Write-Host "Next, install the runner on G7 (from D:\g7-infra):"
Write-Host "    ssh g7 `"rm -rf /tmp/g7-agent-src`""
Write-Host "    scp -r agent g7:/tmp/g7-agent-src"
Write-Host "    scp $key.pub g7:/tmp/g7_agent.pub"
Write-Host "    ssh -t g7 `"sudo sh /tmp/g7-agent-src/install.sh /tmp/g7_agent.pub`""
Write-Host "Then give it a Claude login:   claude setup-token    (copy the token), then:   ssh g7-agent set-token"
Write-Host "And check:                     ssh g7-agent doctor"
