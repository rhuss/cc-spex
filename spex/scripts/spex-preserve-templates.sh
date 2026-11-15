#!/bin/sh
# spex-preserve-templates.sh - Keep project edits to the core spec-kit
# templates across `specify init --force`.
#
# Usage (from the project root):
#   spex-preserve-templates.sh
#
# `specify init --force` (run by /spex:init, --refresh and --update)
# rewrites every core template in .specify/templates/ with the stock
# version, so an edit made there in place is lost silently. spec-kit records
# the SHA-256 of every file it installs in .specify/integrations/
# *.manifest.json. A core template whose current hash matches none of the
# recorded hashes was edited in the project.
#
# Such a template is copied to .specify/templates/overrides/<name>.md.
# spec-kit's template resolution reads overrides/ before the core file
# (overrides -> presets -> extensions -> core), and `specify init` does not
# write to overrides/, so the edit keeps applying after the refresh.
#
#   edited, no override         -> copy to overrides/, print "Preserved: ..."
#   edited, override identical  -> nothing to do
#   edited, override differs    -> print "ERROR: ...", exit 1 (nothing is
#                                  copied; the caller must not run init)
#   no manifest or jq           -> print "WARNING: ..." when core templates
#                                  exist, exit 0 (edits cannot be detected)
#
# Messages go to stderr. Exit codes: 0 safe to refresh, 1 conflict.

TEMPLATES=".specify/templates"
OVERRIDES="$TEMPLATES/overrides"

ls "$TEMPLATES"/*.md >/dev/null 2>&1 || exit 0

warn_unchecked() {
  echo "WARNING: cannot check $TEMPLATES/ for local edits ($1)." >&2
  echo "  A refresh replaces the core templates there with the stock versions." >&2
  echo "  Keep project-specific templates in $OVERRIDES/<name>.md instead." >&2
  exit 0
}

command -v jq >/dev/null 2>&1 || warn_unchecked "jq is not installed"
if command -v sha256sum >/dev/null 2>&1; then
  hash_file() { sha256sum "$1" | cut -d' ' -f1; }
elif command -v shasum >/dev/null 2>&1; then
  hash_file() { shasum -a 256 "$1" | cut -d' ' -f1; }
else
  warn_unchecked "no sha256sum or shasum"
fi
ls .specify/integrations/*.manifest.json >/dev/null 2>&1 \
  || warn_unchecked "no spec-kit manifest in .specify/integrations/"

# "<path> <hash>" for every core template recorded in any manifest.
RECORDED=$(jq -r '
  (.files // {}) | to_entries[]
  | select(.key | test("^\\.specify/templates/[a-z0-9-]+\\.md$"))
  | "\(.key) \(.value)"
' .specify/integrations/*.manifest.json 2>/dev/null | sort -u)

[ -n "$RECORDED" ] || exit 0

conflicts=""
preserved=""
for path in $(printf '%s\n' "$RECORDED" | cut -d' ' -f1 | sort -u); do
  [ -f "$path" ] || continue
  current=$(hash_file "$path")
  printf '%s\n' "$RECORDED" | grep -qxF "$path $current" && continue

  override="$OVERRIDES/$(basename "$path")"
  if [ -f "$override" ]; then
    cmp -s "$path" "$override" && continue
    conflicts="$conflicts $path"
  else
    preserved="$preserved $path"
  fi
done

if [ -n "$conflicts" ]; then
  for path in $conflicts; do
    echo "ERROR: $path has local edits and differs from $OVERRIDES/$(basename "$path")." >&2
  done
  echo "  A refresh would replace the edited core template with the stock version." >&2
  echo "  Merge the edits into the override (spec-kit uses the override), or revert" >&2
  echo "  the core template, then run the refresh again. Nothing was changed." >&2
  exit 1
fi

for path in $preserved; do
  mkdir -p "$OVERRIDES" || exit 1
  cp "$path" "$OVERRIDES/$(basename "$path")" || exit 1
  echo "Preserved: $path has local edits, copied to $OVERRIDES/$(basename "$path") (spec-kit reads overrides first)" >&2
done
exit 0
