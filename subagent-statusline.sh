#!/bin/bash
# Subagent status line: renders one custom row per subagent shown in the agent
# panel below the prompt (Task-tool subagents and Workflow-spawned agents).
# Contract (docs/en/statusline): stdin is a single JSON object with `columns`
# (usable row width) and a `tasks` array; each task carries id/name/type/status/
# description/label/startTime/model/contextWindowSize/tokenCount/tokenSamples/cwd.
# We emit one JSON line per row we override: {"id","content"}. Omitting a task's
# id keeps its default rendering; an empty content hides the row. `content` is
# printed as-is, so ANSI colors and OSC 8 links pass through.
#
# Palette and token humanizing intentionally mirror ~/.claude/statusline.sh so
# the two lines read as one system. On any parse miss we emit nothing, which
# leaves every row at Claude Code's default `name · description · token count`.
set -f

input=$(cat)
[ -z "$input" ] && exit 0
echo "$input" | jq -e '.tasks' >/dev/null 2>&1 || exit 0

# ── Colors (match statusline.sh) ────────────────────────
blue=$'\033[38;2;0;153;255m'
green=$'\033[38;2;0;175;80m'
cyan=$'\033[38;2;86;182;194m'
red=$'\033[38;2;255;85;85m'
yellow=$'\033[38;2;230;200;0m'
orange=$'\033[38;2;255;176;85m'
dim=$'\033[2m'
reset=$'\033[0m'

format_tokens() {
    local num=$1
    if [ "$num" -ge 1000000 ]; then
        awk "BEGIN {printf \"%.1fm\", $num / 1000000}"
    elif [ "$num" -ge 1000 ]; then
        awk "BEGIN {printf \"%.0fk\", $num / 1000}"
    else
        printf "%d" "$num"
    fi
}

truncate_end() {
    local s=$1 maxlen=$2
    [ "$maxlen" -lt 1 ] && maxlen=1
    if [ "${#s}" -le "$maxlen" ]; then printf "%s" "$s"; return; fi
    printf "%s…" "${s:0:maxlen-1}"
}

color_for_pct() {
    local pct=$1
    if [ "$pct" -ge 90 ]; then printf "%s" "$red"
    elif [ "$pct" -ge 70 ]; then printf "%s" "$yellow"
    elif [ "$pct" -ge 50 ]; then printf "%s" "$orange"
    else printf "%s" "$green"
    fi
}

# Glyph + color for a task's status. Enum isn't contractually fixed, so match
# case-insensitive substrings and fall back to a neutral dot.
status_glyph() {
    local s
    s=$(printf "%s" "$1" | tr '[:upper:]' '[:lower:]')
    case "$s" in
        *progress*|*running*|*active*|*working*) printf "%s◐" "$cyan" ;;
        *complete*|*done*|*success*|*finish*)    printf "%s✓" "$green" ;;
        *fail*|*error*)                          printf "%s✗" "$red" ;;
        *cancel*|*stop*|*abort*)                 printf "%s⊘" "$yellow" ;;
        *pend*|*queue*|*wait*)                   printf "%s○" "$dim" ;;
        *)                                       printf "%s●" "$dim" ;;
    esac
}

columns=$(echo "$input" | jq -r '.columns // 80')
[ -z "$columns" ] || ! [ "$columns" -eq "$columns" ] 2>/dev/null && columns=80

# One row per task, fields joined by U+001F — a non-whitespace unit separator so
# `read` preserves empty fields. A tab delimiter would collapse an empty
# description (tab is whitespace-IFS) and shift every later field left. Any
# tab/newline/separator inside a field is squashed to a space first so each task
# stays on exactly one line.
echo "$input" | jq -r '
  .tasks[]? | [
    (.id // ""), (.name // ""), (.description // .label // ""),
    (.status // ""), (.tokenCount // 0 | tostring), (.contextWindowSize // 0 | tostring)
  ] | map(gsub("[\t\n\r\u001f]"; " ")) | join("\u001f")
' | while IFS=$'\037' read -r id name desc status tok ctx; do
    [ -z "$id" ] && continue

    glyph=$(status_glyph "$status")

    # Token segment, colored by context fill when the window size is known.
    tok=${tok:-0}; ctx=${ctx:-0}
    tok_h=$(format_tokens "$tok")
    if [ "$ctx" -gt 0 ] 2>/dev/null; then
        pct=$(( tok * 100 / ctx ))
        [ "$pct" -gt 100 ] && pct=100
        tokseg="$(color_for_pct "$pct")${tok_h} ${pct}%${reset}"
    else
        tokseg="${dim}${tok_h}${reset}"
    fi

    # Width budget: keep name short, give the description whatever remains after
    # reserving room for glyph, name, token segment and separators.
    name=$(truncate_end "$name" 22)
    desc_cap=$(( columns - ${#name} - 26 ))
    [ "$desc_cap" -lt 8 ] && desc_cap=8
    [ "$desc_cap" -gt 64 ] && desc_cap=64

    content="${glyph} ${blue}${name}${reset}"
    if [ -n "$desc" ]; then
        content+="  ${dim}$(truncate_end "$desc" "$desc_cap")${reset}"
    fi
    content+="  ${tokseg}"

    jq -cn --arg id "$id" --arg content "$content" '{id:$id, content:$content}'
done

exit 0
