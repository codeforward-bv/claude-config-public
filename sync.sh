#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# Codeforward · Claude Config Sync
# Syncs team Claude configuration to ~/.claude/
#
# Usage:
#   curl:       /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/codeforward-bv/claude-config-public/main/sync.sh)"
#   from clone: ./sync.sh
#
# The script installs all dependencies (brew, gh, jq, claude)
# before cloning the private config repo.
# ─────────────────────────────────────────────────────────────

set -euo pipefail

# --- Configuration ---
REPO_OWNER="codeforward-bv"
REPO_NAME="claude-config"
REPO_SSH="git@github.com:$REPO_OWNER/$REPO_NAME.git"
REPO_HTTPS="https://github.com/$REPO_OWNER/$REPO_NAME.git"
BRANCH="${CLAUDE_CONFIG_BRANCH:-main}"
CLAUDE_DIR="$HOME/.claude"
TEMP_DIR=""

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# --- Helpers ---
info()  { printf "${BLUE}[info]${NC} %s\n" "$*"; }
ok()    { printf "${GREEN}  ✓${NC} %s\n" "$*"; }
warn()  { printf "${YELLOW}[warn]${NC} %s\n" "$*"; }
fail()  { printf "${RED}[error]${NC} %s\n" "$*" >&2; exit 1; }

cleanup() {
    if [[ -n "${TEMP_DIR:-}" && -d "${TEMP_DIR:-}" ]]; then
        rm -rf "$TEMP_DIR"
    fi
}
trap cleanup EXIT

# --- Dependency management ---

