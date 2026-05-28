#!/bin/bash
set -euo pipefail

# install.sh — one-shot installer for claude-statusline
#
# Test override: set INSTALL_FROM_LOCAL=/path/to/statusline.sh to skip the
# curl download and use a local file instead. Useful for test rigs that run
# without network access or before a release is pushed.

REPO_RAW="https://raw.githubusercontent.com/terrence-kira/claude-statusline/main"
INSTALL_DIR="$HOME/.claude"
TARGET_SCRIPT="$INSTALL_DIR/statusline.sh"
TARGET_SETTINGS="$INSTALL_DIR/settings.json"

STATUSLINE_BLOCK='{"statusLine":{"type":"command","command":"~/.claude/statusline.sh","padding":0,"refreshInterval":1000}}'

# ── Dependency check ─────────────────────────────────────────────────────────
missing=()
command -v jq  >/dev/null 2>&1 || missing+=("jq")
command -v curl >/dev/null 2>&1 || missing+=("curl")

if [ ${#missing[@]} -gt 0 ]; then
    echo "Error: missing required tools: ${missing[*]}"
    echo "Install them with:  brew install ${missing[*]}"
    exit 1
fi

# ── Download (or copy) statusline.sh ─────────────────────────────────────────
mkdir -p "$INSTALL_DIR"

tmp_script=$(mktemp)
trap 'rm -f "$tmp_script"' EXIT

if [ -n "${INSTALL_FROM_LOCAL:-}" ]; then
    # Test-rig path: use a local file instead of curling from GitHub.
    cp "$INSTALL_FROM_LOCAL" "$tmp_script"
else
    curl -fsSL "$REPO_RAW/statusline.sh" -o "$tmp_script"
fi

# Verify the download looks like a real bash script.
if [ ! -s "$tmp_script" ]; then
    echo "Error: downloaded statusline.sh is empty."
    exit 1
fi
head_line=$(head -1 "$tmp_script")
if [[ "$head_line" != "#!/bin/bash"* ]]; then
    echo "Error: downloaded file does not start with #!/bin/bash (got: $head_line)"
    exit 1
fi

mv "$tmp_script" "$TARGET_SCRIPT"
chmod +x "$TARGET_SCRIPT"
# Disarm the trap now that we've moved the file.
trap - EXIT

# ── settings.json handling ────────────────────────────────────────────────────
timestamp=$(date +%Y%m%dT%H%M%S)
backup_path=""

if [ -f "$TARGET_SETTINGS" ]; then
    # Back up the existing file before touching it.
    backup_path="${TARGET_SETTINGS}.${timestamp}.bak"
    cp "$TARGET_SETTINGS" "$backup_path"

    # Warn if we're replacing a different statusLine command.
    existing_command=$(jq -r '.statusLine.command // empty' "$TARGET_SETTINGS" 2>/dev/null || true)
    new_command=$(echo "$STATUSLINE_BLOCK" | jq -r '.statusLine.command')
    if [ -n "$existing_command" ] && [ "$existing_command" != "$new_command" ]; then
        echo "Note: replacing existing statusLine command: $existing_command"
    fi

    # Merge: existing keys are preserved; statusLine is overwritten.
    tmp_merged=$(mktemp)
    jq -s '.[0] * .[1]' "$TARGET_SETTINGS" <(echo "$STATUSLINE_BLOCK") > "$tmp_merged"
    mv "$tmp_merged" "$TARGET_SETTINGS"
else
    # No existing file — write fresh.
    echo "$STATUSLINE_BLOCK" | jq '.' > "$TARGET_SETTINGS"
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo "Installed: $TARGET_SCRIPT"
if [ -n "$backup_path" ]; then
    echo "Backup:    $backup_path"
fi
echo "Settings:  $TARGET_SETTINGS"
echo ""
echo "Restart Claude Code (exit, then \`claude\`) for the new statusline to take effect."
