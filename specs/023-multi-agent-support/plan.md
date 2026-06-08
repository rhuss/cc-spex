# Implementation Plan: Multi-Agent Harness Support

**Branch**: `023-multi-agent-support` | **Date**: 2026-06-08 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `specs/023-multi-agent-support/spec.md`

## Summary

Make spex's enforcement model portable across Claude Code, Codex CLI, and OpenCode by creating per-agent hook adapters that share enforcement logic via POSIX shell functions, generating agent-optimized instruction files, and adapting all extensions for multi-agent operation.

## Technical Context

**Language/Version**: Bash (POSIX-compatible), Python 3 (existing hooks), TypeScript (OpenCode plugin)
**Primary Dependencies**: `jq`, `specify` CLI (spec-kit), agent CLIs (Claude Code, Codex, OpenCode)
**Storage**: File-based state (`.specify/.spex-state`, marker files in `$TMPDIR`)
**Testing**: `make release` (schema validation + integration test), manual testing per agent
**Target Platform**: macOS, Linux (developer workstations)
**Project Type**: CLI plugin (skill/command/hook framework)
**Constraints**: No compiled artifacts, no package dependencies beyond `jq` and `specify` CLI
**Scale/Scope**: 2 new agent adapters, 6 extensions to adapt, ~66 AskUserQuestion call sites

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Spec-Guided Development | PASS | Feature follows full SDD workflow |
| II. Extension Architecture | PASS | Hook adapters extend the existing extension pattern. Extensions remain self-contained and portable. |
| III. Extension Composability | PASS | Agent adapters are independent. Enabling one agent doesn't affect others. |
| IV. Quality Gates | PASS | Existing gates preserved, adapter layer adds agent dispatch |
| V. Naming Discipline | PASS | Hook adapters follow `spex/hooks/{agent}/` naming. Commands keep `/speckit-*` prefix. |
| VI. Skill Autonomy | PASS | Each adapter is self-contained. Shared logic lives in scripts, not duplicated in skills. |
| VII. State as Scripts | PASS | Enforcement logic in shell scripts, not inline markdown. Adapters invoke scripts. |

No violations. No complexity tracking needed.

## Project Structure

### Documentation (this feature)

```text
specs/023-multi-agent-support/
├── plan.md              # This file
├── spec.md              # Feature specification
├── research.md          # Phase 0: agent hook contracts
├── data-model.md        # Phase 1: agent capability profiles
├── checklists/          # Quality checklists
└── tasks.md             # Phase 2: task breakdown
```

### Source Code (repository root)

```text
spex/
├── scripts/
│   ├── hooks/
│   │   ├── context-hook.py          # Existing Claude Code hook (unchanged)
│   │   ├── pretool-gate.py          # Existing Claude Code hook (unchanged)
│   │   └── shared/                  # NEW: shared enforcement logic
│   │       ├── detect-agent.sh      # Agent detection (env vars > dirs > init-options)
│   │       ├── skill-gate.sh        # Skill-first enforcement logic
│   │       ├── stage-gate.sh        # Ship pipeline stage ordering
│   │       ├── teams-gate.sh        # Teams enforcement logic
│   │       └── verify-gate.sh       # Verify-before-commit logic
│   ├── adapters/                    # NEW: per-agent hook adapters
│   │   ├── codex/
│   │   │   ├── context-hook.py      # Codex UserPromptSubmit adapter
│   │   │   └── pretool-gate.py      # Codex PreToolUse adapter
│   │   └── opencode/
│   │       └── spex-plugin.ts       # OpenCode plugin (tool.execute.before)
│   └── spex-init.sh                 # Updated: install correct adapter per agent
├── extensions/
│   ├── spex/commands/
│   │   └── speckit.spex.using-superpowers.md  # Updated: agent-aware tool references
│   ├── spex-gates/commands/         # Updated: AskUser wrapper pattern
│   ├── spex-teams/commands/         # Updated: agent-specific subagent dispatch
│   ├── spex-deep-review/commands/   # Updated: agent-specific review dispatch
│   ├── spex-collab/commands/        # Updated: AskUser wrapper pattern
│   └── spex-worktrees/commands/     # Updated: manual worktree fallback
├── templates/
│   ├── agents-md/                   # NEW: per-agent instruction templates
│   │   ├── claude.md                # Claude Code CLAUDE.md template
│   │   ├── codex.md                 # Codex AGENTS.md template
│   │   └── opencode.md              # OpenCode AGENTS.md template
│   └── skill-preamble/              # NEW: context injection for hookless agents
│       └── opencode-preamble.md     # Preamble snippet for OpenCode skills
└── docs/
    └── help.md                      # Updated: multi-agent section
```

**Structure Decision**: Hook adapters live under `spex/scripts/adapters/{agent}/` (parallel to existing `spex/scripts/hooks/`). Shared logic extracted to `spex/scripts/hooks/shared/`. Agent instruction templates under `spex/templates/agents-md/`. This keeps adapters close to the existing hook code while maintaining per-agent isolation.

## Implementation Approach

### Phase 1: Extract Shared Enforcement Logic

Refactor the existing `pretool-gate.py` and `context-hook.py` to extract enforcement decisions into POSIX shell functions under `spex/scripts/hooks/shared/`. The existing Python hooks become thin wrappers that call the shared functions and format responses for Claude Code's hook API.

This is a pure refactoring with zero behavior change on Claude Code. Validates the extraction before building adapters.

### Phase 2: Agent Detection

Create `detect-agent.sh` that identifies the running agent using the priority order from FR-008: (1) env vars, (2) directory presence, (3) init-options.json. Used by `spex-init.sh` to install correct adapters and by runtime logic to select behavior.

### Phase 3: Codex Adapter

Create Codex-specific hook scripts in `spex/scripts/adapters/codex/`. These read JSON from stdin per Codex's hook contract, call the shared shell functions for enforcement decisions, and format responses per Codex's expected output format. Since Codex has both UserPromptSubmit and PreToolUse, this is a 1:1 mapping.

### Phase 4: OpenCode Adapter

Create an OpenCode TypeScript plugin in `spex/scripts/adapters/opencode/spex-plugin.ts`. It subscribes to `tool.execute.before` events, calls the shared shell functions via `child_process.exec`, and denies/allows based on the result. For prompt interception (no hook equivalent), create a skill preamble snippet that OpenCode skills include.

### Phase 5: Agent-Optimized Instruction Files

Create per-agent instruction templates under `spex/templates/agents-md/`. Each template contains the correct tool names, enforcement expectations, AskUserQuestion fallback pattern, and context-clearing guidance for its agent. Update `spex-init.sh` to generate the right file during init.

### Phase 6: Extension Portability

Update all extension command files to use agent-aware patterns:
- Replace hard-coded `AskUserQuestion` with agent-neutral prompt pattern
- Add agent-specific subagent dispatch to spex-teams
- Add single-agent fallback to spex-deep-review
- Add manual worktree instructions to spex-worktrees
- Test spex-gates and spex-collab work without changes (they should)

### Phase 7: Documentation and Upstream Proposal

Update README.md, help.md with multi-agent section. Finalize the upstream spec-kit hook adapter proposal for review.
