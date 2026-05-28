#!/bin/bash
set -euo pipefail

# uninstall.sh — removes claude-statusline and restores settings.json

INSTALL_DIR="$HOME/.claude"
TARGET_SCRIPT="$INSTALL_DIR/statusline.sh"
TARGET_SETTINGS="$INSTALL_DIR/settings.json"

# ── Dependency check ─────────────────────────────────────────────────────────
missing=()
command -v jq  >/dev/null 2>&1 || missing+=("jq")
command -v curl >/dev/null 2>&1 || missing+=("curl")

if [ ${#missing[@]} -gt 0 ]; then
    echo "Error: missing required tools: ${missing[*]}"
    echo "Install them with:  brew install ${missing[*]}"
    exit 1
fi

# ── Restore settings.json ─────────────────────────────────────────────────────
timestamp=$(date +%Y%m%dT%H%M%S)

# Find the most recent install backup (lexicographic sort is correct because
# the timestamp format is YYYYMMDDTHHmmSS — fixed-width, naturally sortable).
latest_backup=$(ls -1 "${TARGET_SETTINGS}".*.bak 2>/dev/null \
    | grep -v 'pre-uninstall' \
    | sort \
    | tail -1 || true)

if [ -n "$latest_backup" ]; then
    # Back up the current state before overwriting, then restore.
    pre_uninstall_backup="${TARGET_SETTINGS}.pre-uninstall.${timestamp}.bak"
    cp "$TARGET_SETTINGS" "$pre_uninstall_backup"
    cp "$latest_backup" "$TARGET_SETTINGS"
    echo "Restored:  $TARGET_SETTINGS  (from $latest_backup)"
    echo "Saved pre-uninstall state: $pre_uninstall_backup"
elif [ -f "$TARGET_SETTINGS" ]; then
    # No install backup found — strip only the statusLine key.
    tmp_stripped=$(mktemp)
    jq 'del(.statusLine)' "$TARGET_SETTINGS" > "$tmp_stripped"

    # If the result is an empty object, remove the file entirely.
    if [ "$(cat "$tmp_stripped")" = "{}" ]; then
        rm -f "$TARGET_SETTINGS"
        rm -f "$tmp_stripped"
        echo "Removed:   $TARGET_SETTINGS  (was only a statusLine block)"
    else
        mv "$tmp_stripped" "$TARGET_SETTINGS"
        echo "Updated:   $TARGET_SETTINGS  (statusLine block removed)"
    fi
else
    echo "Nothing to restore: $TARGET_SETTINGS does not exist."
fi

# ── Remove statusline.sh ──────────────────────────────────────────────────────
if [ -f "$TARGET_SCRIPT" ]; then
    rm -f "$TARGET_SCRIPT"
    echo "Removed:   $TARGET_SCRIPT"
else
    echo "Nothing to remove: $TARGET_SCRIPT does not exist."
fi

echo ""
echo "Uninstall complete. Restart Claude Code (exit, then \`claude\`) to apply."
