
<!-- SPEX-TRAIT:deep-review -->
## Ship Pipeline Guard

Check if a ship pipeline is active:
```bash
[ -f .specify/.spex-ship-phase ] && jq -r '.status' .specify/.spex-ship-phase 2>/dev/null
```

If the file exists and status is `running` or `paused`, this command is being invoked as part of `/spex:ship`. In that case:
- Do NOT output a completion summary.
- Do NOT ask "Shall I proceed?" or "Ready for the next phase."
- Do NOT use AskUserQuestion.
- Simply complete the specification work and return. The ship pipeline manages stage transitions.
