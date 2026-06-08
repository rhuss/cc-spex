---
description: "Final gate before completion - invokes verification for tests, code hygiene, spec compliance, and drift check"
---

# Stamp - Final Completion Gate

## Ship Pipeline Guard

If `.specify/.spex-state` exists and its `status` is `running`, this command is part of an autonomous pipeline. Check the `ask` field:
- If `ask` is `"smart"` or `"never"`: suppress all user prompts (do NOT use AskUserQuestion), complete the stamp autonomously, and return immediately so the pipeline can advance.
- If `ask` is `"always"`: prompt the user as normal.

```bash
if [ -f ".specify/.spex-state" ]; then
  STATUS=$(jq -r '.status // empty' .specify/.spex-state 2>/dev/null)
  ASK=$(jq -r '.ask // "always"' .specify/.spex-state 2>/dev/null)
  if [ "$STATUS" = "running" ] && [ "$ASK" != "always" ]; then
    echo "AUTONOMOUS_MODE=true"
  else
    echo "AUTONOMOUS_MODE=false"
  fi
else
  echo "AUTONOMOUS_MODE=false"
fi
```

In autonomous mode: do NOT output a completion summary, do NOT ask "Shall I proceed?", do NOT suggest next steps. Complete the stamp and return.

## Relationship to /speckit-spex-finish

`/speckit-spex-stamp` runs verification only. For verification + merge/PR/cleanup in one step, use `/speckit-spex-finish` instead.

## Phase Guard

Stamp and verification only apply **after implementation**. If the flow state shows implementation has not completed, skip this command entirely.

```bash
if [ -f ".specify/.spex-state" ]; then
  IMPL=$(jq -r '.implemented // false' .specify/.spex-state 2>/dev/null)
  if [ "$IMPL" != "true" ]; then
    echo "SKIP: stamp applies post-implementation only (current phase is pre-implementation)"
    exit 0
  fi
fi
```

If no state file exists, check whether there are meaningful code changes on the branch (not just spec artifacts). If the only changes are in `specs/` or `.specify/`, this is still a planning phase and stamp does not apply.

**Do NOT remind the user about stamp during spec, planning, or task generation phases.** It creates noise and does not apply until code exists to verify.

## Purpose

This is the final gate before claiming work is complete. It delegates to the full verification command.

## Execution

Invoke `speckit.spex-gates.verify` with any arguments passed to this command.

The verify command runs all quality gates:
1. Full test suite
2. Code hygiene review
3. Spec compliance validation (100% required)
4. Spec drift check
5. Success criteria verification

Only after all gates pass can work be claimed as complete.
