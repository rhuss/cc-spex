# Validation evidence: First-Class Codex Plugin Support

## Claude regression baseline

Before feature 047, the isolated Claude marketplace lifecycle passed all
applicable acceptance assertions (100%). The harness-specific suite now treats
that 100% value as a release floor and fails if the post-feature rate is lower.

## Automated evidence

- Contract schemas and fixtures: passed.
- Claude/Codex deterministic materialization and strict validation: passed.
- Codex init/refresh/first-command journey: 12/12 passed.
- Worktree lifecycle: 100 runs, zero wrong-checkout mutations.
- Recovery, progress, Teams isolation, and sequential fallback: passed.
- Claude-only and combined installation/coexistence: passed.
- Aggregate `make test`: passed on macOS with no skips.
- Pre-tag `make release-check`: passed without creating a tag.

The controlled 20-user SC-001 study remains external acceptance work and is
not represented by automated fixtures.
