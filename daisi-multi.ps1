<#
.SYNOPSIS
    Multi-repo management script for daisinet projects.

.DESCRIPTION
    Manages branches, PRs, and merges across all daisinet git repos from a single CLI.

.EXAMPLE
    .\daisi-multi.ps1 status
    .\daisi-multi.ps1 branch feature/my-feature
    .\daisi-multi.ps1 pr-create -Base dev
    .\daisi-multi.ps1 pr-merge -MergeStrategy squash
#>

param(
    [Parameter(Mandatory, Position = 0)]
    [ValidateSet('status','branch','checkout','pull','push','pr-create','pr-merge','pr-dev-to-main','worktree-add','worktree-remove')]
    [string]$Command,

    [Parameter(Position = 1)]
    [string]$Name,

    [string]$Base = 'dev',
    [ValidateSet('merge','squash','rebase')]
    [string]$MergeStrategy = 'merge',
    [switch]$DryRun,
    [string[]]$Repos
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

$RootDir = Split-Path -Parent $PSScriptRoot

# ---------------------------------------------------------------------------
# Helper Functions
# ---------------------------------------------------------------------------

function Write-ColorLine {
    param(
        [string]$Text,
        [ConsoleColor]$Color = 'White'
    )
    $prev = $Host.UI.RawUI.ForegroundColor
    $Host.UI.RawUI.ForegroundColor = $Color
    Write-Host $Text
    $Host.UI.RawUI.ForegroundColor = $prev
}

function Get-MainBranch {
    param([string]$RepoPath)

    Push-Location $RepoPath
    try {
        $locals = git branch --list 2>$null | ForEach-Object { $_.Trim().TrimStart('* ') }
        if ($locals -contains 'main') { return 'main' }
        if ($locals -contains 'master') { return 'master' }

        # Fallback: check origin/HEAD
        $originHead = git symbolic-ref refs/remotes/origin/HEAD 2>$null
        if ($originHead -match 'origin/(.+)$') { return $Matches[1] }

        # Last resort: check remote branches
        $remotes = git branch -r --list 2>$null | ForEach-Object { $_.Trim() }
        if ($remotes -contains 'origin/main') { return 'main' }
        if ($remotes -contains 'origin/master') { return 'master' }

        return 'main'
    }
    finally {
        Pop-Location
    }
}

function Get-Repos {
    $excludedRepos = @('daisi-dotnet-console-chat')

    $allRepoDirs = Get-ChildItem -Path $RootDir -Directory | Where-Object {
        (Test-Path (Join-Path $_.FullName '.git')) -and ($excludedRepos -notcontains $_.Name)
    }

    if ($Repos -and $Repos.Count -gt 0) {
        $allRepoDirs = $allRepoDirs | Where-Object { $Repos -contains $_.Name }
    }

    return $allRepoDirs | Sort-Object Name
}

function Get-RepoStatus {
    param([string]$RepoPath)

    $repoName = Split-Path -Leaf $RepoPath

    Push-Location $RepoPath
    try {
        $currentBranch = git branch --show-current 2>$null
        if (-not $currentBranch) { $currentBranch = '(detached)' }

        $statusOutput = git status --porcelain 2>$null
        $isDirty = [bool]$statusOutput

        $mainBranch = Get-MainBranch $RepoPath

        $hasDev = $false
        $locals = git branch --list 2>$null | ForEach-Object { $_.Trim().TrimStart('* ') }
        if ($locals -contains 'dev') { $hasDev = $true }

        $ahead = 0
        $behind = 0
        $upstream = git rev-parse --abbrev-ref '@{upstream}' 2>$null
        if ($upstream) {
            $counts = git rev-list --left-right --count "HEAD...$upstream" 2>$null
            if ($counts -match '(\d+)\s+(\d+)') {
                $ahead = [int]$Matches[1]
                $behind = [int]$Matches[2]
            }
        }

        return [PSCustomObject]@{
            Name          = $repoName
            Path          = $RepoPath
            CurrentBranch = $currentBranch
            IsDirty       = $isDirty
            MainBranch    = $mainBranch
            HasDev        = $hasDev
            Ahead         = $ahead
            Behind        = $behind
        }
    }
    catch {
        return [PSCustomObject]@{
            Name          = $repoName
            Path          = $RepoPath
            CurrentBranch = '(error)'
            IsDirty       = $false
            MainBranch    = 'unknown'
            HasDev        = $false
            Ahead         = 0
            Behind        = 0
        }
    }
    finally {
        Pop-Location
    }
}

function Show-Summary {
    param([PSCustomObject[]]$Results)

    Write-Host ''
    Write-Host '=== Summary ===' -ForegroundColor Cyan
    Write-Host ('-' * 90)

    $header = '{0,-30} {1,-8} {2}' -f 'Repo', 'Status', 'Details'
    Write-Host $header -ForegroundColor Cyan

    foreach ($r in $Results) {
        $color = 'White'
        if ($r.Status -eq 'OK') { $color = 'Green' }
        elseif ($r.Status -eq 'SKIP') { $color = 'Yellow' }
        elseif ($r.Status -eq 'FAIL') { $color = 'Red' }
        elseif ($r.Status -eq 'DRYRUN') { $color = 'DarkYellow' }

        $line = '{0,-30} {1,-8} {2}' -f $r.Repo, $r.Status, $r.Details
        Write-Host $line -ForegroundColor $color
    }

    Write-Host ('-' * 90)

    $okCount = @($Results | Where-Object { $_.Status -eq 'OK' }).Count
    $skipCount = @($Results | Where-Object { $_.Status -eq 'SKIP' }).Count
    $failCount = @($Results | Where-Object { $_.Status -eq 'FAIL' }).Count
    $dryCount = @($Results | Where-Object { $_.Status -eq 'DRYRUN' }).Count

    $parts = @()
    if ($okCount -gt 0) { $parts += "$okCount OK" }
    if ($skipCount -gt 0) { $parts += "$skipCount skipped" }
    if ($failCount -gt 0) { $parts += "$failCount failed" }
    if ($dryCount -gt 0) { $parts += "$dryCount dry-run" }

    Write-Host ($parts -join ', ')
    Write-Host ''
}

# ---------------------------------------------------------------------------
# Command Functions
# ---------------------------------------------------------------------------

function Invoke-Status {
    $repos = Get-Repos
    if (-not $repos) {
        Write-ColorLine 'No repos found.' Red
        return
    }

    Write-Host ''
    $header = '{0,-30} {1,-20} {2,-7} {3,-8} {4,-8} {5}' -f 'Repo', 'Branch', 'Dirty', 'Ahead', 'Behind', 'Default'
    Write-Host $header -ForegroundColor Cyan
    Write-Host ('-' * 90)

    foreach ($repo in $repos) {
        $s = Get-RepoStatus $repo.FullName

        $dirtyStr = if ($s.IsDirty) { 'Yes' } else { '-' }
        $aheadStr = if ($s.Ahead -gt 0) { "+$($s.Ahead)" } else { '-' }
        $behindStr = if ($s.Behind -gt 0) { "-$($s.Behind)" } else { '-' }

        $color = 'White'
        if ($s.MainBranch -eq 'master') { $color = 'Yellow' }
        if ($s.IsDirty) { $color = 'Red' }

        $line = '{0,-30} {1,-20} {2,-7} {3,-8} {4,-8} {5}' -f $s.Name, $s.CurrentBranch, $dirtyStr, $aheadStr, $behindStr, $s.MainBranch
        Write-Host $line -ForegroundColor $color
    }

    Write-Host ('-' * 90)
    Write-Host ''
}

function Invoke-Branch {
    if (-not $Name) {
        Write-ColorLine 'ERROR: -Name is required for branch command.' Red
        return
    }

    $repos = Get-Repos
    $results = @()

    foreach ($repo in $repos) {
        $repoName = $repo.Name
        $repoPath = $repo.FullName

        Push-Location $repoPath
        try {
            # Check if dev exists
            $branches = git branch --list 2>$null | ForEach-Object { $_.Trim().TrimStart('* ') }
            if ($branches -notcontains 'dev') {
                $results += [PSCustomObject]@{ Repo = $repoName; Status = 'SKIP'; Details = 'No dev branch' }
                continue
            }

            # Check if branch already exists
            if ($branches -contains $Name) {
                $results += [PSCustomObject]@{ Repo = $repoName; Status = 'SKIP'; Details = "Branch '$Name' already exists" }
                continue
            }

            if ($DryRun) {
                $results += [PSCustomObject]@{ Repo = $repoName; Status = 'DRYRUN'; Details = "Would create '$Name' from dev" }
                continue
            }

            Write-Host "[$repoName] Checking out dev and pulling..." -ForegroundColor Gray
            git checkout dev 2>$null | Out-Null
            git pull origin dev 2>$null | Out-Null

            $output = git checkout -b $Name 2>&1
            if ($LASTEXITCODE -eq 0) {
                $results += [PSCustomObject]@{ Repo = $repoName; Status = 'OK'; Details = "Created '$Name' from dev" }
            }
            else {
                $results += [PSCustomObject]@{ Repo = $repoName; Status = 'FAIL'; Details = "$output" }
            }
        }
        catch {
            $results += [PSCustomObject]@{ Repo = $repoName; Status = 'FAIL'; Details = $_.Exception.Message }
        }
        finally {
            Pop-Location
        }
    }

    Show-Summary $results
}

function Invoke-Checkout {
    if (-not $Name) {
        Write-ColorLine 'ERROR: -Name is required for checkout command.' Red
        return
    }

    $repos = Get-Repos
    $results = @()

    foreach ($repo in $repos) {
        $repoName = $repo.Name
        $repoPath = $repo.FullName

        Push-Location $repoPath
        try {
            # Check dirty
            $statusOutput = git status --porcelain 2>$null
            if ($statusOutput) {
                $results += [PSCustomObject]@{ Repo = $repoName; Status = 'SKIP'; Details = 'Working tree is dirty' }
                continue
            }

            # Check branch exists (local or remote)
            $localBranches = git branch --list 2>$null | ForEach-Object { $_.Trim().TrimStart('* ') }
            $remoteBranches = git branch -r --list 2>$null | ForEach-Object { $_.Trim() }

            $hasLocal = $localBranches -contains $Name
            $hasRemote = $remoteBranches -contains "origin/$Name"

            if (-not $hasLocal -and -not $hasRemote) {
                $results += [PSCustomObject]@{ Repo = $repoName; Status = 'SKIP'; Details = "Branch '$Name' not found" }
                continue
            }

            if ($DryRun) {
                $results += [PSCustomObject]@{ Repo = $repoName; Status = 'DRYRUN'; Details = "Would checkout '$Name'" }
                continue
            }

            $output = git checkout $Name 2>&1
            if ($LASTEXITCODE -eq 0) {
                $results += [PSCustomObject]@{ Repo = $repoName; Status = 'OK'; Details = "Checked out '$Name'" }
            }
            else {
                $results += [PSCustomObject]@{ Repo = $repoName; Status = 'FAIL'; Details = "$output" }
            }
        }
        catch {
            $results += [PSCustomObject]@{ Repo = $repoName; Status = 'FAIL'; Details = $_.Exception.Message }
        }
        finally {
            Pop-Location
        }
    }

    Show-Summary $results
}

function Invoke-Pull {
    $repos = Get-Repos
    $results = @()

    foreach ($repo in $repos) {
        $repoName = $repo.Name
        $repoPath = $repo.FullName

        Push-Location $repoPath
        try {
            $currentBranch = git branch --show-current 2>$null
            if (-not $currentBranch) {
                $results += [PSCustomObject]@{ Repo = $repoName; Status = 'SKIP'; Details = 'Detached HEAD' }
                continue
            }

            if ($DryRun) {
                $results += [PSCustomObject]@{ Repo = $repoName; Status = 'DRYRUN'; Details = "Would pull origin/$currentBranch" }
                continue
            }

            Write-Host "[$repoName] Pulling $currentBranch..." -ForegroundColor Gray
            $output = git pull origin $currentBranch 2>&1
            if ($LASTEXITCODE -eq 0) {
                $detail = 'Up to date'
                if ($output -match 'files? changed') { $detail = 'Updated' }
                $results += [PSCustomObject]@{ Repo = $repoName; Status = 'OK'; Details = "$detail ($currentBranch)" }
            }
            else {
                $results += [PSCustomObject]@{ Repo = $repoName; Status = 'FAIL'; Details = "$output" }
            }
        }
        catch {
            $results += [PSCustomObject]@{ Repo = $repoName; Status = 'FAIL'; Details = $_.Exception.Message }
        }
        finally {
            Pop-Location
        }
    }

    Show-Summary $results
}

function Invoke-Push {
    $repos = Get-Repos
    $results = @()

    foreach ($repo in $repos) {
        $repoName = $repo.Name
        $repoPath = $repo.FullName

        Push-Location $repoPath
        try {
            $currentBranch = git branch --show-current 2>$null
            if (-not $currentBranch) {
                $results += [PSCustomObject]@{ Repo = $repoName; Status = 'SKIP'; Details = 'Detached HEAD' }
                continue
            }

            # Check if upstream exists
            $upstream = git rev-parse --abbrev-ref '@{upstream}' 2>$null
            $needsSetUpstream = -not $upstream

            # Check ahead count
            if (-not $needsSetUpstream) {
                $counts = git rev-list --left-right --count "HEAD...$upstream" 2>$null
                $ahead = 0
                if ($counts -match '(\d+)\s+(\d+)') {
                    $ahead = [int]$Matches[1]
                }
                if ($ahead -eq 0) {
                    $results += [PSCustomObject]@{ Repo = $repoName; Status = 'SKIP'; Details = "Nothing to push ($currentBranch)" }
                    continue
                }
            }

            if ($DryRun) {
                $flag = ''
                if ($needsSetUpstream) { $flag = ' (with -u)' }
                $results += [PSCustomObject]@{ Repo = $repoName; Status = 'DRYRUN'; Details = "Would push $currentBranch$flag" }
                continue
            }

            Write-Host "[$repoName] Pushing $currentBranch..." -ForegroundColor Gray
            if ($needsSetUpstream) {
                $output = git push -u origin $currentBranch 2>&1
            }
            else {
                $output = git push origin $currentBranch 2>&1
            }

            if ($LASTEXITCODE -eq 0) {
                $results += [PSCustomObject]@{ Repo = $repoName; Status = 'OK'; Details = "Pushed $currentBranch" }
            }
            else {
                $results += [PSCustomObject]@{ Repo = $repoName; Status = 'FAIL'; Details = "$output" }
            }
        }
        catch {
            $results += [PSCustomObject]@{ Repo = $repoName; Status = 'FAIL'; Details = $_.Exception.Message }
        }
        finally {
            Pop-Location
        }
    }

    Show-Summary $results
}

function Invoke-PrCreate {
    $repos = Get-Repos
    $results = @()

    foreach ($repo in $repos) {
        $repoName = $repo.Name
        $repoPath = $repo.FullName

        Push-Location $repoPath
        try {
            $currentBranch = git branch --show-current 2>$null
            if (-not $currentBranch) {
                $results += [PSCustomObject]@{ Repo = $repoName; Status = 'SKIP'; Details = 'Detached HEAD' }
                continue
            }

            if ($currentBranch -eq $Base) {
                $results += [PSCustomObject]@{ Repo = $repoName; Status = 'SKIP'; Details = "Already on $Base" }
                continue
            }

            # Check for commits between base and head
            git fetch origin 2>$null | Out-Null
            $commits = git log "origin/$Base..$currentBranch" --oneline 2>$null
            if (-not $commits) {
                $results += [PSCustomObject]@{ Repo = $repoName; Status = 'SKIP'; Details = "No changes vs $Base" }
                continue
            }

            # Generate title from branch name
            $titleBase = $currentBranch -replace '[/_]', ' '
            $prTitle = "$titleBase"

            # Generate body from commits
            $commitList = git log "origin/$Base..$currentBranch" --format='- %s' 2>$null
            $prBody = "## Changes`n`n$($commitList -join "`n")"

            if ($DryRun) {
                Write-Host "[$repoName] PR Preview:" -ForegroundColor DarkYellow
                Write-Host "  Title: $prTitle" -ForegroundColor DarkYellow
                Write-Host "  Base:  $Base <- $currentBranch" -ForegroundColor DarkYellow
                Write-Host "  Commits:" -ForegroundColor DarkYellow
                foreach ($c in $commitList) {
                    Write-Host "    $c" -ForegroundColor DarkYellow
                }
                $results += [PSCustomObject]@{ Repo = $repoName; Status = 'DRYRUN'; Details = "Would create PR: $prTitle" }
                continue
            }

            Write-Host "[$repoName] Creating PR..." -ForegroundColor Gray
            $output = gh pr create --base $Base --head $currentBranch --title $prTitle --body $prBody 2>&1
            if ($LASTEXITCODE -eq 0) {
                # Enable auto-merge so the PR completes automatically
                $prUrl = "$output".Trim()
                $mergeFlag = "--$MergeStrategy"
                $autoOutput = gh pr merge $prUrl --auto $mergeFlag --delete-branch 2>&1
                if ($LASTEXITCODE -eq 0) {
                    $results += [PSCustomObject]@{ Repo = $repoName; Status = 'OK'; Details = "PR created with auto-merge: $prUrl" }
                }
                else {
                    $results += [PSCustomObject]@{ Repo = $repoName; Status = 'OK'; Details = "PR created (auto-merge failed: $autoOutput): $prUrl" }
                }
            }
            else {
                $outputStr = "$output"
                if ($outputStr -match 'already exists') {
                    $results += [PSCustomObject]@{ Repo = $repoName; Status = 'SKIP'; Details = 'PR already exists' }
                }
                else {
                    $results += [PSCustomObject]@{ Repo = $repoName; Status = 'FAIL'; Details = $outputStr }
                }
            }
        }
        catch {
            $results += [PSCustomObject]@{ Repo = $repoName; Status = 'FAIL'; Details = $_.Exception.Message }
        }
        finally {
            Pop-Location
        }
    }

    Show-Summary $results
}

function Invoke-PrMerge {
    $repos = Get-Repos
    $results = @()

    foreach ($repo in $repos) {
        $repoName = $repo.Name
        $repoPath = $repo.FullName

        Push-Location $repoPath
        try {
            $currentBranch = git branch --show-current 2>$null
            if (-not $currentBranch) {
                $results += [PSCustomObject]@{ Repo = $repoName; Status = 'SKIP'; Details = 'Detached HEAD' }
                continue
            }

            # Find open PR for this branch
            $prJson = gh pr list --head $currentBranch --state open --json number --limit 1 2>$null
            $prData = $prJson | ConvertFrom-Json
            if (-not $prData -or $prData.Count -eq 0) {
                $results += [PSCustomObject]@{ Repo = $repoName; Status = 'SKIP'; Details = "No open PR for $currentBranch" }
                continue
            }

            $prNumber = $prData[0].number

            if ($DryRun) {
                $results += [PSCustomObject]@{ Repo = $repoName; Status = 'DRYRUN'; Details = "Would merge PR #$prNumber ($MergeStrategy, delete branch)" }
                continue
            }

            Write-Host "[$repoName] Merging PR #$prNumber..." -ForegroundColor Gray
            $mergeFlag = "--$MergeStrategy"
            $output = gh pr merge $prNumber $mergeFlag --delete-branch 2>&1
            if ($LASTEXITCODE -eq 0) {
                $results += [PSCustomObject]@{ Repo = $repoName; Status = 'OK'; Details = "Merged PR #$prNumber ($MergeStrategy)" }
            }
            else {
                $results += [PSCustomObject]@{ Repo = $repoName; Status = 'FAIL'; Details = "$output" }
            }
        }
        catch {
            $results += [PSCustomObject]@{ Repo = $repoName; Status = 'FAIL'; Details = $_.Exception.Message }
        }
        finally {
            Pop-Location
        }
    }

    Show-Summary $results
}

function Invoke-PrDevToMain {
    $repos = Get-Repos
    $results = @()

    foreach ($repo in $repos) {
        $repoName = $repo.Name
        $repoPath = $repo.FullName

        Push-Location $repoPath
        try {
            Write-Host "[$repoName] Fetching..." -ForegroundColor Gray
            git fetch origin 2>$null | Out-Null

            $mainBranch = Get-MainBranch $repoPath

            # Check dev exists on remote
            $remoteBranches = git branch -r --list 2>$null | ForEach-Object { $_.Trim() }
            if ($remoteBranches -notcontains "origin/dev") {
                $results += [PSCustomObject]@{ Repo = $repoName; Status = 'SKIP'; Details = 'No remote dev branch' }
                continue
            }

            if ($remoteBranches -notcontains "origin/$mainBranch") {
                $results += [PSCustomObject]@{ Repo = $repoName; Status = 'SKIP'; Details = "No remote $mainBranch branch" }
                continue
            }

            # Check divergence
            $commits = git log "origin/$mainBranch..origin/dev" --oneline 2>$null
            if (-not $commits) {
                $results += [PSCustomObject]@{ Repo = $repoName; Status = 'SKIP'; Details = "dev is not ahead of $mainBranch" }
                continue
            }

            $commitCount = @($commits).Count
            $commitList = git log "origin/$mainBranch..origin/dev" --format='- %s' 2>$null
            $prBody = "## Merge dev to $mainBranch`n`n$($commitList -join "`n")"
            $prTitle = "Merge dev to $mainBranch"

            if ($DryRun) {
                Write-Host "[$repoName] PR Preview:" -ForegroundColor DarkYellow
                Write-Host "  $commitCount commit(s) dev -> $mainBranch" -ForegroundColor DarkYellow
                foreach ($c in $commitList) {
                    Write-Host "    $c" -ForegroundColor DarkYellow
                }
                $results += [PSCustomObject]@{ Repo = $repoName; Status = 'DRYRUN'; Details = "$commitCount commit(s) to merge dev -> $mainBranch" }
                continue
            }

            Write-Host "[$repoName] Creating PR dev -> $mainBranch..." -ForegroundColor Gray
            $output = gh pr create --base $mainBranch --head dev --title $prTitle --body $prBody 2>&1
            if ($LASTEXITCODE -eq 0) {
                $prUrl = "$output".Trim()
                $mergeFlag = "--$MergeStrategy"
                $autoOutput = gh pr merge $prUrl --auto $mergeFlag 2>&1
                if ($LASTEXITCODE -eq 0) {
                    $results += [PSCustomObject]@{ Repo = $repoName; Status = 'OK'; Details = "PR created with auto-merge: $prUrl" }
                }
                else {
                    $results += [PSCustomObject]@{ Repo = $repoName; Status = 'OK'; Details = "PR created (auto-merge failed: $autoOutput): $prUrl" }
                }
            }
            else {
                $outputStr = "$output"
                if ($outputStr -match 'already exists') {
                    $results += [PSCustomObject]@{ Repo = $repoName; Status = 'SKIP'; Details = 'PR already exists' }
                }
                else {
                    $results += [PSCustomObject]@{ Repo = $repoName; Status = 'FAIL'; Details = $outputStr }
                }
            }
        }
        catch {
            $results += [PSCustomObject]@{ Repo = $repoName; Status = 'FAIL'; Details = $_.Exception.Message }
        }
        finally {
            Pop-Location
        }
    }

    Show-Summary $results
}

function Invoke-WorktreeAdd {
    if (-not $Name) {
        Write-ColorLine 'ERROR: -Name is required for worktree-add command.' Red
        return
    }

    # Sanitize branch name into folder suffix: feature/xyz -> feature-xyz
    $folderSuffix = $Name -replace '[/\\]', '-'
    $worktreeRoot = Join-Path (Split-Path $RootDir) "daisinet-$folderSuffix"

    if (Test-Path $worktreeRoot) {
        Write-ColorLine "ERROR: Worktree directory already exists: $worktreeRoot" Red
        return
    }

    $repos = Get-Repos
    $results = @()

    if ($DryRun) {
        Write-Host "Worktree root: $worktreeRoot" -ForegroundColor DarkYellow
        Write-Host ''
    }

    foreach ($repo in $repos) {
        $repoName = $repo.Name
        $repoPath = $repo.FullName
        $wtPath = Join-Path $worktreeRoot $repoName

        Push-Location $repoPath
        try {
            # Check if dev exists for branching
            $branches = git branch --list 2>$null | ForEach-Object { $_.Trim().TrimStart('* ') }
            $remoteBranches = git branch -r --list 2>$null | ForEach-Object { $_.Trim() }
            $branchExists = ($branches -contains $Name) -or ($remoteBranches -contains "origin/$Name")

            if ($DryRun) {
                if ($branchExists) {
                    $results += [PSCustomObject]@{ Repo = $repoName; Status = 'DRYRUN'; Details = "Would create worktree on existing branch '$Name' at $wtPath" }
                }
                else {
                    $results += [PSCustomObject]@{ Repo = $repoName; Status = 'DRYRUN'; Details = "Would create worktree with new branch '$Name' from dev at $wtPath" }
                }
                continue
            }

            if ($branchExists) {
                # Branch exists — create worktree for it
                $output = git worktree add $wtPath $Name 2>&1
            }
            else {
                # Create new branch from dev
                if ($branches -notcontains 'dev') {
                    $results += [PSCustomObject]@{ Repo = $repoName; Status = 'SKIP'; Details = 'No dev branch to create from' }
                    continue
                }
                git fetch origin dev 2>$null | Out-Null
                $output = git worktree add -b $Name $wtPath dev 2>&1
            }

            if ($LASTEXITCODE -eq 0) {
                $results += [PSCustomObject]@{ Repo = $repoName; Status = 'OK'; Details = "Worktree at $wtPath ($Name)" }
            }
            else {
                $results += [PSCustomObject]@{ Repo = $repoName; Status = 'FAIL'; Details = "$output" }
            }
        }
        catch {
            $results += [PSCustomObject]@{ Repo = $repoName; Status = 'FAIL'; Details = $_.Exception.Message }
        }
        finally {
            Pop-Location
        }
    }

    # Copy the CLAUDE.md to the worktree root so Claude picks it up there too
    if (-not $DryRun) {
        $claudeMd = Join-Path $RootDir 'CLAUDE.md'
        if (Test-Path $claudeMd) {
            if (-not (Test-Path $worktreeRoot)) {
                New-Item -ItemType Directory -Path $worktreeRoot -Force | Out-Null
            }
            Copy-Item $claudeMd (Join-Path $worktreeRoot 'CLAUDE.md')
        }
        # Copy the daisi-multi.ps1 script directory structure
        $daisiFolderDst = Join-Path $worktreeRoot 'daisi'
        if (Test-Path (Join-Path $worktreeRoot 'daisi')) {
            # daisi repo was added as a worktree — script is already there
        }
        else {
            # daisi wasn't included — copy the script so it's available
            New-Item -ItemType Directory -Path $daisiFolderDst -Force | Out-Null
            Copy-Item $PSCommandPath (Join-Path $daisiFolderDst 'daisi-multi.ps1')
        }
    }

    Show-Summary $results

    if (-not $DryRun) {
        $failCount = @($results | Where-Object { $_.Status -eq 'FAIL' }).Count
        if ($failCount -gt 0) {
            Write-Host "Worktree creation had failures - skipping Claude launch." -ForegroundColor Yellow
            return
        }

        Write-Host "Worktree ready at: $worktreeRoot" -ForegroundColor Green

        # Launch Claude Code in a new Windows Terminal tab
        try {
            $quotedPath = '"' + $worktreeRoot + '"'
            Start-Process wt -ArgumentList "-d", $quotedPath, "claude" -ErrorAction Stop
            Write-Host "Launched Claude Code in new terminal at $worktreeRoot" -ForegroundColor Green
        }
        catch {
            # Fallback: open a new PowerShell window with claude
            try {
                Start-Process powershell -ArgumentList "-NoExit", "-Command", "Set-Location '$worktreeRoot'; claude"
                Write-Host "Launched Claude Code in new PowerShell window at $worktreeRoot" -ForegroundColor Green
            }
            catch {
                Write-Host "Could not auto-launch terminal. Open Claude manually in: $worktreeRoot" -ForegroundColor Yellow
            }
        }
        Write-Host ''
    }
}

function Invoke-WorktreeRemove {
    if (-not $Name) {
        Write-ColorLine 'ERROR: -Name is required for worktree-remove command.' Red
        return
    }

    $folderSuffix = $Name -replace '[/\\]', '-'
    $worktreeRoot = Join-Path (Split-Path $RootDir) "daisinet-$folderSuffix"

    if (-not (Test-Path $worktreeRoot)) {
        Write-ColorLine "ERROR: Worktree directory not found: $worktreeRoot" Red
        return
    }

    $repos = Get-Repos
    $results = @()

    foreach ($repo in $repos) {
        $repoName = $repo.Name
        $repoPath = $repo.FullName
        $wtPath = Join-Path $worktreeRoot $repoName

        Push-Location $repoPath
        try {
            # Check if this worktree exists for this repo
            $worktrees = git worktree list --porcelain 2>$null
            $hasWorktree = $false
            foreach ($line in $worktrees) {
                if ($line -match "^worktree\s+(.+)$") {
                    $wtCandidate = $Matches[1].TrimEnd()
                    # Normalize paths for comparison
                    $normalizedCandidate = $wtCandidate -replace '[\\/]', '/'
                    $normalizedTarget = $wtPath -replace '[\\/]', '/'
                    if ($normalizedCandidate -eq $normalizedTarget) {
                        $hasWorktree = $true
                        break
                    }
                }
            }

            if (-not $hasWorktree) {
                $results += [PSCustomObject]@{ Repo = $repoName; Status = 'SKIP'; Details = 'No worktree found' }
                continue
            }

            if ($DryRun) {
                $results += [PSCustomObject]@{ Repo = $repoName; Status = 'DRYRUN'; Details = "Would remove worktree at $wtPath" }
                continue
            }

            $output = git worktree remove $wtPath --force 2>&1
            if ($LASTEXITCODE -eq 0) {
                $results += [PSCustomObject]@{ Repo = $repoName; Status = 'OK'; Details = "Removed worktree ($Name)" }
            }
            else {
                $results += [PSCustomObject]@{ Repo = $repoName; Status = 'FAIL'; Details = "$output" }
            }
        }
        catch {
            $results += [PSCustomObject]@{ Repo = $repoName; Status = 'FAIL'; Details = $_.Exception.Message }
        }
        finally {
            Pop-Location
        }
    }

    # Clean up the worktree root directory if empty
    if (-not $DryRun -and (Test-Path $worktreeRoot)) {
        $remaining = Get-ChildItem -Path $worktreeRoot -Force
        # Only CLAUDE.md and daisi folder (script copy) might remain
        $nonCopied = $remaining | Where-Object { $_.Name -ne 'CLAUDE.md' -and $_.Name -ne 'daisi' }
        if (-not $nonCopied) {
            Remove-Item $worktreeRoot -Recurse -Force
            Write-Host "Cleaned up worktree root: $worktreeRoot" -ForegroundColor Green
        }
        else {
            Write-Host "Worktree root still has files, not removing: $worktreeRoot" -ForegroundColor Yellow
        }
    }

    Show-Summary $results
}

# ---------------------------------------------------------------------------
# Main Dispatch
# ---------------------------------------------------------------------------

if ($DryRun) {
    Write-ColorLine '*** DRY RUN MODE — no changes will be made ***' DarkYellow
    Write-Host ''
}

switch ($Command) {
    'status' {
        Invoke-Status
    }
    'branch' {
        if (-not $Name) {
            Write-ColorLine "ERROR: branch command requires a name. Usage: .\daisi-multi.ps1 branch [name]" Red
            exit 1
        }
        Invoke-Branch
    }
    'checkout' {
        if (-not $Name) {
            Write-ColorLine "ERROR: checkout command requires a name. Usage: .\daisi-multi.ps1 checkout [name]" Red
            exit 1
        }
        Invoke-Checkout
    }
    'pull' {
        Invoke-Pull
    }
    'push' {
        Invoke-Push
    }
    'pr-create' {
        Invoke-PrCreate
    }
    'pr-merge' {
        Invoke-PrMerge
    }
    'pr-dev-to-main' {
        Invoke-PrDevToMain
    }
    'worktree-add' {
        if (-not $Name) {
            Write-ColorLine "ERROR: worktree-add requires a branch name. Usage: .\daisi-multi.ps1 worktree-add [branch]" Red
            exit 1
        }
        Invoke-WorktreeAdd
    }
    'worktree-remove' {
        if (-not $Name) {
            Write-ColorLine "ERROR: worktree-remove requires a branch name. Usage: .\daisi-multi.ps1 worktree-remove [branch]" Red
            exit 1
        }
        Invoke-WorktreeRemove
    }
}
