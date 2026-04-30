---
description: "Refine rough ideas into executable specifications through collaborative questioning, alternative exploration, and incremental validation"
---

# Brainstorming Ideas Into Specifications

Help turn rough ideas into clear, agreed-upon feature descriptions through natural collaborative dialogue. The output is a brainstorm document capturing the problem, approaches considered, and the decision, ready for formal specification.

**Key Principle:** Brainstorming explores WHAT to build and WHY. The formal spec (via `/speckit-specify`) and implementation planning come after.

<HARD-GATE>
Do NOT invoke any implementation skill, write any code, scaffold any project, create spec files, or take any implementation action during brainstorming. Brainstorming ends with a decision and a brainstorm document, not a spec.
</HARD-GATE>

<HARD-GATE>
## Command Namespace: Use the correct prefixes

spex extension commands use the `speckit-spex-*` prefix (e.g., `/speckit-spex-brainstorm`).
speckit core commands use the `speckit-` prefix (e.g., `/speckit-specify`, `/speckit-plan`).

Commands like `/spex:specify`, `/spex:plan`, `/spex:implement`, `/spex:tasks` DO NOT EXIST.
</HARD-GATE>

## Checklist

You MUST create a task for each of these items and complete them in order:

1. **Initialize spec-kit** - ensure specify CLI and project are set up
2. **Explore project context** - check files, specs, constitution, recent commits
3. **Check for related brainstorms** - scan `brainstorm/` for existing docs on similar topics, offer to update or create new
4. **Ask clarifying questions** - one at a time, understand purpose/constraints/success criteria
5. **Propose 2-3 approaches** - with trade-offs and your recommendation
6. **Reach agreement** - confirm the chosen approach and scope with the user
7. **Write brainstorm document** - persist session summary to `brainstorm/NN-topic-slug.md`
8. **Update overview** - create or refresh `brainstorm/00-overview.md` with index, open threads, parked ideas
9. **Transition** - offer next steps

## Process Flow

```dot
digraph brainstorming {
    "Initialize spec-kit" [shape=box];
    "Explore project context" [shape=box];
    "Related brainstorm exists?" [shape=diamond];
    "Ask clarifying questions" [shape=box];
    "Propose 2-3 approaches" [shape=box];
    "User chooses approach?" [shape=diamond];
    "Write brainstorm document" [shape=box];
    "Update overview" [shape=box];
    "Offer next steps" [shape=box];
    "Done" [shape=doublecircle];

    "Initialize spec-kit" -> "Explore project context";
    "Explore project context" -> "Related brainstorm exists?";
    "Related brainstorm exists?" -> "Ask clarifying questions" [label="no, or user chooses new"];
    "Related brainstorm exists?" -> "Ask clarifying questions" [label="yes, user chooses update"];
    "Ask clarifying questions" -> "Propose 2-3 approaches";
    "Propose 2-3 approaches" -> "User chooses approach?";
    "User chooses approach?" -> "Ask clarifying questions" [label="needs more exploration"];
    "User chooses approach?" -> "Write brainstorm document" [label="agreed"];
    "Write brainstorm document" -> "Update overview";
    "Update overview" -> "Offer next steps";
    "Offer next steps" -> "Done";
}
```

## Prerequisites

Spec-kit must be initialized before brainstorming. If `.specify/` directory does not exist, tell the user to run `/spex:init` first and stop.

## The Process

### Understanding the idea

**Check context first:**
- Review existing specs (if any) in `specs/` directory
- Check for constitution (`.specify/memory/constitution.md`)
- Review recent commits to understand project state
- Look for related features or patterns
- Scan `brainstorm/` directory for existing brainstorm documents (triggers revisit detection, see step 3 in checklist)

**Assess scope before deep-diving:**
- Before asking detailed questions, assess scope: if the request describes multiple independent subsystems (e.g., "build a platform with chat, file storage, billing, and analytics"), flag this immediately. Don't spend questions refining details of a project that needs to be decomposed first.
- If the project is too large for a single spec, help the user decompose into sub-projects: what are the independent pieces, how do they relate, what order should they be built? Then brainstorm the first sub-project through the normal design flow. Each sub-project gets its own spec, plan, and implementation cycle.

**Ask questions to refine:**
- For appropriately-scoped projects, ask questions one at a time to refine the idea
- Only one question per message. If a topic needs more exploration, break it into multiple questions
- Prefer multiple choice when possible, but open-ended is fine too
- Focus on: purpose, constraints, success criteria, edge cases
- Identify dependencies and integrations

**Remember:** You're exploring WHAT needs to happen, not HOW it will be implemented.

