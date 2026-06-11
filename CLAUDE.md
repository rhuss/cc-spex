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

- `spex`: Core extension with brainstorm, ship, flow state, and methodology entry point
- `spex-gates`: Quality gates on speckit commands (review-spec, review-code, review-plan, stamp, verification)
- `spex-worktrees`: Git worktree isolation after speckit.specify (creates sibling worktree, restores main)
- `spex-teams`: Parallel implementation via Claude Code Agent Teams (experimental)
- `spex-deep-review`: Multi-agent code review with 5 specialized review agents and autonomous fix loop
- `spex-collab`: Collaborative PR workflows (REVIEWERS.md, phase-split, phase-manager, revise, reconcile)

## Documentation Maintenance

When adding, removing, or changing features, commands, extensions, or workflows, ALWAYS update the documentation in the same change:

- **README.md**: Workflow section, Commands Reference table, extension descriptions, flowchart
- **spex/docs/help.md**: Quick reference commands, extensions, PR conventions
- **Constitution** (`.specify/memory/constitution.md`): If the change introduces a new architectural principle

Do not treat documentation as a follow-up task. Stale docs mislead users and erode trust.

## Recent Changes

- 016-traits-to-extensions: Migrated traits to extension bundles, renamed commands from `/spex:*` to `speckit-spex-*` prefix

<!-- SPECKIT START -->
For additional context about technologies to be used, project structure,
shell commands, and other important information, read the current plan
at specs/025-guided-smoke-test/plan.md
<!-- SPECKIT END -->
