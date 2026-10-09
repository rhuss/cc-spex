# Brainstorm: Mechanical Compliance Gate (move the verify verdict out of the agent)

**Date:** 2026-10-04
**Status:** idea
**Origin:** Fact check of the blog post "Fences the Flock Can't Talk Around" (ro14nd.de), which described a compliance script that does not exist.

## Problem Framing

Commit [3d9d392](https://github.com/rhuss/cc-spex/commit/3d9d392) ("Prevent verify gate from rationalizing non-compliance", 2026-05-09) fixed the "COMPLIANT (with documented gap)" incident with three changes to `speckit.spex-gates.verify.md`:

1. Only two valid statuses: IMPLEMENTED or MISSING (no PARTIAL, invented statuses named and banned)
2. A machine-readable `SPEC_COMPLIANCE_RESULT` block whose gate "is determined mechanically: if missing > 0, FAIL"
3. An anti-rationalization table mapping common excuses to MISSING

The commit message says the gate decision "is now structural, not discretionary." It isn't. The whole chain is self-certified by the agent:

- The agent fills in `SPEC_COMPLIANCE_RESULT` and computes `gate: PASS | FAIL` itself. No script parses the block.
- The agent writes the verification marker itself (`touch ${TMPDIR}/.claude-spex-verified-${SESSION_ID}`, step 7 of verify).
- `verify-gate.sh` reads the marker but is non-blocking: it returns a reminder, never a deny.

The prompt-level changes are good rope fences, and no rationalization has been observed since May 9. But nothing would catch it if one happened. The machine-readable block is the precondition for an electric fence; the fence itself was never built.

### Failure modes the current design cannot catch

- **Invented status inside the matrix**: `Status: IMPLEMENTED (known limitation)` or similar
- **Dropped rows**: an FR silently omitted from the matrix, giving 100% of a subset
- **Inconsistent result block**: `missing: 1` with `gate: PASS`
- **Marker without verdict**: marker touched although verify reported FAIL, or without verify running at all
- **Relabeling**: a partial implementation marked IMPLEMENTED. This is a judgment error, not a format error, and cannot be caught mechanically. Out of scope here (adversarial review territory).

## Prior Art in This Repo

`spex-closeout-gate.sh` already does exactly this for review findings: it reads the review report from disk, counts unresolved Critical/Important findings, and decides pass/fail with exit codes and `CLOSEOUT_PASS` / `CLOSEOUT_FAIL` output, including a fail-open default and `SPEX_CLOSEOUT_STRICT=1`. The compliance gate should mirror that design.

## Approaches Considered

### A: Compliance gate script (leaning)

Verify writes the matrix to disk (e.g. `specs/<feature>/COMPLIANCE.md`). A new `spex-compliance-gate.sh <spec-dir>` (or Python):

- Parses every `Status:` line; allowlist: anything that is not exactly `IMPLEMENTED` fails
- Extracts FR IDs from `spec.md` deterministically and fails if any FR has no row (or a row has no FR)
- Recomputes totals itself and ignores the agent's `gate:` field
- Outputs `COMPLIANCE_PASS` / `COMPLIANCE_FAIL missing=N invalid=M unmapped=K`
- Is the only writer of the verification marker; verify.md calls the script instead of `touch`

- Pros: Small, mirrors closeout gate, harness-agnostic, turns the prompt's claim into reality
- Cons: Requires a stable matrix format and FR ID convention

### B: A + blocking commit hook

`verify-gate.sh` denies `git commit` (non-spec commits) when the marker is absent, instead of reminding.

- Pros: The fence actually stops something
- Cons: Behavior change for all users; needs escape hatch and strict/fail-open mode like closeout

### C: JSON result with schema validation

Agent emits structured JSON validated against a schema.

- Pros: Robust parsing
- Cons: Heavier change to verify output; schema validation alone still doesn't check FR coverage

### D: Second-agent re-check

A fresh-context agent re-audits the matrix.

- Pros: Could catch relabeling
- Cons: Still LLM judgment, so still a rope fence. Complements A, doesn't replace it.

## Decision

Not decided. Leaning A now, B as opt-in strict mode (mirroring `SPEX_CLOSEOUT_STRICT`), D as a later complement for the relabeling case.

## Key Requirements (draft)

- Deterministic FR extraction from the spec (FR-NNN identifiers)
- Allowlist status check; unknown statuses fail
- Row coverage check in both directions (every FR has a row, every row maps to an FR)
- Agent's computed totals and gate field ignored
- Script is the sole writer of the verification marker
- Exit codes and output conventions aligned with `spex-closeout-gate.sh`
- Works for the Codex adapter as well (no Claude-only assumptions)
- Tests in `tests/` covering each failure mode listed above

## Open Questions

- Matrix format: keep markdown `Status:` lines, or move to a fenced JSON/YAML block?
- How to stop the agent from touching the marker directly (pretool-gate deny on writes to `.claude-spex-verified-*`?)
- Fail-open or strict by default?
- Fallback for specs without numbered FR IDs
- Remove the `gate:` field from the agent's block entirely, so there is nothing to rationalize?
- Should verify.md's wording ("determined mechanically") change until the script exists?
