                          spex Quick Reference

WORKFLOW

     ┌──────────┐      ┌──────────┐      ┌──────────┐
     │   IDEA   │─────▶│   SPEC   │─────▶│   PLAN   │
     └──────────┘      └──────────┘      └──────────┘
           │                │                   │
           │  /speckit-spex-brainstorm  /speckit-specify    /speckit-plan
           │                │                   │
           │    ┌───────────┤                   │
           │    │  OR       │                   │
           │    ▼           ▼                   ▼
           │  ┌──────┐  ┌──────────┐      ┌──────────────┐
           │  │ SHIP │  │  REVIEW  │      │  REVIEW PLAN │
           │  └──┬───┘  └──────────┘      └──────────────┘
           │     │   (auto via spex-gates hooks)    (auto via spex-gates hooks)
           │     │                                 │
           │     │   /speckit-spex-ship                    │
           │     │   (chains all                   ▼
           │     │    stages)              ┌──────────┐
           │     │                         │IMPLEMENT │
           │     │                         └──────────┘
           │     │                                 │  /speckit-implement
           │     │                                 ▼
           │     │                         ┌──────────┐
           │     │                         │  FINISH  │
           │     │                         └──────────┘
           │     │                        /speckit-spex-finish
           │     │                                 ▼
           │     │                         ╔══════════╗
           │     └────────────────────────▶║ COMPLETE ║
           │                               ╚══════════╝
           │                                   ▲
           │                            ┌──────┴─────┐
           │                            │   EVOLVE   │ /speckit-spex-evolve
           │                            └────────────┘
           │                                   ▲
           └───────────────────────────────────┘
                       (when drift detected)


SPEC-KIT COMMANDS (core workflow)

  /speckit-specify     Create or update feature specification
  /speckit-plan        Generate implementation plan from spec
  /speckit-tasks       Generate dependency-ordered tasks from plan
                       TIP: Run /clear after tasks before implementing
                       to free context for the implementation phase
  /speckit-implement   Execute tasks from the implementation plan
  /speckit-checklist   Generate a custom checklist for the feature
  /speckit-clarify     Identify underspecified areas in the spec
  /speckit-analyze     Cross-artifact consistency and quality analysis
  /speckit-taskstoissues  Convert tasks into GitHub issues
  /speckit-constitution   Create or update project constitution


BUILT ON
  Superpowers (Jesse Vincent): Process discipline, TDD, verification,
                                anti-rationalization patterns
  Spec-Kit (GitHub):            Specification templates, artifacts,
                                `specify` CLI
  spex adds:                    Spec-first enforcement, compliance
                                scoring, drift detection, evolution


