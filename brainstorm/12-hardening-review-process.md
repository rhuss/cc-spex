# Brainstorm 12: Hardening the Spec-Driven Review Process

**Date**: 2026-05-22
**Origin**: Post-mortem on kagenti-operator bug where `r.Patch()` inside `persistCardFetchAnnotation` wiped in-memory status mutations, causing `status.card` and all conditions to disappear from the API server
**Status**: active

## The Incident

Feature spec 001-agentcard-into-status defined clear acceptance criteria: "confirm `status.card` is populated via `kubectl get agentruntime -o yaml`". The deep review ran, found 18 issues (3 Critical), and the fix loop resolved them. One Critical finding (FINDING-1) flagged that annotations weren't being persisted to the API server. The fix introduced `persistCardFetchAnnotation` with `r.Patch()`.

That fix introduced a new bug: `r.Patch()` refreshes the passed object from the API server, wiping all in-memory status mutations (card data, CardSynced, TargetResolved, ConfigResolved conditions) that hadn't yet been persisted via `Status().Update()`.

The deep review passed. All 180 unit tests passed. The bug was only caught during manual testing on a kind cluster.

## Detailed Regression Analysis

### The Code Path

The `AgentRuntimeReconciler.Reconcile` method builds up status in-memory across several steps:

1. **Step 4**: Sets `TargetResolved=True` condition (in-memory on `rt`)
2. **Step 5**: Sets `ConfigResolved=True` condition (in-memory on `rt`)
3. **Step 5.5**: Calls `fetchAndUpdateCard(ctx, rt)` which:
   - Resolves the Service for the workload
   - Fetches the card via HTTP
   - Sets `rt.Status.Card = cardStatus` (in-memory)
   - Sets `CardSynced=True` condition (in-memory)
   - Calls `persistCardFetchAnnotation(ctx, rt, changeKey)`
4. **Step 6**: Applies workload config
5. **Step 8**: Sets `Ready=True` condition, calls `r.Status().Update(ctx, rt)` to persist everything

The critical function `persistCardFetchAnnotation` does this:

```go
func (r *AgentRuntimeReconciler) persistCardFetchAnnotation(ctx context.Context, rt *agentv1alpha1.AgentRuntime, changeKey string) {
    patch := client.MergeFrom(rt.DeepCopy())
    annotations := rt.GetAnnotations()
    annotations[AnnotationLastCardFetchHash] = changeKey
    rt.SetAnnotations(annotations)
    if err := r.Patch(ctx, rt, patch); err != nil {  // <-- THIS LINE
        logger.Error(err, "Failed to persist card fetch annotation")
    }
}
```

The `r.Patch(ctx, rt, patch)` call at the marked line does two things:
1. Sends the annotation change to the API server (intended)
2. Refreshes `rt` from the API server response (unintended side effect)

After the Patch call, `rt` reflects the API server's state, which has no knowledge of the in-memory status mutations from steps 1-3. All conditions (`TargetResolved`, `ConfigResolved`, `CardSynced`) and `status.card` are gone.

When step 8 finally calls `Status().Update(ctx, rt)`, it persists only the `Ready` condition (set after `fetchAndUpdateCard` returns) and nothing else.

### Observable Symptoms

**Before the fix (running locally with `make run` against a dummy workload with no Service)**:
- Status showed: `TargetResolved`, `ConfigResolved`, `Ready` (3 conditions)
- No `CardSynced` because the Service resolution failed, so `persistCardFetchAnnotation` was never called, so the in-memory conditions survived

**After the fix (deployed in-cluster against the currency converter agent with a matching Service)**:
- Status showed: `Ready` only (1 condition)
- `TargetResolved`, `ConfigResolved`, `CardSynced`, and `status.card` all missing
- The card fetch actually succeeded (visible in operator logs: "Successfully fetched agent card"), but the data was wiped before persistence

This asymmetry between "no Service" (conditions survive) and "Service found" (conditions wiped) made the bug hard to spot during development, since local testing typically used dummy workloads without a matching Service.

### Why Unit Tests Didn't Catch It

The existing card fetch tests called `fetchAndUpdateCard` on `rt` objects that were either:
- Not created in the envtest API server at all (pure in-memory), or
- Created but the test only checked `rt` in-memory after the call

When `r.Patch(ctx, rt, patch)` runs against an object that doesn't exist in the API server, it returns a NotFound error. The error is logged but not returned (the function has no return value). The Patch fails silently, `rt` is NOT refreshed from the server, and the in-memory mutations survive. The test passes.

This means the tests were accidentally testing the happy path of a different code path: the one where the Patch fails. In production, the Patch succeeds, the object is refreshed, and the status is wiped.

### The Fix

Two lines in `persistCardFetchAnnotation`:

```go
savedStatus := rt.Status.DeepCopy()
// ... r.Patch(ctx, rt, patch) ...
rt.Status = *savedStatus
```

Save the in-memory status before the Patch call, restore it after. The Patch can now refresh `rt` from the server (updating metadata, resourceVersion) without losing the accumulated status mutations.

### Regression Test

