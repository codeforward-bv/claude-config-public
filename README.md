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
3. **Syncs team files** — `global_context.md`, `settings.json`, commands, guidelines → `~/.claude/`
4. **Builds composite CLAUDE.md** — combines global rules, local overrides, and candidates
5. **Configures MCP servers** — context7, playwright, github

> First run? You may be prompted to authenticate with `gh auth login` to access the private config repo.

## Re-sync

Run the same command again anytime to pull the latest team configuration.

## Knowledge Management

The sync uses a **Knowledge Promotion Pipeline**:

```
~/.claude/
├── global_context.md     ← Team rules (synced, read-only)
├── global_candidates.md  ← Your nominations (append-only, never overwritten)
├── CLAUDE.local.md       ← Personal overrides (never synced)
└── CLAUDE.md             ← Composite (auto-generated from above)
```

When Claude learns something new:
- **Project-specific** → update the project's `CLAUDE.md`
- **Global** → append to `~/.claude/global_candidates.md`

Candidates are reviewed periodically and promoted to the central repo via PR.

## What Gets Synced

| File | Destination | Strategy |
|------|-------------|----------|
| `global_context.md` | `~/.claude/global_context.md` | Overwrite |
| `global_candidates.template.md` | `~/.claude/global_candidates.md` | Create if missing |
| `.claude/settings.json` | `~/.claude/settings.json` | Deep merge |
| `commands/*.md` | `~/.claude/commands/` | Overwrite |
| `guidelines/*.md` | `~/.claude/guidelines/` | Overwrite |

Personal files (`CLAUDE.local.md`, `global_candidates.md`, `settings.local.json`) are never touched after initial creation.

## Config Repo

The actual configuration lives in the private [claude-config](https://github.com/codeforward-bv/claude-config) repo. Edit files there and team members re-run the sync to pick up changes.

## Override Branch

```bash
CLAUDE_CONFIG_BRANCH=staging /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/codeforward-bv/claude-config-public/main/sync.sh)"
```
