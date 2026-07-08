---
description: "Triage PR review comments: autonomously handle bot suggestions, interactively review human comments"
argument-hint: "[--pr <number>]"
---

# PR Review Comment Triage

Triage all review comments on a PR: autonomously handle bot comments (assess, apply valid fixes, reject invalid, reply), then interactively present human comments for approval.

## Ship Pipeline Guard

If `.specify/.spex-state` exists with `mode: "ship"`, return immediately. Triage is an interactive collab workflow.

## Script References

```bash
TRIAGE_STATE=".specify/extensions/spex-collab/scripts/spex-triage-state.sh"
SANITIZE_JSON=".specify/extensions/spex-collab/scripts/sanitize-gh-json.py"
```

## Step 1: Resolve PR Context

Determine the PR number. If `--pr <number>` is provided in arguments, use that. Otherwise, detect the open PR for the current branch:

```bash
BRANCH=$(git branch --show-current)
PR_NUM=$(gh pr view "$BRANCH" --json number --jq '.number' 2>/dev/null)
```

If no PR is found, report "No open PR found for branch `$BRANCH`" and stop.

Verify `gh` authentication by checking the exit code. If it fails, report "gh CLI not authenticated, run `gh auth login`" and stop without partial processing.

**Validate PR number**: Ensure `PR_NUM` is a positive integer. If `--pr` was provided with a non-numeric value, report "Invalid PR number" and stop.

Extract owner and repo:

```bash
REMOTE_URL=$(git remote get-url origin 2>/dev/null)
OWNER=$(echo "$REMOTE_URL" | sed -n 's|.*github.com[:/]\([^/]*\)/.*|\1|p')
REPO=$(echo "$REMOTE_URL" | sed -n 's|.*github.com[:/][^/]*/\(.*\)\.git$|\1|p; s|.*github.com[:/][^/]*/\(.*\)$|\1|p')
```

**Validate extracted values**: If `OWNER` or `REPO` is empty (e.g., remote URL is not a GitHub URL), report "Could not extract owner/repo from origin URL. Ensure the remote points to a GitHub repository." and stop.

## Step 2: Initialize State

```bash
"$TRIAGE_STATE" init "$PR_NUM"
```

## Step 3: Fetch Review Threads

Fetch ALL review threads with their comments using GraphQL. PRs with many review comments (e.g., 3 bots x 20+ findings each) regularly exceed 100 threads, so pagination is mandatory.

**Important**: GitHub API responses can contain raw control characters (U+0000-U+001F) in comment bodies, which break `jq`. The sanitizer script MUST be in the pipeline between `gh api graphql` and any `jq` call.

**CRITICAL**: The entire fetch-sanitize-extract pipeline below MUST run in a SINGLE Bash tool call. Do NOT split it across multiple Bash calls, because shell variables (`PAGE_JSON`, `ALL_THREADS`, `CURSOR`) do not persist between calls, and the sanitized JSON data can be corrupted by re-serialization through `echo`.

### 3a: Pagination Loop

You MUST use a pagination loop. A single fetch is NOT sufficient -- a PR with 150 threads returns only the first 100, silently dropping the rest.

Run this entire block in one Bash call. Replace `$SANITIZE_JSON` with the literal path from the Script References section:

```bash
ALL_THREADS="[]"
CURSOR=""
PAGE=1

while true; do
  CURSOR_ARG=""
  [ -n "$CURSOR" ] && CURSOR_ARG="-f cursor=$CURSOR"

  # Fetch and sanitize in one pipeline - never run jq on unsanitized output
  PAGE_JSON=$(gh api graphql -f query='
    query($owner: String!, $repo: String!, $number: Int!, $cursor: String) {
      repository(owner: $owner, name: $repo) {
        pullRequest(number: $number) {
          reviewThreads(first: 100, after: $cursor) {
            totalCount
            pageInfo {
              hasNextPage
              endCursor
            }
            nodes {
              id
              isResolved
              path
              line
              comments(first: 50) {
                nodes {
                  id
                  databaseId
                  author {
                    login
                    ... on Bot { id }
                  }
                  body
                  createdAt
                }
              }
            }
          }
        }
      }
    }
  ' -f owner="$OWNER" -f repo="$REPO" -F number="$PR_NUM" $CURSOR_ARG \
    | python3 "$SANITIZE_JSON")

  # Use printf '%s' instead of echo to preserve sanitized JSON intact
  PAGE_THREADS=$(printf '%s' "$PAGE_JSON" | jq '.data.repository.pullRequest.reviewThreads.nodes')
  ALL_THREADS=$(printf '%s\n%s' "$ALL_THREADS" "$PAGE_THREADS" | jq -s '.[0] + .[1]')

  # Check for next page
  HAS_NEXT=$(printf '%s' "$PAGE_JSON" | jq -r '.data.repository.pullRequest.reviewThreads.pageInfo.hasNextPage')
  if [ "$HAS_NEXT" != "true" ]; then
    break
  fi

  CURSOR=$(printf '%s' "$PAGE_JSON" | jq -r '.data.repository.pullRequest.reviewThreads.pageInfo.endCursor')
  PAGE=$((PAGE + 1))
done

TOTAL_COUNT=$(printf '%s' "$PAGE_JSON" | jq -r '.data.repository.pullRequest.reviewThreads.totalCount')
FETCHED_COUNT=$(printf '%s' "$ALL_THREADS" | jq 'length')
```

