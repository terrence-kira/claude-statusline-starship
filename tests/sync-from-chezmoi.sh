#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEMP_ROOT"' EXIT

SOURCE="$TEMP_ROOT/source"
PROJECT="$TEMP_ROOT/project"
mkdir -p "$SOURCE/dot_claude/private_lib" "$PROJECT/scripts"

printf '#!/bin/bash\nprintf "main\\n"\n' > "$SOURCE/dot_claude/private_executable_statusline.sh"
printf '#!/bin/bash\nprintf "subagent\\n"\n' > "$SOURCE/dot_claude/private_executable_subagent-statusline.sh"
printf '#!/usr/bin/env bash\nprintf "helper\\n"\n' > "$SOURCE/dot_claude/private_lib/private_statusline-cache.sh"

cp "$ROOT/scripts/sync-from-chezmoi.sh" "$PROJECT/scripts/sync-from-chezmoi.sh"

bash "$PROJECT/scripts/sync-from-chezmoi.sh" --write --source "$SOURCE"
cmp "$SOURCE/dot_claude/private_executable_statusline.sh" "$PROJECT/statusline.sh"
cmp "$SOURCE/dot_claude/private_executable_subagent-statusline.sh" "$PROJECT/subagent-statusline.sh"
cmp "$SOURCE/dot_claude/private_lib/private_statusline-cache.sh" "$PROJECT/lib/statusline-cache.sh"
bash "$PROJECT/scripts/sync-from-chezmoi.sh" --check --source "$SOURCE"

printf '# drift\n' >> "$PROJECT/statusline.sh"
if bash "$PROJECT/scripts/sync-from-chezmoi.sh" --check --source "$SOURCE"; then
  printf 'expected --check to report drift\n' >&2
  exit 1
fi

rm "$SOURCE/dot_claude/private_lib/private_statusline-cache.sh"
set +e
bash "$PROJECT/scripts/sync-from-chezmoi.sh" --write --source "$SOURCE"
status=$?
set -e
if [ "$status" -ne 2 ]; then
  printf 'expected missing source to exit 2, got %s\n' "$status" >&2
  exit 1
fi

printf 'sync tests passed\n'
