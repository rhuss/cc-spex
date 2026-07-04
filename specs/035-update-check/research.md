# Research: Update Check on Init

## GitHub Releases API

**Decision**: Use `https://api.github.com/repos/rhuss/cc-spex/releases/latest` endpoint.
**Rationale**: Returns the single latest non-prerelease, non-draft release. No pagination needed. Response includes `tag_name` and `body` fields. Unauthenticated access is available for public repos at 60 requests/hour per IP.
**Alternatives considered**: `git ls-remote --tags` (heavier response, needs shell-based semver sorting), GitHub GraphQL API (requires authentication).

## Semver Comparison in Shell

**Decision**: Numeric component comparison using `cut` and arithmetic evaluation.
**Rationale**: POSIX shell can split on `.` with `cut -d. -f1,2,3` and compare integers with `-gt`, `-lt`, `-eq`. No external tools needed beyond basic shell builtins.
**Alternatives considered**: `sort -V` (not POSIX, unavailable on some macOS versions), `dpkg --compare-versions` (Debian-only), Python semver parsing (adds dependency).

## Dev Version Handling

**Decision**: Strip `-dev` suffix before comparison; treat any `-dev` version as "ahead" of its base.
**Rationale**: Per semver, `5.9.1-dev` is a pre-release of `5.9.1`, which means it's newer than `5.9.0` but older than `5.9.1`. Since the dev version exists only between releases, the user is always running code newer than the last release. Showing an update warning would be misleading.
**Alternatives considered**: Full semver pre-release comparison (over-complex for a single `-dev` identifier).

## Breaking Change Extraction

**Decision**: `grep` the release body for lines starting with `BREAKING:` and display them verbatim.
**Rationale**: Simple pattern matching. Release maintainers include `BREAKING:` prefixed lines in release notes when breaking changes exist. No structured format needed.
**Alternatives considered**: Parsing conventional commit messages from the release (too complex, requires structured commit format).

## VERSION File Location

**Decision**: Repository root (`VERSION`), not plugin root (`spex/VERSION`).
**Rationale**: The VERSION file is a project-level artifact consumed by the Makefile (which runs from the repo root). The init script resolves it relative to its own location by traversing up from the plugin scripts directory.
**Alternatives considered**: Plugin root (would require Makefile to navigate into `spex/` for version reads).