### 3b: Verify Complete Fetch

After the pagination loop, verify all threads were fetched:

```
Fetched $FETCHED_COUNT / $TOTAL_COUNT review threads (in $PAGE pages)
```

**Hard rule**: If `FETCHED_COUNT < TOTAL_COUNT`, something went wrong with pagination. Report the mismatch and stop -- do not proceed with partial data.

If the API returns a 403 or 429 status on any page, detect rate limiting: report remaining rate limit info, and exit cleanly. Progress is already saved in the state file.

### 3c: CodeRabbit Rate Limit Detection and Local Fallback

After fetching review threads, check if CodeRabbit was rate-limited. CodeRabbit posts a summary comment (not an inline review thread) containing "Review limit reached" when the PR review limit is hit.

**Detection**: Fetch PR issue comments (not review threads) and check for a CodeRabbit rate-limit message:

```bash
CR_RATE_LIMITED=$(gh api "repos/$OWNER/$REPO/issues/$PR_NUM/comments" \
  --jq '[.[] | select(.user.login == "coderabbitai[bot]" and (.body | test("Review limit reached")))] | length' \
  2>/dev/null || echo "0")
```

**If `CR_RATE_LIMITED` > 0**: CodeRabbit could not review this PR due to rate limits. Check if the `coderabbit` CLI is available for a local review:

```bash
if command -v coderabbit >/dev/null 2>&1; then
  echo "CodeRabbit PR review was rate-limited. Running local CodeRabbit review as fallback..."
  coderabbit review 2>&1 || echo "WARNING: Local CodeRabbit review failed"
fi
```

If the local review succeeds, `coderabbit review` posts review comments directly to the PR (same as the bot would). The triage command then processes these comments in the normal flow (they appear as `coderabbitai[bot]` threads when fetched again, or as local output to parse).

**After running local review**, re-fetch review threads (go back to Step 3a) to pick up any new comments the local CLI posted. To avoid an infinite loop, only re-fetch once:

```bash
if [ "$CR_RATE_LIMITED" -gt 0 ] && command -v coderabbit >/dev/null 2>&1; then
  # Re-fetch after local review (one retry only)
  # ... repeat 3a pagination loop ...
fi
```

**If `coderabbit` CLI is not available**: Skip silently. The triage proceeds with whatever review threads exist from other bots. Report in the summary:
```
**CodeRabbit**: rate-limited (CLI not available for local fallback)
```

**If `CR_RATE_LIMITED` is 0**: No rate limit detected. Proceed normally to Step 4.

## Step 4: Partition Threads

Parse the GraphQL response and partition threads into bot and human categories.

For each thread in `reviewThreads.nodes`:

1. **Skip resolved threads**: If `isResolved` is true, skip entirely.
2. **Check state by exact comment ID**: For the first comment's `databaseId`, run:
   ```bash
   STATE_RESULT=$("$TRIAGE_STATE" get "$PR_NUM" "$COMMENT_DB_ID" 2>/dev/null || echo "")
   ```
   **Hard rule**: The ONLY way to determine if a comment was already handled is by checking the state file for the specific `databaseId`. Do NOT skip comments based on bot author name, file path, or similarity to previously handled comments. Bots re-post comments with new IDs after PR updates, so the old IDs are no longer valid. If `STATE_RESULT` is empty or "not_found", the comment is NEW and must be processed.
   For non-empty state results: if already handled, check for re-evaluation (see Step 10 for loop mode). For non-loop first invocations, skip handled comments.
3. **Determine author type**: Check the first comment's author. The primary indicator is the GraphQL `... on Bot { id }` fragment: if the author has a `Bot` type in the response, classify as bot. As a secondary fallback (for cases where the GraphQL type fragment is absent), check if the author login ends with `[bot]`. Classify as human only when neither indicator matches. The GraphQL type takes priority per FR-002.

Create two lists:
- **Bot threads**: Threads where the first comment is from a bot author
- **Human threads**: Threads where the first comment is from a human author

## Step 5: Bot Profile Matching

For each bot thread, match the bot author against known profiles.

**Hardcoded profiles**:

