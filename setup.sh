#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Claude Hub Setup Script
# Sets up ~/claude (skills repo) and ~/.claude (configuration)
# Run on a fresh device after installing Claude Code
# ============================================================

CLAUDE_DIR="$HOME/claude"
CLAUDE_CONFIG="$HOME/.claude"
REPO_URL="git@github.com-personal:laithalenooz/claude.git"
MARKETPLACE_NAME="claude-hub"
PLUGIN_NAME="awesome-skills"
PLUGIN_VERSION="1.0.0"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ============================================================
# Phase 1: Clone the repo to ~/claude
# ============================================================
phase1_clone_repo() {
    echo ""
    echo -e "${CYAN}=== Phase 1: Clone Skills Repository ===${NC}"

    if [ -d "$CLAUDE_DIR/.git" ]; then
        ok "Repo already exists at $CLAUDE_DIR — pulling latest"
        git -C "$CLAUDE_DIR" pull --ff-only 2>/dev/null || warn "Pull failed (may need manual merge)"
    elif [ -d "$CLAUDE_DIR" ] && [ "$(ls -A "$CLAUDE_DIR" 2>/dev/null)" ]; then
        error "$CLAUDE_DIR exists and is not empty. Back it up or remove it first."
        exit 1
    else
        info "Cloning repo to $CLAUDE_DIR..."
        git clone "$REPO_URL" "$CLAUDE_DIR"
        ok "Repo cloned"
    fi
}

# ============================================================
# Phase 2: Ensure ~/.claude directory structure
# ============================================================
phase2_ensure_claude_dirs() {
    echo ""
    echo -e "${CYAN}=== Phase 2: Ensure ~/.claude Directory Structure ===${NC}"

    local dirs=(
        "$CLAUDE_CONFIG"
        "$CLAUDE_CONFIG/plugins"
        "$CLAUDE_CONFIG/plugins/cache"
        "$CLAUDE_CONFIG/backups"
    )

    for dir in "${dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir"
            info "Created $dir"
        fi
    done
    ok "Directory structure ready"
}

# ============================================================
# Phase 3: Register marketplace in known_marketplaces.json
# ============================================================
phase3_register_marketplace() {
    echo ""
    echo -e "${CYAN}=== Phase 3: Register Marketplace ===${NC}"

    local file="$CLAUDE_CONFIG/plugins/known_marketplaces.json"

    # Create file if it doesn't exist
    if [ ! -f "$file" ]; then
        echo '{}' > "$file"
        info "Created $file"
    fi

    # Backup
    cp "$file" "$CLAUDE_CONFIG/backups/known_marketplaces.json.bak"

    # Check if already registered
    if python3 -c "
import json, sys
with open('$file') as f:
    data = json.load(f)
sys.exit(0 if '$MARKETPLACE_NAME' in data else 1)
" 2>/dev/null; then
        ok "Marketplace '$MARKETPLACE_NAME' already registered"
        return
    fi

    # Add marketplace entry
    python3 -c "
import json
with open('$file') as f:
    data = json.load(f)
data['$MARKETPLACE_NAME'] = {
    'source': {
        'source': 'github',
        'repo': 'laithalenooz/claude'
    },
    'installLocation': '$CLAUDE_DIR',
    'lastUpdated': '$TIMESTAMP'
}
with open('$file', 'w') as f:
    json.dump(data, f, indent=2)
"
    ok "Marketplace registered"
}

# ============================================================
# Phase 4: Install plugin to cache
# ============================================================
phase4_install_plugin() {
    echo ""
    echo -e "${CYAN}=== Phase 4: Install Plugin to Cache ===${NC}"

    local cache_dir="$CLAUDE_CONFIG/plugins/cache/$MARKETPLACE_NAME/$PLUGIN_NAME/$PLUGIN_VERSION"
    local source_dir="$CLAUDE_DIR/claude-plugins/$PLUGIN_NAME"

    if [ ! -d "$source_dir" ]; then
        error "Plugin source not found at $source_dir"
        exit 1
    fi

    # Copy plugin to cache
    mkdir -p "$cache_dir"
    cp -r "$source_dir"/* "$cache_dir/"

    local skill_count
    skill_count=$(ls -d "$cache_dir/skills"/*/ 2>/dev/null | wc -l)
    ok "Plugin cached with $skill_count skills"
}

# ============================================================
# Phase 5: Register plugin in installed_plugins.json
# ============================================================
phase5_register_plugin() {
    echo ""
    echo -e "${CYAN}=== Phase 5: Register Plugin ===${NC}"

    local file="$CLAUDE_CONFIG/plugins/installed_plugins.json"
    local plugin_key="${PLUGIN_NAME}@${MARKETPLACE_NAME}"
    local install_path="$CLAUDE_CONFIG/plugins/cache/$MARKETPLACE_NAME/$PLUGIN_NAME/$PLUGIN_VERSION"

    # Create file if it doesn't exist
    if [ ! -f "$file" ]; then
        echo '{"version": 2, "plugins": {}}' > "$file"
        info "Created $file"
    fi

    # Backup
    cp "$file" "$CLAUDE_CONFIG/backups/installed_plugins.json.bak"

    # Check if already registered
    if python3 -c "
import json, sys
with open('$file') as f:
    data = json.load(f)
plugins = data.get('plugins', data)
sys.exit(0 if '$plugin_key' in plugins else 1)
" 2>/dev/null; then
        ok "Plugin '$plugin_key' already registered — updating install path"
    fi

    # Add/update plugin entry
    python3 -c "
import json
with open('$file') as f:
    data = json.load(f)
if 'plugins' not in data:
    data = {'version': 2, 'plugins': data}
data['plugins']['$plugin_key'] = [{
    'scope': 'user',
    'installPath': '$install_path',
    'version': '$PLUGIN_VERSION',
    'installedAt': '$TIMESTAMP',
    'lastUpdated': '$TIMESTAMP'
}]
with open('$file', 'w') as f:
    json.dump(data, f, indent=2)
"
    ok "Plugin registered"
}

