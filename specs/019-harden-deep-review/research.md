# Research: Harden Deep Review Process

## R1: Fix Loop Insertion Point for Test Execution

**Decision**: Insert test suite execution between Step 7.5 (after applying fixes and staging) and Step 7.7 (before re-dispatching review agents). The test run happens after `git add` but before re-review.

**Rationale**: Running tests after staging confirms the fix doesn't break existing functionality. Running before re-review means test failures can be reported as findings in the same round's output.

**Alternatives considered**:
- Run tests before staging: Rejected because unstaged changes could cause spurious failures.
- Run tests after re-review: Rejected because test failures would be discovered too late (after agents already re-reviewed).

## R2: Test Command Auto-Detection Order

**Decision**: Detection order: (1) Config override `test_command` in `deep-review-config.yml`, (2) Makefile with `test` target, (3) `go.mod` -> `go test ./...`, (4) `package.json` with `test` script -> `npm test`, (5) `pyproject.toml` or `setup.py` -> `pytest`. First match wins.

**Rationale**: Config override takes precedence for projects with non-standard test commands. The remaining order follows ecosystem prevalence in the projects most likely to use deep review.

**Detection commands**:
```bash
# 1. Config override
yq -r '.test_command // ""' "$DEEP_REVIEW_CONFIG" 2>/dev/null

# 2. Makefile test target
grep -q '^test:' Makefile 2>/dev/null && echo "make test"

# 3. Go module
[ -f go.mod ] && echo "go test ./..."

# 4. Node.js
[ -f package.json ] && jq -e '.scripts.test' package.json >/dev/null 2>&1 && echo "npm test"

# 5. Python
([ -f pyproject.toml ] || [ -f setup.py ]) && echo "pytest"
```

## R3: Review Hints Injection Position

**Decision**: Inject `.specify/review-hints.md` content after the common preamble (item 9: SPEC AWARENESS) and before each agent's role-specific prompt. Wrap in a clearly delimited section.

**Rationale**: The common preamble sets behavioral rules for all agents. The hints provide project-specific knowledge that should be available before the agent reads its checklist. Placing between preamble and checklist ensures hints inform the review without overriding behavioral rules.

**Injection format**:
```
10. PROJECT REVIEW HINTS: The following framework-specific patterns have been
    identified by the project maintainers. Use this knowledge when reviewing code.
    These patterns describe non-obvious behaviors that may not be apparent from
    reading the code alone.

    [contents of .specify/review-hints.md]
```

## R4: Swallowed Error Detection Scope

**Decision**: The correctness agent checks for functions that call fallible operations and log the error without returning or propagating it. Scope limited to: API server calls (`Patch`, `Update`, `Create`, `Delete`, `Get`), file I/O operations (`os.Open`, `os.Create`, `ioutil.ReadFile`), network calls (`http.Get`, `http.Post`, `net.Dial`), and language-equivalent patterns in Python/JS/Bash.

**Rationale**: Narrowing to specific operation categories prevents false positives from intentional fire-and-forget patterns (e.g., best-effort logging, metric emission).

**Alternatives considered**:
- Flag all logged-but-not-returned errors: Too broad, would flag legitimate best-effort patterns.
- Only flag API server calls: Too narrow, would miss file I/O and network swallowed errors.

## R5: Test Failure Finding Schema

**Decision**: Test failures use the standard finding schema with specific field values:
```json
{
  "source_agent": "test-suite",
  "category": "regression",
  "confidence": 95,
  "severity": "Critical",
  "description": "Test [test name] failed after fix round N: [failure message]",
  "file": "[test file path]",
  "line_start": 0,
  "fix": "Revert or correct the fix that caused the regression"
}
```

**Rationale**: Using `source_agent = "test-suite"` distinguishes test failures from review agent findings. High confidence (95) because test failures are objective, not heuristic. `category = "regression"` enables filtering in the summary table.
