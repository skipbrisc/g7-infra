<#
install-pc-backup.ps1 - set up this PC's daily backup to G7 (g7-infra g7/pc-backup/README.md).
Run once in an ADMIN PowerShell from D:\g7-infra, after G7's side is installed:

    winget install restic.restic          # once, then open a new admin PowerShell
    powershell -NoProfile -ExecutionPolicy Bypass -File pc\backup\install-pc-backup.ps1

Asks for the two secrets G7's install printed (also in Vaultwarden), stores them for your
account only, checks the login, and creates the scheduled task "PC backup to G7".
Safe to re-run: it keeps stored secrets unless you pass -Reset.
#>
param([switch]$Reset, [string]$At = '12:30')
$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { throw 'Run this from an admin PowerShell (the task runs elevated to copy open files).' }
$restic = (Get-Command restic -ErrorAction SilentlyContinue).Source
if (-not $restic) {  # just installed by winget, or PATH not refreshed yet
    $restic = @(Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\restic.exe') +
        @(Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages') -Recurse -Filter 'restic*.exe' -ErrorAction SilentlyContinue |
          ForEach-Object FullName) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
}
if (-not $restic) { throw 'restic is not installed: winget install restic.restic, then open a new PowerShell.' }

$cfgDir = Join-Path $env:USERPROFILE '.config\pc-backup'
$envFile = Join-Path $cfgDir 'rest.env'
$pwFile = Join-Path $cfgDir 'repo-password.txt'
New-Item -ItemType Directory -Force -Path $cfgDir | Out-Null
# Only this account, SYSTEM and Administrators may read the folder.
& icacls $cfgDir /inheritance:r /grant:r "$($env:USERNAME):(OI)(CI)F" "*S-1-5-18:(OI)(CI)F" "*S-1-5-32-544:(OI)(CI)F" | Out-Null

function Read-Secret([string]$prompt) {
    $s = Read-Host -AsSecureString $prompt
    $b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b).Trim() } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b) }
}

if ($Reset -or -not (Test-Path $envFile)) {
    $rest = Read-Secret 'REST login password for user pc (printed by G7''s install)'
    $hc = Read-Host 'Optional Healthchecks.io ping URL for this PC (Enter to skip)'
    $lines = @('RESTIC_REPOSITORY=rest:http://192.168.0.6:8000/pc/restic/', 'RESTIC_REST_USERNAME=pc', "RESTIC_REST_PASSWORD=$rest")
    if ($hc) { $lines += "HC_PING_URL=$($hc.Trim())" }
    [IO.File]::WriteAllText($envFile, ($lines -join "`n") + "`n", $utf8)
}
if ($Reset -or -not (Test-Path $pwFile)) {
    [IO.File]::WriteAllText($pwFile, (Read-Secret 'Repository password (printed by G7''s install)') + "`n", $utf8)
}

Write-Host '== checking the login and the repository'
foreach ($line in Get-Content $envFile) {
    if ($line -match '^\s*([A-Z_]+)\s*=\s*(.*)$') { Set-Item -Path "Env:$($Matches[1])" -Value $Matches[2].Trim() }
}
$env:RESTIC_PASSWORD_FILE = $pwFile
$ErrorActionPreference = 'Continue'
& $restic cat config *> $null
$rc = $LASTEXITCODE
$ErrorActionPreference = 'Stop'
if ($rc -ne 0) { throw "restic could not open the repository (exit $rc). Wrong password, or G7 unreachable? Re-run with -Reset to enter them again." }
Write-Host '   ok'

Write-Host '== scheduled task "PC backup to G7"'
$script = Join-Path $PSScriptRoot 'pc-backup.ps1'
$action = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$script`""
$trigger = New-ScheduledTaskTrigger -Daily -At $At
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -RunOnlyIfNetworkAvailable -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Hours 12) -MultipleInstances IgnoreNew
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest
Register-ScheduledTask -TaskName 'PC backup to G7' -Action $action -Trigger $trigger -Settings $settings `
    -Principal $principal -Description 'restic backup to G7 (g7-infra g7/pc-backup/README.md)' -Force | Out-Null
Write-Host "   daily at $At, or as soon as possible after a missed run"
Write-Host ''
Write-Host 'Done. First backup now (takes a while):   Start-ScheduledTask "PC backup to G7"'
Write-Host "Logs:  $env:LOCALAPPDATA\pc-backup\"
