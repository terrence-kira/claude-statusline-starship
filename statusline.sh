#!/bin/bash
set -f

input=$(cat)

if [ -z "$input" ]; then
    printf "Claude"
    exit 0
fi

cache_helper="$HOME/.claude/lib/statusline-cache.sh"
if [ -r "$cache_helper" ]; then
    . "$cache_helper" >/dev/null 2>&1 || true
fi

# ── Colors ──────────────────────────────────────────────
blue='\033[38;2;0;153;255m'
orange='\033[38;2;255;176;85m'
green='\033[38;2;0;175;80m'
cyan='\033[38;2;86;182;194m'
red='\033[38;2;255;85;85m'
yellow='\033[38;2;230;200;0m'
white='\033[38;2;220;220;220m'
magenta='\033[38;2;180;140;255m'
dim='\033[2m'
reset='\033[0m'

sep=" ${dim}│${reset} "

# ── Helpers ─────────────────────────────────────────────
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

truncate_middle() {
    # Cap a string to maxlen with a single-char ellipsis "…" in the middle,
    # preserving the head and tail equally. p10k-style — long branches and
    # worktree slugs stay recognizable at both ends.
    local s=$1 maxlen=$2
    local len=${#s}
    if [ "$len" -le "$maxlen" ]; then
        printf "%s" "$s"
        return
    fi
    local keep=$(( (maxlen - 1) / 2 ))
    printf "%s…%s" "${s:0:keep}" "${s: -keep}"
}

color_for_pct() {
    local pct=$1
    if [ "$pct" -ge 90 ]; then printf "$red"
    elif [ "$pct" -ge 70 ]; then printf "$yellow"
    elif [ "$pct" -ge 50 ]; then printf "$orange"
    else printf "$green"
    fi
}

build_bar() {
    local pct=$1
    local width=$2
    [ "$pct" -lt 0 ] 2>/dev/null && pct=0
    [ "$pct" -gt 100 ] 2>/dev/null && pct=100

    local filled=$(( pct * width / 100 ))
    local denom=$(( width - 1 ))
    [ "$denom" -lt 1 ] && denom=1

    # Per-cell RGB interpolation along green → yellow → orange → red.
    # Filled cells take the gradient at their own bar position; empty cells
    # form a dim track. DOUBLE HORIZONTAL ═ is a box-drawing extender, so
    # cells tile edge-to-edge with no seams (unlike geometric ▬), and its
    # two parallel strokes give noticeably more vertical presence than the
    # single-stroke ━ while staying vertically centered.
    local i t sub r g b r1 g1 b1 r2 g2 b2
    for ((i=0; i<width; i++)); do
        if [ "$i" -lt "$filled" ]; then
            t=$(( i * 100 / denom ))
            if [ "$t" -le 50 ]; then
                r1=0;   g1=175; b1=80; r2=230; g2=200; b2=0;  sub=$(( t * 2 ))
            elif [ "$t" -le 75 ]; then
                r1=230; g1=200; b1=0;  r2=255; g2=176; b2=85; sub=$(( (t - 50) * 4 ))
            else
                r1=255; g1=176; b1=85; r2=255; g2=85;  b2=85; sub=$(( (t - 75) * 4 ))
            fi
            r=$(( (r1*(100-sub) + r2*sub) / 100 ))
            g=$(( (g1*(100-sub) + g2*sub) / 100 ))
            b=$(( (b1*(100-sub) + b2*sub) / 100 ))
            printf "\033[0;38;2;%d;%d;%dm═" "$r" "$g" "$b"
        else
            printf "\033[0;2m═"
        fi
    done
    printf "\033[0m"
}

iso_to_epoch() {
    local iso_str="$1"

    local epoch
    epoch=$(date -d "${iso_str}" +%s 2>/dev/null)
    if [ -n "$epoch" ]; then
        echo "$epoch"
        return 0
    fi

    local stripped="${iso_str%%.*}"
    stripped="${stripped%%Z}"
    stripped="${stripped%%+*}"
    stripped="${stripped%%-[0-9][0-9]:[0-9][0-9]}"

    if [[ "$iso_str" == *"Z"* ]] || [[ "$iso_str" == *"+00:00"* ]] || [[ "$iso_str" == *"-00:00"* ]]; then
        epoch=$(env TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "$stripped" +%s 2>/dev/null)
    else
        epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$stripped" +%s 2>/dev/null)
    fi

    if [ -n "$epoch" ]; then
        echo "$epoch"
        return 0
    fi

    return 1
}

format_reset_time() {
    local iso_str="$1"
    [ -z "$iso_str" ] || [ "$iso_str" = "null" ] && return

    local epoch
    epoch=$(iso_to_epoch "$iso_str")
    [ -z "$epoch" ] && return

    local now_epoch
    now_epoch=$(date +%s)
    local diff=$(( epoch - now_epoch ))

    if [ "$diff" -le 0 ]; then
        printf "now"
        return
    fi

    local days=$(( diff / 86400 ))
    local hours=$(( (diff % 86400) / 3600 ))
    local minutes=$(( (diff % 3600) / 60 ))

    local result=""
    if [ "$days" -gt 0 ]; then
        result="in ${days}d"
        [ "$hours" -gt 0 ] && result="${result} ${hours}h"
    elif [ "$hours" -gt 0 ]; then
        result="in ${hours}h"
        [ "$minutes" -gt 0 ] && result="${result} ${minutes}m"
    else
        result="in ${minutes}m"
    fi

    printf "%s" "$result"
}

# ── Extract JSON data ───────────────────────────────────
eval "$(jq -r '
  "model_name="   + (.model.display_name // "Claude" | @sh),
  "size="         + (.context_window.context_window_size // 0 | tostring | @sh),
  "pct_used="     + (.context_window.used_percentage // 0 | floor | tostring | @sh),
  "input_tokens=" + (.context_window.current_usage.input_tokens // 0 | tostring | @sh),
  "cache_create=" + (.context_window.current_usage.cache_creation_input_tokens // 0 | tostring | @sh),
  "cache_read="     + (.context_window.current_usage.cache_read_input_tokens // 0 | tostring | @sh),
  "output_tokens="  + (.context_window.current_usage.output_tokens // 0 | tostring | @sh),
  "cwd="            + (.cwd // "" | @sh),
  "git_worktree="   + (.workspace.git_worktree // "" | @sh),
  "effort_level="   + (.effort.level // "" | @sh),
  "session_id="     + (.session_id // "" | @sh)
' <<< "$input")"
[ "$size" -eq 0 ] 2>/dev/null && size=200000

current=$(( input_tokens + cache_create + cache_read + output_tokens ))

# Hand the authoritative context usage off to hooks: hook stdin never carries
# context_window (only the status line gets it), so the compact-reminder
# UserPromptSubmit hook reads this per-session cache instead of recomputing.
if declare -F claude_statusline_write_context >/dev/null 2>&1; then
    claude_statusline_write_context "$session_id" "$pct_used" "$size" >/dev/null 2>&1 || true
fi
used_tokens=$(format_tokens $current)
total_tokens=$(format_tokens $size)

# Prefer the live session effort level from stdin; fall back to the persisted config.
effort="$effort_level"
if [ -z "$effort" ]; then
    settings_path="$HOME/.claude/settings.json"
    if [ -f "$settings_path" ]; then
        effort=$(jq -r '.effortLevel // "default"' "$settings_path" 2>/dev/null)
    fi
fi
[ -z "$effort" ] && effort="default"

# ── LINE 1: Model │ Context % │ Directory (branch) │ Session │ Thinking ──
pct_color=$(color_for_pct "$pct_used")
[ -z "$cwd" ] && cwd=$(pwd)
dirname=$(basename "$cwd")

git_branch=""
git_dirty=""
if git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git_branch=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null)
    if [ -n "$(git -C "$cwd" --no-optional-locks status --porcelain 2>/dev/null)" ]; then
        git_dirty="*"
    fi
fi

line1="${blue}${model_name}${reset}"
line1+="${sep}"
line1+="${pct_color}${pct_used}%${reset} ${dim}${used_tokens}/${total_tokens}${reset}"
line1+="${sep}"
# Dir/branch segment. In worktree mode dirname == worktree slug (the basename
# of .worktrees/<user>/<scope>) and the branch is <user>/<scope>, so the
# slug would appear twice; we replace the dirname with the MAIN repo name
# (derived from the worktree's common .git dir — its parent IS the main
# checkout, so basename gives the repo name) and strip the implicit user/
# prefix from the branch. Long names get middle-ellipsis truncation so the
# head and tail (issue ID, last word) stay recognizable.
DIR_CAP=24
BRANCH_CAP=28
if [ -n "$git_worktree" ] && [ -n "$git_branch" ]; then
    main_repo=""
    common_git=$(git -C "$cwd" rev-parse --git-common-dir 2>/dev/null)
    if [ -n "$common_git" ]; then
        case "$common_git" in
            /*) ;;
            *) common_git="$cwd/$common_git" ;;
        esac
        main_repo=$(basename "$(dirname "$common_git")")
    fi
    [ -z "$main_repo" ] && main_repo="$dirname"
    display_branch="${git_branch#*/}"
    line1+="${cyan}$(truncate_middle "$main_repo" "$DIR_CAP")${reset} 🌳 ${magenta}$(truncate_middle "$display_branch" "$BRANCH_CAP")${red}${git_dirty}${reset}"
elif [ -n "$git_branch" ]; then
    line1+="${cyan}$(truncate_middle "$dirname" "$DIR_CAP")${reset}"
    line1+=" ${green}($(truncate_middle "$git_branch" "$BRANCH_CAP")${red}${git_dirty}${green})${reset}"
else
    line1+="${cyan}$(truncate_middle "$dirname" "$DIR_CAP")${reset}"
fi
line1+="${sep}"
case "$effort" in
    max)    line1+="${red}● ${effort}${reset}" ;;
    xhigh)  line1+="${orange}● ${effort}${reset}" ;;
    high)   line1+="${yellow}◕ ${effort}${reset}" ;;
    medium) line1+="${green}◑ ${effort}${reset}" ;;
    low)    line1+="${dim}◔ ${effort}${reset}" ;;
    *)      line1+="${dim}◑ ${effort}${reset}" ;;
esac

# Render a stable cache snapshot and ask the helper to refresh stale data in a
# detached process for the next invocation. Helper failure never blocks output.
usage_data=""
if declare -F claude_statusline_read_usage >/dev/null 2>&1; then
    usage_data="$(claude_statusline_read_usage 2>/dev/null)" || usage_data=""
fi
if declare -F claude_statusline_refresh_usage_async >/dev/null 2>&1; then
    claude_statusline_refresh_usage_async || true
fi

# ── Rate limit lines ────────────────────────────────────
rate_lines=""
extra_segment=""

if [ -n "$usage_data" ] && echo "$usage_data" | jq -e . >/dev/null 2>&1; then
    bar_width=10

    # Single jq pass over the cache instead of ~10 separate jq/awk subprocesses.
    # Percentages arrive pre-rounded; dollar amounts come through as plain
    # numbers and are %.2f-formatted with a bash builtin below. extra_unlimited
    # is true when extra usage is on but has no monthly cap (limit null or 0).
    eval "$(echo "$usage_data" | jq -r '
      "extra_enabled="       + ((.extra_usage.is_enabled // false)        | tostring | @sh),
      "extra_unlimited="     + (((.extra_usage.monthly_limit // 0) == 0)  | tostring | @sh),
      "five_hour_pct="       + ((.five_hour.utilization // 0)  | round | tostring | @sh),
      "seven_day_pct="       + ((.seven_day.utilization // 0)  | round | tostring | @sh),
      "five_hour_reset_iso=" + ((.five_hour.resets_at // "")             | @sh),
      "seven_day_reset_iso=" + ((.seven_day.resets_at // "")            | @sh),
      "extra_used_usd="      + ((.extra_usage.used_credits // 0)  / 100  | tostring | @sh),
      "extra_limit_usd="     + ((.extra_usage.monthly_limit // 0) / 100  | tostring | @sh)
    ')"

    five_hour_reset=$(format_reset_time "$five_hour_reset_iso")
    five_hour_bar=$(build_bar "$five_hour_pct" "$bar_width")
    five_hour_pct_color=$(color_for_pct "$five_hour_pct")

    seven_day_reset=$(format_reset_time "$seven_day_reset_iso")
    seven_day_bar=$(build_bar "$seven_day_pct" "$bar_width")
    seven_day_pct_color=$(color_for_pct "$seven_day_pct")

    rate_lines+="${white}current${reset} ${five_hour_bar} ${five_hour_pct_color}${five_hour_pct}%${reset} ${dim}⟳${reset} ${white}${five_hour_reset}${reset}"
    rate_lines+="${sep}"
    rate_lines+="${white}weekly${reset} ${seven_day_bar} ${seven_day_pct_color}${seven_day_pct}%${reset} ${dim}⟳${reset} ${white}${seven_day_reset}${reset}"

    if [ "$extra_enabled" = "true" ]; then
        extra_used=$(printf "%.2f" "$extra_used_usd")

        if [ "$extra_unlimited" = "true" ]; then
            extra_segment="${white}↗${reset} ${green}\$${extra_used} used${reset} ${dim}·${reset} ${green}unlimited${reset}"
        else
            extra_limit=$(printf "%.2f" "$extra_limit_usd")

            extra_reset=$(date -v+1m -v1d +"%b %-d" 2>/dev/null | tr '[:upper:]' '[:lower:]')
            if [ -z "$extra_reset" ]; then
                extra_reset=$(date -d "$(date +%Y-%m-01) +1 month" +"%b %-d" 2>/dev/null | tr '[:upper:]' '[:lower:]')
            fi

            extra_segment="${white}↗${reset} ${white}\$${extra_used}${dim}/${reset}${white}\$${extra_limit}${reset}"
        fi
    fi

    [ -n "$extra_reset" ] && rate_lines+=" ${dim}resets ${extra_reset}${reset}"
fi

# ── Output ──────────────────────────────────────────────
[ -n "$extra_segment" ] && line1+="${sep}${extra_segment}"
printf "%b" "$line1"
[ -n "$rate_lines" ] && printf "\n\n%b" "$rate_lines"

exit 0
