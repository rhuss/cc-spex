#!/bin/sh
# python-resolve.sh - Cross-platform Python interpreter resolution
#
# Tries python3 (macOS/Linux), py (Windows launcher), python (fallback).
# py comes before python because on Windows, python can resolve to the
# Microsoft Store stub that opens the Store instead of running code.
#
# Usage:
#   sh python-resolve.sh script.py [args...]

for cmd in python3 py python; do
  command -v "$cmd" >/dev/null 2>&1 && exec "$cmd" "$@"
done

echo "ERROR: No Python interpreter found (tried python3, python, py)" >&2
exit 1
