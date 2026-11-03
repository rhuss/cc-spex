# Research: Modernize Generated Permission Rules

## R1: Bare tool names vs `Tool(*)`

- **Decision**: Write `Bash`, `Read`, `Edit`, `Write` (bare).
- **Rationale**: Claude Code 2.1.317 warns that `Read(*)`, `Edit(*)`, `Write(*)` now mean "working directories only" and that the bare name allows every path. Older releases treat `Tool(*)` as `Tool`, so the bare name means the same in all supported versions. `Bash(*)` is normalized for consistency; bare `Bash` has always meant every command.
- **Alternatives**: Version-gated output (rejected, no behavioral difference); `Read(**)`/`Read(/**)` (rejected, still path-scoped syntax with unclear semantics across versions).

## R2: Where the logic lives

- **Decision**: One POSIX sh script, `spex/scripts/spex-permissions.sh`, with `migrate` and `apply`.
- **Rationale**: Constitution VII and FR-016. The skill's prose jq merge is non-deterministic. `setup.yml` and `spex-init.sh` already call scripts from `spex/scripts/` by path. The `apply` subcommand takes the rule list as arguments, so the existing per-caller lists (which differ between `setup.yml` and the skill) stay where they are and do not get unified as a side effect.
- **Alternatives**: Python helper next to `spex-setup-profile.py` (rejected: the task is pure JSON list editing, which jq handles; sh matches neighboring scripts); inline jq in each caller (rejected by the user in review-spec).

## R3: Output channel

- **Decision**: All messages on stderr.
- **Rationale**: The `specify` workflow engine stores step stderr in run state, and `spex-setup-report.sh` relays selected step ids. `spex-init.sh` output reaches the skill either way.

## R4: Writing safely

- **Decision**: Temp file in the resolved target's directory, then `mv`; resolve symlinks first; copy the file mode; write only when the allow list changed.
- **Rationale**: FR-008 (exact bytes on no-op), FR-011a (original intact on failure), symlink edge case. The existing `jq > TMP; mv` pattern in `setup.yml` truncates the file on jq failure, which `apply` fixes as a side benefit.
- **Symlink resolution**: Loop over `readlink` (POSIX-available on macOS and Linux without `-f`) until the path is not a link, resolving relative targets against the link's directory.

## R5: Deduplication scope

- **Decision**: Only the four bare names, and only when a rewrite happened (FR-006 as amended by review).
- **Rationale**: Keeps the "no-op without legacy rules" promise and leaves user duplicates alone.

## R6: Invalid settings in `apply`

- **Decision**: Warn and exit 0 without writing.
- **Rationale**: Failing setup over a broken personal settings file blocks extension setup for an unrelated reason; overwriting it loses hooks. The warning is relayed by the setup report and by Step 4.