| Bot Login | Self-Resolves | Auto-Resolve After Handling |
|-----------|--------------|----------------------------|
| `coderabbitai[bot]` | Yes | No |
| `copilot[bot]` | No | Yes |
| `devin-ai-integration[bot]` | No | Yes |

**Config overrides**: Check if `.specify/extensions/spex-collab/collab-config.yml` exists. If so, read it with `yq`:

```bash
COLLAB_CONFIG=".specify/extensions/spex-collab/collab-config.yml"
if [ -f "$COLLAB_CONFIG" ]; then
  CUSTOM_PROFILES=$(yq -o=json '.triage.bot-profiles // []' "$COLLAB_CONFIG")
  OVERRIDES=$(yq -o=json '.triage.overrides // {}' "$COLLAB_CONFIG")
fi
```

Apply overrides to hardcoded profiles. For unknown bots (no matching profile), use conservative defaults: `selfResolves=false`, `autoResolve=false`.

## Step 5b: Bot Discovery Log

Before processing, log all discovered bot authors and thread counts. This makes it visible if any bot's threads are later skipped.

```
Found bot threads:
- copilot[bot]: 4 threads
- devin-ai-integration[bot]: 12 threads
- coderabbitai[bot]: 19 threads
Total: 35 bot threads to process
```

**Hard rule**: Every bot thread listed here MUST be individually assessed in Step 6. Do NOT batch-resolve, skip, or ignore threads from any bot. If a bot is not in the hardcoded profiles, use conservative defaults -- but still assess each thread.

## Step 6: Assess and Apply Bot Fixes

For each unresolved bot thread -- across ALL bot authors, not just one -- process the bot's suggestion:

### 6a: Read the Context

1. Read the comment body to understand the suggestion.
2. Read the file referenced by `thread.path` at the relevant lines.
3. If a spec exists (see Step 11 for spec-aware mode), include relevant spec requirements as context.

### 6b: Assess Validity

Evaluate the bot suggestion against the actual code. **Code correctness is the primary concern**, not spec compliance. A bot comment that identifies a real bug or inconsistency is valid even if the spec doesn't mention it. A rejection that only argues "the spec says X" without verifying the code actually does X is not acceptable.

Assessment approach:

1. **Verify the specific claim.** If the bot says "code does X but should do Y", confirm what the code *actually* does. Read the relevant lines and trace the logic. Do not assume alignment.
2. **Check for real issues.** Does the code have the bug/inconsistency the bot describes? Would the suggestion improve correctness, clarity, or robustness?
3. **Then check spec alignment.** If both code and suggestion are valid, prefer the approach that aligns with spec requirements. If the spec contradicts correct behavior, flag the spec for update.

Verdicts:

- **Valid**: The suggestion identifies a real issue (bug, inconsistency, misleading documentation) or improves code quality. The fix can be applied within the current PR scope.
- **Invalid**: The code is demonstrably correct at the specific lines cited, and the suggestion would not improve it. The rejection MUST cite the specific line(s) or function(s) that prove the bot wrong.
- **Deferred**: The suggestion has merit but is out of scope for this PR -- it requires a larger refactoring, an architectural change, a new feature, or touches code outside the PR's intent. The issue is real but cannot be addressed with a localized fix.

### 6c: Apply, Skip, or Defer

- **If valid**: Apply the fix using the Edit tool. Track the file path and a 1-line summary for the batch commit message.
- **If fix application fails** (file changed, line mismatch, syntax error): Skip the fix, mark for a reply noting the fix could not be applied automatically, and continue.
- **If invalid**: Skip the fix. Prepare a rejection reply with 1-5 sentence justification.
- **If deferred**: Skip the fix. Track the item in a deferred list with: bot author, file path, 1-line summary of the suggested improvement, and why it's out of scope. Prepare a deferral reply.

### 6d: Conflict Detection

Before applying a fix, check if another fix in this batch already modified the same file at overlapping lines. If so, skip the later fix and note the conflict for the summary.

### 6e: Deleted File Detection

If `thread.path` refers to a file that does not exist in the working tree, skip the fix and reply noting the target file no longer exists.

### 6f: Summary Comment Detection

If a bot comment is not attached to a specific file/line (no `path` or `line`), skip it. Summary comments are informational, not actionable.

## Step 7: Batch Commit and Push

After processing all bot comments, if any fixes were applied:

1. Stage all changed files.
2. Create a single commit:

```
fix: apply bot review suggestions (#<PR_NUM>)

Applied fixes from bot review comments:
- Comment #<id>: <1-line summary>
- Comment #<id>: <1-line summary>
...

Assisted-By: 🤖 Claude Code
```

3. Push to the remote branch.

If the commit or push fails (branch protection, remote rejection), report the error, keep the applied fixes in the working tree (do not revert), and skip reply posting for accepted comments (since fixes are not on the remote yet). Continue posting rejection replies.

Capture the commit SHA after pushing for use in acceptance replies.

