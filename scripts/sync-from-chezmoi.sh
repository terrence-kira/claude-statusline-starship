#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODE=""
SOURCE_ROOT=""

usage() {
  printf 'Usage: %s --check|--write [--source <chezmoi-root>]\n' "${0##*/}"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --check|--write)
      [ -z "$MODE" ] || { usage >&2; exit 2; }
      MODE="$1"
      shift
      ;;
    --source)
      [ "$#" -ge 2 ] || { usage >&2; exit 2; }
      SOURCE_ROOT="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

[ -n "$MODE" ] || { usage >&2; exit 2; }
if [ -z "$SOURCE_ROOT" ]; then
  command -v chezmoi >/dev/null 2>&1 || { printf 'error: chezmoi is required\n' >&2; exit 2; }
  SOURCE_ROOT="$(chezmoi source-path 2>/dev/null)" || { printf 'error: unable to resolve chezmoi source\n' >&2; exit 2; }
fi

SOURCE_PATHS=(
  "dot_claude/private_executable_statusline.sh"
  "dot_claude/private_executable_subagent-statusline.sh"
  "dot_claude/private_lib/private_statusline-cache.sh"
)
DEST_PATHS=(
  "statusline.sh"
  "subagent-statusline.sh"
  "lib/statusline-cache.sh"
)

for relative in "${SOURCE_PATHS[@]}"; do
  [ -f "$SOURCE_ROOT/$relative" ] || { printf 'error: missing source file: %s\n' "$SOURCE_ROOT/$relative" >&2; exit 2; }
done

if [ "$MODE" = "--check" ]; then
  drift=0
  for ((index = 0; index < ${#SOURCE_PATHS[@]}; index++)); do
    source_path="$SOURCE_ROOT/${SOURCE_PATHS[index]}"
    destination_path="$ROOT/${DEST_PATHS[index]}"
    if ! cmp -s "$source_path" "$destination_path"; then
      printf 'drift: %s\n' "${DEST_PATHS[index]}" >&2
      drift=1
    fi
  done
  exit "$drift"
fi

for ((index = 0; index < ${#SOURCE_PATHS[@]}; index++)); do
  source_path="$SOURCE_ROOT/${SOURCE_PATHS[index]}"
  destination_path="$ROOT/${DEST_PATHS[index]}"
  mkdir -p "$(dirname "$destination_path")"
  temporary="$(mktemp "${destination_path}.tmp.XXXXXX")"
  trap 'rm -f "$temporary"' EXIT
  cp "$source_path" "$temporary"
  case "${DEST_PATHS[index]}" in
    *.sh) chmod 755 "$temporary" ;;
  esac
  mv "$temporary" "$destination_path"
  trap - EXIT
  printf 'updated: %s\n' "${DEST_PATHS[index]}"
done
