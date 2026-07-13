# Agent Guidelines

Docs and Git commits must be in English. Respond to users in Simplified Chinese.

## Repository Purpose

This repository publishes a portable Claude Code status-line bundle:

- `statusline.sh` renders the main status line.
- `subagent-statusline.sh` renders rows in the subagent panel.
- `lib/statusline-cache.sh` owns OAuth lookup, usage refresh, locking, and context handoff.

The user's chezmoi source repository is canonical. Do not edit the three exported
payload files independently; update the canonical source, then run the sync
command in this repository.

## Maintenance

```bash
scripts/sync-from-chezmoi.sh --check
scripts/sync-from-chezmoi.sh --write
bash tests/sync-from-chezmoi.sh
bash tests/render.smoke.sh
bash tests/install-uninstall.sh
```

The sync script reads exactly three allowlisted files and never writes to
chezmoi. Keep `.codex/`, credentials, sessions, caches, and machine-specific
state out of Git.

## Runtime Invariants

- Rendering must never block on a network request.
- The cache helper must keep tokens out of process arguments and logs.
- Date and stat behavior must remain portable across macOS and Linux.
- The installer must preserve unrelated settings and create a reversible backup.
- Repeated installation must not replace the original pre-install backup.
- The uninstaller must remove only this bundle and its two settings keys when no
  backup exists.

## Workflow

- Inspect before editing and preserve unrelated changes.
- Add tests before behavior changes and observe the expected failure.
- Run every test before committing.
- Use Conventional Commits and signed commits only.