## Step 7b: Check CI Status After Push

After pushing triage fixes, check if GitHub Actions CI is passing. Triage fixes can introduce regressions (e.g., a bot suggestion that breaks a test).

**Skip this step if**: no fixes were applied (nothing was pushed), or `gh` CLI is not available.

**Procedure:**

1. **Wait briefly for CI to start** (CI may take a few seconds to queue after a push):
   ```bash
   sleep 10
   ```

2. **Poll CI status** (up to 3 polls, 30 seconds apart):
   ```bash
   CI_OUTPUT=$(gh pr checks "$PR_NUM" 2>&1 || true)
   ```

   Check the output:
   - If all checks show `pass`/`success`: CI is green. Proceed to Step 8.
   - If checks show `pending`/`queued`/`in_progress`: Wait 30 seconds and poll again (up to 3 polls total). If still pending after 3 polls, report the status and proceed (do not block indefinitely).
   - If any check shows `fail`/`error`: Attempt a fix (see below).

3. **On CI failure**: Read the failing run's log:
   ```bash
   FAILING_URL=$(gh pr checks "$PR_NUM" --json name,state,detailsUrl --jq '.[] | select(.state == "FAILURE") | .detailsUrl' 2>/dev/null | head -1)
   ```

   Extract the run ID from the URL and read the failure log:
   ```bash
   RUN_ID=$(echo "$FAILING_URL" | grep -oE '[0-9]+$')
   gh run view "$RUN_ID" --log-failed 2>/dev/null | tail -50
   ```

   Scope the fix to files changed in this triage pass. Attempt to fix the issue (max 1 attempt). If the fix succeeds:
   ```bash
   git add -u
   git commit -m "fix: repair CI after triage fixes (#$PR_NUM)

   Assisted-By: 🤖 Claude Code"
   git push
   ```

   If the fix fails or the failure is unrelated to triage changes, report it in the summary and continue:
   ```
   WARNING: CI is failing after triage fixes. The failure may need manual attention.
   Failing check: <check-name>
   ```

4. **Report CI status** in Step 13 summary (add a line after the commit SHA):
   ```
   **CI status**: passing | failing (<check-name>) | pending (timed out waiting)
   ```

## Step 7c: Re-fetch Comment IDs After Push

Some bots (notably `devin-ai-integration[bot]`) delete and re-post their review comments when a PR is updated (new commits or force-push). This means the `databaseId` values collected in Step 3 may now be stale (return 404 when replying).

**Skip this step if**: no fixes were applied (nothing was pushed in Step 7).

**Procedure**:

1. Identify which bots in the processed set have `selfResolves=false` (from the bot profile in Step 5). These are the bots likely to re-post.

2. If any such bots exist, re-fetch review threads using the same GraphQL query from Step 3a (full pagination).

3. For each processed comment, match the old thread to the new thread by `path` and `line` (file path and line number). If a match is found and the `databaseId` has changed, update the comment ID mapping:

```bash
# For each processed comment, update ID if the thread was re-posted
# OLD_ID -> NEW_ID mapping built by matching (path, line, author)
```

4. Use the updated IDs for all reply posting in Step 8. Log any ID changes:

```
Re-fetched comment IDs after push (bot re-post detected):
- Comment <old_id> -> <new_id> (devin-ai-integration[bot], path/to/file.sh:42)
```

If a thread cannot be matched (path+line+author combination not found in the re-fetched data), skip replying to that thread and report it in the Step 13 summary as "reply skipped (thread not found after push)".

## Step 8: Post Replies

For each bot comment that was processed, post a reply via the REST API (using the updated IDs from Step 7c if applicable):

```bash
gh api "repos/$OWNER/$REPO/pulls/$PR_NUM/comments/$COMMENT_DB_ID/replies" \
  -f body="$REPLY_BODY"
```

### Acceptance Reply Format

When a fix was applied. Include a brief assessment of why the suggestion is valid before noting the applied fix:

```
<1-5 sentence assessment explaining why the suggestion is correct and what it improves.>

Applied in <SHA>.

<!-- spex-triage -->
```

### Rejection Reply Format

When a suggestion was rejected. Every rejection MUST cite specific evidence (line number, function name, or quoted code) that disproves the bot's claim. Generic assertions like "the code is correct" or "this is by design" without pointing to the proof are not acceptable.

```
<1-5 sentence justification citing the specific code/line that disproves the claim.>

<!-- spex-triage -->
```

### Deferral Reply Format

When a suggestion has merit but is out of scope:

```
Valid point -- this is out of scope for this PR (<1 sentence why: requires larger refactoring / architectural change / etc>). Tracked for a follow-up brainstorm.

<!-- spex-triage:deferred -->
```

### Fix Failure Reply Format

When a fix could not be applied:

