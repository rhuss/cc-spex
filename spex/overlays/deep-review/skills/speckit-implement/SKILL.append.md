
<!-- SPEX-TRAIT:deep-review -->
## Deep Review Enhancement

When `deep-review` trait is active, `spex:review-code` automatically runs
multi-perspective review agents after spec compliance passes. Five agents
(correctness, architecture, security, production-readiness, test-quality)
analyze code independently, followed by an autonomous fix loop for Critical
and Important findings (up to 3 rounds).

No additional commands needed. The enhancement activates within the
existing `spex:review-code` flow. See {Skill: spex:deep-review} for details.
