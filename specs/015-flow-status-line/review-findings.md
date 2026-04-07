# Deep Review Findings

**Date:** 2026-04-07
**Branch:** 015-flow-status-line
**Rounds:** 1
**Gate Outcome:** PASS
**Invocation:** superpowers

## Summary

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 0 | 0 | 0 |
| Important | 9 | 2 | 7 (pre-existing) |
| Minor | 10 | 0 | 10 (pre-existing) |
| **Total** | **19** | **2** | **17** |

**Agents completed:** 5/5 (+ 0 external tools)
**Agents failed:** none

## Findings

### FINDING-1
- **Severity:** Important
- **Confidence:** 90
- **File:** spex/scripts/spex-ship-statusline.sh:86-118
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
Four nearly identical if/elif/else blocks rendered milestone checkmarks for spec, plan, tasks, and impl. Each block tested the same three conditions with the same color scheme.

**Why this matters:**
Adding a new milestone would require copying the same 8-line block. Changing colors means touching four places.

**How it was resolved:**
Refactored into a loop over arrays of milestone names, completion states, and next-step names.

### FINDING-2
- **Severity:** Important
- **Confidence:** 90
- **File:** spex/scripts/spex-ship-statusline.sh:12-16,45,51,134-138
- **Category:** production-readiness
- **Source:** production-readiness-agent (also reported by: architecture-agent)
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
Multiple separate `jq` process invocations to read fields from the same small JSON file. Flow mode had 3 calls, ship mode had 5. Each spawns a new process (5-15ms overhead each on macOS).

**Why this matters:**
FR-007 requires the script to complete within 500ms. Multiple jq calls added 30-120ms of unnecessary overhead and created a TOCTOU race where the state file could change between reads.

**How it was resolved:**
Read the entire state file once with `cat` into a variable. Each mode now uses a single `jq` call with `@tsv` output to extract all needed fields atomically.

### FINDING-3 through FINDING-17 (pre-existing)

The remaining 15 findings are in pre-existing code not introduced by this feature. They include:
- Argument parsing crash in `do_create` on trailing flags (correctness)
- JSON construction via string interpolation in `write_state` (security)
- Bash arithmetic injection risk from jq output (security)
- Non-atomic writes in `write_state` vs atomic in `do_pause`/`do_fail` (production)
- `find_spec_dir` brittle glob heuristic (architecture)
- Missing automated tests for statusline and artifact validation (test-quality)

These are documented for future improvement but are not blocking for this feature.