```
Could not apply this fix automatically (<reason: file changed/line mismatch/etc>). Leaving for manual review.

<!-- spex-triage -->
```

After each reply is posted, update the state file:

```bash
"$TRIAGE_STATE" set "$PR_NUM" "$COMMENT_DB_ID" "<action>" "$REPLY_ID"
```

Where `<action>` is `accepted`, `rejected`, `deferred`, or `skipped`.

## Step 9: Resolve Handled Threads

**Hard rule**: NEVER resolve a thread that has not been replied to with a `<!-- spex-triage -->` or `<!-- spex-triage:deferred -->` signature. Resolving without a reply silently discards review feedback.

A thread is eligible for resolution when BOTH of these are true:
1. The thread was assessed in Step 6 (valid, invalid, deferred verdict reached), AND
2. A reply was posted in Step 8 (acceptance, rejection, deferral, or fix-failure reply)

Once a reply has been posted, determine whether to resolve based on the verdict and bot profile:

| Verdict | selfResolves=true | selfResolves=false |
|---------|-------------------|--------------------|
| **Rejected** | Resolve | Resolve |
| **Deferred** | Resolve | Resolve |
| **Accepted** | Leave open (bot will self-resolve after acknowledging the fix) | Resolve |

In other words:
- **Rejected or deferred**: Always resolve -- we've made our decision and replied, leaving it open implies it still needs attention.
- **Accepted + selfResolves=true** (e.g., CodeRabbit): Leave open -- the bot will detect the fix was applied and resolve its own thread.
- **Accepted + selfResolves=false** (e.g., Copilot, Devin, unknown bots): Resolve -- the bot won't self-resolve, so we do it.

Resolve via GraphQL:

```bash
gh api graphql -f query='
  mutation($id: ID!) {
    resolveReviewThread(input: {threadId: $id}) {
      thread { isResolved }
    }
  }
' -f id="$THREAD_NODE_ID"
```

**Never batch-resolve threads.** Each thread must be resolved individually, only after its own reply has been posted. Do not resolve threads that were skipped, not assessed, or that belong to a different processing batch.

### Step 9b: Resolve Stale Handled Threads

On each triage pass, after processing new threads, check for threads that were handled in a previous pass but are still unresolved. A thread is stale-handled when:

1. It is in the state file as `accepted` or `rejected` (we already replied), AND
2. It is still unresolved on GitHub, AND
3. The last comment in the thread is either from us (the triage reply) or from the bot acknowledging our reply

For each stale-handled thread, resolve it via the same GraphQL mutation above. These were left open due to the previous behavior and should be cleaned up.

## Step 10: Re-evaluation for Loop Mode

When processing threads, for comments that are already marked as handled in the state file:

1. Get the `handledAt` timestamp from the state.
2. Check if any new comments appeared in the thread after `handledAt` (compare `createdAt` of thread comments against `handledAt`).
3. If new activity is detected, re-process the thread (go through Steps 6-9 again for this thread).
4. If no new activity, skip the thread.

## Step 11: Spec-Aware Assessment

Before assessing bot comments, check for a feature spec:

```bash
PREREQ=$(.specify/scripts/bash/check-prerequisites.sh --json --paths-only 2>/dev/null || true)
if [ -n "$PREREQ" ]; then
  SPEC_DIR=$(echo "$PREREQ" | jq -r '.FEATURE_DIR // empty')
fi
```

If `$SPEC_DIR` is non-empty and `$SPEC_DIR/spec.md` exists, read the spec and use it as additional context when assessing bot suggestions in Step 6b.

When rejecting a suggestion that conflicts with a spec requirement, reference the specific requirement ID (e.g., FR-003) in the rejection reply.

If no spec exists, fall back to code-only analysis. This is not an error.

## Step 12: Human Comment Interactive Review

After all bot comments are processed, handle human comment threads.

For each unresolved human thread:

1. **Present the comment**: Show the reviewer's comment text, the file/line context, and the current code.

2. **Assess**: Provide a validity verdict:
   - **Agree**: The comment identifies a real issue that should be addressed.
   - **Disagree**: The comment is incorrect or the current code is already correct.
   - **Partial**: The comment has merit but the suggested approach needs modification.

   Include 1-2 sentence reasoning for the assessment.

3. **Draft a reply**: Compose a proposed reply based on the assessment.

4. **Present for approval**: Present these options to the user:
   - **Approve**: Post the reply as-is (with `<!-- spex-triage -->` signature)
   - **Edit**: Let the user modify the reply, then post the edited version
   - **Skip**: Do not post a reply, leave the comment open for the next triage pass

5. **Update state**: After posting an approved or edited reply, update the state:
   ```bash
   "$TRIAGE_STATE" set "$PR_NUM" "$COMMENT_DB_ID" "<action>" "$REPLY_ID"
   ```
   For skipped comments, record action as `skipped`.

