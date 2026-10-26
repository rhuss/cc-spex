#!/usr/bin/env sh
# codex-progress.sh - Run spex-codex-progress.py from the Spex source bundled
# with the cc-spex Codex plugin (check, apply, snippet, decline).
#
# The source is resolved like bootstrap.sh:
#   1. SPEX_SOURCE (an explicit local Spex source)
#   2. ./spex (the cc-spex repository itself)
#   3. the bundled plugin tree, four directories above this script
# Exit codes of spex-codex-progress.py are passed through; 1 with ERROR: when
# no Spex source or no python3 interpreter is found.
set -eu

if [ -n "${SPEX_SOURCE:-}" ]; then
  source_dir=$SPEX_SOURCE
elif [ -f "spex/setup.yml" ] && [ -d "spex/extensions/spex" ]; then
  source_dir=spex
else
  script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P) || {
    echo "ERROR: cannot resolve the cc-spex plugin directory from $0." >&2
    exit 1
  }
  # <root>/codex/skills/cc-spex-init/scripts/codex-progress.sh
  source_dir=$(CDPATH='' cd -- "$script_dir/../../../.." && pwd -P) || {
    echo "ERROR: cannot resolve the cc-spex plugin root above $script_dir." >&2
    exit 1
  }
fi

tool="$source_dir/scripts/spex-codex-progress.py"
if [ ! -f "$tool" ]; then
  echo "ERROR: spex-codex-progress.py not found in the Spex source: $tool" >&2
  echo "Reinstall or update the cc-spex plugin, or set SPEX_SOURCE to a local Spex source." >&2
  exit 1
fi

# Prefer an interpreter with tomllib (Python 3.11+); otherwise use any
# python3, and the tool reports UNSUPPORTED unless tomli is installed.
python=""
for candidate in python3 python3.14 python3.13 python3.12 python3.11; do
  if command -v "$candidate" >/dev/null 2>&1 &&
    "$candidate" -c 'import sys; sys.exit(sys.version_info < (3, 11))' >/dev/null 2>&1; then
    python=$candidate
    break
  fi
done
if [ -z "$python" ] && command -v python3 >/dev/null 2>&1; then
  python=python3
fi
[ -n "$python" ] || { echo "ERROR: python3 is required. Install it and retry." >&2; exit 1; }

exec "$python" "$tool" "$@"
