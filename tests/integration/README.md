# Integration test conventions

This directory contains end-to-end tests that cross process or component
boundaries: plugin installation, initialization, worktree lifecycle, workflow
recovery, progress presentation, Teams orchestration, and multi-harness
coexistence. Logic that can be verified without a real boundary belongs in
`tests/unit/`.

## Naming and scenarios

- Name shell scenarios `test_<journey>.sh`; use Python only when fault injection
  or structured state assertions are materially clearer there.
- Each file should state its prerequisites, supported platforms, and whether it
  uses a real harness client near the top of the file.
- Build each suite around an independently useful user journey. Include the
  expected success path plus cleanup, interruption, or partial-failure behavior
  relevant to that journey.
- Reuse fixtures from `tests/fixtures/` and disposable-environment helpers from
  `tests/lib/test_helpers.sh`.

## Safety and isolation

- Run against disposable homes, repositories, worktrees, plugin caches, and
  project configuration. Never install into or mutate the user's real setup.
- Resolve paths from the test file or temporary repository, not the caller's
  current directory. This is required for worktree and delegated-CWD scenarios.
- Register cleanup before installation or mutation. Preserve diagnostic output
  on failure, but remove temporary registrations and processes reliably.
- Do not use the network unless the scenario is explicitly a remote-install
  test. Local materialized distributions are the default.
- Detect required clients and capabilities before mutation. Report an explicit
  skip when a supported environment is unavailable; do not turn a product
  failure into a skip.
- Use unique marketplace, plugin, repository, branch, and cache identities so
  parallel runs cannot collide.

## Assertions and execution

Assert both the visible journey and its durable effects: exit status, emitted
events, installed inventory, configuration, state revisions, active worktree,
and absence of writes in the wrong checkout. Cross-harness tests must also
check for identity collisions and foreign-harness leakage.

Run a scenario directly while developing it. The aggregate installation and
integration targets are wired through the repository `Makefile`; use `make
test` for the release-level suite once those targets are available. Tests that
require an unavailable client must identify the skipped prerequisite in their
summary, and every run must leave the source working tree unchanged.
