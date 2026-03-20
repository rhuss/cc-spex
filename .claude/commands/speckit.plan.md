---
description: Execute the implementation planning workflow using the plan template to generate design artifacts.
handoffs: 
  - label: Create Tasks
    agent: speckit.tasks
    prompt: Break the plan into tasks
    send: true
  - label: Create Checklist
    agent: speckit.checklist
    prompt: Create a checklist for the following domain...
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

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

2. **Generate API contracts** from functional requirements:
   - For each user action → endpoint
   - Use standard REST/GraphQL patterns
   - Output OpenAPI/GraphQL schema to `/contracts/`

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


<!-- SDD-TRAIT:superpowers -->
## SDD Quality Gates for Planning

**Before generating the plan:**
1. Invoke {Skill: sdd:review-spec} to validate the spec is sound
2. If review finds critical issues, stop and fix before planning

**After the plan is generated:**
1. Run `/speckit.tasks` to generate the task breakdown
2. Invoke {Skill: sdd:review-plan} to validate coverage, task quality, and generate review-summary.md

**Pre-PR Quality Gate (mandatory):**

Before creating a spec PR, verify that ALL three quality checks have been completed:
1. `/sdd:review-spec` (spec soundness, completeness, implementability)
2. `/sdd:review-plan` (coverage matrix, task quality, review-summary.md generation)
3. `/speckit.clarify` (clarification questions resolved, answers encoded in spec)

If any of these have NOT been run during this planning session, run them now before proceeding. Do NOT skip any of these steps. The review-summary.md file MUST exist in the spec directory.

**Commit and PR:**
1. Commit spec artifacts (spec.md, plan.md, tasks.md, review-summary.md) to the feature branch
2. **Ask the user** before creating a spec PR. Do NOT create a PR automatically.
   - If approved, proceed with:
   - Target remote: `upstream` if configured, otherwise `origin`
   - PR title: feature name from spec
   - PR body: summarize the feature, then direct reviewers to review-summary.md
     in the spec directory for detailed review guidance


<!-- SDD-TRAIT:teams -->
## Agent Teams: Parallel Codebase Research for Planning

When this trait is active, orchestrate the research phase of planning using
Claude Code Agent Teams for parallel codebase exploration before the lead
generates the plan.

**Pre-flight**: Check if `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` is enabled.
If not, set it in `.claude/settings.local.json` under `env` and inform the user
that a restart is needed.

**Execution**: Delegate to {Skill: sdd:teams-research} for research topic
identification, agent spawning, findings consolidation, and plan generation.


<!-- SDD-TRAIT:worktrees -->
## Worktree Context

Before starting the planning workflow, check for a handoff file from the specify session:

```bash
if [ -f ".claude/handoff.md" ]; then cat .claude/handoff.md; fi
```

If found, read it and use its content (brainstorm summary, key decisions, constraints) as additional context for planning. This file bridges the gap between the specify session (in the main repo) and this planning session (in the worktree).
