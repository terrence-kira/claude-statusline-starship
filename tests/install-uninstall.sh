#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEMP_ROOT"' EXIT

HOME_DIR="$TEMP_ROOT/home"
mkdir -p "$HOME_DIR/.claude"
printf '{"theme":"dark"}\n' > "$HOME_DIR/.claude/settings.json"

HOME="$HOME_DIR" INSTALL_FROM_LOCAL="$ROOT/statusline.sh" bash "$ROOT/install.sh" >/dev/null
cmp "$ROOT/statusline.sh" "$HOME_DIR/.claude/statusline.sh"
cmp "$ROOT/subagent-statusline.sh" "$HOME_DIR/.claude/subagent-statusline.sh"
cmp "$ROOT/lib/statusline-cache.sh" "$HOME_DIR/.claude/lib/statusline-cache.sh"
jq -e '
  .theme == "dark"
  and .statusLine.command == "bash \"$HOME/.claude/statusline.sh\""
  and .subagentStatusLine.command == "bash \"$HOME/.claude/subagent-statusline.sh\""
' "$HOME_DIR/.claude/settings.json" >/dev/null

HOME="$HOME_DIR" INSTALL_FROM_LOCAL="$ROOT/statusline.sh" bash "$ROOT/install.sh" >/dev/null
if [ "$(find "$HOME_DIR/.claude" -name 'settings.json.*.bak' | wc -l | tr -d ' ')" -ne 1 ]; then
  printf 'repeat install should not create a second backup\n' >&2
  exit 1
fi

HOME="$HOME_DIR" bash "$ROOT/uninstall.sh" >/dev/null
jq -e '. == {"theme":"dark"}' "$HOME_DIR/.claude/settings.json" >/dev/null
test ! -e "$HOME_DIR/.claude/statusline.sh"
test ! -e "$HOME_DIR/.claude/subagent-statusline.sh"
test ! -e "$HOME_DIR/.claude/lib/statusline-cache.sh"

NO_BACKUP_HOME="$TEMP_ROOT/no-backup-home"
mkdir -p "$NO_BACKUP_HOME/.claude"
printf '{"theme":"light","statusLine":{"type":"command"},"subagentStatusLine":{"type":"command"}}\n' > "$NO_BACKUP_HOME/.claude/settings.json"
HOME="$NO_BACKUP_HOME" bash "$ROOT/uninstall.sh" >/dev/null
jq -e '. == {"theme":"light"}' "$NO_BACKUP_HOME/.claude/settings.json" >/dev/null

printf 'install and uninstall tests passed\n'