## Step 12b: Status Bot Detection

**Mandatory**: Steps 12b and 12c MUST execute after every triage pass, even when there are zero review threads. Codecov and other status bots post as issue comments (not review threads), so they are invisible to the review thread scan. Skipping these steps when "0 threads found" is the most common cause of missed coverage regressions.

After processing review threads (bot + human), scan PR issue comments for status bots that post reports rather than inline code reviews. These bots cannot be triaged like review bots, but their status should be surfaced in the summary.

**Fetch PR issue comments** (these are distinct from review threads):

```bash
BOT_COMMENTS=$(gh api "repos/$OWNER/$REPO/issues/$PR_NUM/comments" \
  --jq '[.[] | select(.user.type == "Bot" or (.user.login | test("\\[bot\\]$|codecov|coveralls|dependabot|renovate|netlify|vercel|sonarcloud|snyk"; "i")))] | group_by(.user.login) | map({bot: .[0].user.login, count: length, latest: (sort_by(.created_at) | last)})' \
  2>/dev/null || echo "[]")
```

**Known status bot profiles:**

| Bot | Type | What to extract |
|-----|------|-----------------|
| `codecov-commenter` or `codecov[bot]` | Coverage | Coverage delta (look for "Coverage" and percentage change) |
| `coveralls` | Coverage | Coverage percentage |
| `dependabot[bot]` | Dependency | Update type (security/version) |
| `renovate[bot]` | Dependency | Update type |
| `netlify[bot]` | Deploy preview | Preview URL |
| `vercel[bot]` | Deploy preview | Preview URL |
| `sonarcloud[bot]` | Quality | Quality gate status (Passed/Failed) |
| `snyk-bot` | Security | Vulnerability count |

**For each detected status bot**, extract a summary from the latest comment:

- **Dependabot/Renovate**: Note the update: `dependabot: security update for lodash`.
- **Deploy previews**: Extract the URL: `netlify: preview at https://...`.
- **Other bots**: Just note presence: `sonarcloud: Quality Gate Passed`.

**Do NOT attempt to "fix" status bot findings** except for Codecov coverage regressions (see Step 12c). Other status bots (deploy previews, dependency updates, quality gates) are informational only.

### Codecov Deep Parse

For Codecov (`codecov-commenter` or `codecov[bot]`), extract detailed per-file coverage from the comment body instead of just the one-line delta. Codecov comments contain a markdown table with per-file patch coverage and missing line counts.

**1. Extract the overall project coverage:**

Parse the comment body for the project coverage line. Look for patterns like:
- `| **Totals** |` or `| Totals |` row with percentage
- `Coverage:` or `codecov` header lines with percentage and delta

Extract: current percentage, previous percentage, delta.

**2. Extract per-file patch coverage table:**

Codecov comments include a `Files with Reduced Coverage` or `Impacted Files` table. Parse it to extract:

| Column | What to extract |
|--------|-----------------|
| File path | Relative file path (may be truncated with `...`) |
| Patch % | Patch coverage percentage for lines changed in this PR |
| Missing lines | Count of uncovered lines in the patch |

Build a list of files with their patch coverage and missing line counts.

**3. Cross-reference with bot review findings:**

For each file in the Codecov table, check if any bot review threads from this triage pass (Steps 6-11) reference the same file. This tells the developer whether coverage gaps overlap with issues bots already flagged.

```
For each codecov_file in codecov_files:
  overlaps = []
  For each bot_thread in processed_bot_threads:
    if bot_thread.path == codecov_file.path:
      overlaps.append(f"{bot_thread.summary} ({bot_thread.bot_author})")
  codecov_file.overlaps = overlaps
```

**4. Format the coverage section for the Step 13 summary:**

```
**Coverage** (from Codecov):
| File | Patch % | Missing | Overlaps with bot findings |
|------|---------|---------|---------------------------|
| path/to/file.go | 79.8% | 22 lines | wg race guard (copilot), retry loop (coderabbit) |
| path/to/other.go | 80.0% | 2 lines | - |

Project: 89.74% (was 90.12%, delta -0.38%)
```

If no Codecov comment is found, omit the coverage section entirely. If the Codecov comment doesn't contain a per-file table (e.g., it's a simple "patch coverage: 100%"), fall back to a one-line summary: `Codecov: 100% patch coverage (ok)`.

Store the parsed coverage data for inclusion in the Step 13 summary output.

## Step 12c: Coverage Remediation

After parsing Codecov data (Step 12b), check whether a Codecov CI check is failing. Coverage regressions that cause CI failures are actionable, not merely informational.

**Skip this step if**: no Codecov data was parsed in Step 12b, or the CI check for Codecov is passing (check via `gh pr checks`), or `--no-coverage-fix` was passed as an argument.

### 1. Detect Coverage CI Failure

