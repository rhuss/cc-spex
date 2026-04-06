---
name: "speckit-plan"
description: "Execute the implementation planning workflow using the plan template to generate design artifacts."
argument-hint: "Optional guidance for the planning phase"
compatibility: "Requires spec-kit project structure with .specify/ directory"
metadata:
  author: "github-spec-kit"
  source: "templates/commands/plan.md"
user-invocable: true
disable-model-invocation: true
---


## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Pre-Execution Checks

**Check for extension hooks (before planning)**:
- Check if `.specify/extensions.yml` exists in the project root.
- If it exists, read it and look for entries under the `hooks.before_plan` key
- If the YAML cannot be parsed or is invalid, skip hook checking silently and continue normally
- Filter out hooks where `enabled` is explicitly `false`. Treat hooks without an `enabled` field as enabled by default.
- For each remaining hook, do **not** attempt to interpret or evaluate hook `condition` expressions:
  - If the hook has no `condition` field, or it is null/empty, treat the hook as executable
  - If the hook defines a non-empty `condition`, skip the hook and leave condition evaluation to the HookExecutor implementation
- For each executable hook, output the following based on its `optional` flag:
  - **Optional hook** (`optional: true`):
    ```
    ## Extension Hooks

    **Optional Pre-Hook**: {extension}
    Command: `/{command}`
    Description: {description}

    Prompt: {prompt}
    To execute: `/{command}`
    ```
  - **Mandatory hook** (`optional: false`):
    ```
    ## Extension Hooks

    **Automatic Pre-Hook**: {extension}
    Executing: `/{command}`
    EXECUTE_COMMAND: {command}

    Wait for the result of the hook command before proceeding to the Outline.
    ```
- If no hooks are registered or `.specify/extensions.yml` does not exist, skip silently

## Outline

1. **Setup**: Run `.specify/scripts/bash/setup-plan.sh --json` from repo root and parse JSON for FEATURE_SPEC, IMPL_PLAN, SPECS_DIR, BRANCH. For single quotes in args like "I'm Groot", use escape syntax: e.g 'I'\''m Groot' (or double-quote if possible: "I'm Groot").

2. **Load context**: Read FEATURE_SPEC and `.specify/memory/constitution.md`. Load IMPL_PLAN template (already copied).

3. **Execute plan workflow**: Follow the structure in IMPL_PLAN template to:
   - Fill Technical Context (mark unknowns as "NEEDS CLARIFICATION")
   - Fill Constitution Check section from constitution
   - Evaluate gates (ERROR if violations unjustified)
   - Phase 0: Generate research.md (resolve all NEEDS CLARIFICATION)
   - Phase 1: Generate data-model.md, contracts/, quickstart.md
   - Phase 1: Update agent context by running the agent script
   - Re-evaluate Constitution Check post-design

4. **Stop and report**: Command ends after Phase 2 planning. Report branch, IMPL_PLAN path, and generated artifacts.

5. **Check for extension hooks**: After reporting, check if `.specify/extensions.yml` exists in the project root.
   - If it exists, read it and look for entries under the `hooks.after_plan` key
   - If the YAML cannot be parsed or is invalid, skip hook checking silently and continue normally
   - Filter out hooks where `enabled` is explicitly `false`. Treat hooks without an `enabled` field as enabled by default.
   - For each remaining hook, do **not** attempt to interpret or evaluate hook `condition` expressions:
     - If the hook has no `condition` field, or it is null/empty, treat the hook as executable
     - If the hook defines a non-empty `condition`, skip the hook and leave condition evaluation to the HookExecutor implementation
   - For each executable hook, output the following based on its `optional` flag:
     - **Optional hook** (`optional: true`):
       ```
       ## Extension Hooks

       **Optional Hook**: {extension}
       Command: `/{command}`
       Description: {description}

       Prompt: {prompt}
       To execute: `/{command}`
       ```
     - **Mandatory hook** (`optional: false`):
       ```
       ## Extension Hooks

       **Automatic Hook**: {extension}
       Executing: `/{command}`
       EXECUTE_COMMAND: {command}
       ```
   - If no hooks are registered or `.specify/extensions.yml` does not exist, skip silently

## Phases

### Phase 0: Outline & Research

1. **Extract unknowns from Technical Context** above:
   - For each NEEDS CLARIFICATION → research task
   - For each dependency → best practices task
   - For each integration → patterns task

2. **Generate and dispatch research agents**:

   ```text
   For each unknown in Technical Context:
     Task: "Research {unknown} for {feature context}"
   For each technology choice:
     Task: "Find best practices for {tech} in {domain}"
   ```

