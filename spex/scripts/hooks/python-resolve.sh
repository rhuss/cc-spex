#!/bin/sh
# python-resolve.sh - Cross-platform Python interpreter resolution
#
# Tries python3 (macOS/Linux), python (some distros/venvs), py (Windows).
# Passes all arguments through to the resolved interpreter.
#
# Usage:
#   sh python-resolve.sh script.py [args...]

for cmd in python3 python py; do
  command -v "$cmd" >/dev/null 2>&1 && exec "$cmd" "$@"
done

echo "ERROR: No Python interpreter found (tried python3, python, py)" >&2
exit 1