ensure_homebrew() {
    if command -v brew &>/dev/null; then
        ok "Homebrew"
        return
    fi

    info "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    # Add brew to PATH for current session (Apple Silicon vs Intel)
    if [[ -f /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -f /usr/local/bin/brew ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi

    command -v brew &>/dev/null || fail "Homebrew installation failed"
    ok "Homebrew installed"
}

ensure_brew_package() {
    local cmd="$1"
    local pkg="${2:-$1}"

    if command -v "$cmd" &>/dev/null; then
        ok "$cmd"
        return
    fi

    info "Installing $pkg via Homebrew..."
    brew install "$pkg"
    command -v "$cmd" &>/dev/null || fail "Failed to install $pkg"
    ok "$pkg installed"
}

ensure_claude() {
    if command -v claude &>/dev/null; then
        ok "Claude Code"
        return
    fi

    # Claude Code requires npm
    if ! command -v npm &>/dev/null; then
        info "Installing Node.js via Homebrew (required for Claude Code)..."
        brew install node
        command -v npm &>/dev/null || fail "Failed to install Node.js"
        ok "Node.js installed"
    fi

    info "Installing Claude Code..."
    npm install -g @anthropic-ai/claude-code
    command -v claude &>/dev/null || fail "Failed to install Claude Code"
    ok "Claude Code installed"
}

install_dependencies() {
    info "Checking dependencies..."

    # Platform check
    if [[ "$(uname -s)" != "Darwin" ]]; then
        warn "This script is designed for macOS. Skipping Homebrew-based installs."
        warn "Ensure git, gh, jq, and claude are installed manually."
        command -v git &>/dev/null || fail "git is required"
        return
    fi

    command -v git &>/dev/null || fail "git is required (install Xcode Command Line Tools: xcode-select --install)"
    ok "git"

    ensure_homebrew
    ensure_brew_package gh
    ensure_brew_package jq
    ensure_claude
}

# --- Steps ---

banner() {
    echo ""
    printf "${BOLD}Codeforward · Claude Config Sync${NC}\n"
    echo "────────────────────────────────"
    echo ""
}

resolve_source() {
    # Note: info/ok/warn output goes to stderr here so that
    # only the path is captured by command substitution.

    # If running from within the config repo, use it directly
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"

    if [[ -f "$script_dir/CLAUDE.md" && -d "$script_dir/commands" ]]; then
        info "Source: local repo ($script_dir)" >&2
        echo "$script_dir"
        return
    fi

    # Otherwise, clone to a temp directory
    TEMP_DIR="$(mktemp -d)"
    info "Cloning config repo..." >&2

    # Try SSH first, then gh CLI (handles private repo auth), then HTTPS
    if git clone --quiet --depth 1 --branch "$BRANCH" "$REPO_SSH" "$TEMP_DIR" 2>/dev/null; then
        ok "Cloned via SSH" >&2
    elif command -v gh &>/dev/null && gh repo clone "$REPO_OWNER/$REPO_NAME" "$TEMP_DIR" -- --quiet --depth 1 --branch "$BRANCH" 2>/dev/null; then
        ok "Cloned via gh CLI" >&2
    elif git clone --quiet --depth 1 --branch "$BRANCH" "$REPO_HTTPS" "$TEMP_DIR" 2>/dev/null; then
        ok "Cloned via HTTPS" >&2
    else
        echo "" >&2
        fail "Failed to clone repo. Run 'gh auth login' and try again."
    fi

    echo "$TEMP_DIR"
}

sync_files() {
    local source="$1"
    local synced=0

    info "Syncing files to $CLAUDE_DIR/"

    # Ensure target directories exist
    mkdir -p "$CLAUDE_DIR" "$CLAUDE_DIR/commands"

    # CLAUDE.md → global_context.md (team rules, overwrite)
    if [[ -f "$source/CLAUDE.md" ]]; then
        cp "$source/CLAUDE.md" "$CLAUDE_DIR/global_context.md"
        ok "global_context.md (from CLAUDE.md)"
        ((synced++))
    fi

    # global_candidates.md (create from template if missing, never overwrite)
    if [[ ! -f "$CLAUDE_DIR/global_candidates.md" ]]; then
        if [[ -f "$source/global_candidates.template.md" ]]; then
            cp "$source/global_candidates.template.md" "$CLAUDE_DIR/global_candidates.md"
            ok "global_candidates.md (created from template)"
            ((synced++))
        fi
    else
        ok "global_candidates.md (preserved)"
    fi

    # settings.json — deep merge (team settings win, local keys preserved)
    local team_settings="$source/.claude/settings.json"
    local target_settings="$CLAUDE_DIR/settings.json"

    if [[ -f "$team_settings" ]]; then
        if [[ -f "$target_settings" ]] && command -v jq &>/dev/null; then
            local merged
            merged="$(jq -s '.[0] * .[1]' "$target_settings" "$team_settings")"
            printf '%s\n' "$merged" > "$target_settings"
            ok "settings.json (merged)"
        else
            cp "$team_settings" "$target_settings"
            ok "settings.json (created)"
        fi
        ((synced++))
    fi

    # commands/*.md
    for file in "$source/commands"/*.md; do
        [[ -f "$file" ]] || continue
        cp "$file" "$CLAUDE_DIR/commands/"
        ok "commands/$(basename "$file")"
        ((synced++))
    done

    info "Synced $synced file(s)"
}

build_composite() {
    info "Building composite CLAUDE.md..."

    local composite="$CLAUDE_DIR/CLAUDE.md"
    local header="# CLAUDE.md (Generated)

> **WARNING:** This file is auto-generated. Do not edit directly.
>
> **Remember:** When corrected, log the learning IMMEDIATELY:
> - Project-specific → project's \`CLAUDE.md\`
> - Global → \`~/.claude/global_candidates.md\` (between the markers)

---

"

    # Start with header
    printf '%s' "$header" > "$composite"

    # Append global_context.md
    if [[ -f "$CLAUDE_DIR/global_context.md" ]]; then
        cat "$CLAUDE_DIR/global_context.md" >> "$composite"
        printf '\n\n' >> "$composite"
    fi

    # Append CLAUDE.local.md if it exists
    if [[ -f "$CLAUDE_DIR/CLAUDE.local.md" ]]; then
        printf '%s\n\n' "---" >> "$composite"
        printf '%s\n\n' "# Local Overrides" >> "$composite"
        cat "$CLAUDE_DIR/CLAUDE.local.md" >> "$composite"
        printf '\n\n' >> "$composite"
    fi

    # Append global_candidates.md if it has actual candidates between markers
    if [[ -f "$CLAUDE_DIR/global_candidates.md" ]]; then
        # Extract content between CANDIDATES markers and check if non-empty
        local candidates_content
        candidates_content=$(sed -n '/<!-- CANDIDATES:START -->/,/<!-- CANDIDATES:END -->/p' "$CLAUDE_DIR/global_candidates.md" | grep -v '^<!-- CANDIDATES' || true)
        local has_content
        has_content=$(echo "$candidates_content" | grep -v '^[[:space:]]*$' || true)
        if [[ -n "$has_content" ]]; then
            printf '%s\n\n' "---" >> "$composite"
            printf '%s\n\n' "# Candidate Rules (Pending Promotion)" >> "$composite"
            printf '%s\n\n' "$candidates_content" >> "$composite"
        fi
    fi

    ok "CLAUDE.md (composite built)"
}

setup_mcp_servers() {
    if ! command -v claude &>/dev/null; then
        warn "claude CLI not found — skipping MCP server setup"
        return
    fi

    info "Configuring MCP servers (user scope)..."

    # Context7 — live documentation (https://github.com/upstash/context7)
    if claude mcp add context7 --scope user -- npx -y @upstash/context7-mcp 2>/dev/null; then
        ok "context7 (documentation)"
    else
        warn "context7 — already configured or failed"
    fi

    # Playwright — browser testing (https://github.com/microsoft/playwright-mcp)
    if claude mcp add playwright --scope user -- npx -y @playwright/mcp 2>/dev/null; then
        ok "playwright (browser testing)"
    else
        warn "playwright — already configured or failed"
    fi

    # GitHub — uses Copilot auth (no PAT needed, requires Copilot license)
    if claude mcp add github --scope user --transport http https://api.githubcopilot.com/mcp 2>/dev/null; then
        ok "github (GitHub integration)"
    else
        warn "github — already configured or failed"
    fi
}

# --- Main ---

main() {
    banner
    install_dependencies

    echo ""
    local source
    source="$(resolve_source)"

    sync_files "$source"
    echo ""
    build_composite
    echo ""
    setup_mcp_servers

    echo ""
    ok "Sync complete!"
    echo ""
    info "Knowledge management files:"
    echo "    ~/.claude/global_context.md     (team rules - read only)"
    echo "    ~/.claude/global_candidates.md  (nominate new global rules here)"
    echo "    ~/.claude/CLAUDE.local.md       (personal overrides)"
    echo "    ~/.claude/CLAUDE.md             (composite - auto-generated)"
    echo ""
    info "Re-run this script anytime to pull the latest team config."
    echo ""
}

main "$@"
