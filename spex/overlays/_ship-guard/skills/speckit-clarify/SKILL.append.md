
<!-- SPEX-GUARD:ship -->
## Ship Pipeline Guard

If `.specify/.spex-state` exists and its `status` is `running`, this command is part of an autonomous `/spex:ship` pipeline. Read the `ask` level from the state file. You MUST:
- If `ask` is `smart` or `never`: Do NOT present clarification questions to the user. Select the recommended answer for each question yourself. Process all questions in a single pass and update the spec.
- Do NOT output a completion summary.
- Do NOT ask "Ready for the next phase" or similar.
- Do NOT use AskUserQuestion (unless `ask` is `always`).
- Return immediately so the pipeline can advance to the next stage.
