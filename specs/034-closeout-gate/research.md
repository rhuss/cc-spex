# Research: Deterministic closeout gate

## Decision: Parsing approach

**Decision**: Use `grep` + `awk` to parse the markdown severity summary table.

**Rationale**: The input is a markdown table, not JSON. Using `grep` to match rows by severity name and `awk` to extract the Remaining column is simpler and has no dependencies beyond standard Unix tools. No `jq` needed.

**Alternatives considered**:
- **jq with markdown-to-JSON conversion**: Rejected. Adds complexity and a conversion step for no benefit.
- **Python parser**: Rejected. Adds a Python dependency for a simple table extraction.

## Decision: Fail-open vs fail-closed default

**Decision**: Fail-open by default. `SPEX_CLOSEOUT_STRICT=1` enables fail-closed.

**Rationale**: The gate should catch problems when a review was done, not mandate that reviews must be done. Projects and features that don't use deep review should not be blocked by a missing report.

**Alternatives considered**:
- **Fail-closed by default**: Rejected. Would force deep review on all features, which contradicts the constitution's "SDD is not a gate on every code change" principle.

## Decision: Script output format

**Decision**: Machine-readable single-line output (e.g., `CLOSEOUT_FAIL critical=2 important=1`) with human-readable details on stderr.

**Rationale**: Follows the pattern of `spex-ship-state.sh` which outputs machine-readable status on stdout for callers to parse, and human-readable messages on stderr. The verify/stamp commands can check the exit code and display the stderr output to the user.
