# Feature Specification: Update Check on Init

**Feature Branch**: `feat/001-update-check`
**Created**: 2026-07-04
**Status**: Draft
**Input**: User description: "Add update check to spex-init.sh, VERSION file as source of truth, dev versioning, make release automation, breaking change notices from GitHub release notes"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Update notification on init (Priority: P1)

A user runs `/spex:init` (or the init script runs automatically). The init script reads the local VERSION file, queries the GitHub releases API for the latest release, and compares versions. If the user is behind, a single-line warning appears in the init output showing the local and latest versions. If the network is unreachable or the API fails, nothing happens. The user is never blocked.

**Why this priority**: This is the core ask from issue #12. Users currently have no signal that they're behind, leading to missed releases.

**Independent Test**: Run `/spex:init` with a VERSION file set to an older version than the latest GitHub release. Verify the warning appears. Then disconnect from network and verify init completes silently.

**Acceptance Scenarios**:

1. **Given** VERSION contains `5.8.0` and the latest GitHub release is `v5.9.0`, **When** the user runs `/spex:init`, **Then** the output includes `spex update available: 5.8.0 -> 5.9.0`
2. **Given** VERSION contains `5.9.0` and the latest GitHub release is `v5.9.0`, **When** the user runs `/spex:init`, **Then** no update message appears
3. **Given** VERSION contains `5.9.1-dev` and the latest GitHub release is `v5.9.0`, **When** the user runs `/spex:init`, **Then** no update message appears (dev build is ahead)
4. **Given** the GitHub API is unreachable (network down, DNS failure, timeout), **When** the user runs `/spex:init`, **Then** no update message appears and init completes normally
5. **Given** VERSION contains `5.7.0` and the latest release is `v6.0.0` with `BREAKING: Major restructuring` in the release body, **When** the user runs `/spex:init`, **Then** the warning includes the breaking change notice alongside the version info

---

### User Story 2 - VERSION file as version source of truth (Priority: P1)

A VERSION file at the repository root contains the current project version as a single line (e.g., `5.9.0` or `5.9.1-dev`). This file is the canonical version source. The marketplace.json version field is derived from VERSION during release, not maintained independently.

**Why this priority**: Without a clear version source of truth, the update check has nothing to compare against. This also eliminates the current problem of marketplace.json being the only version record.

**Independent Test**: Read the VERSION file and verify it contains a valid semver string. Verify marketplace.json version matches (after release) or VERSION has `-dev` suffix (between releases).

**Acceptance Scenarios**:

1. **Given** a fresh clone of the repository, **When** the VERSION file is read, **Then** it contains a single line with a valid semver version (e.g., `5.9.1-dev`)
2. **Given** a tagged release at `v5.9.0`, **When** marketplace.json is inspected, **Then** its version field reads `5.9.0` (matching the VERSION file at tag time)

---

### User Story 3 - Automated release workflow (Priority: P2)

A maintainer runs `make release` to publish a new version. The target reads VERSION (e.g., `5.9.0`), updates the marketplace.json version field, commits the change, creates a git tag `v5.9.0`, pushes the commit and tag, then bumps VERSION to `5.9.1-dev`, commits, and pushes. One command handles the entire release cycle.

**Why this priority**: Automates the release process and ensures VERSION and marketplace.json stay in sync. Also ensures the dev suffix is always applied after release.

**Independent Test**: Set VERSION to a test version, run `make release` in a dry-run mode or test repo, verify marketplace.json was updated, tag was created, and VERSION was bumped to the next dev version.

**Acceptance Scenarios**:

1. **Given** VERSION contains `5.9.0`, **When** `make release` runs, **Then** marketplace.json version is updated to `5.9.0`, a commit is created, tag `v5.9.0` is created, everything is pushed, VERSION is bumped to `5.9.1-dev`, a second commit is created, and that commit is pushed
2. **Given** VERSION contains `5.9.1-dev`, **When** `make release` runs, **Then** it fails with an error because releasing a dev version requires first removing the `-dev` suffix
3. **Given** tag `v5.9.0` already exists, **When** `make release` runs with VERSION `5.9.0`, **Then** it fails with a "tag already exists" error (existing behavior preserved)

---

### Edge Cases

