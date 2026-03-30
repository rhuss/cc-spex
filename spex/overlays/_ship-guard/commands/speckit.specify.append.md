
<!-- SPEX-GUARD:ship -->
## Ship Pipeline Guard

If `.specify/.spex-ship-phase` exists and its `status` is `running`, this command is part of an autonomous `/spex:ship` pipeline. You MUST:
- Complete the specification work normally.
- Do NOT output a completion summary.
- Do NOT ask "Shall I proceed?", "Ready for the next phase", or similar.
- Do NOT use AskUserQuestion.
- Return immediately so the pipeline can advance to the next stage.
