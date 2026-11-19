<#
get-restic.ps1 - install restic for this PC's backup without winget (g7-infra g7/pc-backup/README.md).
Downloads the latest Windows build from restic's official GitHub releases, checks it against the
release's SHA256SUMS, and puts it at %LOCALAPPDATA%\Programs\restic\restic.exe, where
pc-backup.ps1 and install-pc-backup.ps1 look first. No admin needed. Re-run to update.

    powershell -NoProfile -ExecutionPolicy Bypass -File pc\backup\get-restic.ps1
#>
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # Invoke-WebRequest is very slow with the progress bar
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$dest = Join-Path $env:LOCALAPPDATA 'Programs\restic'
$exe = Join-Path $dest 'restic.exe'
$tmp = Join-Path $env:TEMP ("restic-download-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $dest, $tmp | Out-Null

try {
    Write-Host "== latest release of restic"
    $rel = Invoke-RestMethod -Uri 'https://api.github.com/repos/restic/restic/releases/latest' -Headers @{ 'User-Agent' = 'g7-infra-get-restic' }
    $zipAsset = $rel.assets | Where-Object { $_.name -match '^restic_[0-9.]+_windows_amd64\.zip$' } | Select-Object -First 1
    $sumAsset = $rel.assets | Where-Object { $_.name -eq 'SHA256SUMS' } | Select-Object -First 1
    if (-not $zipAsset -or -not $sumAsset) { throw "release $($rel.tag_name) has no windows_amd64 zip or SHA256SUMS" }
    Write-Host "   $($rel.tag_name): $($zipAsset.name)"

    $zip = Join-Path $tmp $zipAsset.name
    $sums = Join-Path $tmp 'SHA256SUMS'
    Invoke-WebRequest -UseBasicParsing -Uri $zipAsset.browser_download_url -OutFile $zip
    Invoke-WebRequest -UseBasicParsing -Uri $sumAsset.browser_download_url -OutFile $sums

    Write-Host "== checking the SHA-256 against the release's SHA256SUMS"
    $want = Get-Content $sums | ForEach-Object {
        $parts = $_ -split '\s+', 2
        if ($parts.Count -eq 2 -and $parts[1].TrimStart('*').Trim() -eq $zipAsset.name) { $parts[0].ToLower() }
    } | Select-Object -First 1
    $have = (Get-FileHash -Algorithm SHA256 $zip).Hash.ToLower()
    if (-not $want) { throw "SHA256SUMS does not list $($zipAsset.name)" }
    if ($want -ne $have) { throw "checksum mismatch for $($zipAsset.name): expected $want, got $have. Not installed." }
    Write-Host "   ok ($have)"

    Expand-Archive -Path $zip -DestinationPath $tmp -Force
    $bin = Get-ChildItem $tmp -Filter 'restic*.exe' -Recurse | Select-Object -First 1
    if (-not $bin) { throw "no restic .exe inside $($zipAsset.name)" }
    Copy-Item -Force $bin.FullName $exe
    Write-Host "== installed $exe"
    & $exe version
} finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}