```bash
CODECOV_FAILING=$(gh pr checks "$PR_NUM" 2>&1 | grep -iE 'codecov|coverage' | grep -iE 'fail|error' || true)
```

If `CODECOV_FAILING` is empty, coverage CI is not failing. Skip to Step 13.

### 2. Identify Files Needing Coverage

From the Codecov data parsed in Step 12b, select files that need coverage improvement. Prioritize by:

1. Files with the lowest patch coverage percentage
2. Files with the most missing lines
3. Files changed in this PR (from the git diff, not the entire project)

Build a work list of up to 5 files, starting from the worst coverage.

### 3. Write Tests for Uncovered Code

For each file in the work list:

1. Read the file and identify the uncovered lines/functions (from the Codecov missing lines data and the actual code).
2. Identify the project's test framework and test directory conventions by examining existing test files.
3. Write tests that exercise the uncovered code paths. Focus on:
   - Untested branches (if/else paths, error returns)
   - Untested functions that are called but not directly tested
   - Edge cases in newly added code
4. Place test files following the project's existing test conventions (e.g., `*_test.go` next to the source file for Go, `test_*.py` in `tests/` for Python).

**Constraints:**
- Only add tests for code changed in this PR (do not fix pre-existing coverage gaps)
- Tests must compile and pass locally before committing
- Do not modify source code to make it more testable (that changes behavior and is out of triage scope)
- Maximum 2 fix attempts per file. If tests cannot be made to pass, skip that file

### 4. Validate Tests Pass

Run the project's test command to verify the new tests pass:

```bash
# Auto-detect test command (same heuristic as ship pipeline)
if [ -f "Makefile" ] && grep -q '^test:' Makefile; then
  make test
elif [ -f "package.json" ]; then
  npm test
elif [ -f "go.mod" ]; then
  go test ./...
elif command -v pytest >/dev/null 2>&1; then
  pytest
elif [ -f "Cargo.toml" ]; then
  cargo test
fi
```

If tests fail, fix or remove the failing test (max 2 attempts). Do not push tests that break CI.

### 5. Commit and Push

If any test files were added:

```bash
git add -A
git commit -m "test: improve coverage for PR #$PR_NUM

Added tests to address Codecov coverage regression:
$(for f in $TEST_FILES; do echo "- $f"; done)

Assisted-By: 🤖 Claude Code"
git push
```

### 6. Report

Add a coverage remediation section to the Step 13 summary:

```
**Coverage remediation**:
- Files targeted: N
- Tests added: N files
- Tests skipped: N files (reason)
```

If all targeted files were successfully covered, note: "Coverage fixes pushed. Codecov will re-check on the next CI run."

## Step 13: Summary Output

**Mandatory**: Steps 13-15 MUST execute after every triage pass, even when all threads were already handled or all were resolved. These steps surface patterns, capture learnings, and track deferred work. Skipping them silently discards the feedback loop.

At the end of the triage pass, report a summary:

```
## Triage Summary for PR #<PR_NUM>

**Bot comments** (by author):
| Bot | Accepted | Rejected | Deferred | Skipped | Already Handled |
|-----|----------|----------|----------|---------|-----------------|
| copilot[bot] | N | N | N | N | N |
| devin-ai-integration[bot] | N | N | N | N | N |
| coderabbitai[bot] | N | N | N | N | N |

**Bot totals**:
- Accepted: N (fixes applied)
- Rejected: N
- Deferred: N (out of scope, pending brainstorm capture in Step 15)
- Skipped: N (deleted files, conflicts, summary comments)
- Already handled: N

**Human comments**:
- Approved: N (replies posted)
- Edited: N (replies posted with edits)
- Skipped: N (left open)
- Pending: N (not yet reviewed)

**Coverage** (from Codecov, if detected):
| File | Patch % | Missing | Overlaps with bot findings |
|------|---------|---------|---------------------------|
| path/to/file.go | 79.8% | 22 lines | race guard (copilot), retry loop (coderabbit) |
| path/to/other.go | 100% | 0 lines | - |

Project: 89.74% (was 90.12%, delta -0.38%)

**Other status bots** (from Step 12b, if any detected):
| Bot | Status |
|-----|--------|
| dependabot[bot] | security update for lodash |

**Commit**: <SHA> (if fixes were applied)
**CodeRabbit**: reviewed | rate-limited (local fallback ran) | rate-limited (CLI not available) | not detected
**CI status**: passing | failing (<check-name>) | pending | not checked
**Open bot comments remaining**: N
```

When `Open bot comments remaining` is 0, this signals that a `/loop` invocation can exit.

## Step 14: Extract Principles from Review Findings

After the summary, analyze the processed bot comments for recurring patterns that could become constitutional principles.

