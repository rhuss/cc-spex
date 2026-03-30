
<!-- SPEX-GUARD:ship -->
## Ship Pipeline Guard

If `.specify/.spex-ship-phase` exists and its `status` is `running`, this command is part of an autonomous `/spex:ship` pipeline. You MUST:
- Complete the implementation work normally.
- Do NOT output a completion summary.
- Do NOT ask "Shall I proceed?" or suggest next steps.
- Do NOT use AskUserQuestion.
- Return immediately so the pipeline can advance to the next stage.
