---
description: "Triage PR review comments: autonomously handle bot suggestions, interactively review human comments"
argument-hint: "[--pr <number>]"
---

# PR Review Comment Triage

Triage all review comments on a PR: autonomously handle bot comments (assess, apply valid fixes, reject invalid, reply), then interactively present human comments for approval.

## Ship Pipeline Guard

If `.specify/.spex-state` exists with `mode: "ship"`, return immediately. Triage is an interactive collab workflow.

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
bash spex/scripts/spex-triage-state.sh init "$PR_NUM"
```

## Step 3: Fetch Review Threads

Fetch ALL review threads with their comments using GraphQL. PRs with many review comments (e.g., 3 bots x 20+ findings each) regularly exceed 100 threads, so pagination is mandatory.

**Important**: GitHub API responses can contain raw control characters (U+0000–U+001F) in comment bodies, which break `jq` and Python's `json` module. Always pipe `gh api graphql` output through the sanitizer before any JSON processing.

### 3a: Pagination Loop

You MUST use a pagination loop. A single fetch is NOT sufficient -- a PR with 150 threads returns only the first 100, silently dropping the rest.

```bash
ALL_THREADS="[]"
CURSOR=""
PAGE=1

while true; do
  CURSOR_ARG=""
  [ -n "$CURSOR" ] && CURSOR_ARG="-f cursor=$CURSOR"

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
    | python3 spex/scripts/sanitize-gh-json.py)

  # Extract threads from this page and append
  PAGE_THREADS=$(echo "$PAGE_JSON" | jq '.data.repository.pullRequest.reviewThreads.nodes')
  ALL_THREADS=$(echo "$ALL_THREADS" "$PAGE_THREADS" | jq -s '.[0] + .[1]')

  # Check for next page
  HAS_NEXT=$(echo "$PAGE_JSON" | jq -r '.data.repository.pullRequest.reviewThreads.pageInfo.hasNextPage')
  if [ "$HAS_NEXT" != "true" ]; then
    break
  fi

  CURSOR=$(echo "$PAGE_JSON" | jq -r '.data.repository.pullRequest.reviewThreads.pageInfo.endCursor')
  PAGE=$((PAGE + 1))
done

TOTAL_COUNT=$(echo "$PAGE_JSON" | jq -r '.data.repository.pullRequest.reviewThreads.totalCount')
FETCHED_COUNT=$(echo "$ALL_THREADS" | jq 'length')
```

### 3b: Verify Complete Fetch

After the pagination loop, verify all threads were fetched:

```
Fetched $FETCHED_COUNT / $TOTAL_COUNT review threads (in $PAGE pages)
```

**Hard rule**: If `FETCHED_COUNT < TOTAL_COUNT`, something went wrong with pagination. Report the mismatch and stop -- do not proceed with partial data.

If the API returns a 403 or 429 status on any page, detect rate limiting: report remaining rate limit info, and exit cleanly. Progress is already saved in the state file.

## Step 4: Partition Threads

Parse the GraphQL response and partition threads into bot and human categories.

For each thread in `reviewThreads.nodes`:

1. **Skip resolved threads**: If `isResolved` is true, skip entirely.
2. **Check state**: For the first comment's `databaseId`, call `bash spex/scripts/spex-triage-state.sh get "$PR_NUM" "$COMMENT_ID"`. If already handled, check for re-evaluation (see Step 10 for loop mode). For non-loop first invocations, skip handled comments.
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

## Step 8: Post Replies

For each bot comment that was processed, post a reply via the REST API:

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
bash spex/scripts/spex-triage-state.sh set "$PR_NUM" "$COMMENT_DB_ID" "<action>" "$REPLY_ID"
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
   bash spex/scripts/spex-triage-state.sh set "$PR_NUM" "$COMMENT_DB_ID" "<action>" "$REPLY_ID"
   ```
   For skipped comments, record action as `skipped`.

## Step 13: Summary Output

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
- Deferred: N (out of scope, tracked for brainstorm)
- Skipped: N (deleted files, conflicts, summary comments)
- Already handled: N

**Human comments**:
- Approved: N (replies posted)
- Edited: N (replies posted with edits)
- Skipped: N (left open)
- Pending: N (not yet reviewed)

**Commit**: <SHA> (if fixes were applied)
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

## Step 15: Brainstorm Deferred Findings

After principle extraction, check if any bot comments were deferred during this triage pass.

**Skip this step if**: no comments were deferred (deferred count is 0).

**Procedure:**

1. **Collect deferred items**: Gather all deferred findings from this pass into a summary list:

```
Deferred review findings (out of scope for PR #<PR_NUM>):

1. <Bot>: <file path> — <1-line summary of suggested improvement>
   Why deferred: <1 sentence>
2. <Bot>: <file path> — <1-line summary>
   Why deferred: <1 sentence>
...
```

2. **Group by theme**: If multiple deferred items address the same concern (e.g., "error handling consistency", "missing validation"), group them under a common theme. Each theme becomes one brainstorm candidate.

3. **Offer brainstorm creation**: Present the deferred themes to the user:

   - header: "Brainstorm?"
   - multiSelect: true
   - Each theme becomes an option with the theme name as label and "N deferred findings from Bot1, Bot2" as description
   - Include a "Skip all" option

4. **Create brainstorms**: For each selected theme, invoke `/speckit-spex-brainstorm` with a pre-filled problem framing that includes:
   - The deferred findings that belong to this theme (bot author, file, suggestion)
   - The PR number and context where they were identified
   - A note that these originated from AI code review

   The brainstorm skill handles the document creation, numbering, issue creation (offering to create a GitHub issue), and overview update. Do not duplicate that logic here.

5. **Link back to PR**: If a GitHub issue was created by the brainstorm skill, post a single summary comment on the PR linking to the issue(s):

```bash
BODY="Deferred review findings tracked for follow-up:
$(for each issue: echo "- [Theme name]($ISSUE_URL)")

<!-- spex-triage:deferred-summary -->"

gh api "repos/$OWNER/$REPO/issues/$PR_NUM/comments" -f body="$BODY"
```

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
