# Research: Detach Exclude Gap and Config Loss on Refresh

## R1: Where to hook "write + verify" so every setup path is covered

- **Decision**: Run it at the end of `spex/scripts/spex-apply-extensions.sh`, whenever spex-detach is enabled in the registry after the selection loop. The legacy no-declaration path in `spex-init.sh` (`run_detach_enable`) calls the same detach subcommand, but only when `install_extensions` did not already go through `spex-apply-extensions.sh` in this run.
- **Rationale**: All selection paths converge on `spex-apply-extensions.sh`: the `apply-extensions` step of `spex/setup.yml` (Codex setup, and Claude `/spex:init` without flags, since `spex-init.sh` delegates to the workflow; `--refresh` and `--update` call `install_extensions` directly), the init skill's Step 2 block (interactive Claude selection), and `install_extensions` in `spex-init.sh` when a declaration exists. The only path that bypasses it is the legacy no-declaration path, where `run_detach_enable` already runs after the previous enabled state is restored.
- **Alternatives considered**:
  - A separate `setup.yml` step after `apply-extensions`: misses the init skill's own `spex-apply-extensions.sh` call, which is exactly the corgi path.
  - Fixing only the init skill markdown: misses Codex setup and refresh; puts logic in skill prose (violates Constitution VII).
  - Relying on the extension's `after_init` hook: `/spex:init` never fires it.

## R2: How to verify a configured exclude entry

- **Decision**: New `spex-detach.py verify` subcommand. For each configured entry (skipping blank lines, comments, and `!` negations):
  - Directory entry (ends with `/`): probe `<entry><probe-name>` (a file under it).
  - Glob entry (contains `*`, `?` or `[`): probe a synthetic name derived from the glob (`**` and `*` become `spex-probe`, `?` becomes `x`, a bracket class becomes its first character).
  - Plain file entry: probe the path itself.
  - A leading `/` (anchored) or `**/` prefix is stripped to build the probe path.
  - Probes are checked with `git check-ignore -q -- <probe>` (index-aware; probes are never created on disk).
  - Additionally, `git ls-files -- <entry-path>` non-empty marks the entry visible with reason `tracked`, because an untracked probe under a tracked directory still reports ignored.
  - Re-include probes: `.specify/spex.json` and `.specify/memory/constitution.md` are checked when a configured entry covers them (directory prefix match, or `fnmatch` for globs).
- **Rationale**: `git check-ignore` is git's own answer, so verification cannot disagree with what `git add` does. The review-spec stage confirmed by experiment that probe-only checks miss tracked content.
- **Alternatives considered**: Parsing `.git/info/exclude` textually (does not account for negations, `.gitignore`, global excludes); creating real probe files (side effects, races with concurrent sessions).

## R3: "Repair" vs. first-time write

- **Decision**: `spex-detach.py ensure [--was-enabled]` runs `enable` then `verify`. When entries were added and `--was-enabled` is set, it reports `Repaired stealth mode: added <paths>`; when entries were added without the flag, it reports `Stealth mode: exclude entries written: <paths>`. `spex-apply-extensions.sh` passes `--was-enabled` when the reference state (the `--before` snapshot if it knows spex-detach, else the registry state before the loop) shows spex-detach enabled.
- **Rationale**: Reuses the reference-state logic apply-extensions already uses for its `Enabled:` lines. Keeps the decision in one script.
- **Alternatives considered**: Separate `repair` subcommand (duplicates enable+verify); inferring from the marker comment (the corgi case had entries without the marker).

## R4: Preserving the detach configuration across reinstall

- **Decision**: New canonical script `spex/scripts/spex-detach-config.sh` with `save` and `restore`:
  - `save`: if `.specify/extensions/spex-detach/spex-detach-config.yml` exists, copy it (`cp -p`) to `.specify/.spex-detach-config.saved.yml`. Copy failure exits 1 with `ERROR: cannot save .specify/extensions/spex-detach/spex-detach-config.yml ...`. If the config is missing but a saved copy exists (left by an interrupted run), keep the saved copy. Otherwise no-op.
  - `restore`: if a saved copy exists, move it over the (template) config; failure exits 1 with an error naming both files and leaves the saved copy in place. No saved copy: no-op (template stays, FR-008).
  - `setup.yml`: a new `save-detach-config` step right after `validate-source`, before `snapshot-registry` (the first step that can change the project; `install-ext-spex` is the first that uninstalls); `install-ext-spex-detach` calls `restore` after `specify extension add`.
  - `spex-init.sh`: `save` in the main `case` before `do_refresh`, `do_update` and the legacy path (exit 1 on failure), `restore` in `install_extensions` right after spex-detach is re-added.
- **Rationale**: Satisfies FR-009 ("save before any extension is uninstalled; on failure stop before anything is changed"). Independent of whether `specify extension add` overwrites a kept config, so `--keep-config` is not relied on. The saved file lives under `.specify/`, which is outside the extension directory that `remove` deletes, and is excluded from git by spex's own rules.
- **Alternatives considered**: `specify extension remove --keep-config` (behavior of the subsequent `add` on an existing config is unverified and upstream-owned); skipping reinstall of spex-detach (leaves it on an older version, rejected in review-spec).

## R5: Output channel

- **Decision**: All human lines go to stderr (convention of `spex-apply-extensions.sh`; `spex-setup-report.sh` already relays the whole `apply-extensions` step stderr). `verify` and `ensure` print a JSON result on stdout, like the other detach subcommands. `verify` exits 0 when every entry is ignored, 1 when any is visible, 2 on error. Callers never fail setup on exit 1 (FR-004).

## R6: Tests

- **Decision**:
  - `tests/test_spex_detach.sh`: `verify` (directory, file, glob entries; tracked path; re-include probes; negation skipped), `ensure` (written vs. repair message, idempotence).
  - `tests/test_apply_extensions.sh`: detach selected → entries written and verified; snapshot shows detach enabled + entries missing → repair message; detach not selected → no stealth output, exclude file untouched.
  - New `tests/test_detach_config_preserve.sh`: save/restore round trip (byte-identical), no config, stale saved copy, save failure (unwritable destination) exits 1 and leaves the config.
  - `tests/test_workflow_setup.sh`: end-to-end with the real `specify` CLI: setup with spex-detach, customized config survives a refresh (hash compare), probes under all paths ignored, second refresh adds no duplicate lines.
  - Makefile: new `test-detach` target running the detach and preserve tests.
