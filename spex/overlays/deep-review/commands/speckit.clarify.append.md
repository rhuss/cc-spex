
<!-- SPEX-TRAIT:deep-review -->
## Ship Pipeline Guard

Check if a ship pipeline is active:
```bash
[ -f .specify/.spex-ship-phase ] && jq -r '.status' .specify/.spex-ship-phase 2>/dev/null
```

If the file exists and status is `running` or `paused`, this command is being invoked as part of `/spex:ship`. In that case:
- Read the `ask` level from `.specify/.spex-ship-phase`.
- If `ask` is `smart` or `never`: Do NOT present clarification questions to the user. Select the recommended answer for each question yourself. Process all questions in a single pass.
- Do NOT output a completion summary.
- Do NOT ask "Ready for the next phase" or similar prompts.
- Do NOT use AskUserQuestion.
- Simply complete the clarification work and return. The ship pipeline manages stage transitions.
