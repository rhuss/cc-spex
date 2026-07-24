#!/usr/bin/env bash
# Disposable Codex Teams writer lifecycle contract (T055).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
IMPLEMENT="$REPO_ROOT/spex/extensions/spex-teams/commands/speckit.spex-teams.implement.md"
ORCHESTRATE="$REPO_ROOT/spex/extensions/spex-teams/commands/speckit.spex-teams.orchestrate.md"

for dependency in git; do
  command -v "$dependency" >/dev/null 2>&1 || {
    echo "ERROR: required integration dependency is missing: $dependency" >&2
    exit 2
  }
done

# T059/T060 own an instruction-driven integration boundary. Fail once until
# all lifecycle phases are explicit, rather than cascading through a Git
# fixture that cannot prove the orchestrator is required to perform them.
teams_contract="$(cat "$IMPLEMENT" "$ORCHESTRATE")"
missing_contract=()
for requirement in \
  "isolated writer worktree" \
  "accepted reconciliation" \
  "dependent release" \
  "preserve partial work" \
  "replacement assignment" \
  "cleanup worktree"; do
  if ! grep -qiF "$requirement" <<<"$teams_contract"; then
    missing_contract+=("$requirement")
  fi
done
if ((${#missing_contract[@]} > 0)); then
  echo "FAIL: Codex Teams writer lifecycle is not implemented." >&2
  printf 'T055 requires explicit protocol for: %s\n' "${missing_contract[*]}" >&2
  exit 1
fi

# shellcheck source=../lib/test_helpers.sh
source "$REPO_ROOT/tests/lib/test_helpers.sh"
trap spex_test_cleanup EXIT HUP INT TERM

PASSED=0
FAILED=0
pass() { printf 'PASS: %s\n' "$1"; PASSED=$((PASSED + 1)); }
fail() { printf 'FAIL: %s\n' "$1" >&2; FAILED=$((FAILED + 1)); }

commit_file() {
  local worktree="$1" path="$2" content="$3" message="$4"
  mkdir -p "$(dirname "$worktree/$path")"
  printf '%s\n' "$content" >"$worktree/$path"
  git -C "$worktree" add "$path" && git -C "$worktree" commit -q -m "$message"
}

review_writer() {
  local worktree="$1" allowed_file="$2" required_text="$3"
  local base changed
  base="$(git -C "$worktree" merge-base HEAD "$FEATURE_BRANCH")" || return 1
  changed="$(git -C "$worktree" diff --name-only "$base" HEAD)" || return 1
  [[ "$changed" == "$allowed_file" ]] || return 1
  grep -qF "$required_text" "$worktree/$allowed_file"
}

remove_writer() {
  local repository="$1" worktree="$2"
  git -C "$repository" worktree remove "$worktree"
}

echo "=== Two isolated writers and gated dependent release ==="
spex_test_make_repo FEATURE_REPO
FEATURE_BRANCH="$(git -C "$FEATURE_REPO" branch --show-current)"
mkdir -p "$FEATURE_REPO/specs/055-teams"
cat >"$FEATURE_REPO/specs/055-teams/spec.md" <<'EOF'
# Teams fixture

- Writer A must provide alpha capability.
- Writer B must provide beta capability.
- The dependent combines reviewed alpha and beta results.
EOF
git -C "$FEATURE_REPO" add specs/055-teams/spec.md
git -C "$FEATURE_REPO" commit -q -m "Add Teams fixture specification"

spex_test_make_worktree "$FEATURE_REPO" "teams/writer-a" WRITER_A
spex_test_make_worktree "$FEATURE_REPO" "teams/writer-b" WRITER_B

if [[ "$WRITER_A" != "$WRITER_B" ]] &&
   [[ "$(git -C "$WRITER_A" rev-parse --show-toplevel)" == "$(cd "$WRITER_A" && pwd -P)" ]] &&
   [[ "$(git -C "$WRITER_B" rev-parse --show-toplevel)" == "$(cd "$WRITER_B" && pwd -P)" ]]; then
  pass "independent writers receive distinct isolated worktrees"
else
  fail "writer worktrees are not distinct and explicit"
fi

commit_file "$WRITER_A" src/alpha.txt "alpha capability" "Implement writer A"
commit_file "$WRITER_B" src/beta.txt "beta capability" "Implement writer B"
WRITER_A_OID="$(git -C "$WRITER_A" rev-parse HEAD)"
WRITER_B_OID="$(git -C "$WRITER_B" rev-parse HEAD)"

if [[ ! -e "$FEATURE_REPO/src/alpha.txt" && ! -e "$FEATURE_REPO/src/beta.txt" ]]; then
  pass "writer mutations remain isolated before review"
else
  fail "writer mutations leaked into the feature checkout before review"
fi

DEPENDENT_RELEASED=false
if review_writer "$WRITER_A" src/alpha.txt "alpha capability" &&
   review_writer "$WRITER_B" src/beta.txt "beta capability"; then
  pass "both writer results pass scope and specification review"
else
  fail "writer result failed specification review"
fi

if [[ "$DEPENDENT_RELEASED" == false ]]; then
  pass "dependent remains blocked before prerequisite reconciliation"
else
  fail "dependent was released before reconciliation"
fi

if git -C "$FEATURE_REPO" cherry-pick "$WRITER_A_OID" >/dev/null &&
   git -C "$FEATURE_REPO" cherry-pick "$WRITER_B_OID" >/dev/null &&
   [[ -f "$FEATURE_REPO/src/alpha.txt" && -f "$FEATURE_REPO/src/beta.txt" ]]; then
  DEPENDENT_RELEASED=true
  pass "accepted writer commits reconcile into the feature branch"
else
  fail "accepted writer results were not reconciled"
fi

if [[ "$DEPENDENT_RELEASED" == true ]]; then
  spex_test_make_worktree "$FEATURE_REPO" "teams/dependent" DEPENDENT
  if [[ -f "$DEPENDENT/src/alpha.txt" && -f "$DEPENDENT/src/beta.txt" ]]; then
    commit_file "$DEPENDENT" src/combined.txt \
      "combined reviewed alpha and beta" "Implement dependent result"
    DEPENDENT_OID="$(git -C "$DEPENDENT" rev-parse HEAD)"
    if git -C "$FEATURE_REPO" cherry-pick "$DEPENDENT_OID" >/dev/null; then
      pass "dependent starts only after reviewed prerequisites are reconciled"
    else
      fail "dependent result could not be reconciled"
    fi
  else
    fail "dependent worktree does not contain reconciled prerequisites"
  fi
fi

echo "=== Partial failure preservation and replacement ==="
spex_test_make_worktree "$FEATURE_REPO" "teams/failed-writer" FAILED_WRITER
commit_file "$FAILED_WRITER" evidence/partial.txt \
  "partial implementation and failure diagnostics" "Preserve failed writer evidence"
FAILED_OID="$(git -C "$FAILED_WRITER" rev-parse HEAD)"

spex_test_make_worktree "$FEATURE_REPO" "teams/replacement" REPLACEMENT
if [[ -f "$FAILED_WRITER/evidence/partial.txt" ]] &&
   git -C "$FEATURE_REPO" cat-file -e "$FAILED_OID^{commit}"; then
  pass "failed writer evidence survives replacement dispatch"
else
  fail "replacement dispatch discarded partial failure evidence"
fi

commit_file "$REPLACEMENT" src/recovered.txt \
  "replacement completed remaining assignment" "Complete replacement assignment"
REPLACEMENT_OID="$(git -C "$REPLACEMENT" rev-parse HEAD)"
if review_writer "$REPLACEMENT" src/recovered.txt \
    "replacement completed remaining assignment" &&
   git -C "$FEATURE_REPO" cherry-pick "$REPLACEMENT_OID" >/dev/null; then
  pass "reviewed replacement result reconciles without failed partial changes"
else
  fail "replacement result failed scope or specification review"
fi

echo "=== Successful lifecycle cleanup ==="
for worktree in "$WRITER_A" "$WRITER_B" "$DEPENDENT" "$REPLACEMENT" "$FAILED_WRITER"; do
  [[ -n "$worktree" ]] &&
    remove_writer "$FEATURE_REPO" "$worktree" || fail "could not clean worktree $worktree"
done
git -C "$FEATURE_REPO" worktree prune

remaining="$(git -C "$FEATURE_REPO" worktree list --porcelain)"
if [[ "$remaining" != *"$WRITER_A"* && "$remaining" != *"$WRITER_B"* &&
      "$remaining" != *"$DEPENDENT"* && "$remaining" != *"$REPLACEMENT"* &&
      "$remaining" != *"$FAILED_WRITER"* ]]; then
  pass "all Teams worktrees are removed after reconciliation"
else
  fail "Teams cleanup left a registered writer worktree"
fi

if git -C "$FEATURE_REPO" show "teams/failed-writer:evidence/partial.txt" \
    | grep -qF "failure diagnostics" &&
   [[ -f "$FEATURE_REPO/src/combined.txt" && -f "$FEATURE_REPO/src/recovered.txt" &&
      ! -e "$FEATURE_REPO/evidence/partial.txt" ]]; then
  pass "cleanup preserves failure evidence by branch and accepted feature results"
else
  fail "cleanup lost evidence or reconciled the rejected partial result"
fi

printf '\nCodex Teams lifecycle: %d passed, %d failed\n' "$PASSED" "$FAILED"
[[ $FAILED -eq 0 ]]
