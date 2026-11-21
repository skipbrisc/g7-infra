<#
repos-to-g7.ps1 - put every repository on this PC onto G7, the same way as TaxGlasses (push to
the remote g7; G7 mirrors to GitHub). Written 2026-11-18 from an inventory of D:\.

    powershell -NoProfile -ExecutionPolicy Bypass -File pc\repos-to-g7.ps1            # dry run
    powershell -NoProfile -ExecutionPolicy Bypass -File pc\repos-to-g7.ps1 -Apply     # do it

Before -Apply, create each repository on G7 (bare repository, GitHub mirror, Healthchecks ping),
from D:\g7-infra. For cryptoagent, first create an empty private GitHub repository called
cryptoagent:

    scp template/g7-new-repo.sh g7:/tmp/
    ssh -t g7 "sudo bash /tmp/g7-new-repo.sh Aeraphim-Chatbot skipbrisc/Aeraphim-Chatbot --mirror-only"
    ssh -t g7 "sudo bash /tmp/g7-new-repo.sh househack skipbrisc/house-hack --mirror-only"
    ssh -t g7 "sudo bash /tmp/g7-new-repo.sh cryptoagent skipbrisc/cryptoagent --mirror-only"

For each repository it then:
  1. runs git init -b main and makes a first commit, for a folder that is not a repository yet
     (cryptoagent). Its .gitignore already keeps out .env, secrets/, databases and .venv;
  2. adds the remote g7;
  3. pushes every branch to G7 without force, from wherever the branch is furthest along (here
     or on GitHub), and all tags. It skips a branch that differs in both places and says so;
  4. turns off pushing to origin (GitHub) like the other repositories (DISABLED-push-to-g7),
     and makes the current branch track g7.

