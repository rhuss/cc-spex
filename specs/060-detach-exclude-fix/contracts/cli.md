# CLI Contracts

## `spex-detach.sh verify` (new)

Runs from the project root. Changes nothing.

- Reads the configured exclude entries (same reader as `enable`, defaults when the config is missing or unreadable).
- stdout: one JSON object
  ```json
  {
    "active": true,
    "verified": [".specify/", "specs/", "brainstorm/"],
    "visible": [{"entry": "specs/", "probe": "specs/.spex-detach-probe", "reason": "not-ignored|tracked"}],
    "reinclude_checked": [".specify/spex.json", ".specify/memory/constitution.md"]
  }
  ```
- stderr, all ignored: `Stealth mode: active (verified: <entries>)`
- stderr, any visible: `WARNING: stealth mode is NOT fully active. Still visible to git:` followed by one `  <entry> (<reason>)` line each (for a visible re-include probe: `  <file> (not-ignored, re-included under <entry>)`, so the line names the file that is still visible); for `tracked`, an extra hint that tracked files must be removed from history separately.
- Exit: 0 all ignored, 1 at least one visible, 2 not a git repository / usage error.

## `spex-detach.sh ensure [--was-enabled]` (new)

- Runs `enable`, then `verify`. Idempotent.
- stderr before the verify lines:
  - entries added and `--was-enabled`: `Repaired stealth mode: added <paths>`
  - entries added, no flag: `Stealth mode: exclude entries written: <paths>`
  - nothing added: no extra line
- stdout: JSON `{"enable": <enable result>, "verify": <verify result>}`
- Not a git repository: prints nothing, writes nothing, exit 2 (no `ERROR` line).
- enable's tracked-files warning is not printed inside `ensure` (verify's `tracked` lines cover it).
- Exit: verify's exit code (0/1), 2 on error or not a git repository.

## `spex-apply-extensions.sh` (changed)

After the selection loop, when the registry shows spex-detach enabled and `.specify/extensions/spex-detach/scripts/spex-detach.sh` is executable:

- Runs `spex-detach.sh ensure` (with `--was-enabled` when the reference state of spex-detach was enabled), relays its stderr, discards its stdout.
- A non-zero `ensure` exit does not change the script's exit code.
- When spex-detach is not enabled: no detach call and no extra output (FR-012).

## `spex-detach-config.sh save|restore` (new, canonical in `spex/scripts/`)

- Config: `.specify/extensions/spex-detach/spex-detach-config.yml`. Saved copy: `.specify/.spex-detach-config.saved.yml`.
- `save`: config exists → copy to saved (preserving content byte for byte); copy fails → `ERROR: cannot save <config> to <saved>; nothing was changed` on stderr, exit 1. Config missing and saved copy present → keep saved, exit 0. Neither → exit 0.
- `restore`: saved present → move over config, exit 0; move fails → `ERROR: cannot restore <config> from <saved>; your configuration is kept in <saved>`, exit 1. No saved copy → exit 0.

## Callers

- `spex/setup.yml`: new step `save-detach-config` right after `validate-source`, before `snapshot-registry` (runs `save`; non-zero fails the workflow before anything is changed). `install-ext-spex-detach` runs `restore` after `specify extension add` and before `specify extension disable`.
- `spex/scripts/spex-init.sh`: `save_detach_config` (runs `save`, exit 1 on failure) in the main `case` before `do_refresh`, `do_update` and the legacy path; `install_extensions` runs `restore` immediately after spex-detach is re-added. `run_detach_enable` calls `ensure` (with `--was-enabled`), is also called from `do_refresh` and `do_update`, and is skipped when `install_extensions` already applied the selection through `spex-apply-extensions.sh` in this run.
