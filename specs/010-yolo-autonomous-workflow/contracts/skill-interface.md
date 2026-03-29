# Skill Interface Contract: spex:yolo

## Invocation

```
/spex:yolo [brainstorm-file] [options]
```

### Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `brainstorm-file` | No | Path to brainstorm document. If omitted, auto-detects the highest-numbered file in `brainstorm/`. |

### Options

| Flag | Default | Description |
|------|---------|-------------|
| `--autonomy <level>` | `balanced` | Autonomy level: `cautious`, `balanced`, `autopilot` |
| `--create-pr` | off | Create a pull request after successful completion |
| `--no-external` | (from config) | Skip all external review tools |
| `--external` | (from config) | Enable all external review tools |
| `--no-coderabbit` | (from config) | Skip CodeRabbit during deep-review |
| `--coderabbit` | (from config) | Enable CodeRabbit during deep-review |
| `--no-copilot` | (from config) | Skip Copilot during deep-review |
| `--copilot` | (from config) | Enable Copilot during deep-review |
| `--resume` | off | Resume an interrupted pipeline from the last completed stage |
| `--start-from <stage>` | (none) | Start execution from a specific stage (specify, clarify, review-spec, plan, review-plan, tasks, implement, deep-review, verify) |

External tool flags default to values in `.specify/spex-traits.json` under `external_tools`. CLI flags override config.

## Preconditions

1. `superpowers` trait MUST be enabled
2. `deep-review` trait MUST be enabled
3. Brainstorm file MUST exist (explicit or auto-detected)
4. Working tree MUST be clean (no uncommitted changes)
5. If `--coderabbit` is explicitly set, CodeRabbit auth MUST be valid

## Postconditions (on success)

1. Feature branch exists with spec artifacts and implementation
2. All review stages passed (within retry limits)
3. Verification completed successfully
4. `.specify/.spex-yolo-phase` has `status: "completed"`
5. If `--create-pr`: PR created targeting main branch

## Error Conditions

| Condition | Behavior |
|-----------|----------|
| Missing required traits | Fail at startup with trait enable instructions |
| Brainstorm file not found | Fail with error listing available brainstorm files |
| `--resume` with no state file | Fail with error: "No interrupted pipeline found" |
| `--start-from` with invalid stage | Fail listing valid stage names |
| Dirty working tree | Fail with message to commit or stash |
| External tool auth failure | Fail at startup (only when tool explicitly requested) |
| Stage failure after 2 retries | Pause, present findings, wait for user guidance |
| User Ctrl+C interruption | State file remains with last stage; no auto-resume on next invocation |

## State File Contract

**Path:** `.specify/.spex-yolo-phase`
**Format:** JSON (see data-model.md for schema)

Written at each stage transition. Consumers (status line scripts) may read this file at any time. The file is deleted on successful completion or left in place on interruption/failure.

## Downstream Skill Contracts

The yolo skill invokes these skills/commands with these expectations:

| Stage | Invocation | Expected Input | Expected Output |
|-------|-----------|----------------|-----------------|
| specify | `/speckit.specify` | Brainstorm content as feature description | `spec.md` created |
| clarify | `/speckit.clarify` | Active spec in specs dir | Updated `spec.md` |
| review-spec | `{Skill: spex:review-spec}` | Spec file path | Review report with severity |
| plan | `/speckit.plan` | Spec file | `plan.md`, `research.md`, artifacts |
| review-plan | `{Skill: spex:review-plan}` | Plan + tasks files | `REVIEWERS.md` |
| tasks | `/speckit.tasks` | Plan file | `tasks.md` |
| implement | `/speckit.implement` | Tasks file | Source code changes |
| deep-review | `{Skill: spex:deep-review}` | Implementation changes, external tool flags | Review findings |
| verify | `{Skill: spex:verification-before-completion}` | Implementation + spec | Verification report |
