# Code Review: Replace Traits with Spec-Kit Extensions

**Spec:** specs/016-traits-to-extensions/spec.md
**Date:** 2026-04-18
**Compliance Score:** 90% (12/13 FR compliant)

---

## Code Review Guide (30 minutes)

> This section guides a code reviewer through the implementation changes,
> focusing on high-level questions that need human judgment.

**Changed files:** ~35 files changed across 5 extension bundles, 2 scripts, 1 test suite, 1 constitution, 1 marketplace manifest

### Understanding the changes (8 min)

- Start with `spex/extensions/spex/extension.yml`: This is the core extension manifest that replaced the old commands directory. All 9 core commands are registered here. Understanding this manifest pattern is key to understanding all 5 extensions.
- Then `spex/scripts/spex-init.sh`: The `install_extensions()` function (line 183) is the new entry point that replaced `apply_traits()`. It loops over bundled extensions and installs each via spec-kit's native mechanism.
- Question: Is the extension-per-capability decomposition the right granularity? Could spex-gates and spex-deep-review be a single extension, or does the current split make enable/disable more useful?

### Key decisions that need your eyes (12 min)

**Ship-guard as inline behavior** (`spex/extensions/spex/commands/speckit.spex.ship.md`)

Each extension command checks `.spex-state` itself instead of receiving injected overlay content. This distributes the autonomous-mode logic across all command files.
- Question: Is this better than the centralized overlay approach? The benefit is no content injection, but the cost is that every command must independently check `.spex-state`.

**Config file paths** (`spex/extensions/spex-deep-review/config-template.yml`, relates to [FR-005](spec.md#fr-005))

External tools config moved from `.specify/spex-traits.json` (flat) to `.specify/extensions/spex-deep-review/deep-review-config.yml` (per-extension). Commands reference this path directly.
- Question: Is hardcoding the config path in commands correct, or should there be an indirection layer via the registry?

**Teams as standalone command, not hook** (`spex/extensions/spex-teams/commands/speckit.spex-teams.implement.md`, relates to [Clarification Q1](spec.md#clarifications))

Teams implement is invoked directly (by ship or user), not via a hook. This keeps the hook contract clean but means the ship command needs routing logic.
- Question: Is the current missing routing in ship (FR-008 deviation) acceptable as-is, given that the CLAUDE.md teams trait section already handles routing via overlay injection?

### Areas where I'm less certain (5 min)

- `spex/extensions/spex-teams/extension.yml` and `spex/extensions/spex-deep-review/extension.yml`: Both are missing `requires.extensions` declarations for their dependency on spex-gates. The dependency is documented in [R5](research.md) but not enforced in manifests. If spec-kit validates dependencies on enable, this could cause silent failures.
- `spex/scripts/spex-ship-statusline.sh:29-41`: The `read_extensions()` function reads from `.specify/extensions/.registry` to display enabled extensions. I'm not 100% certain the jq query matches the actual registry format produced by spec-kit. The registry format was inferred from documentation, not verified against a live install.
- `tests/test_marketplace_install.sh:237-252`: The extension manifest validation uses `yq` to parse YAML, which may not be available in all CI environments.

### Deviations and risks (5 min)

- `spex/extensions/spex/commands/speckit.spex.ship.md` Stage 6: Ship always invokes `/speckit-implement` without checking spex-teams status. [FR-008](spec.md#fr-008) requires routing to `speckit.spex-teams.implement` when teams is enabled and tasks have 2+ independent tasks. Question: "Should this routing be added to ship, or is the existing CLAUDE.md overlay-based routing sufficient during the transition?"
- The `DEFAULT_ENABLED` variable is referenced at line 130 of `speckit.spex.ship.md` but was removed during the traits-to-extensions migration. This is a stale reference that won't cause errors (yq returns empty) but is misleading.