### Exploring approaches

**Propose 2-3 different approaches:**
- Present options conversationally with trade-offs
- Lead with your recommended option
- Explain reasoning clearly
- Consider: complexity, maintainability, user impact

**Questions to explore:**
- What are the core requirements vs. nice-to-have?
- What are the error cases and edge conditions?
- How does this integrate with existing features?
- What are the success criteria?

### Reaching agreement

Once the user picks an approach, confirm the scope:
- Summarize what's in scope and out of scope
- Confirm key requirements and constraints
- Note any open questions that the spec phase should resolve

This is the decision point. The brainstorm document captures this agreement.

### Transition: next steps

After the brainstorm document is written and overview updated, offer the user a choice of how to proceed:

Use AskUserQuestion with:
- header: "Next steps"
- multiSelect: false
- Options:
  - "Specify step-by-step (/speckit-specify)": "Create a formal spec interactively, then plan and implement in separate steps"
  - "Ship autonomously (/speckit-spex-ship)": "Run the full pipeline (specify, plan, implement, review) with configurable oversight. Best for small to mid-sized features."
  - "Done for now": "Stop here. The brainstorm document is saved for later."

If the user chooses "Specify step-by-step": suggest running `/speckit-specify` with the brainstorm document as context.

If the user chooses "Ship autonomously": invoke `/speckit-spex-ship` with the brainstorm document path as argument.

If the user chooses "Done for now": end the session.

## Brainstorm Document Structure

Each brainstorm session produces a structured summary document. The document uses this format:

```markdown
# Brainstorm: [Topic]

**Date:** YYYY-MM-DD
**Status:** active | parked | abandoned | spec-created

## Problem Framing
[What problem is being explored and why it matters]

## Approaches Considered

### A: [Approach Name]
- Pros: ...
- Cons: ...

### B: [Approach Name]
- Pros: ...
- Cons: ...

## Decision
[What was chosen and why, or "Parked: [reason]" if no decision was reached]

## Key Requirements
[Core requirements agreed during brainstorming, to feed into the spec]

## Open Questions
- [Unresolved question that the spec phase should address]
```

**Status values:**
- `active` - session completed, idea is being pursued
- `parked` - session stopped intentionally, idea may be revisited
- `abandoned` - session stopped, idea is not being pursued
- `spec-created` - a spec was created from this brainstorm (include spec path)

## Overview Document Structure

The `brainstorm/00-overview.md` file provides a navigable index of all brainstorm sessions:

```markdown
# Brainstorm Overview

Last updated: YYYY-MM-DD

## Sessions

| # | Date | Topic | Status | Spec |
|---|------|-------|--------|------|
| 01 | YYYY-MM-DD | topic-slug | spec-created | 0003 |
| 02 | YYYY-MM-DD | topic-slug | active | - |
| 03 | YYYY-MM-DD | topic-slug | parked | - |

## Open Threads
- [Thread description] (from #NN)
- [Thread description] (from #NN)

## Parked Ideas
- [Idea description] (#NN)
  Reason: [why parked]
```

## Revisit Detection

**When:** During step 3 of the checklist (after exploring project context).

**How:**
1. Check if `brainstorm/` directory exists. If not, skip (no prior brainstorms).
2. List all `NN-*.md` files in `brainstorm/` (excluding `00-overview.md`).
3. Extract topic slugs from filenames (the part after the number prefix).
4. Compare the current brainstorm topic against existing slugs using keyword overlap.
5. If a related brainstorm document is found, use AskUserQuestion:
   - **Option A: "Create new document"** - session produces a new numbered file
   - **Option B: "Update existing"** - session appends a new dated section to the existing document

**If "Update existing" is chosen:**
At session end, instead of creating a new file, append a new section to the existing document:

```markdown

---

## Revisit: YYYY-MM-DD

### Updated Problem Framing
[How understanding has evolved]

### New Approaches Considered
...

### Updated Decision
...

### Open Threads
- [New or updated threads]
```

Then update the overview to reflect any status or thread changes.

## Writing the Brainstorm Document

**When:** Step 7 of the checklist (after reaching agreement).

You MUST write the brainstorm document at session end. This step is NOT optional.

**Procedure:**

1. **Create directory** if it does not exist:
   ```bash
   mkdir -p brainstorm/
   ```

2. **Detect next number** by scanning existing files:
   ```bash
   ls brainstorm/[0-9][0-9]-*.md 2>/dev/null
   ```
   Use `max_existing_number + 1`. If no files exist, start at 01. Do NOT gap-fill (if 01 and 03 exist, next is 04).

