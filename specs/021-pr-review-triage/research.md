# Research: PR Review Comment Triage

## R-001: GitHub API for fetching PR review comments

**Decision**: Use two endpoints: REST for inline comments with metadata, GraphQL for thread resolution status.

**Rationale**: The REST endpoint `GET /repos/{owner}/{repo}/pulls/{pull_number}/comments` provides comment body, author, file/line info, and `in_reply_to_id` for threading. However, thread resolution status (`isResolved`) is only available via GraphQL's `reviewThreads` connection. The skill needs both.

**Alternatives considered**:
- REST-only: Would miss thread resolution status entirely. Rejected.
- GraphQL-only: Could work but is more complex for simple comment fetching and doesn't match existing patterns in `speckit.spex-collab.revise.md`.
- `gh pr view --json`: Limited, doesn't expose inline code comments with file/line context.

## R-002: Bot identification via GitHub API

**Decision**: Use `user.type == "Bot"` field on comment author, cross-referenced with login patterns from bot profiles.

**Rationale**: The GitHub API `user` object has a `type` field with values `"User"`, `"Bot"`, or `"Organization"`. This is the authoritative way to identify bots. Login pattern matching (e.g., `coderabbitai[bot]`) provides additional specificity for known bots with custom behavior profiles.

**Alternatives considered**:
- Login pattern only: Would miss unknown bots. Rejected.
- `type` field only: Sufficient for partitioning, but doesn't distinguish between bots with different behaviors (auto-resolve vs not). Both approaches combined.

## R-003: Posting threaded replies to review comments

**Decision**: Use REST endpoint `POST /repos/{owner}/{repo}/pulls/{pull_number}/comments/{comment_id}/replies`.

**Rationale**: This endpoint creates a reply within an existing review comment thread, which is the correct interaction model. The `gh pr comment` command posts top-level PR comments (not threaded replies), so direct API use is needed.

**Alternatives considered**:
- `gh pr comment`: Posts top-level comments, not threaded replies. Wrong UX.
- `gh pr review --comment`: Creates new review comments, not replies to existing threads. Wrong semantics.

## R-004: Thread resolution via GraphQL

**Decision**: Use GraphQL mutations `resolveReviewThread` and `unresolveReviewThread` for thread resolution (FR-012).

**Rationale**: The REST API has no endpoint for resolving/unresolving review threads. This is exclusively a GraphQL capability. The `gh api graphql` command supports this.

**Implementation**:
```bash
gh api graphql -f query='
  mutation($id: ID!) {
    resolveReviewThread(input: {threadId: $id}) {
      thread { isResolved }
    }
  }
' -f id="$THREAD_NODE_ID"
```

**Alternatives considered**:
- REST API: No support for thread resolution. Not possible.
- Skip thread resolution: Would break FR-012 (auto-resolve for Copilot). Rejected.

## R-005: Comment threading model

**Decision**: Use GraphQL `reviewThreads` to get the thread-level view, with `comments` nested under each thread.

**Rationale**: The REST API returns a flat list of comments with `in_reply_to_id` for threading. Reconstructing threads from this is possible but fragile. The GraphQL `reviewThreads` query returns threads as first-class objects with `id`, `isResolved`, and nested `comments`, which maps directly to the triage model (process thread by thread, skip resolved threads).

**GraphQL query**:
```bash
gh api graphql -f query='
  query($owner: String!, $repo: String!, $number: Int!) {
    repository(owner: $owner, name: $repo) {
      pullRequest(number: $number) {
        reviewThreads(first: 100) {
          nodes {
            id
            isResolved
            path
            line
            comments(first: 50) {
              nodes {
                id
                databaseId
                author { login ... on Bot { id } }
                body
                createdAt
              }
            }
          }
        }
      }
    }
  }
' -f owner="$OWNER" -f repo="$REPO" -F number="$PR_NUM"
```

**Alternatives considered**:
- REST flat list + manual thread reconstruction: More API calls, fragile grouping logic, no resolution status. Rejected for primary data source (but REST reply endpoint still needed for posting).

## R-006: Applying bot-suggested code fixes

**Decision**: The AI skill reads the bot's suggestion, understands the intent, reads the current file, and applies the fix using the Edit tool. No automated patch application.

**Rationale**: Bot suggestions come in various formats (GitHub suggestion blocks, prose descriptions, code snippets). There is no universal patch format. The AI agent is the best tool for interpreting diverse suggestion formats and applying them correctly to the current code state.

**Alternatives considered**:
- Parse GitHub suggestion blocks (`suggestion` code fences) and apply as patches: Only handles one format (GitHub suggestions), misses prose-based suggestions from CodeRabbit. Too narrow.
- `git apply`: Requires generating patches from suggestion text, which is itself an AI task. Adds unnecessary complexity.

## R-007: State file structure

**Decision**: Single JSON file at `.specify/.pr-triage-state.json`, keyed by PR number, tracking handled comment IDs and timestamps.

**Schema**:
```json
{
  "142": {
    "last_run": "2026-05-31T10:00:00Z",
    "comments": {
      "12345": {
        "handled_at": "2026-05-31T10:00:00Z",
        "action": "accepted",
        "our_reply_id": 67890
      },
      "12346": {
        "handled_at": "2026-05-31T10:00:00Z",
        "action": "rejected",
        "our_reply_id": 67891
      }
    }
  }
}
```

**Rationale**: Per the clarification session, a single file with PR-number keys avoids directory clutter while preventing collisions across PRs. Tracking `our_reply_id` enables fast reply-based detection without scanning all replies.

**Alternatives considered**:
- Separate files per PR: More files to manage, harder to clean up. Rejected per clarification.
- Branch-keyed: Fragile if branches are renamed. Rejected per clarification.
