# Review Guide: Workflow-Based Setup

**Generated**: 2026-07-07 | **Spec**: [spec.md](spec.md)

## Why This Change

Spex's installation and setup logic lives in a 400-line bash script (`spex-init.sh`) that only works on Claude Code. Every new agent harness or extension requires more branches in this centralized script, maintained by someone who didn't write the extension. The spec-kit workflow engine already has everything needed to express this setup logic as declarative YAML with per-agent branching, making spex installable on any spec-kit-supported harness with a single command.

## What Changes

`spex-init.sh` is replaced by a spec-kit setup workflow (`setup.yml`) as the primary install mechanism. The workflow installs all spex extensions, auto-detects the agent harness (Claude Code, Codex, OpenCode), applies per-agent configuration (permissions, hooks, context files), and optionally offers interactive extension selection. Users install spex via `specify workflow run <url>` regardless of their harness. The Claude Code plugin stays as a compatibility shim that delegates to the workflow. No breaking changes for existing users: the plugin's `/spex:init` falls through to the legacy path if `specify` CLI is not available.

## How It Works

The setup workflow (`spex/setup.yml`) uses spec-kit's workflow engine with `shell`, `switch`, `if`, and `prompt` step types:

1. **Version check**: Validates `specify` CLI >= 0.7.4
2. **Init**: Runs `specify init` with the detected or specified integration
3. **Agent detection**: Runs `detect-agent.sh` when integration is "auto" (checks env vars, directory presence, init-options.json)
4. **Extension install**: 7 sequential `specify extension add` calls in dependency order (spex first, then gates, worktrees, deep-review, teams, collab, detach)
5. **Extension selection**: `if` step that either prompts for interactive selection, applies a `--set extensions=<list>` override, or keeps all enabled (default)
6. **Harness adaptation**: `switch` on detected integration with branches for Claude (settings.json, statusline, hooks), Codex (.codex/hooks.json, AGENTS.md), OpenCode (.opencode/plugins/, AGENTS.md), and a neutral default
7. **Permissions**: Nested `switch` for standard/yolo/none permission profiles per harness
8. **Housekeeping**: gitignore, constitution migration, version check

A `bundle.yml` declares the distribution metadata (provenance, extension list) but is not required for installation. The workflow is self-contained.

`spex-init.sh` gains delegation logic: if `specify` CLI is available and `setup.yml` exists, it delegates. Otherwise it falls through to the legacy init path.

## When It Applies

**Applies when**:
- Installing spex on any agent harness (Claude Code, Codex, OpenCode, or others)
- Reinstalling or refreshing an existing spex installation
- Setting up a new project with spex extensions
- Migrating from the Claude Code plugin-only install path

**Does not apply when**:
- Rewriting command content to remove Claude Code-specific tool references (e.g., `Agent`, `AskUserQuestion`). That is command content neutralization (brainstorm #28, separate feature).
- Renaming the repository from `cc-spex` to `spex`. Deferred until the workflow setup is proven.
- Deprecating the Claude Code plugin. The plugin stays as a compatibility shim.

## Key Decisions

1. **Workflow-first distribution (not bundle-first)**: `specify workflow run <url>` is the single-command entry point. The workflow calls `specify extension add` directly. This follows spec-kit's canonical pattern where bundles install artifacts and workflows run logic, deliberately separated. A bundle manifest exists for provenance but is not the install mechanism.

2. **Check-and-skip idempotency**: Re-running the workflow skips already-installed extensions (relying on `specify extension add`'s existing-check behavior) and merges permission entries into existing config files. This preserves any user customizations rather than overwriting them.

3. **OpenCode as the third harness**: SC-003 requires 3 harnesses. OpenCode was chosen over Cursor because it already has adapter scripts (`spex/scripts/adapters/opencode/`) and brainstorm #15 explored its adaptation.

4. **Prompt step with fallback for extension selection**: The `prompt` step asks the AI agent to present extension choices via its native mechanism. If the harness can't handle structured prompts, the workflow falls back to installing all extensions and logging a message about `specify extension disable`. This degrades gracefully rather than blocking setup.

5. **Workflow-enforced dependency ordering**: Extensions are installed sequentially in the correct order (spex before spex-gates before spex-teams) via sequential `shell` steps. This does not depend on `specify bundle install` handling ordering.

## Areas Needing Attention

- **Prompt step UX is unvalidated**: Phase 1 (T001-T003) validates the workflow engine capabilities before proceeding. If `prompt` steps can't drive interactive selection reliably, the fallback strategy (install all, suggest `specify extension disable`) is the safety net. This is the highest-risk assumption in the spec.

- **Remote URL install requires repo cloning**: When running from a GitHub URL, the workflow downloads only the YAML file, not the extensions. The workflow clones the repo to a temp directory, installs from the clone, and cleans up. This adds latency and requires git. Local clone users don't have this overhead.

- **Permission merge complexity**: The check-and-skip strategy for permissions requires reading existing JSON config, adding new entries, and writing back without clobbering user additions. JSON merge in a `shell` step is doable with `jq` but error-prone for deeply nested structures.

- **Legacy init fallback in spex-init.sh**: The delegation logic means `spex-init.sh` has two code paths (workflow delegation vs legacy). Both must produce functionally equivalent results on Claude Code, which doubles the testing surface.

## Open Questions

- Can workflow step outputs (from `shell` steps) be reliably referenced in subsequent `switch` expressions via `{{ steps.<id>.output }}`? Validated in Phase 1 (T002).
- Will `specify workflow run <https-url>` handle GitHub release asset URLs correctly (redirects, authentication for private repos)?
- How does the `prompt` step interact with each harness's native prompt mechanism? Does the agent see the prompt text and can it respond with structured data?

## Review Checklist

- [ ] Key decisions are justified
- [ ] Breaking changes are documented with migration guidance
- [ ] Scope matches the stated boundaries
- [ ] Success criteria are achievable
- [ ] No unstated assumptions
- [ ] Phase 1 validation gate adequately covers workflow engine risks
- [ ] Idempotency strategy handles all config file formats (JSON, YAML, INI)
- [ ] All 3 harness branches (Claude, Codex, OpenCode) have equivalent coverage

---

<!-- Code phase sections are appended below this line by the phase-manager command -->
