
<!-- SPEX-TRAIT:deep-review -->
## Deep Review Enhancement

When `deep-review` trait is active, `spex:review-code` automatically runs
multi-perspective review agents after spec compliance passes. Five agents
(correctness, architecture, security, production-readiness, test-quality)
analyze code independently, followed by an autonomous fix loop for Critical
and Important findings (up to 3 rounds).

No additional commands needed. The enhancement activates within the
existing `spex:review-code` flow. See {Skill: spex:deep-review} for details.

## Ship Pipeline Guard

Check if a ship pipeline is active:
```bash
[ -f .specify/.spex-ship-phase ] && jq -r '.status' .specify/.spex-ship-phase 2>/dev/null
```

If the file exists and status is `running` or `paused`, this command is being invoked as part of `/spex:ship`. In that case:
- Do NOT output a completion summary.
- Do NOT ask "Shall I proceed?" or suggest next steps.
- Do NOT use AskUserQuestion.
- Simply complete the implementation work and return. The ship pipeline manages stage transitions.
