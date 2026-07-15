# Implementation Plan: Brainstorm Directory Sync

**Branch**: `044-brainstorm-sync` | **Date**: 2026-07-15 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/044-brainstorm-sync/spec.md`

## Summary

Add a `--sync` option to the brainstorm skill that scans all brainstorm documents, cross-references them against specs, classifies their status, presents an interactive confirmation table, moves terminal-state documents to `brainstorm/attic/`, updates the overview, and commits the result. The implementation modifies the existing brainstorm skill markdown (both canonical source and installed copy) and updates documentation.

## Technical Context

**Language/Version**: Bash (POSIX-compatible), Markdown (skill files)
**Primary Dependencies**: `jq`, `yq`, `rg` (ripgrep), git, Claude Code AskUserQuestion tool
**Storage**: Filesystem (brainstorm/*.md, specs/*/)
**Testing**: Manual smoke test via the brainstorm skill invocation
**Target Platform**: Claude Code CLI (macOS/Linux)
**Project Type**: AI agent skill/plugin
**Performance Goals**: N/A (interactive CLI skill, runs once)
**Constraints**: Must work with existing brainstorm directory conventions, must not modify document content
**Scale/Scope**: Handles 40+ brainstorm documents, 30+ spec directories

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Spec-Guided Development | PASS | Following full SDD workflow |
| II. Extension Architecture | PASS | Modifying existing extension command, following conventions |
| III. Extension Composability | PASS | Self-contained within spex extension, no cross-extension deps |
| IV. Quality Gates | PASS | Running through ship pipeline gates |
| V. Naming Discipline | PASS | Using `speckit-spex-brainstorm` prefix, no new commands |
| VI. Skill Autonomy | PASS | Adding a mode to existing skill, not mixing roles |
| VII. State as Scripts | N/A | No persistent state management needed; sync is a one-shot operation |

No violations. No complexity tracking needed.

## Project Structure

### Documentation (this feature)

```text
specs/044-brainstorm-sync/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── checklists/
│   └── requirements.md  # Spec quality checklist
└── tasks.md             # Phase 2 output (via /speckit-tasks)
```

### Source Code (repository root)

```text
spex/extensions/spex/commands/
└── speckit.spex.brainstorm.md    # Modified: add --sync argument handling + sync logic

spex/docs/
└── help.md                       # Modified: add --sync to command reference

README.md                         # Modified: add --sync to brainstorm command docs
```

**Structure Decision**: No new files created. The `--sync` logic is added as a new section within the existing brainstorm skill markdown. The skill already handles argument parsing; `--sync` is a new argument that short-circuits the normal brainstorm flow (per FR-016).

## Implementation Approach

### Argument Detection

The brainstorm skill receives arguments via `$ARGUMENTS`. When `--sync` is detected:
1. Skip the normal brainstorm flow (checklist steps 2-7: context exploration, inbox check, clarifying questions, approach proposal, agreement, document writing)
2. Execute the sync-specific flow instead
3. After sync completes, update the overview (reusing the existing overview update logic) and exit

### Sync Flow (inserted as a new section in the skill)

**Step 1: Scan documents**
- List all `.md` files in `brainstorm/`, excluding `00-overview.md` and `idea-inbox.md`
- For each file, parse the `**Status:**` field from the header (regex: `^\*\*Status\*\*:\s*(.+)$`)
- Normalize status to lowercase for comparison
- Files with no Status field default to `active`

**Step 2: Cross-reference specs**
- List all directories in `specs/` to build a slug index
- For each spec directory, extract the slug (portion after the number prefix, e.g., `008-rename-to-cc-spex` yields `rename-to-cc-spex`)
- For each brainstorm document, extract its slug (portion after the number prefix for numbered files, full filename minus `.md` for unnumbered)
- Match using token overlap: split both slugs on hyphens, count shared tokens. Match if >= 2 shared tokens OR one slug is a complete substring of the other
- Also parse the overview table's Spec column for explicit `NNN` mappings

**Step 3: Classify**
- Terminal states (attic candidates): `spec-created`, `abandoned`, `completed`, `resolved`, `decided`
- Keep states: `active`, `parked`, `draft`, `idea`
- If a document is in a keep state but has a spec match, infer `spec-created` and mark as attic candidate with "(inferred)" annotation

**Step 4: Present interactive confirmation**
- Use `AskUserQuestion` with `multiSelect: true`
- Each attic candidate is a pre-selected option with label = document name and description = "status → attic"
- Keep items are NOT shown as options (they're not actionable)
- A summary of keep items is shown in the question text

**Step 5: Execute moves**
- Create `brainstorm/attic/` if needed
- For each confirmed item, run `git mv brainstorm/<file> brainstorm/attic/<file>`
- Skip files that already exist in attic (warn user)

**Step 6: Update overview**
- Remove attic'd documents from the Sessions table
- Remove their open threads from Open Threads section
- Remove their parked ideas from Parked Ideas section (though terminal-state docs shouldn't have parked ideas)
- Keep all entries for documents remaining in `brainstorm/`

**Step 7: Commit**
- Stage all changes: `git add brainstorm/`
- Commit with message: `chore(brainstorm): sync - archive N documents to attic`

### Token Matching Algorithm

```
function slug_match(brainstorm_slug, spec_slug):
  bs_tokens = brainstorm_slug.split("-")
  sp_tokens = spec_slug.split("-")
  shared = intersection(bs_tokens, sp_tokens)
  
  if len(shared) >= 2: return true
  if brainstorm_slug in spec_slug: return true
  if spec_slug in brainstorm_slug: return true
  return false
```

Example matches:
- `rename-to-cc-spex` ↔ `rename-to-cc-spex` (exact, 4 shared tokens)
- `traits-to-extensions` ↔ `traits-to-extensions` (exact, 3 shared tokens)
- `smoke-test-v2` ↔ `smoke-test-rethink` (2 shared tokens: smoke, test)
- `flow-status-line` ↔ `flow-status-line` (exact, 3 shared tokens)

Non-matches (correctly rejected):
- `spec-evolution` ↔ `smoke-test-rethink` (0 shared tokens)
- `brainstorm-sync` ↔ `guided-smoke-test` (0 shared tokens)

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| False positive spec match | Low | Medium | 2-token minimum + interactive confirmation |
| Git mv fails on unnumbered files | Low | Low | Error handling per file, skip on failure |
| Overview parsing breaks on edge cases | Medium | Low | Use existing overview rebuild logic pattern |
| User rejects all items | Low | None | Clean exit, no changes |
