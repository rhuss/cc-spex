# cc-spex Development Guidelines

Auto-generated from all feature plans. Last updated: 2026-04-22

## Active Technologies

- Bash (POSIX-compatible), Markdown, Python 3 (hooks), `jq`, `specify` CLI (spec-kit)

## Project Structure

```text
spex/
  extensions/          # Extension bundles
    spex/              # Core spex extension (brainstorm, ship, using-superpowers)
    spex-gates/        # Quality gates (review-spec, review-code, review-plan, stamp)
    spex-worktrees/    # Git worktree isolation
    spex-teams/        # Parallel agent orchestration
    spex-deep-review/  # Multi-agent code review
  skills/              # Standalone skills (init/)
  scripts/             # Shell/Python scripts and hooks
  docs/                # Tutorials and help
specs/                 # Feature specifications (historical)
```

## Code Style

Bash (POSIX-compatible, uses `jq` for JSON), Markdown for commands/skills: Follow standard conventions

## Extensions

- `spex`: Core extension with brainstorm, ship, and methodology entry point
- `spex-gates`: Quality gates on speckit commands (review-spec, review-code, review-plan, stamp, verification)
- `spex-worktrees`: Git worktree isolation after speckit.specify (creates sibling worktree, restores main)
- `spex-teams`: Parallel implementation via Claude Code Agent Teams (experimental)
- `spex-deep-review`: Multi-agent code review with 5 specialized review agents and autonomous fix loop

## Recent Changes

- 016-traits-to-extensions: Migrated traits to extension bundles, renamed commands from `/spex:*` to `speckit-spex-*` prefix
