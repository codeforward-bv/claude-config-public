# Codeforward Claude Config Sync

Public sync script for the Codeforward team's [Claude Code](https://docs.anthropic.com/en/docs/claude-code) configuration. This script installs dependencies, pulls team config from a private repo, and sets up MCP servers.

## Install

Run this in your terminal:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/codeforward-bv/claude-config-public/main/sync.sh)"
```

That's it. The script handles everything:

1. **Installs missing tools** — Homebrew, `gh`, `jq`, Node.js, Claude Code
2. **Clones the private config repo** — via SSH or `gh` auth
3. **Syncs team files** — `CLAUDE.md`, `settings.json`, commands, guidelines → `~/.claude/`
4. **Configures MCP servers** — context7, playwright, github

> First run? You may be prompted to authenticate with `gh auth login` to access the private config repo.

## Re-sync

Run the same command again anytime to pull the latest team configuration.

## What Gets Synced

| File | Destination | Strategy |
|------|-------------|----------|
| `CLAUDE.md` | `~/.claude/CLAUDE.md` | Overwrite |
| `.claude/settings.json` | `~/.claude/settings.json` | Deep merge |
| `commands/*.md` | `~/.claude/commands/` | Overwrite |
| `guidelines/*.md` | `~/.claude/guidelines/` | Overwrite |

Personal customizations in `~/.claude/CLAUDE.local.md` and `~/.claude/settings.local.json` are never touched.

## Config Repo

The actual configuration lives in the private [claude-config](https://github.com/codeforward-bv/claude-config) repo. Edit files there and team members re-run the sync to pick up changes.

## Override Branch

```bash
CLAUDE_CONFIG_BRANCH=staging /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/codeforward-bv/claude-config-public/main/sync.sh)"
```
