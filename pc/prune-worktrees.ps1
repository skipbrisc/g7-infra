<#
prune-worktrees.ps1 - remove TaxGlasses worktrees whose work is already in the release branch.
Run it only when no Claude Code session is working in those worktrees.

    powershell -NoProfile -ExecutionPolicy Bypass -File pc\prune-worktrees.ps1                  # report only
    powershell -NoProfile -ExecutionPolicy Bypass -File pc\prune-worktrees.ps1 -Apply           # remove them
    powershell -NoProfile -ExecutionPolicy Bypass -File pc\prune-worktrees.ps1 -Apply -DeleteBranches

A worktree is removed only when all of these hold:
  * its commit is in master (locally or on g7);
  * it has no uncommitted or untracked files;
  * it is not locked.
Removing it deletes its folder, node_modules included. -DeleteBranches also deletes the merged
branch here with "git branch -d", which refuses anything unmerged; the branch stays on G7.
Everything else is listed with the reason it stays. Folders called TaxGlasses-wt* that Git does
not know as worktrees are listed too, but never touched.
#>
param([string]$Repo = 'D:\TaxGlasses', [switch]$Apply, [switch]$DeleteBranches)
$ErrorActionPreference = 'Stop'
$env:GIT_OPTIONAL_LOCKS = '0'
function G {
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $out = & git @args 2>&1 | ForEach-Object { "$_" }
    $script:rc = $LASTEXITCODE; $ErrorActionPreference = $old
    return $out
}

$release = ((G -C $Repo symbolic-ref --quiet --short refs/remotes/g7/HEAD) | Select-Object -First 1)
$release = if ($release) { $release -replace '^g7/', '' } else { 'master' }
$targets = @($release, "g7/$release")
if (-not $Apply) { Write-Host "REPORT ONLY. Add -Apply to remove the worktrees marked 'remove'.`n" }
Write-Host "Release branch: $release`n"

# Parse "git worktree list --porcelain"
$wts = @(); $cur = $null
foreach ($line in (G -C $Repo worktree list --porcelain)) {
    if ($line -like 'worktree *') { if ($cur) { $wts += $cur }; $cur = @{ Path = $line.Substring(9).Replace('/', [IO.Path]::DirectorySeparatorChar); Branch = ''; Head = ''; Locked = $false; Prunable = $false } }
    elseif ($line -like 'HEAD *') { $cur.Head = $line.Substring(5) }
    elseif ($line -like 'branch *') { $cur.Branch = $line.Substring(7) -replace '^refs/heads/', '' }
    elseif ($line -like 'locked*') { $cur.Locked = $true }
    elseif ($line -like 'prunable*') { $cur.Prunable = $true }
}
if ($cur) { $wts += $cur }
$main = (Resolve-Path $Repo).Path.TrimEnd('\', '/')

$remove = @(); $rows = @()
foreach ($w in $wts) {
    if ($w.Path.TrimEnd('\', '/') -ieq $main) { continue }
    $name = Split-Path $w.Path -Leaf
    $branch = if ($w.Branch) { $w.Branch } else { "(detached $($w.Head.Substring(0,8)))" }
    $why = $null
    if ($w.Prunable -or -not (Test-Path $w.Path)) { $why = 'folder missing (git worktree prune clears it)' }
    elseif ($w.Locked) { $why = 'locked' }
    else {
        $merged = $false
        foreach ($t in $targets) { G -C $Repo merge-base --is-ancestor $w.Head $t | Out-Null; if ($script:rc -eq 0) { $merged = $true; break } }
        if (-not $merged) {
            $ahead = (G -C $Repo rev-list --count "$release..$($w.Head)") | Select-Object -First 1
            $why = "not merged ($ahead commits not in $release)"
        } else {
            $dirty = @(G -C $w.Path status --porcelain --untracked-files=normal)
            if ($script:rc -ne 0) { $why = 'git status failed' }
            elseif ($dirty.Count -gt 0) { $why = "$($dirty.Count) uncommitted/untracked file(s)" }
        }
    }
    $action = if ($why) { "keep: $why" } else { 'remove' }
    if (-not $why) { $remove += $w }
    $rows += [pscustomobject]@{ Worktree = $name; Branch = $branch; Action = $action }
}
$rows | Sort-Object Action, Worktree | Format-Table -AutoSize | Out-String -Width 200 | Write-Host

$known = $wts | ForEach-Object { (Split-Path $_.Path -Leaf).ToLower() }
$stray = Get-ChildItem -Path (Split-Path $main) -Directory -Filter 'TaxGlasses-wt*' | Where-Object { $known -notcontains $_.Name.ToLower() }
if ($stray) {
    Write-Host "Folders that are not Git worktrees (left alone; check and delete by hand if unwanted):"
    $stray | ForEach-Object { Write-Host "   $($_.FullName)" }
    Write-Host ""
}

Write-Host "$($remove.Count) worktree(s) can be removed."
if ($Apply) {
    foreach ($w in $remove) {
        Write-Host "== removing $($w.Path)"
        G -C $Repo worktree remove $w.Path | ForEach-Object { Write-Host "   $_" }
        if ($script:rc -ne 0) { Write-Host "   could not remove it (see above); left as it is"; continue }
        if ($DeleteBranches -and $w.Branch) {
            G -C $Repo branch -d $w.Branch | ForEach-Object { Write-Host "   $_" }
        }
    }
    G -C $Repo worktree prune | Out-Null
    Write-Host "Done."
}
