# Daisinet Project

## Multi-Repo Structure

This project spans 11 git repos, all under `C:\repos\daisinet`:

- `daisi` — solution root, shared config
- `daisi-bot-dotnet` — bot engine and TUI
- `daisi-dotnet-console-chat` — console chat client
- `daisi-drive-dotnet` — Drive storage
- `daisi-hosts-dotnet` — host runtime
- `daisi-manager-dotnet` — admin/manager web UI
- `daisi-openai-dotnet` — OpenAI-compatible inference
- `daisi-orc-dotnet` — orchestrator
- `daisi-sdk-dotnet` — SDK and proto definitions
- `daisi-tools-dotnet` — tools and skills
- `daisi-web-public` — public website

All repos use `main` as the default branch and `dev` as the integration branch.

## Multi-Repo Management Script

Use `daisi\daisi-multi.ps1` for any operation that should apply across multiple repos:

```
.\daisi\daisi-multi.ps1 status              # Check branch, dirty, ahead/behind for all repos
.\daisi\daisi-multi.ps1 branch <name>       # Create feature branch from dev in all repos
.\daisi\daisi-multi.ps1 checkout <name>     # Switch all repos to a branch
.\daisi\daisi-multi.ps1 pull                # Pull current branch in all repos
.\daisi\daisi-multi.ps1 push                # Push unpushed commits in all repos
.\daisi\daisi-multi.ps1 pr-create           # Create PRs for all repos with changes vs base
.\daisi\daisi-multi.ps1 pr-merge            # Merge open PRs for current branch in all repos
.\daisi\daisi-multi.ps1 pr-dev-to-main      # Create PRs from dev to main where diverged
.\daisi\daisi-multi.ps1 worktree-add <name>  # Create worktree for parallel branch work
.\daisi\daisi-multi.ps1 worktree-remove <name> # Remove a worktree and clean up
```

### When to use this script

- **Starting a new feature**: when the user asks to work on a new feature or create a new branch, always use `worktree-add <branch>` to create a parallel working copy at `C:\repos\daisinet-<branch>`. This keeps the main directory on `dev` and opens a new Claude console for the feature work automatically. Never switch the main directory off `dev`.
- **Before starting work**: run `status` to see the state of all repos.
- **Pushing and PRs**: use `push`, `pr-create`, and `pr-merge` to batch operations instead of doing them one repo at a time.
- **Releasing**: use `pr-dev-to-main` to promote dev to main across all repos.
- **Cleaning up**: use `worktree-remove <branch>` after a feature is merged to clean up the worktree directory.

### User Shortcuts

- **"ship to dev"** — For each repo that has uncommitted changes: stage and commit with a descriptive message, then run `push` across all repos, then run `pr-create` (which auto-merges). This ships the current feature branch back to dev.
- **"closeout this feature"** — Do everything in "ship to dev", then determine the current branch name, run `worktree-remove <branch>` from the main `C:\repos\daisinet` directory to clean up, and close the console window. Since the worktree-remove must run from the main directory (not the worktree itself), use: `powershell.exe -Command "Start-Process powershell -ArgumentList '-Command', 'Set-Location C:\repos\daisinet; powershell -ExecutionPolicy Bypass -File C:\repos\daisinet\daisi\daisi-multi.ps1 worktree-remove <branch>'"` then exit the current session.

### Important flags

- **`-DryRun`**: Always use this first for mutating commands (`branch`, `push`, `pr-create`, `pr-merge`, `pr-dev-to-main`) to preview what will happen before executing.
- **`-Repos`**: Filter to specific repos, e.g. `-Repos daisi-sdk-dotnet,daisi-orc-dotnet`.
- **`-Base`**: Override the base branch for PR operations (default: `dev`).
- **`-MergeStrategy`**: Choose `merge`, `squash`, or `rebase` for `pr-merge` (default: `merge`).
