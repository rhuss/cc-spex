# spex Smoke Test

A hands-on walkthrough that exercises every spex command on a fresh repo. Follow these steps in order to verify the plugin works end-to-end and to get a feel for the workflow.

spex builds on two upstream projects:
- [Superpowers](https://github.com/obra/superpowers) by Jesse Vincent: process discipline, TDD, verification, anti-rationalization patterns
- [Spec-Kit](https://github.com/github/spec-kit) by GitHub: specification templates, artifact management, and the `specify` CLI

## Prerequisites

- [`specify` CLI](https://github.com/github/spec-kit) installed and on PATH (`uv pip install specify-cli`)
- Claude Code with the spex plugin loaded
- `gh` CLI authenticated (for the PR step)


## 1. Create a test repo

```bash
cd /tmp
mkdir spex-smoke && cd spex-smoke
git init
echo "# spex Smoke Test" > README.md
git add README.md && git commit -m "Initial commit"
claude
```

## 2. Show the quick reference

```
/spex:help
```

You should see the workflow diagram, all spec-kit commands, trait descriptions, and the spex command list.

## 3. Initialize the project

```
/spex:init
```

Claude runs `specify init`, then asks you to pick traits and a permission level. For this test, enable the **superpowers** trait and choose **Standard** permissions.

Verify:
- `.specify/` directory created (templates, scripts, config)
- `.specify/spex-traits.json` shows `superpowers: true`
- `.claude/commands/speckit.*.md` files exist
- Overlay sentinels present: `grep SDD-TRAIT .claude/commands/speckit.*.md`

Restart Claude Code now (the init installs new commands that need a reload).

```bash
claude
```

## 4. Create a project constitution

```
/speckit.constitution
```

Tell Claude the project is a CLI tool written in Python that should follow standard CLI conventions (exit codes, stderr for errors, stdout for output). Let Claude generate the constitution.

Verify:
- `.specify/memory/constitution.md` created with your principles

## 5. Brainstorm a feature from a rough idea

```
/spex:brainstorm
```

Give Claude a vague idea:

> "I want a command-line tool that can count words, lines, and characters in a file, like a simplified wc."

Claude should ask clarifying questions (flags? multiple files? stdin support?) and then produce a formal spec. Answer the questions however you like, keeping it simple.

Verify:
- Claude asked 3-5 clarifying questions before writing the spec
- A spec file was created at `specs/<NNN>-<feature>/spec.md`
- The spec captures requirements, edge cases, and success criteria

## 6. Review the spec

```
/spex:review-spec
```

Claude reads the spec and checks it for completeness, clarity, implementability, and constitution alignment.

Verify:
- Review output covers structure, ambiguity, and testability
- If issues are found, Claude suggests concrete fixes

## 7. Plan and generate tasks

```
/speckit.plan
```

With the superpowers trait enabled, this command runs the full planning pipeline:
1. Spec review (pre-planning gate)
2. Plan generation from the spec
3. Task generation (`/speckit.tasks`)
4. Plan review (`/spex:review-plan`) producing `REVIEWERS.md`
5. Commits spec artifacts to a feature branch
6. Offers to create a spec PR (accept or decline)

Verify:
- `plan.md` created in the spec directory
- `tasks.md` created with dependency-ordered tasks
- `REVIEWERS.md` generated
- Artifacts committed (check `git log --oneline`)

## 8. Review the plan independently

You already got an automatic plan review in step 7, but you can also run it manually:

```
/spex:review-plan
```

Verify:
- Coverage matrix mapping requirements to tasks
- Red flag scanning (vague language, missing tests)
- Task quality assessment (actionable, testable, atomic)

## 9. Implement the feature

```
/speckit.implement
```

With the superpowers trait, Claude:
1. Verifies the spec package exists (spec, plan, tasks)
2. Implements using TDD (tests first, then code)
3. Runs `/spex:review-code` after implementation
4. Runs verification (tests + spec compliance) before claiming completion

Verify:
- Implementation code created
- Tests created and passing
- Code review ran with a compliance score
- The tool works: `python wc.py README.md` (or whatever the implementation is)

## 10. Review code against the spec

Run this independently to see the compliance check in isolation:

```
/spex:review-code
```

Verify:
- Compliance matrix with per-requirement status
- Compliance percentage calculated
- Deviations (if any) clearly identified

## 11. Test spec evolution

Manually introduce a deviation. For example, edit the implementation to add a `--json` output flag that the spec does not mention.

Then run:

```
/spex:evolve
```

Claude detects the mismatch and recommends either updating the spec (to accept the new flag) or removing the code (to match the spec). Pick one and let Claude restore alignment.

Verify:
- Mismatch detected and described
- Recommendation with reasoning provided
- After your choice, spec and code are back in sync

## 12. Toggle traits

List current traits:

```
/spex:traits list
```

Disable the superpowers trait:

```
/spex:traits disable superpowers
```

Claude warns about resetting spec-kit files and asks for confirmation. Confirm.

Re-enable it:

```
/spex:traits enable superpowers
```

Verify:
- `list` shows correct trait status
- Disabling removes overlay sentinels from command files
- Re-enabling reapplies them
- Running enable twice is idempotent (no double-application)

## 13. Test utility commands

Run each of these against the spec you created:

```
/speckit.clarify
```
Identifies underspecified areas and asks targeted questions.

```
/speckit.analyze
```
Cross-artifact consistency check across spec, plan, and tasks.

```
/speckit.checklist
```
Generates a custom QA checklist for the feature.

## 14. Clean up

```bash
rm -rf /tmp/spex-smoke
```

## Quick pass vs full pass

**Quick pass** (steps 1-9): Covers init, constitution, brainstorm, spec review, plan, implement. This is the core workflow.

**Full pass** (all steps): Adds independent reviews, evolution, trait toggling, and utility commands.
