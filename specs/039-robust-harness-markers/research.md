# Research: Unified Harness Marker Syntax

## R1: Current Marker Inventory

Verified by codebase grep. See plan.md R1 section for full details.

- 6 HTML-comment section markers across 4 files
- 15 inline substitution entries targeting 7 files
- Total: 20 distinct adaptation points to migrate

## R2: Token Key Naming

Decision: Use lowercase kebab-case matching `[a-z][a-z0-9-]*`. Reuse existing section marker names for block tokens. Derive new names for inline tokens from the neutral phrase's semantic intent.

Rationale: Consistent with the existing capability marker names. Short, greppable, self-documenting.

Alternatives considered: camelCase (rejected, not shell-friendly), dot-separated (rejected, conflicts with command naming), numbered IDs (rejected, not self-documenting).

## R3: Processing Order

Decision: Block markers first, then inline tokens.

Rationale: A block's opening `{harness:key}` line looks identical to an inline token. If inline processing runs first, it would replace the opening marker and break block detection. Processing blocks first removes them entirely, leaving only true inline tokens for the second pass.

Alternatives considered: Single-pass regex (rejected, too complex to handle both block and inline in one pass reliably), reverse order (rejected, same problem as single-pass).

## R4: Multi-line Token Values

Decision: Store as JSON strings with `\n` escape sequences.

Rationale: At current scale (5 block tokens, longest ~20 lines), JSON `\n` strings are manageable. External file references would add file discovery complexity for marginal readability benefit.

Alternatives considered: External files per token (rejected, adds I/O complexity), YAML (rejected, adds `yq` dependency).

## R5: False Positive Analysis

The phrases "suppress all interactive prompts" in `finish.md` and `submit.md` are NOT targets of the inline substitutions. The actual inline entries are longer, more specific phrases ("...complete the stamp", "...complete the verification"). These files do NOT need inline token conversion.

Verified: `finish.md` and `submit.md` are not in the 7-file scope.