**Skip this step if**: fewer than 5 bot comments were assessed in this pass (not enough signal), or if no constitution exists (`.specify/memory/constitution.md` is missing -- the project hasn't opted into constitutional governance).

**Procedure:**

1. **Identify recurring patterns**: Group all assessed bot comments (both accepted and rejected) by the type of issue they flagged. Look for patterns where 2+ independent reviewers (different bot authors) flagged the same category of problem, or where a single reviewer flagged the same category 3+ times across different files.

2. **Present recurring patterns** with attribution:

```
Recurring patterns from N review comments:

1. <Pattern name> (<Bot1> + <Bot2>): <1-line description of what was flagged and why it matters>
2. <Pattern name> (<Bot1> x3): <1-line description>
...
```

3. **Offer principle extraction**: If patterns were found, present them as candidate constitutional principles using a multi-select question:

   - header: "Principles"
   - multiSelect: true
   - Each pattern becomes an option with a short principle name as label and a 1-2 sentence principle statement as description
   - Include a "Type something" free-text option for custom principles
   - Include a "Skip" option

4. **Apply selected principles**: For each selected principle, invoke `/speckit-constitution` with the principle text as argument. This adds the principles to `.specify/memory/constitution.md` following the existing format and triggers template sync.

## Step 15: Capture Deferred and Rejected Findings to Idea Inbox

**This step is MANDATORY when deferred or rejected count > 0.** The Step 13 summary references this step ("pending brainstorm capture in Step 15"). Skipping it makes the summary a lie. You MUST NOT end the triage pass without executing this step when there are items to capture.

After principle extraction, check if any bot comments were deferred or rejected during this triage pass. Both categories can surface real improvement opportunities worth tracking:

- **Deferred**: Valid suggestions that are out of scope for this PR
- **Rejected**: Suggestions we disagreed with, but that may reveal a pattern worth addressing differently (e.g., the bot keeps flagging error handling because our approach is unconventional, worth documenting or reconsidering)

**Skip this step if**: no comments were deferred AND no comments were rejected.

**Procedure:**

1. **Collect candidate items**: Gather all deferred findings and all rejected findings from this pass into separate lists:

```
Deferred review findings (out of scope for PR #<PR_NUM>):

1. <Bot>: <file path> — <1-line summary of suggested improvement>
   Why deferred: <1 sentence>

Rejected review findings worth considering:

1. <Bot>: <file path> — <1-line summary of what the bot flagged>
   Why rejected: <1 sentence>
...
```

2. **Group by theme**: Group both deferred AND rejected items by the concern they address (e.g., "error handling consistency", "missing validation", "concurrency safety"). Items from both categories can land in the same theme. A theme triggers when it has **2 or more findings** regardless of verdict mix (deferred + rejected combined). Themes with only 1 finding are excluded. Each qualifying theme becomes one inbox candidate.

3. **Offer inbox capture**: Present the qualifying themes to the user:

   - header: "Capture to idea inbox?"
   - multiSelect: true
   - Each theme becomes an option with the theme name as label and "N findings (M deferred, K rejected) from Bot1, Bot2" as description
   - Include a "Skip all" option

4. **Write to idea inbox**: For each selected theme, append an entry to `brainstorm/idea-inbox.md`. Create the directory and file if they don't exist:

   ```bash
   mkdir -p brainstorm
   ```

   **If the file does not exist**, create it first:
   ```markdown
   # Idea Inbox

   Ideas captured from code reviews for future brainstorming.
   ```

   **For each selected theme**, append an entry at the end of the file:
   ```markdown

   ### <theme-slug>

   - **Source**: triage
   - **Date**: YYYY-MM-DD
   - **Reference**: <PR number or feature branch name>
   - **Summary**: <1-2 sentence description synthesizing the findings in this theme>

   > <relevant excerpt from the review findings that belong to this theme>
   ```

   Where `<theme-slug>` is the theme name in kebab-case (e.g., "error handling consistency" becomes `error-handling-consistency`).

   Report: `Captured N themes to brainstorm/idea-inbox.md`

## Step 16: High Volume Batching

For PRs with more than 100 review threads, process in batches of 50. After each batch:

1. Check GitHub API rate limit remaining via `gh api rate_limit`.
2. If rate limit is low (< 100 remaining), save progress to state and exit cleanly with a message indicating the rate limit pause.
3. Otherwise, continue to the next batch.

## Error Handling Summary

| Error | Behavior |
|-------|----------|
| `gh` not authenticated | Report error, exit immediately |
| No open PR for branch | Report "No open PR found", exit |
| API rate limit (403/429) | Save progress to state, exit cleanly |
| Fix application failure | Skip fix, reply noting failure, continue |
| Commit/push failure | Report error, keep changes, skip acceptance replies |
| Deleted file reference | Skip fix, reply noting file deleted, continue |
| Conflicting fixes in batch | Skip later fix, reply noting conflict, continue |
