# Research: Workflow-Based Setup

## Decision: Workflow as Primary Install Mechanism

**Chosen**: `specify workflow run <url>` as the single-command entry point
**Rationale**: Spec-kit's canonical pattern separates artifact installation (bundles) from logic execution (workflows). The maintainer explicitly recommended workflows over `on_install` hooks (#3359). A workflow can call `specify extension add` directly, making it self-contained.
**Alternatives considered**:
- `on_install` lifecycle hook: Rejected by spec-kit maintainer. Would make `specify extension add` a code-execution step, increasing trust surface.
- Bundle-first (`specify bundle install` then `specify workflow run`): Two commands. The workflow can do everything in one.

## Decision: Extension Source Access from Remote URL

**Chosen**: Workflow clones the repository to a temporary directory, installs from the clone, cleans up
**Rationale**: `specify workflow run <url>` only downloads the YAML file, not the extensions. The workflow needs extension source files for `specify extension add`. Cloning is the simplest approach that works offline after the initial clone.
**Alternatives considered**:
- Ship extensions as separate downloadable archives: Complex release process, no spec-kit support
- Embed extension content in the workflow YAML: Impractical for 7 extensions with scripts

## Decision: Agent Detection Strategy

**Chosen**: Reuse existing `detect-agent.sh` in a `shell` step, pass result to `switch`
**Rationale**: The detection script already handles Claude/Codex/OpenCode with a clean priority chain (env vars, directory presence, init-options.json). No need to reimplement.
**Alternatives considered**:
- Use `inputs.integration` auto-resolution in expression engine: Depends on `.specify/init-options.json` which may not exist yet during initial setup. The detect script handles the pre-init case.

## Decision: Interactive Extension Selection

**Chosen**: `prompt` step with fallback to "all" default
**Rationale**: The `prompt` step sends text to the AI agent, which uses its native mechanism (AskUserQuestion on Claude, equivalent elsewhere). If the prompt fails or the harness can't handle it, the workflow falls back to enabling all extensions with a log message about `specify extension disable`.
**Alternatives considered**:
- `gate` steps (one per extension): Deterministic but tedious (7 approve/reject prompts)
- Inputs-only (no interactive): Works for CLI/CI but not for first-time users who want guidance

## Decision: Idempotency via Check-and-Skip

**Chosen**: Skip already-installed extensions, merge permissions
**Rationale**: `specify extension add` already skips existing extensions. Permission files can be merged by reading existing JSON, adding new entries, and writing back. This preserves any user customizations.
**Alternatives considered**:
- Remove-and-reinstall: Loses user customizations
- Version-aware updates: Requires tracking installed versions, more complex than needed

## Finding: spex-init.sh Can Delegate Safely

The `do_init()` function in `spex-init.sh` can be modified to check for `specify` CLI and `setup.yml`, then delegate. The fallback path (legacy init) remains for users who don't have spec-kit installed yet. This makes the migration non-breaking: the plugin still works for CC-only users.

## Finding: Adapter Scripts Are Already Harness-Agnostic

The Codex adapter (`adapters/codex/context-hook.py`, `pretool-gate.py`) and OpenCode adapter (`adapters/opencode/spex-plugin.ts`) are already self-contained scripts that can be installed by the workflow's `switch` step. No new adapter code is needed.

## Finding: AGENTS.md Templates Exist

The `templates/agents-md/` directory already has `codex.md` and `opencode.md` templates. The workflow's adapt-harness step just copies the right one.