spex EXTENSIONS (quality gates for spec-kit commands)

  Extensions inject automated quality gates into the spec-kit workflow
  via lifecycle hooks. Enable them with `specify extension enable <name>`.

  spex-gates extension:
    /speckit-specify  → auto-runs spec review + constitution check
    /speckit-plan     → auto-runs spec review before planning,
                        plan review + task generation after,
                        commits spec artifacts, offers spec PR
    /speckit-implement → verifies spec package before starting,
                         runs code review + verification after

  spex-teams extension (experimental):
    /speckit-implement → parallel task execution via Claude Code
                         Agent Teams with spec guardian review

  spex-deep-review extension:
    /speckit-spex-review-code → runs 5 specialized review agents
                        (correctness, architecture, security,
                        production-readiness, test-quality) after spec
                        compliance passes, auto-fixes Critical/Important
                        findings (up to 3 rounds), writes
                        review-findings.md.
                        Fix loop runs project test suite after each round
                        (auto-detected or configured via test_command).
                        Correctness agent detects swallowed errors.
                        Test-quality agent cross-refs spec acceptance
                        scenarios against test verification methods.
                        Agent leaderboard with MVP after every run.
                        Layer comparison (checkpoint vs final) in ship mode.
                        Project hints via .specify/review-hints.md.
                        Combines with spex-teams for parallel execution.
                        Optionally includes CodeRabbit + Copilot CLIs.
                        Flags: --no-external, --no-coderabbit, --no-copilot
                               --external, --coderabbit, --copilot

  spex-worktrees extension:
    /speckit-specify  → creates git worktree for feature branch,
                        restores main (also auto-created by ship)
    /speckit-spex-worktrees-manage → list, create, finish, or cleanup worktrees

  spex-collab extension:
    /speckit-tasks    → auto-generates REVIEWERS.md, offers [Spec] PR
    /speckit-implement → presents phase split proposal (before hook)
    /speckit-spex-collab-phase-manager → PR creation + REVIEWERS.md updates per phase
                                         After spec PR: suggests triage with /loop command
                                         After spec triage: gate check recommends same-PR or split
                                         After impl push: suggests triage (deep-review first if enabled)
    /speckit-spex-collab-revise   → revise spec from PR feedback, cascade plan/tasks
    /speckit-spex-collab-reconcile → scan code against revised tasks, produce delta
    /speckit-spex-collab-triage   → triage PR review comments (bot autonomous + human interactive)
                                    Flags: --pr <number>
                                    Loop:  /loop 5m /speckit-spex-collab-triage

  spex-detach extension:
    /speckit-spex-finish → creates clean PR branch (pr/<branch>) with spec
                           artifacts stripped, offers "Push clean PR branch
                           to upstream" option. Verifies no .specify/, specs/,
                           or brainstorm/ dirs remain on the clean branch.
    /speckit-spex-detach-detach  → manual detach, archive, or brainstorm-context
                                   Subcommands: detach, archive, brainstorm-context
    /speckit-spex-brainstorm     → when enabled + archive.path configured,
                                   writes brainstorm docs to project-specs repo
    Optional before_finish hook archives specs to project-specs repo

  Triage lifecycle (spex-collab):
    After spec PR  → flow state: triage-spec, suggest /loop with delay notice
    After triage   → gate check: comment count vs split_threshold (default 100)
                     Below threshold: offer [Spec + Impl] title update
                     Above threshold: recommend separate impl PR(s)
    After impl PR  → flow state: triage-impl, suggest /loop with delay notice
    Status line    → T badge: ○ pending, ▶ active, ✓ complete
    Config         → triage.split_threshold (100), triage.loop_interval ("5m")
                     in .specify/extensions/spex-collab/collab-config.yml


spex COMMANDS (helpers and configuration)

  /spex:init                  Initialize spec-kit + configure extensions and permissions
                                --refresh: update templates without reconfiguring
                                --update: upgrade specify CLI and refresh
                                --clear: reset status line state
  /speckit-spex-worktrees-manage  List active worktrees, finish, or cleanup merged ones
  /speckit-spex-brainstorm    Rough idea into formal spec (interactive dialogue)
  /speckit-spex-ship          Autonomous full-cycle pipeline (brainstorm to finish)
                                Requires: spex-gates + spex-deep-review extensions
                                Flags: --ask always|smart|never, --create-pr,
                                       --resume, --start-from <stage>
                                Worktree: auto-creates if spex-worktrees enabled
  /speckit-spex-smoke-test    Focused interactive smoke test from spec's ## Smoke Test section
                                Claude automates setup/execution, human provides judgment
                                Auto-skips when no ## Smoke Test section exists
                                Writes SMOKE-TEST.md report to spec directory
                                Always interactive (even in ship pipeline)
  /speckit-spex-finish        Verify + merge/PR/keep (all-in-one feature completion)
                                Flags: --create-pr, --watch
                                --watch: monitor CI after PR, auto-fix failures,
                                         triage comments (if spex-collab enabled)
  /speckit-spex-review-spec   Check spec quality and completeness
  /speckit-spex-review-plan   Validate plan coverage, task quality, red flags
  /speckit-spex-review-code   Check code compliance against spec
  /speckit-spex-stamp         Verification only (use /speckit-spex-finish for full flow)
  /speckit-spex-evolve        Reconcile spec/code drift
  /speckit-spex-clear         Clear stuck state, dismiss status line
  /speckit-spex-help          This quick reference