-TaxGlassesBranches also pushes TaxGlasses branches that exist only on this PC (the fig-*
branches, 36 on 2026-11-18). Use it once your running Claude Code workflow has finished, so
nothing is writing to that repository while it pushes.
#>
param([switch]$Apply, [switch]$TaxGlassesBranches,
      [string]$Root = 'D:\', [string]$G7Url = 'ssh://git@192.168.0.6:3333/srv/git/repos')
$ErrorActionPreference = 'Stop'
$env:GIT_OPTIONAL_LOCKS = '0'
$G7 = $G7Url
# The same Git key TaxGlasses, g7-infra and memesniper pin, so no call asks for a passphrase.
$g7Key = Join-Path $HOME '.ssh\g7_git'
$sshCmd = $null
if (Test-Path $g7Key) {
    $sshCmd = "ssh -i $($g7Key.Replace('\', '/')) -o IdentitiesOnly=yes"
    $env:GIT_SSH_COMMAND = $sshCmd
}
$repos = @(
    @{ Name = 'Aeraphim-Chatbot'; Path = (Join-Path $Root 'Aeraphim-Chatbot'); GitHub = 'skipbrisc/Aeraphim-Chatbot' },
    @{ Name = 'househack';        Path = (Join-Path $Root 'househack'); GitHub = 'skipbrisc/house-hack' },
    @{ Name = 'cryptoagent';      Path = (Join-Path $Root 'cryptoagent'); GitHub = 'skipbrisc/cryptoagent' }
)

function G {  # run git, return its output lines; $script:rc holds the exit code
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $out = & git @args 2>&1 | ForEach-Object { "$_" }
    $script:rc = $LASTEXITCODE; $ErrorActionPreference = $old
    return $out
}
function Act([string]$what, [scriptblock]$do) {
    if ($Apply) { Write-Host "   $what"; & $do } else { Write-Host "   would: $what" }
}
function Is-Ancestor($repo, $a, $b) { G -C $repo merge-base --is-ancestor $a $b | Out-Null; return ($script:rc -eq 0) }

if (-not $Apply) { Write-Host "DRY RUN: nothing will change. Add -Apply to do it.`n" }

foreach ($r in $repos) {
    $p = $r.Path; $url = "$G7/$($r.Name).git"
    Write-Host "== $($r.Name)  ($p)"
    if (-not (Test-Path $p)) { Write-Host "   folder missing, skipped"; continue }

    G ls-remote $url | Out-Null
    if ($script:rc -ne 0) {
        Write-Host "   not on G7 yet: ssh -t g7 `"sudo bash /tmp/g7-new-repo.sh $($r.Name) $($r.GitHub) --mirror-only`""
        continue
    }

    $isRepo = Test-Path (Join-Path $p '.git')
    $hasCommit = $false
    if ($isRepo) { G -C $p rev-parse --verify --quiet HEAD | Out-Null; $hasCommit = ($script:rc -eq 0) }
    if (-not $hasCommit) {
        $what = if ($isRepo) { 'commit everything .gitignore allows (the repository has no commits yet)' } else { 'git init -b main, then commit everything .gitignore allows' }
        Act $what {
            if (-not $isRepo) { G -C $p init -b main | Out-Null }
            G -C $p add -A | Out-Null
            G -C $p status --short | ForEach-Object { Write-Host "      $_" }
            $msg = G -C $p commit -q -m 'Initial commit (moved onto G7)'
            if ($script:rc -ne 0) { $msg | ForEach-Object { Write-Host "      $_" }; throw "first commit failed in $p" }
        }
        if (-not $Apply) {
            $n = (Get-ChildItem -Path $p -Recurse -File -Force | Where-Object { $_.FullName -notmatch '[\\/](\.git|\.venv|__pycache__|secrets)[\\/]' }).Count
            Write-Host "      (about $n files; .gitignore decides)"
            continue
        }
    }

    $remotes = G -C $p remote
    if ($remotes -notcontains 'g7') { Act "git remote add g7 $url" { G -C $p remote add g7 $url | Out-Null } }
    if ($sshCmd -and ((G -C $p config --get core.sshCommand) -ne $sshCmd)) {
        Act "pin the G7 Git key (core.sshCommand), like TaxGlasses" { G -C $p config core.sshCommand $sshCmd | Out-Null }
    }
    $hasOrigin = $remotes -contains 'origin'
    if ($hasOrigin) { G -C $p fetch --quiet --prune --tags origin | Out-Null }

    $local = @{}; G -C $p for-each-ref --format='%(refname:short) %(objectname)' refs/heads | ForEach-Object {
        $x = $_ -split ' '; if ($x.Count -eq 2) { $local[$x[0]] = $x[1] } }
    $origin = @{}; if ($hasOrigin) { G -C $p for-each-ref --format='%(refname:short) %(objectname)' refs/remotes/origin | ForEach-Object {
        $x = $_ -split ' '; if ($x.Count -eq 2 -and $x[0] -ne 'origin/HEAD' -and $x[0] -ne 'origin') { $origin[$x[0].Substring(7)] = $x[1] } } }

    foreach ($b in (@($local.Keys) + @($origin.Keys) | Sort-Object -Unique)) {
        $l = $local[$b]; $o = $origin[$b]; $src = $null
        if ($l -and -not $o) { $src = "refs/heads/$b" }
        elseif ($o -and -not $l) { $src = "refs/remotes/origin/$b" }
        elseif ($l -eq $o -or (Is-Ancestor $p $o $l)) { $src = "refs/heads/$b" }
        elseif (Is-Ancestor $p $l $o) { $src = "refs/remotes/origin/$b" }
        else { Write-Host "   SKIPPED $b : this PC and GitHub have different commits; merge them first"; continue }
        Act "push $b to G7 (from $($src -replace '^refs/(heads|remotes)/',''))" {
            G -C $p push --quiet g7 "${src}:refs/heads/$b" | ForEach-Object { Write-Host "      $_" }
            if ($script:rc -ne 0) { Write-Host "      PUSH FAILED for $b" }
        }
    }
    Act "push tags to G7" { G -C $p push --quiet g7 --tags | Out-Null }
    if ($hasOrigin) {
        Act "stop pushes to GitHub (origin push URL DISABLED-push-to-g7)" { G -C $p remote set-url --push origin DISABLED-push-to-g7 | Out-Null }
    }
    $cur = (G -C $p symbolic-ref --quiet --short HEAD) | Select-Object -First 1
    if ($cur) {
        Act "track g7/$cur" { G -C $p fetch --quiet g7 | Out-Null; G -C $p branch --quiet --set-upstream-to="g7/$cur" | Out-Null }
    }
}

if ($TaxGlassesBranches) {
    $p = Join-Path $Root 'TaxGlasses'
    Write-Host "== TaxGlasses: branches that exist only on this PC"
    G -C $p fetch --quiet g7 | Out-Null
    $onG7 = @{}; G -C $p for-each-ref --format='%(refname:short)' refs/remotes/g7 | ForEach-Object { $onG7[$_.Substring(3)] = $true }
    $count = 0
    G -C $p for-each-ref --format='%(refname:short)' refs/heads | ForEach-Object {
        $b = $_
        if (-not $onG7[$b]) {
            $count++
            Act "push $b" { G -C $p push --quiet g7 "refs/heads/${b}:refs/heads/$b" | Out-Null; if ($script:rc -ne 0) { Write-Host "      PUSH FAILED for $b" } }
        }
    }
    Write-Host "   $count branch(es) only on this PC"
}

Write-Host ""
Write-Host "Afterwards: re-run the G7 agent's install.sh (agent/README.md) so it adds its push hook to the new repositories."
