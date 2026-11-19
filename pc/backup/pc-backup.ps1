<#
pc-backup.ps1 - back this PC up to G7 with restic (g7-infra g7/pc-backup/README.md).
Run by the scheduled task "PC backup to G7" (set up by install-pc-backup.ps1). By hand:

    powershell -NoProfile -ExecutionPolicy Bypass -File pc\backup\pc-backup.ps1 [-DryRun]

Settings and secrets: %USERPROFILE%\.config\pc-backup\rest.env and repo-password.txt.
Logs: %LOCALAPPDATA%\pc-backup\ (30 days). Exit code: 0 ok (also when a few files could not be
read), 1 failed.
#>
param([switch]$DryRun)
$ErrorActionPreference = 'Stop'

$cfgDir = Join-Path $env:USERPROFILE '.config\pc-backup'
$logDir = Join-Path $env:LOCALAPPDATA 'pc-backup'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$stamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
$log = Join-Path $logDir "pc-backup-$stamp.log"
function Log([string]$m) {
    $line = '{0}  {1}' -f (Get-Date -Format 'HH:mm:ss'), $m
    Add-Content -Path $log -Value $line -Encoding UTF8
    Write-Host $line
}
function Quote-Arg([string]$s) {  # Windows command-line quoting for Start-Process
    if ($s -ne '' -and $s -notmatch '[\s"]') { return $s }
    $s = $s -replace '(\\*)"', '$1$1\"'
    $s = $s -replace '(\\+)$', '$1$1'
    return '"' + $s + '"'
}

# Settings
$envFile = Join-Path $cfgDir 'rest.env'
$pwFile = Join-Path $cfgDir 'repo-password.txt'
if (-not (Test-Path $envFile) -or -not (Test-Path $pwFile)) { Log "not set up: run install-pc-backup.ps1"; exit 1 }
foreach ($line in Get-Content $envFile) {
    if ($line -match '^\s*([A-Z_]+)\s*=\s*(.*)$') { Set-Item -Path "Env:$($Matches[1])" -Value $Matches[2].Trim() }
}
$env:RESTIC_PASSWORD_FILE = $pwFile
$env:RESTIC_CACHE_DIR = Join-Path $env:LOCALAPPDATA 'restic-cache'
$restic = (Get-Command restic -ErrorAction SilentlyContinue).Source
if (-not $restic) {  # just installed by winget, or PATH not refreshed yet
    $restic = @(Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\restic.exe') +
        @(Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages') -Recurse -Filter 'restic*.exe' -ErrorAction SilentlyContinue |
          ForEach-Object FullName) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
}
if (-not $restic) { Log "restic is not installed (winget install restic.restic)"; exit 1 }

# What to back up
$h = $env:USERPROFILE
$paths = @('D:\')
foreach ($p in 'Documents', 'Desktop', 'Pictures', 'Videos', 'Music', 'Favorites', 'Contacts',
               '.claude', '.codex', '.config', '.gstack', '.remember', '.memesniper', '.jenkins-cli', '.gitconfig') {
    $full = Join-Path $h $p
    if (Test-Path $full) { $paths += $full }
}
$exclude = @(
    'D:\SteamLibrary', 'D:\$RECYCLE.BIN', 'D:\System Volume Information',
    'node_modules', '.venv', '__pycache__', '.vite', '.next', '.turbo', '.cache', '.pytest_cache', '.mypy_cache', '*.tmp',
    (Join-Path $h '.claude\.credentials.json'),
    (Join-Path $h '.codex\auth.json'),
    $cfgDir
)

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
$resticArgs = @('backup', '--host', $env:COMPUTERNAME, '--tag', 'pc', '--retry-lock', '30m',
                '--exclude-caches', '--exclude-if-present', '.nobackup')
foreach ($e in $exclude) { $resticArgs += @('--exclude', $e) }
if ($isAdmin) { $resticArgs += '--use-fs-snapshot' } else { Log "not elevated: open files may be skipped (no VSS snapshot)" }
if ($DryRun) { $resticArgs += @('--dry-run', '-v') }
$resticArgs += $paths

Log ("restic backup of " + ($paths -join ', ') + $(if ($DryRun) { ' (dry run)' } else { '' }))
$out = Join-Path $logDir "restic-$stamp.out"
$err = Join-Path $logDir "restic-$stamp.err"
$proc = Start-Process -FilePath $restic -ArgumentList (($resticArgs | ForEach-Object { Quote-Arg $_ }) -join ' ') `
    -NoNewWindow -Wait -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
$rc = $proc.ExitCode
Get-Content $out, $err -ErrorAction SilentlyContinue | Where-Object { $_ -notmatch '^\[\d' } | Select-Object -Last 40 |
    ForEach-Object { Log $_ }
Remove-Item $out, $err -ErrorAction SilentlyContinue

$ok = ($rc -eq 0 -or $rc -eq 3)
if ($rc -eq 3) { Log "snapshot saved, but some files could not be read (see above)" }
Log $(if ($ok) { "backup ok (exit $rc)" } else { "BACKUP FAILED (exit $rc)" })

# Optional outside alarm. G7 alarms on its own when the newest snapshot gets old.
if ($env:HC_PING_URL -and -not $DryRun) {
    try { Invoke-WebRequest -UseBasicParsing -TimeoutSec 15 -Uri ($env:HC_PING_URL + $(if ($ok) { '' } else { '/fail' })) | Out-Null }
    catch { Log "Healthchecks ping failed: $($_.Exception.Message)" }
}

Get-ChildItem $logDir -Filter 'pc-backup-*.log' | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } | Remove-Item
if ($ok) { exit 0 } else { exit 1 }