CLOSING OUT A FEATURE (after review passes)

  After /speckit-spex-review-code (or deep-review) passes:

    1. /speckit-spex-smoke-test    Walk through curated smoke test scenarios
    2. /clear                      Free context for final verification
    3. /speckit-spex-finish         Verify + merge/PR (all-in-one)

  /speckit-spex-finish checks for before_finish hooks first (e.g., the
  smoke test prompt fires automatically via hook if not run manually).
  Then it runs all verification gates (tests, spec compliance, drift
  check), offers merge/PR/keep options with automatic worktree cleanup,
  and fires after_finish hooks (e.g., flow state cleanup). If a PR
  already exists for the branch, the "create PR" option becomes
  "push to PR #N" instead. One command to close out a feature.

  Extensions are managed via the specify CLI:
    specify extension enable <name>    Enable an extension
    specify extension disable <name>   Disable an extension


PR TITLE CONVENTIONS

  Feature Name [Spec]              Spec-only PR for review
  Feature Name [Spec + Impl]       Spec + implementation (single phase)
  Feature Name [Spec + Impl (1/3)] Multi-phase implementation

  Labels (auto-applied, configurable in collab-config.yml):
    spex/spec           Spec under review
    spex/spec-approved  Spec approved, ready for implementation
    spex/implement      Implementation in progress
    Set labels.enabled: false to disable


MULTI-AGENT SUPPORT

  spex works across Claude Code, Codex CLI, and OpenCode.
  Enforcement adapts to each agent's hook API.

  Agent detection priority:
    1. Environment variables (CLAUDE_PROJECT_DIR, CODEX_SESSION_ID)
    2. Directory presence (.claude/, .codex/, .opencode/)
    3. --ai value from .specify/init-options.json

  Per-agent adapters:
    Claude Code  Python hooks in .claude/settings.json (existing)
    Codex CLI    Python hooks in .codex/hooks.json
    OpenCode     TypeScript plugin in .opencode/plugins/

  Shared enforcement logic lives in spex/scripts/hooks/shared/.
  All adapters call the same POSIX shell functions for gate decisions.

  Extensions degrade gracefully:
    spex-gates, spex-collab     Full functionality on all agents
    spex-teams                  Sequential fallback (no parallel)
    spex-worktrees              Manual git worktree commands
    spex-deep-review            Single-session sequential review


BACKPRESSURE CONFIGURATION (.specify/extensions/spex/spex-config.yml)

  implement:
    test_between_tasks: true     # Run tests after each task (default: true)
                                 # Set false to skip inter-task checkpoints
    review_checkpoints: true     # Mid-impl correctness reviews at 1/3 and 2/3
                                 # Requires spex-deep-review, min 3 tasks
                                 # Set false to skip mid-implementation reviews
  watch:
    timeout_minutes: 30          # Max watch duration (default: 30)
    poll_interval_seconds: 60    # CI polling interval (default: 60)

  Per-task test checkpoints run during ship Stage 6 (implement).
  Test command auto-detected: Makefile, package.json, go.mod, pytest, cargo.
  Mid-impl review checkpoints at 1/3 and 2/3 (requires spex-deep-review, 3+ tasks).
  Agent leaderboard with MVP shown after every deep review run.
  Ship Stage 8 is smoke-test (curated scenarios from ## Smoke Test section).
  Claude automates setup/execution, human provides pass/fail judgment.
  Auto-skips when no ## Smoke Test section exists. Writes SMOKE-TEST.md.
  The pipeline stops after smoke-test; run /speckit-spex-finish manually.
  Watch mode runs during finish (when --create-pr is set after manual finish).
  Watch monitors CI, auto-fixes failures (max 2 attempts), and triages
  review comments when spex-collab is enabled.


COMMON MISTAKES (do NOT use these)

  /spex:specify   ✗  Does not exist → use /speckit-specify
  /spex:plan      ✗  Does not exist → use /speckit-plan
  /spex:tasks     ✗  Does not exist → use /speckit-tasks
  /spex:implement ✗  Does not exist → use /speckit-implement
  /spex:brainstorm ✗  Old name → use /speckit-spex-brainstorm
  /spex:ship       ✗  Old name → use /speckit-spex-ship
  /spex:evolve     ✗  Old name → use /speckit-spex-evolve
  /spex:traits    ✗  Removed → use `specify extension enable/disable`

  Rule: spex commands use /speckit-spex-* prefix (brainstorm, review, evolve).
        Spec-kit commands use /speckit-* prefix (specify, plan, implement).
