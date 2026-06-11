# Research: Guided Smoke Test

## R1: How to parse Given/When/Then scenarios from spec.md

**Decision**: Scan the "User Scenarios & Testing" section for numbered items containing bold **Given**, **When**, **Then** keywords. Exclude the Edge Cases section. Parse each scenario into a structured triple: precondition (Given), action (When), expected outcome (Then).

**Rationale**: The spec template already uses this format consistently. No custom syntax needed. The parsing is text-based (grep/regex on markdown), not a formal grammar.

**Alternatives considered**:
- Formal BDD parser (Gherkin): Over-engineered for markdown-embedded scenarios
- Separate test file: Rejected in brainstorm (scenarios should live in the spec)

## R2: How to auto-detect project type and start command

**Decision**: Reuse the existing detection logic from the verify command. Check in order:
1. Makefile with `run` or `serve` target
2. package.json with `start` script
3. go.mod (use `go run .`)
4. Python with `manage.py` (Django), `app.py`/`main.py` (Flask/FastAPI)
5. Cargo.toml (use `cargo run`)
6. Delegate to `/run` skill if available (checked at runtime via active skill list)

**Rationale**: Consistency with existing spex behavior. The `/run` skill may have more sophisticated detection, so delegate to it when present.

## R3: How to manage the app process lifecycle

**Decision**: Start the app as a background process via Bash tool with `run_in_background`. Track the process ID. Attempt graceful shutdown (SIGTERM) when the smoke test completes or the user exits early. If graceful shutdown fails after 5 seconds, force kill (SIGKILL).

**Rationale**: The smoke test must clean up after itself. Orphaned processes would confuse the user and waste resources.

## R4: Ship pipeline stage restructuring

**Decision**: Replace stage 8 (finish) with smoke-test. The pipeline becomes 9 stages (0-8) with smoke-test at index 8. Finish is removed from the pipeline entirely; the user runs it manually.

**Changes needed in `speckit.spex.ship.md`**:
- Stage 8 definition: change from finish to smoke-test
- Remove the finish subagent spawn
- Add smoke-test invocation (always interactive, ignores `ask` level)
- After smoke-test completes, output instructions to run `/speckit-spex-finish` manually
- Update the `--start-from` valid stage names: replace `finish` with `smoke-test`
- Update the state script's stage list if hardcoded

**Impact**: The `spex-ship-state.sh` advance command auto-cleans after stage 8. This behavior should now output `PIPELINE_COMPLETE` with a message about running finish manually, rather than implying the pipeline is fully done.

## R5: Verify/stamp smoke test reminder

**Decision**: Add a check at the beginning of the verify command: if the spec has acceptance scenarios (detected by grepping for Given/When/Then in the spec) and the state file does not contain `smoke_test_completed: true`, display an informational reminder. Do not block.

**Implementation point**: Add this check before the existing "Run Tests" step in `speckit.spex-gates.verify.md`. It's a read-only check that prints a message.
