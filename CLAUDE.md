# cc-sdd Development Guidelines

Auto-generated from all feature plans. Last updated: 2026-03-12

## Active Technologies
- Bash (POSIX-compatible), Markdown for commands/skills + `jq` (JSON parsing), `specify` CLI (spec-kit), `grep`/`rg` (sentinel detection)
- JSON (`.specify/sdd-traits.json`), Markdown files
- Bash (POSIX-compatible) + Markdown + Python 3 (for hooks) + `jq` (JSON parsing), `sdd-traits.sh`, Claude Code Agent Teams

## Project Structure

```text
sdd/
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


<!-- MANUAL ADDITIONS START -->
<!-- MANUAL ADDITIONS END -->
