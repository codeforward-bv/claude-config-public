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

    if [[ -f "$script_dir/CLAUDE.md" && -d "$script_dir/commands" && -d "$script_dir/guidelines" ]]; then
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
    mkdir -p "$CLAUDE_DIR" "$CLAUDE_DIR/commands" "$CLAUDE_DIR/guidelines"

    # CLAUDE.md
    if [[ -f "$source/CLAUDE.md" ]]; then
        cp "$source/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"
        ok "CLAUDE.md"
        ((synced++))
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

    # guidelines/*.md
    for file in "$source/guidelines"/*.md; do
        [[ -f "$file" ]] || continue
        cp "$file" "$CLAUDE_DIR/guidelines/"
        ok "guidelines/$(basename "$file")"
        ((synced++))
    done

    info "Synced $synced file(s)"
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

setup_odoo_mcp() {
    local MCP_DIR="$CLAUDE_DIR/servers/codeforward-odoo-mcp"
    local ODOO_REPO_SSH="git@github.com:codeforward-bv/codeforward-odoo-mcp.git"
    local ODOO_REPO_NAME="codeforward-bv/codeforward-odoo-mcp"

    if ! command -v claude &>/dev/null; then
        return
    fi

    echo ""
    info "Codeforward Odoo MCP server (task management)"

    # Check if already configured
    if [[ -f "$CLAUDE_DIR/settings.json" ]] && command -v jq &>/dev/null; then
        if jq -e '.mcpServers["codeforward-odoo"]' "$CLAUDE_DIR/settings.json" &>/dev/null; then
            ok "codeforward-odoo — already configured"
            printf "    Reconfigure? (y/N) "
            read -r reconfigure
            if [[ ! "$reconfigure" =~ ^[Yy]$ ]]; then
                return
            fi
        fi
    fi

    printf "    Set up Odoo integration? (y/N) "
    read -r answer
    if [[ ! "$answer" =~ ^[Yy]$ ]]; then
        info "Skipped Odoo MCP setup"
        return
    fi

    # Ensure uv is installed
    if ! command -v uv &>/dev/null; then
        if [[ "$(uname -s)" == "Darwin" ]] && command -v brew &>/dev/null; then
            info "Installing uv via Homebrew..."
            brew install uv
        else
            info "Installing uv..."
            curl -LsSf https://astral.sh/uv/install.sh | sh
        fi
        command -v uv &>/dev/null || fail "Failed to install uv"
        ok "uv installed"
    else
        ok "uv"
    fi

    # Clone or update the server repo
    mkdir -p "$CLAUDE_DIR/servers"
    if [[ -d "$MCP_DIR/.git" ]]; then
        info "Updating codeforward-odoo-mcp..."
        git -C "$MCP_DIR" pull --quiet
        ok "Repository updated"
    else
        info "Cloning codeforward-odoo-mcp..."
        rm -rf "$MCP_DIR"
        if git clone --quiet "$ODOO_REPO_SSH" "$MCP_DIR" 2>/dev/null; then
            ok "Cloned via SSH"
        elif command -v gh &>/dev/null && gh repo clone "$ODOO_REPO_NAME" "$MCP_DIR" -- --quiet 2>/dev/null; then
            ok "Cloned via gh CLI"
        else
            warn "Failed to clone codeforward-odoo-mcp — skipping"
            return
        fi
    fi

    # Install dependencies
    info "Installing server dependencies..."
    uv sync --quiet --directory "$MCP_DIR"
    ok "Dependencies installed"

    # Prompt for Odoo credentials
    echo ""
    info "Enter your Odoo credentials"
    info "(API key: Odoo > Settings > Users > Preferences > API Keys)"
    echo ""

    printf "    ODOO_URL [https://codeforward.nl]: "
    read -r odoo_url
    odoo_url="${odoo_url:-https://codeforward.nl}"

    printf "    ODOO_DB: "
    read -r odoo_db
    [[ -n "$odoo_db" ]] || fail "ODOO_DB is required"

    printf "    ODOO_USER (email): "
    read -r odoo_user
    [[ -n "$odoo_user" ]] || fail "ODOO_USER is required"

    printf "    ODOO_API_KEY: "
    read -rs odoo_api_key
    echo ""
    [[ -n "$odoo_api_key" ]] || fail "ODOO_API_KEY is required"

    # Register MCP server
    if claude mcp add codeforward-odoo --scope user \
        -e "ODOO_URL=$odoo_url" \
        -e "ODOO_DB=$odoo_db" \
        -e "ODOO_USER=$odoo_user" \
        -e "ODOO_API_KEY=$odoo_api_key" \
        -- uv run --directory "$MCP_DIR" python -m codeforward_odoo_mcp 2>/dev/null; then
        ok "codeforward-odoo (Odoo task management)"
    else
        warn "codeforward-odoo — registration failed"
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
    setup_mcp_servers
    setup_odoo_mcp

    echo ""
    ok "Sync complete!"
    echo ""
    info "Personal customizations belong in:"
    echo "    ~/.claude/CLAUDE.local.md       (user instructions)"
    echo "    ~/.claude/settings.local.json   (user settings)"
    echo ""
    info "Re-run this script anytime to pull the latest team config."
    echo ""
}

main "$@"