# ============================================================
# Phase 6: Enable plugin in settings.json
# ============================================================
phase6_enable_plugin() {
    echo ""
    echo -e "${CYAN}=== Phase 6: Enable Plugin ===${NC}"

    local file="$CLAUDE_CONFIG/settings.json"
    local plugin_key="${PLUGIN_NAME}@${MARKETPLACE_NAME}"

    # Create settings.json if it doesn't exist
    if [ ! -f "$file" ]; then
        cat > "$file" << 'SETTINGS'
{
  "permissions": {
    "defaultMode": "plan"
  },
  "enabledPlugins": {},
  "alwaysThinkingEnabled": true
}
SETTINGS
        info "Created default $file"
    fi

    # Backup
    cp "$file" "$CLAUDE_CONFIG/backups/settings.json.bak"

    # Check if already enabled
    if python3 -c "
import json, sys
with open('$file') as f:
    data = json.load(f)
sys.exit(0 if '$plugin_key' in data.get('enabledPlugins', {}) else 1)
" 2>/dev/null; then
        ok "Plugin already enabled"
        return
    fi

    # Enable the plugin
    python3 -c "
import json
with open('$file') as f:
    data = json.load(f)
if 'enabledPlugins' not in data:
    data['enabledPlugins'] = {}
data['enabledPlugins']['$plugin_key'] = True
with open('$file', 'w') as f:
    json.dump(data, f, indent=2)
"
    ok "Plugin enabled in settings"
}

# ============================================================
# Phase 7: Create global CLAUDE.md
# ============================================================
phase7_global_claude_md() {
    echo ""
    echo -e "${CYAN}=== Phase 7: Global CLAUDE.md ===${NC}"

    local file="$CLAUDE_CONFIG/CLAUDE.md"

    if [ -f "$file" ]; then
        ok "Global CLAUDE.md already exists — skipping"
        return
    fi

    cat > "$file" << 'CLAUDEMD'
# Global Preferences

## Skills Hub
Skills are managed from ~/claude/ — launch Claude from there for the full skill catalog.

## Coding Conventions
- Write clean, readable code with meaningful names
- Prefer composition over inheritance
- Handle errors explicitly, never silently swallow exceptions
- Follow the project's existing patterns and conventions

## Git
- Write concise, descriptive commit messages
- Never force-push without explicit permission
- Always check git status before committing
CLAUDEMD
    ok "Global CLAUDE.md created"
}

# ============================================================
# Summary
# ============================================================
summary() {
    echo ""
    echo -e "${GREEN}============================================================${NC}"
    echo -e "${GREEN}  Setup Complete!${NC}"
    echo -e "${GREEN}============================================================${NC}"
    echo ""
    echo -e "  Skills repo:     ${CYAN}$CLAUDE_DIR${NC}"
    echo -e "  Plugin cache:    ${CYAN}$CLAUDE_CONFIG/plugins/cache/$MARKETPLACE_NAME/$PLUGIN_NAME/$PLUGIN_VERSION${NC}"
    echo -e "  Global config:   ${CYAN}$CLAUDE_CONFIG/CLAUDE.md${NC}"
    echo ""
    echo -e "  ${YELLOW}Next steps:${NC}"
    echo -e "  1. Restart Claude Code (or start a new session)"
    echo -e "  2. Launch from ${CYAN}cd ~/claude && claude${NC}"
    echo -e "  3. Skills available as ${CYAN}awesome-skills:<skill-name>${NC}"
    echo ""
    echo -e "  Backups saved to: ${CYAN}$CLAUDE_CONFIG/backups/${NC}"
    echo ""
}

# ============================================================
# Main
# ============================================================
main() {
    echo -e "${GREEN}============================================================${NC}"
    echo -e "${GREEN}  Claude Hub Setup${NC}"
    echo -e "${GREEN}============================================================${NC}"

    # Check prerequisites
    if ! command -v git &>/dev/null; then
        error "git is not installed"
        exit 1
    fi
    if ! command -v python3 &>/dev/null; then
        error "python3 is not installed (needed for JSON manipulation)"
        exit 1
    fi

    phase1_clone_repo
    phase2_ensure_claude_dirs
    phase3_register_marketplace
    phase4_install_plugin
    phase5_register_plugin
    phase6_enable_plugin
    phase7_global_claude_md
    summary
}

main "$@"
