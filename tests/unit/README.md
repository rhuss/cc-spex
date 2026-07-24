# Unit test conventions

This directory contains fast, deterministic tests of one script, contract, or
adapter behavior at a time. Unit tests must not require an installed Claude,
Codex, or OpenCode client, network access, or changes to the user's real
configuration.

## Naming and layout

- Name shell suites `test_<behavior>.sh` and Python suites
  `test_<behavior>.py`.
- Keep reusable fixtures under `tests/fixtures/`; do not generate test data in
  the source or plugin distribution trees.
- Put shared shell helpers in `tests/lib/test_helpers.sh`. Keep assertions that
  are specific to one behavior in that behavior's test file.
- Resolve repository paths from the test file's location so a suite works from
  any current directory and from a Git worktree.

## Isolation and determinism

- Create disposable homes, repositories, and worktrees for filesystem tests.
  Register cleanup before the first operation that can fail.
- Never read or write the developer's real harness configuration, plugin cache,
  Git configuration, or home directory.
- Stub capability probes and external clients. A test that needs a real harness
  belongs in `tests/integration/`.
- Assert machine-readable output and exit status. For stateful behavior, also
  assert the resulting files, revisions, and failure atomicity.
- Cover the successful path, malformed input, and refusal/failure behavior.
  State and materialization tests should include idempotence where applicable.
- Use fixed inputs and compare semantic content. Normalize paths, timestamps,
  and generated identifiers rather than relying on the host environment.

## Running tests

Run the complete suite from the repository root with:

```sh
make test-unit
```

During development, run the affected file directly (`bash` for shell suites or
`python3 -m unittest`/`python3 -m pytest` as selected by that suite). A unit
test must leave the working tree unchanged after both success and failure.