3. **Consolidate findings** in `research.md` using format:
   - Decision: [what was chosen]
   - Rationale: [why chosen]
   - Alternatives considered: [what else evaluated]

**Output**: research.md with all NEEDS CLARIFICATION resolved

### Phase 1: Design & Contracts

**Prerequisites:** `research.md` complete

1. **Extract entities from feature spec** → `data-model.md`:
   - Entity name, fields, relationships
   - Validation rules from requirements
   - State transitions if applicable

2. **Define interface contracts** (if project has external interfaces) → `/contracts/`:
   - Identify what interfaces the project exposes to users or other systems
   - Document the contract format appropriate for the project type
   - Examples: public APIs for libraries, command schemas for CLI tools, endpoints for web services, grammars for parsers, UI contracts for applications
   - Skip if project is purely internal (build scripts, one-off tools, etc.)

3. **Agent context update**:
   - Run `.specify/scripts/bash/update-agent-context.sh claude`
   - These scripts detect which AI agent is in use
   - Update the appropriate agent-specific context file
   - Add only new technology from current plan
   - Preserve manual additions between markers

**Output**: data-model.md, /contracts/*, quickstart.md, agent-specific file

## Key rules

- Use absolute paths
- ERROR on gate failures or unresolved clarifications


<!-- SPEX-GUARD:ship -->
## Ship Pipeline Guard

If `.specify/.spex-ship-phase` exists and its `status` is `running`, this command is part of an autonomous `/spex:ship` pipeline. You MUST:
- Complete the planning work normally.
- Do NOT output a completion summary.
- Do NOT ask "Shall I proceed?" or "Ready for implementation."
- Do NOT use AskUserQuestion.
- Return immediately so the pipeline can advance to the next stage.


<!-- SPEX-TRAIT:superpowers -->
## Protect User-Maintained Agent Files

After Phase 1 runs `update-agent-context.sh`, immediately restore CLAUDE.md (and any other user-maintained agent file) to its pre-script state:

```bash
git checkout -- CLAUDE.md 2>/dev/null || true
```

The `update-agent-context.sh` script (from spec-kit) auto-generates "Active Technologies" and "Recent Changes" sections that overwrite user-curated content. CLAUDE.md is a user-maintained file, not an auto-generated one.

## Spex Quality Gates for Planning

**Before generating the plan:**
1. Invoke {Skill: spex:review-spec} to validate the spec is sound
2. If review finds critical issues, stop and fix before planning

**After the plan is generated:**
1. Run `/speckit-tasks` to generate the task breakdown
2. Invoke {Skill: spex:review-plan} to validate coverage, task quality, and generate REVIEWERS.md

**Pre-PR Quality Gate (mandatory):**

Before creating a spec PR, verify that ALL three quality checks have been completed:
1. `/spex:review-spec` (spec soundness, completeness, implementability)
2. `/spex:review-plan` (coverage matrix, task quality, REVIEWERS.md generation)
3. `/speckit-clarify` (clarification questions resolved, answers encoded in spec)

If any of these have NOT been run during this planning session, run them now before proceeding. Do NOT skip any of these steps. The REVIEWERS.md file MUST exist in the spec directory.

**Commit and PR:**
1. Commit spec artifacts (spec.md, plan.md, tasks.md, REVIEWERS.md) to the feature branch
2. **Ask the user** before creating a spec PR. Do NOT create a PR automatically.
   - If approved, proceed with:
   - Target remote: `upstream` if configured, otherwise `origin`
   - PR title: feature name from spec
   - PR body: summarize the feature, then direct reviewers to REVIEWERS.md
     in the spec directory for detailed review guidance

## Context Management

**Before starting implementation**, consider running `/clear` to give the implementation stage a fresh context window. The planning conversation carries significant context that is no longer needed during implementation, and a fresh window lets the implementation agent work with full capacity. Spec-kit resolves all artifacts (spec, plan, tasks) from the branch name automatically, so no context is lost.


<!-- SPEX-TRAIT:teams -->
## Agent Teams: Parallel Codebase Research for Planning

When this trait is active, orchestrate the research phase of planning using
Claude Code Agent Teams for parallel codebase exploration before the lead
generates the plan.

**Pre-flight**: Check if `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` is enabled.
If not, set it in `.claude/settings.local.json` under `env` and inform the user
that a restart is needed.

**Execution**: Delegate to {Skill: spex:teams-research} for research topic
identification, agent spawning, findings consolidation, and plan generation.