The new test creates a real `AgentRuntime` in envtest, pre-sets `TargetResolved` and `ConfigResolved` conditions, runs `fetchAndUpdateCard` with a stub fetcher, then asserts that `status.card`, `CardSynced`, `TargetResolved`, and `ConfigResolved` all survive the annotation patch. This test would have caught the original bug immediately because the `r.Patch()` call succeeds against the envtest API server, triggering the object refresh.

## Why the Process Failed

### 1. The fix-for-finding was not re-reviewed

The deep review found FINDING-1 (annotation not persisted). The auto-fix loop added `persistCardFetchAnnotation`. The review validated that the annotation now persists, not that the fix preserved existing behavior. The fix introduced new code that was never reviewed with the same rigor as the original implementation.

**Root cause**: The fix loop validates that the finding is resolved, but doesn't check for regressions introduced by the fix itself.

### 2. Tests verified in-memory state, not API server state

The existing card fetch tests called `fetchAndUpdateCard` on objects that either weren't created in envtest or were only checked in-memory after the call. The `r.Patch()` call inside `persistCardFetchAnnotation` silently failed (no object in the API server to patch), so the side effect never triggered.

The spec's own acceptance scenario says "confirm via `kubectl get`" (i.e., read back from the API server), but the test only checked the in-memory `rt` object.

**Root cause**: Tests validated the function's internal behavior rather than the observable outcome the spec described.

### 3. Framework-specific side effects are invisible to code review

`r.Patch(ctx, rt, patch)` mutating `rt` in-place with the API server response is a controller-runtime implementation detail. Nothing in the function signature or the code structure hints at this. A reviewer would need deep framework knowledge to spot it.

**Root cause**: The review agents don't have specialized knowledge about controller-runtime's mutation semantics.

## Would a Post-Fix Deep Review Have Caught This?

**Probably not, for the same reason the first review missed it.**

A fresh-context deep review after fixes would re-examine all code from scratch. The correctness agent would see `persistCardFetchAnnotation` calling `r.Patch()` and would need to know that Patch mutates the input object. Without controller-runtime-specific knowledge, the agent would see a standard patch-and-log pattern and move on.

However, a post-fix review **would help** if:

- The review agents were primed with framework-specific gotchas (see Proposal 3 below)
- The test quality agent checked whether tests match the spec's verification method ("confirm via kubectl get" means test must read back from API server)

So the answer is: a post-fix deep review is necessary but not sufficient. It catches regressions the fix loop doesn't look for, but it won't catch framework-specific side effects without domain knowledge.

## Proposals

### Proposal 1: Re-review After Fix Loop (Low Effort, Moderate Impact)

Run a second deep review pass after all fix-loop rounds complete, with a fresh context. The review prompt should explicitly include: "The following findings were fixed in this session. Check whether any fix introduced new issues."

This catches:
- Regressions from fix code that the finding-specific validation missed
- New patterns introduced by fixes that the original review didn't see

This misses:
- Framework-specific gotchas (same blind spot as the first review)

**Implementation**: Add a `post_fix_review` phase to `speckit-spex-deep-review-run` that re-dispatches the correctness and test-quality agents after the fix loop completes. The prompt includes the findings and their fixes as context.

### Proposal 2: Spec-Anchored Test Validation (Medium Effort, High Impact)

Add a check to the test-quality review agent: for each acceptance scenario in the spec, verify that the corresponding test uses the same verification method the spec describes.

If the spec says "confirm `status.card` is populated via `kubectl get agentruntime -o yaml`", the test must read the object back from the API server (envtest client), not just inspect in-memory state.

Concretely, the test-quality agent should:
1. Parse acceptance scenarios from spec.md
2. For each scenario, find the corresponding test
3. Check whether the test's assertions match the spec's verification method
4. Flag mismatches: "Spec says 'confirm via kubectl get' but test only checks in-memory object"

This catches:
- Tests that pass locally but don't verify the observable outcome
- Tests that mock away the exact layer where bugs hide

**Implementation**: Enhance the test-quality agent's prompt with instructions to cross-reference spec acceptance scenarios against test verification methods.

### Proposal 3: Framework Gotchas Context (Medium Effort, High Impact)

Allow projects to provide framework-specific review hints in a `.specify/review-hints.md` or similar file. These are injected into the deep review agents' context.

Example for a controller-runtime project:
```markdown
## controller-runtime Gotchas

- `client.Patch(ctx, obj, patch)` and `client.Update(ctx, obj)` refresh `obj`
  from the API server response. Any in-memory mutations to `obj` that haven't
  been persisted will be lost.
- `Status().Update()` only persists the status subresource. Metadata changes
  (labels, annotations) require a separate Patch/Update on the main resource.
- When mixing metadata patches and status updates in a single reconcile, the
  metadata patch must either happen before all in-memory status mutations, or
  the status must be saved/restored across the patch.
```

This catches:
- The exact class of bug we hit: Patch wiping in-memory status
- Other framework-specific patterns that are invisible to generic code review

**Implementation**: If `.specify/review-hints.md` exists, append its content to each review agent's system prompt. Projects opt in by creating the file.

