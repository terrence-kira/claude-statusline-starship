# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A single-file Bash statusline for Claude Code. The deliverable is `statusline.sh`; everything else exists to install, uninstall, or document it. There is no build system, no package manager, no test suite, and no CI — every change ships as a direct edit to one of three shell scripts.

Runtime dependencies are `bash`, `jq`, `curl`, and `git`. The script must stay portable across macOS (BSD `date`/`stat`) and Linux (GNU `date`/`stat`); existing code already branches on this — preserve that pattern when touching date or stat calls.

## Common tasks

```bash
# Smoke-test a render against a realistic stdin payload
echo '{"model":{"display_name":"Sonnet"},"context_window":{"context_window_size":200000,"used_percentage":42,"current_usage":{"input_tokens":1000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":500}},"cwd":"'"$PWD"'","workspace":{},"effort":{"level":"high"}}' | ./statusline.sh

# Exercise install.sh without pulling from GitHub (uses the local script)
INSTALL_FROM_LOCAL=./statusline.sh ./install.sh

# Verify install on a clean machine state, then restore
./uninstall.sh
```

There are no lint or test commands. Validate changes by running the script against a representative JSON payload and visually inspecting the rendered output, then exercising `install.sh` / `uninstall.sh` to confirm the `settings.json` merge and restore paths still work.

## Architecture

**Input contract.** `statusline.sh` reads a single JSON object from stdin (Claude Code's statusline payload) and writes ANSI-colored text to stdout. The payload's `effort.level`, `context_window.*`, `model.display_name`, `cwd`, and `workspace.git_worktree` are the load-bearing fields. A `jq -r ... | eval` block at line ~163 extracts every field used downstream — extending the renderer with a new field means adding it there.

**Two-line render, conditional second line.** Line 1 (model · context · dir/branch · effort, plus an optional `↗` overage segment) is always emitted synchronously from stdin alone. Line 2 (5h + weekly rate bars) is emitted only when the usage cache is populated, separated by a blank line. The renderer must **never block on the network** — this is the load-bearing invariant.

**Non-blocking usage cache.** The 5h / weekly rate data comes from `https://api.anthropic.com/api/oauth/usage`, but the render path only ever reads `/tmp/claude/statusline-usage-cache.json`. When the cache is older than `cache_max_age` (60s), the script grabs an atomic `mkdir` lock and forks a detached subshell to refresh; the current render returns immediately with whatever is on disk. A stale lock (`lock_max_age`, 30s) is reclaimed on the next render to recover from a refresh that died mid-fetch. Do not introduce any code path that calls `curl` synchronously from the render flow.

**OAuth token resolution chain.** `get_oauth_token` tries, in order: `$CLAUDE_CODE_OAUTH_TOKEN` → macOS Keychain (`security find-generic-password -s "Claude Code-credentials"`) → `~/.claude/.credentials.json` → Linux `secret-tool`. Each source returns the JSON blob's `.claudeAiOauth.accessToken`. When adding a credential source, follow the same shape: probe, parse, return on first hit; never log the token.

**Worktree-aware path segment.** When Claude Code reports `workspace.git_worktree`, the dirname is **replaced with the main repo name** — derived from `git rev-parse --git-common-dir` (the parent of the common `.git` directory IS the main checkout, so `basename` of that parent gives the repo name). Without this step the line would show only the worktree slug, leaving no signal as to which repo the worktree belongs to. The implicit `user/` prefix is then stripped from the branch (worktree branches follow `<user>/<scope>`). `truncate_middle` keeps the head and tail of long branch / dir names recognizable. Constants live at top of the dir/branch block: `DIR_CAP=24`, `BRANCH_CAP=28`.

**Gradient bars.** `build_bar` does per-cell RGB interpolation along `green → yellow → orange → red` and renders with the box-drawing `═` (U+2550), specifically chosen because it tiles seamlessly between cells — geometric extenders like `▬` leave visible gaps. The interpolation has three piecewise segments (0–50%, 50–75%, 75–100%) tuned so the yellow/orange transition lines up with the 70% / 90% color thresholds used elsewhere.

**Effort badge.** Reads `effort.level` (live, per-session) from stdin first; falls back to `~/.claude/settings.json` `effortLevel` only when the current model doesn't expose it. The glyph progression `◔ / ◑ / ◕ / ●` plus the `grey → green → yellow → orange → red` color ramp is intentional — both axes encode effort, so changes to one need a matching change to the other.

**User-Agent pin.** The usage endpoint occasionally rejects stale Claude Code user-agents. The string `"User-Agent: claude-code/<version>"` in `refresh_usage_cache` is pinned and must be bumped manually if Anthropic ever returns 403/426 against the current value. The user-facing README already documents this — keep the README troubleshooting section in sync when bumping.

## Install / uninstall scripts

`install.sh` downloads `statusline.sh` from `raw.githubusercontent.com/terrence-kira/claude-statusline/main`, then uses `jq -s '.[0] * .[1]'` to merge a `statusLine` block into `~/.claude/settings.json` — existing keys are preserved, `statusLine` is overwritten. A timestamped `.bak` is always written before any settings edit. `INSTALL_FROM_LOCAL=/path/to/statusline.sh` skips the download (used in local testing and CI rigs).

`uninstall.sh` looks for the latest non-`pre-uninstall` `.bak` (timestamp filenames are `YYYYMMDDTHHmmSS`, lexicographically sortable) and restores it; if none is found, it deletes the `statusLine` key in place. A `pre-uninstall.<ts>.bak` is written before the restore so the uninstall itself is reversible.

When the install URL or repo slug changes, three files need to be updated together: `install.sh` (`REPO_RAW`), `uninstall.sh` (no URL today, but check), and the install/uninstall one-liners in `README.md`.

## Conventions

- Shell scripts start with `#!/bin/bash` and `set -euo pipefail` (installers) or `set -f` (the renderer — the renderer needs unset variables to default to empty, so it deliberately omits `-u`).
- Color codes are 24-bit truecolor (`\033[38;2;R;G;Bm`) and live in a single block at the top of `statusline.sh`. Reuse the existing names; do not introduce a 256-color fallback.
- Commit messages follow Conventional Commits (`feat:`, `fix:`, `refactor:`, `docs:`, `chore:`) — see `git log` for the established style. Keep the subject line under ~72 chars.
