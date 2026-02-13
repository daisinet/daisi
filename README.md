## Daisi Full Solution

This is one repo to rule them all. All daisinet repos live side-by-side under a single parent directory so the solution file can reference them together. The `daisi-multi.ps1` script manages branches, PRs, and merges across all repos from a single CLI.

### To Get Started

Clone all repos into the same parent folder:

```powershell
cd c:\repos\daisinet
git clone https://github.com/daisinet/daisi.git daisi
git clone https://github.com/daisinet/daisi-sdk-dotnet.git daisi-sdk-dotnet
git clone https://github.com/daisinet/daisi-tools-dotnet.git daisi-tools-dotnet
git clone https://github.com/daisinet/daisi-openai-dotnet.git daisi-openai-dotnet
git clone https://github.com/daisinet/daisi-hosts-dotnet.git daisi-hosts-dotnet
git clone https://github.com/daisinet/daisi-bot-dotnet.git daisi-bot-dotnet
git clone https://github.com/daisinet/daisi-drive-dotnet.git daisi-drive-dotnet
git clone https://github.com/daisinet/daisi-manager-dotnet.git daisi-manager-dotnet
git clone https://github.com/daisinet/daisi-orc-dotnet.git daisi-orc-dotnet
git clone https://github.com/daisinet/daisi-dotnet-console-chat.git daisi-dotnet-console-chat
git clone https://github.com/daisinet/daisi-web-public.git daisi-web-public
```

All repos use `main` as the default branch and `dev` as the integration branch.

### Multi-Repo Management Script

`daisi-multi.ps1` lets you run git and GitHub operations across all 11 repos at once. It auto-discovers repos by scanning for `.git` directories under the parent folder.

#### Prerequisites

- PowerShell 5.1+ (ships with Windows)
- [GitHub CLI (`gh`)](https://cli.github.com/) installed and authenticated (for PR commands)

#### Commands

```powershell
.\daisi\daisi-multi.ps1 status                  # Show branch, dirty, ahead/behind for all repos
.\daisi\daisi-multi.ps1 branch <name>            # Create a feature branch from dev in all repos
.\daisi\daisi-multi.ps1 checkout <name>          # Switch all repos to an existing branch
.\daisi\daisi-multi.ps1 pull                     # Pull current branch in all repos
.\daisi\daisi-multi.ps1 push                     # Push unpushed commits in all repos
.\daisi\daisi-multi.ps1 pr-create               # Create PRs for repos with changes vs base
.\daisi\daisi-multi.ps1 pr-merge                # Merge open PRs for current branch
.\daisi\daisi-multi.ps1 pr-dev-to-main          # Create PRs from dev to main where diverged
.\daisi\daisi-multi.ps1 worktree-add <name>      # Create a parallel worktree for another branch
.\daisi\daisi-multi.ps1 worktree-remove <name>   # Remove a worktree and clean up
```

#### Flags

| Flag | Description |
|---|---|
| `-DryRun` | Preview what would happen without making changes. Use this first. |
| `-Repos` | Filter to specific repos, e.g. `-Repos daisi-sdk-dotnet,daisi-orc-dotnet` |
| `-Base` | Base branch for PR operations (default: `dev`) |
| `-MergeStrategy` | `merge`, `squash`, or `rebase` for `pr-merge` (default: `merge`) |

#### Typical Workflow

```powershell
# Check the state of everything
.\daisi\daisi-multi.ps1 status

# Start a new feature
.\daisi\daisi-multi.ps1 branch feature/my-feature

# Do your work, commit in individual repos as needed, then push all
.\daisi\daisi-multi.ps1 push

# Create PRs across all repos that have changes
.\daisi\daisi-multi.ps1 pr-create

# After review, merge all PRs
.\daisi\daisi-multi.ps1 pr-merge

# Promote dev to main for a release
.\daisi\daisi-multi.ps1 pr-dev-to-main
```

#### Parallel Branches with Worktrees

To work on two branches at the same time (e.g. run two Claude Code sessions), use worktrees instead of copying the whole directory:

```powershell
# Creates C:\repos\daisinet-feature-my-feature\ with all repos on that branch
.\daisi\daisi-multi.ps1 worktree-add feature/my-feature

# Open a second terminal/Claude session in the new directory
# Both directories share git history — commits are visible from either side

# When done, clean up
.\daisi\daisi-multi.ps1 worktree-remove feature/my-feature
```

### Claude Code Setup

If you use [Claude Code](https://claude.com/claude-code), create a `CLAUDE.md` file in the parent directory (`c:\repos\daisinet\CLAUDE.md`) so Claude knows about the multi-repo structure and uses the script automatically. Here's a starter template:

```markdown
# Daisinet Project

## Multi-Repo Structure

This project spans 11 git repos, all under `C:\repos\daisinet`.
All repos use `main` as the default branch and `dev` as the integration branch.

## Multi-Repo Management Script

Use `daisi\daisi-multi.ps1` for any operation that should apply across multiple repos.
Always use `-DryRun` first for mutating commands.

See daisi\README.md for full command reference.
```

You can also add a status line to show the current branch in your Claude prompt. Add this to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "git -C C:/repos/daisinet/daisi branch --show-current"
  }
}
```

This shows the `daisi` repo's current branch, which should match all other repos when using the script.