### Proposal 4: Live Smoke Test Gate (High Effort, Highest Impact)

Add an optional gate to spex-finish that runs a minimal deployment test against a local cluster (kind/k3d). The spec's acceptance scenarios define what to check. This is the most expensive option but catches bugs that no amount of code review or unit testing can find.

This is probably too heavyweight for the general case, but could be offered as an extension for Kubernetes operator projects.

### Proposal 5: Reconcile-Level Integration Tests in Spec (Low Effort, Moderate Impact)

Add guidance to the spec template encouraging integration-level acceptance tests for controller reconcile loops. Specifically: "For Kubernetes controllers, acceptance tests SHOULD create resources in envtest, run a full reconcile, then read the resource back from the API server to verify status." This makes the test-quality agent's job easier by making the expectation explicit in the spec.

## Recommended Priority

1. **Proposal 2** (spec-anchored test validation): Highest ROI. Directly prevents the class of bug we hit. The spec already had the right acceptance criteria. The process just didn't enforce that tests matched them.
2. **Proposal 1** (post-fix re-review): Low effort safety net. Catches regressions from the fix loop.
3. **Proposal 3** (framework gotchas): Project-specific but high value for teams working with frameworks that have non-obvious mutation semantics.
4. **Proposal 5** (reconcile test guidance): Nearly free, just template text.
5. **Proposal 4** (live smoke test): Only for projects where it justifies the infrastructure cost.

## Open Questions

1. Should the post-fix review (Proposal 1) run all 5 agents or just correctness + test-quality? Running all 5 doubles the cost.
2. For Proposal 2, how should the test-quality agent handle specs where the verification method is implicit? (e.g., "card data is populated" without specifying how to check)
3. Should framework gotchas (Proposal 3) be per-project or publishable as shared packages? (e.g., a "controller-runtime review hints" package that any operator project can pull in)
4. How do we handle the bootstrapping problem: the first time a project uses spex, there are no review hints yet, and the first bug teaches you what hints you need?

---

## Revisit: 2026-05-22

### Reassessment

Tracing the causal chain backward from the bug:

1. Deep review found FINDING-1 (annotation not persisted). Correct finding.
2. Fix loop added `persistCardFetchAnnotation` with `r.Patch()`. Fix resolved the finding.
3. `r.Patch()` silently mutated `rt` in-place (controller-runtime side effect), wiping in-memory status.
4. Fix loop re-reviewed only whether FINDING-1 was resolved. It was. Gate passed.
5. Tests passed because `r.Patch()` failed silently against objects not in envtest.
6. Bug found manually on a real cluster.

The reassessment identified a gap not in the original proposals: **the fix loop never runs the project's test suite.** It applies fixes, re-reviews the code, but doesn't run `make test`. Even with weak tests, running them is free. With good tests (per Proposal 2), this is the kill shot.

A second gap is **silent error swallowing**: `persistCardFetchAnnotation` logs the Patch error but doesn't return it. The Patch call failed silently in tests (object not in envtest), so the mutation side effect never triggered. The correctness agent should flag functions that swallow errors from API server calls.

**What would NOT have helped**: another full code review pass (same framework blind spot), more external tools (same limitation), or a post-fix re-review alone (Proposal 1 without test execution adds review cost without a stronger signal than running the tests).

### Updated Decision

**Approach A: All changes in the deep review extension.** Four interventions:

1. **Fix loop runs test suite** after each fix round (before re-review). Test failures become Critical findings. Test command auto-detected from project structure (Makefile, package.json, go.mod, etc.).
2. **Spec-anchored test validation** (Proposal 2). Enhance the test-quality agent to cross-reference spec acceptance scenarios against test verification methods. Flag mismatches (e.g., "spec says confirm via kubectl get but test only checks in-memory object").
3. **Swallowed error detection** (new). Enhance the correctness agent to flag functions that call fallible operations (API calls, I/O) and log-but-don't-return errors.
4. **Framework gotchas injection** (Proposal 3). If `.specify/review-hints.md` exists, inject its content into every review agent's preamble. Projects opt in by creating the file.

### Out of Scope

- Post-fix full re-review as a separate pass (Proposal 1 alone). The fix loop test execution provides a stronger regression signal with less cost.
- Live smoke test gate (Proposal 4). Too heavyweight for the general case.
- Separate extension for review hints. The file is project content, not spex infrastructure.
- Reconcile test guidance in spec template (Proposal 5). Nearly free but deferred; the spec-anchored test validation addresses the same gap more rigorously.

### Open Threads

- How should fix loop test failures interact with the round counter? Should a test failure consume a fix round, or should the fix be reverted and the finding re-opened?
- For spec-anchored test validation, how to handle specs where the verification method is implicit? (e.g., "card data is populated" without specifying how to check)
- Should `review-hints.md` support sections per language/framework, or is a flat file sufficient?

## References

- kagenti-operator spec 001-agentcard-into-status (the incident)
- kagenti-operator review-findings.md FINDING-1 (the original finding whose fix introduced the bug)
- controller-runtime client.Patch documentation
- Brainstorm 02 (spec evolution, related concept of keeping specs aligned with reality)