- What happens when the VERSION file is missing? The update check MUST skip silently (no crash).
- What happens when the GitHub API returns an unexpected response format? The check MUST skip silently.
- What happens when the VERSION file contains an invalid format (not semver)? The check MUST skip silently.
- What happens when curl is not available? The check MUST skip silently (curl availability is not guaranteed on all systems).
- What happens when the GitHub API rate limit is exceeded (60/hr for unauthenticated)? The check MUST skip silently (same as network error).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: A `VERSION` file MUST exist at the repository root containing a single line with the project version in semver format (e.g., `5.9.0` or `5.9.1-dev`)
- **FR-002**: The `spex-init.sh` script MUST read the VERSION file from the repository root on every init run (resolved by traversing up from the plugin root, as clarified in Session 2026-07-04)
- **FR-003**: The init script MUST query the GitHub releases API endpoint for the latest release with a maximum timeout of 3 seconds
- **FR-004**: The init script MUST compare the local version against the latest release version using semver comparison logic
- **FR-005**: When the local version is behind the latest release, the init script MUST print a warning line in the format `spex update available: <local> -> <latest>`
- **FR-006**: The warning MUST NOT include any harness-specific update instructions or recommend `--update`
- **FR-007**: When the latest release body contains lines starting with `BREAKING:`, those lines MUST be extracted and displayed below the version warning
- **FR-008**: The update check MUST be completely silent when: versions are equal, local version is ahead of latest, local version has a `-dev` suffix, network is unreachable, API returns an error, or curl is unavailable
- **FR-009**: The `make release` target MUST read VERSION, update `.claude-plugin/marketplace.json` version field, commit, create a git tag, push, bump VERSION to next dev version, commit, and push
- **FR-010**: After release, VERSION MUST be bumped to `{patch+1}-dev` (e.g., `5.9.0` releases, VERSION becomes `5.9.1-dev`)
- **FR-011**: The `make release` target MUST refuse to release a `-dev` version (VERSION must not contain `-dev` suffix)
- **FR-012**: The GitHub API URL (`https://api.github.com/repos/rhuss/cc-spex/releases/latest`) MUST be hardcoded, not derived from git remote (works when installed as a plugin, not just when cloned)

### Key Entities

- **VERSION file**: Single-line file at repo root containing the current semver version string. Canonical source of truth for the project version.
- **marketplace.json**: Plugin manifest at `.claude-plugin/marketplace.json` containing the `version` field. Derived from VERSION during release.
- **GitHub Release**: Tagged release on GitHub with version tag (e.g., `v5.9.0`) and release body that may contain `BREAKING:` lines.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users running an outdated version see the update notification within the first 3 seconds of init (bounded by API timeout)
- **SC-002**: The update check adds zero delay to init when the network is unavailable (timeout-bounded, no retry)
- **SC-003**: The release process completes in a single `make release` command with no manual steps
- **SC-004**: VERSION file and marketplace.json are always in sync after any release

## Smoke Test

1. Set VERSION to an older version (e.g., `5.8.0`), run the init script, and verify the update warning appears with the correct local and latest versions
2. Disconnect from the network, run the init script, and verify it completes normally with no update-related output or errors
3. Run `make release` in a test scenario and verify the full flow: marketplace.json update, tag creation, dev version bump

## Clarifications

### Session 2026-07-04

- Q: Should VERSION live at the repo root or the plugin root (spex/)? → A: Repo root. VERSION is a project-level artifact. The init script resolves it relative to its own location by traversing up from the plugin root.

## Out of Scope

- Automatic updates or self-update mechanisms (the check is informational only)
- Caching of version check results between init runs
- Displaying full changelogs or release notes beyond `BREAKING:` lines
- Support for pre-release version channels or update tracks
- Version checking on any command other than init (normal and `--refresh` modes)

## Assumptions

- The GitHub releases API for public repos is available without authentication (rate-limited to 60 requests/hour per IP)
- `curl` and `jq` are available on the user's system (both are already dependencies of the init script for other operations)
- The VERSION file format is a single line with no trailing newline requirements
- The `-dev` suffix follows semver pre-release conventions where `5.9.1-dev < 5.9.1`
- The update check runs during normal init and `--refresh` modes but not during `--clear` mode
