# Brainstorm: Update Check on Init

**Date:** 2026-07-04
**Status:** active
**Issue:** https://github.com/rhuss/cc-spex/issues/12

## Problem Framing

Users have no signal that a newer cc-spex release is available. The plugin pins a version at install time, and nothing nudges users when they fall behind. This was reported in #12 where a user sat on 5.6.0 without realizing 5.8.0 had shipped. The fix should be lightweight, harness-agnostic (works for Claude Code, Codex, OpenCode), and fail silently on network errors.

Additionally, the project lacks a clean versioning scheme for development builds between releases. Currently the version in `marketplace.json` is only bumped at release time, leaving no way to distinguish "released 5.9.0" from "unreleased work after 5.9.0."

## Approaches Considered

### A: Inline check in spex-init.sh (chosen)
- Add update check directly to `spex-init.sh`, no new scripts
- Read local version from a `VERSION` file at plugin root
- Curl GitHub releases API with short timeout, silent fail on network error
- Compare versions with semver logic, warn if behind
- Pros: simplest possible implementation, no caching, no background processes, harness-agnostic
- Cons: adds a brief network call to every init run (mitigated by short timeout)

### B: Separate version-check script
- Extract check into standalone `spex-version-check.sh` called from init
- Pros: reusable for future `/spex:version` command or statusline
- Cons: over-generalizes for current needs, adds unnecessary moving parts given the goal of harness-agnostic simplicity

### C: Cached check with JSON file
- Separate script plus a JSON cache at `~/.cache/cc-spex/` with 24h TTL
- Pros: avoids redundant API calls, enables statusline reads
- Cons: most complex, cache invalidation edge cases, over-engineered for init-only use

## Decision

Approach A: inline check in spex-init.sh. Keeps it simple with no extra files or caching. The check runs during init, which already does heavier work (installing extensions, configuring statusline). A 2-3 second timeout on the API call is acceptable.

## Key Requirements

1. **VERSION file**: create at repo root as the single source of truth for the project version (e.g., `5.9.0` or `5.9.1-dev`)
2. **Dev versioning**: after each release, VERSION bumps to `{patch+1}-dev` (e.g., release `5.9.0`, then VERSION becomes `5.9.1-dev`). Per semver, `-dev` is a pre-release identifier, so `5.9.1-dev < 5.9.1`.
3. **marketplace.json sync**: the `make release` target reads VERSION and updates `.claude-plugin/marketplace.json` version field before tagging
4. **make release automation**: reads VERSION, updates marketplace.json, commits, creates git tag `vX.Y.Z`, pushes, bumps VERSION to next-dev, commits, pushes
5. **Update check in init**: read VERSION from plugin root, curl GitHub releases API (`https://api.github.com/repos/rhuss/cc-spex/releases/latest`) with 2-3s timeout, compare versions
6. **Warning output**: version-only message like `spex update available: 5.8.0 -> 5.9.0` with no harness-specific update instructions (users know their harness)
7. **Silent cases**: equal version, ahead of latest release, running a `-dev` build, network unreachable
8. **No `--update` recommendation**: the warning must NOT suggest `spex:init --update` since that updates the `specify` CLI, not the spex plugin itself. Plugin updates go through the harness plugin mechanism.
9. **Breaking change notices**: when the latest release body contains lines starting with `BREAKING:`, extract and display them alongside the version warning. This uses the same releases API response (no extra call). For major version bumps (e.g., 5.x to 6.0), the release notes should include `BREAKING:` lines describing migration requirements. The VERSION file stays single-line; breaking info lives in GitHub release notes.

## Open Questions

- Should the update check also run during `--refresh` and `--update` modes, or only on normal init?
- Should the repo URL for the API call be hardcoded or derived from git remote? (Hardcoded is simpler and works when spex is installed as a plugin, not cloned)
