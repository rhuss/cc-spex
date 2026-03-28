# cc-spex Development Guidelines

Auto-generated from all feature plans. Last updated: 2026-03-27

## Active Technologies
- Bash (POSIX-compatible), Markdown for commands/skills + `jq` (JSON parsing), `specify` CLI (spec-kit), `grep`/`rg` (sentinel detection)
- JSON (`.specify/spex-traits.json`), Markdown files
- Bash (POSIX-compatible) + Markdown + Python 3 (for hooks) + `jq` (JSON parsing), `spex-traits.sh`, Claude Code Agent Teams
- Bash (POSIX-compatible), Python 3 (hooks), Markdown (commands/skills) + `jq` (JSON parsing), `specify` CLI (spec-kit), Claude Code plugin system (008-rename-to-cc-spex)
- File-based (JSON config, Markdown documents) (008-rename-to-cc-spex)

## Project Structure

```text
spex/
  commands/        # Slash command definitions
  skills/          # Skill prompt files
  overlays/        # Trait overlay files
  scripts/         # Shell/Python scripts and hooks
  docs/            # Tutorials and help
specs/             # Feature specifications (historical)
```

## Code Style

Bash (POSIX-compatible, uses `jq` for JSON), Markdown for commands/skills: Follow standard conventions

## Traits

- `superpowers`: Quality gates on speckit commands (review-spec, review-code, verification)
- `teams`: Parallel implementation via Claude Code Agent Teams (experimental, requires superpowers)
- `worktrees`: Git worktree isolation after speckit.specify (creates sibling worktree, restores main)


<!-- MANUAL ADDITIONS START -->
<!-- MANUAL ADDITIONS END -->

## Recent Changes
- 008-rename-to-cc-spex: Added Bash (POSIX-compatible), Python 3 (hooks), Markdown (commands/skills) + `jq` (JSON parsing), `specify` CLI (spec-kit), Claude Code plugin system
