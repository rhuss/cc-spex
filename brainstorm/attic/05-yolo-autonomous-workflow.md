# spex:yolo - Autonomous Full-Cycle Workflow

## Context

The spex workflow currently requires manual orchestration: brainstorm, then specify, then clarify, then plan, then tasks, then implement, then review. Each step is a separate skill/command invocation with human confirmation between steps. For well-scoped features (especially after a thorough brainstorm), this manual handoff adds friction without adding value.

## Concept

`spex:yolo` is a skill that chains the full spex workflow autonomously after a brainstorm session. It runs all stages in sequence, only pausing when it encounters a question where the AI genuinely needs human guidance. The name reflects the "let it rip" philosophy: trust the process, trust the reviews, intervene only when necessary.

## Pipeline

```
brainstorm (already complete)
  → speckit.specify (create spec from brainstorm doc)
  → speckit.clarify (resolve ambiguities)
  → spex:review-spec (validate spec quality)
  → speckit.plan (generate architecture/design)
  → spex:review-plan (validate plan quality)
  → speckit.tasks (generate task breakdown)
  → speckit.implement (execute tasks)
  → spex:deep-review (full code review with external tools)
  → spex:verify (tests, hygiene, compliance)
```

If worktrees trait is enabled, specify creates the worktree (existing behavior), and all subsequent stages run inside it.

## Decisions

| # | Topic | Decision | Rationale |
|---|-------|----------|-----------|
| 1 | Review tools | Pass-through flags to `spex:deep-review`: `--no-external`, `--no-coderabbit`, `--no-copilot`, `--external`, `--coderabbit`, `--copilot` | Let user control which external reviewers participate |
| 2 | Auto-fix policy | Three levels: `cautious` / `balanced` (default) / `autopilot` via `--autonomy` flag | `cautious` stops at every finding, `balanced` auto-fixes clear issues, `autopilot` fixes everything and only stops on genuine blockers |
| 3 | Brainstorm handoff | Reads brainstorm document from `brainstorm/` directory, passes content as feature description to specify | Brainstorm docs exist before spec directories |
| 4 | Trait dependencies | Requires both `superpowers` and `deep-review` traits enabled | Yolo without quality gates would be reckless |
| 5 | Resume behavior | Auto-continues pipeline after human answers a blocking question | No need to re-invoke yolo; answering the question is the signal to proceed |
| 6 | Worktree timing | After specify (Option B), following existing worktrees trait behavior | Specify creates the branch; worktree is created after |
| 7 | Progress reporting | Full verbose output from each stage | User sees everything happening in real time |
| 8 | Status line | Optional: write current phase to `.specify/.spex-yolo-phase`, custom status line script reads it | Status line is passive/script-driven, not API-controllable |
| 9 | Skill type | `spex:yolo` skill (`spex/skills/yolo/SKILL.md`), not a `speckit.*` command | Stays in the `spex:` namespace for our extensions |
| 10 | PR creation | Optional via `--create-pr` flag, off by default | Let user decide when to publish |

## Interface

```
/spex:yolo [brainstorm-file] [options]

Arguments:
  brainstorm-file    Path to brainstorm doc (default: auto-detect latest in brainstorm/)

Options:
  --autonomy <level>   cautious | balanced (default) | autopilot
  --create-pr          Create a PR after successful completion
  --no-external        Skip external review tools (CodeRabbit, Copilot)
  --no-coderabbit      Skip CodeRabbit review
  --no-copilot         Skip Copilot review
  --external           Force external reviews (even if trait defaults differ)
  --coderabbit         Force CodeRabbit review
  --copilot            Force Copilot review
```

## Autonomy Levels

### `cautious`
- Stops at every review finding for human approval
- Clarify questions always presented to user
- Review failures always shown before attempting fix
- Best for: learning the workflow, critical features, unfamiliar codebases

### `balanced` (default)
- Auto-fixes clear review issues (formatting, missing tests, obvious gaps)
- Stops when the AI is genuinely uncertain about the right approach
- Clarify questions with obvious answers (from brainstorm context) answered automatically
- Re-runs review after fixes (max 2 retry cycles per stage)
- Best for: day-to-day feature development

### `autopilot`
- Auto-fixes everything it can
- Only stops if implementation is genuinely blocked (missing dependency, ambiguous requirement with no context)
- Maximum autonomy, minimum interruption
- Best for: well-scoped features after thorough brainstorming, confident developers

## State Tracking

Yolo writes its current phase to `.specify/.spex-yolo-phase` for status line integration:

```json
{
  "phase": "implement",
  "stage": 6,
  "total_stages": 9,
  "autonomy": "balanced",
  "started_at": "2026-03-29T10:00:00Z",
  "retries": 0
}
```

An optional status line script (`spex/scripts/spex-yolo-statusline.sh`) can read this file to display progress in the Claude Code status bar.

## Preconditions (checked at startup)

1. `superpowers` trait enabled
2. `deep-review` trait enabled
3. Brainstorm document exists and is readable
4. If `--coderabbit` or `--external`: `coderabbit auth status` succeeds
5. If worktrees trait enabled: git working tree is clean

## Error Handling

- **Review failure + auto-fix**: Apply fixes, re-run review (max 2 retries per stage)
- **Review failure after retries**: Stop, present findings, ask human
- **Specify/plan/tasks failure**: Stop, present error, ask human
- **Implementation test failure**: Attempt fix based on test output (respects autonomy level)
- **External tool unavailable**: Skip with warning (unless explicitly requested via flag)

## Open Questions

None remaining. Ready for `/speckit.specify`.