3. **Generate topic slug**: Derive from the brainstorm topic. Lowercase, hyphens, 2-4 words.
   Example: "user authentication system" becomes `auth-system`

4. **Determine status**:
   - If the user chose to park the idea: `parked`
   - If the user abandoned early: `abandoned`
   - Otherwise: `active`

5. **Write the document** using the Brainstorm Document Structure defined above.

6. **Commit the brainstorm document**:
   ```bash
   git add brainstorm/NN-topic-slug.md
   git commit -m "Add brainstorm: [topic]

   Assisted-By: 🤖 Claude Code"
   ```

## Updating the Overview

**When:** Step 8 of the checklist (immediately after writing the brainstorm document).

You MUST update the overview after every brainstorm document write or update. This step is NOT optional.

**Procedure:**

1. **If `brainstorm/00-overview.md` does not exist**, create it.
   If `brainstorm/` exists but `00-overview.md` is missing, regenerate it from all existing documents.

2. **Always regenerate by scanning all documents** (idempotent full rebuild):
   - List all `NN-*.md` files in `brainstorm/` (excluding `00-overview.md`)
   - For each file, extract: number, date, status, spec reference (from frontmatter)
   - For each file, extract all items under `## Open Questions`
   - For each file with status `parked`, collect the idea and reason

3. **Build the overview** using the Overview Document Structure defined above:
   - Sessions table: one row per document, sorted by number
   - Open Threads: aggregated from all documents, tagged with source `(from #NN)`
   - Parked Ideas: collected from all `parked` documents

4. **Write `brainstorm/00-overview.md`** with the rebuilt content.

5. **Commit the overview update**:
   ```bash
   git add brainstorm/00-overview.md
   git commit -m "Update brainstorm overview

   Assisted-By: 🤖 Claude Code"
   ```

## Incomplete Session Handling

**When:** The user stops the brainstorm before reaching agreement.

**Zero-interaction guard:** If the session had no meaningful interaction (no approaches explored, no clarifying questions answered beyond the initial topic), do NOT prompt to save. Simply end the session without creating any artifacts.

**For sessions with meaningful interaction** (approaches were discussed, questions were answered):

Use AskUserQuestion to ask: **"Save this brainstorm session?"**

- **Option A: "Save as parked"** - Write the document with status `parked`, update overview
- **Option B: "Save as abandoned"** - Write the document with status `abandoned`, update overview
- **Option C: "Discard"** - Do not create any brainstorm document, do not update overview

If the user chooses to save, follow the "Writing the Brainstorm Document" and "Updating the Overview" procedures above.

## Key Principles

- **One question at a time** - Don't overwhelm with multiple questions
- **Multiple choice preferred** - Easier to answer than open-ended when possible
- **YAGNI ruthlessly** - Remove unnecessary features from all specs
- **Explore alternatives** - Always propose 2-3 approaches before settling
- **Be flexible** - Go back and clarify when something doesn't make sense
- **Separate WHAT from HOW** - Focus on requirements and outcomes, not implementation
- **Brainstorm, don't specify** - The formal spec comes later via `/speckit-specify` or `/speckit-spex-ship`

## Common Pitfalls

**Don't:**
- Write spec files during brainstorming
- Include implementation details ("use Redis for caching")
- Run review gates (that's for the specify phase)
- Skip exploring alternatives
- Rush past clarifying questions
- Invoke implementation skills

**Do:**
- Focus on requirements and behavior
- Specify WHAT, defer HOW
- Explore multiple approaches
- Capture the decision and reasoning
- Note open questions for the spec phase
- Write the brainstorm document

## Example Flow

```
User: I want to add a comment system to the blog

You: I'm using speckit-spex-brainstorm to refine this idea.

Let me understand the context first...
[Reviews existing code and specs]

For the comment system, what level of features do you want?

A) Basic - Name, email, comment text only
B) Standard - Above + threading/replies
C) Advanced - Above + reactions, editing, moderation
D) Full - Above + notifications, mentions, markdown

User: B - Standard with threading

You: Great. For threading, should replies be:

A) Unlimited depth (comments on comments on comments...)
B) One level only (reply to top-level comments)
C) Two levels (reply and one nested level)

[... conversation continues, approaches explored ...]

You: Based on our discussion, here's what we've agreed on:

- Standard comment system with one level of threading
- Comments require name, email, and text
- Newest first, replies nested under parent
- Markdown support for comment text
- No moderation in first version (out of scope)

I'll save this as a brainstorm document. How would you like to proceed?

A) Specify step-by-step (/speckit-specify)
B) Ship autonomously (/speckit-spex-ship)
C) Done for now
```
