
<!-- SPEX-GUARD:ship -->
## Ship Pipeline Guard

If `.specify/.spex-state` exists and its `status` is `running`, this command is part of an autonomous `/spex:ship` pipeline. You MUST:
- Complete the planning work normally.
- Do NOT output a completion summary.
- Do NOT ask "Shall I proceed?" or "Ready for implementation."
- Do NOT use AskUserQuestion.
- Return immediately so the pipeline can advance to the next stage.
