# cc-sdd Development Guidelines

Auto-generated from all feature plans. Last updated: 2026-02-13

## Active Technologies
- Bash (POSIX-compatible), Markdown for commands/skills + `jq` (JSON parsing), `specify` CLI (spec-kit), `grep`/`rg` (sentinel detection) (003-command-consolidation)
- JSON (`.specify/sdd-traits.json`), Markdown files (003-command-consolidation)
- Markdown (skill prompt definition) + Existing brainstorm skill, filesystem (mkdir, ls), existing spec creation flow (004-brainstorm-persistence)
- Markdown files in `brainstorm/` directory at project roo (004-brainstorm-persistence)
- Bash (POSIX-compatible) + Markdown + `jq` for JSON parsing + `sdd-traits.sh` (existing), Claude Code Agent Teams (experimental, `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`), `bd` CLI (beads, for teams-spec only) (005-teams-traits)
- `.specify/sdd-traits.json` (trait config), `.beads/` (beads database, existing) (005-teams-traits)
- Bash (POSIX-compatible) + Markdown + Python 3 (for hooks) + `jq` (JSON parsing), `sdd-traits.sh` (existing), `bd` CLI (beads), Claude Code Agent Teams (006-teams-trait-consolidation)
- `.specify/sdd-traits.json` (trait config), `.beads/` (beads database) (006-teams-trait-consolidation)

- Bash (POSIX-compatible, uses `jq` for JSON), Markdown for commands/skills + `jq` (JSON parsing), `specify` CLI (spec-kit), `grep` (sentinel detection) (002-traits-infrastructure)

## Project Structure

```text
src/
tests/
```

## Commands

# Add commands for Bash (POSIX-compatible, uses `jq` for JSON), Markdown for commands/skills

## Code Style

Bash (POSIX-compatible, uses `jq` for JSON), Markdown for commands/skills: Follow standard conventions

## Recent Changes
- 006-teams-trait-consolidation: Added Bash (POSIX-compatible) + Markdown + Python 3 (for hooks) + `jq` (JSON parsing), `sdd-traits.sh` (existing), `bd` CLI (beads), Claude Code Agent Teams
- 005-teams-traits: Added Bash (POSIX-compatible) + Markdown + `jq` for JSON parsing + `sdd-traits.sh` (existing), Claude Code Agent Teams (experimental, `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`), `bd` CLI (beads, for teams-spec only)
- 004-brainstorm-persistence: Added Markdown (skill prompt definition) + Existing brainstorm skill, filesystem (mkdir, ls), existing spec creation flow


<!-- MANUAL ADDITIONS START -->
<!-- MANUAL ADDITIONS END -->
