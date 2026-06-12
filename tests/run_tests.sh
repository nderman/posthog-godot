#!/usr/bin/env bash
# run_tests.sh — runs the headless test suite in one Godot process (autoloads load once).
# Exits non-zero if any assertion failed, so CI can gate on it.
#   GODOT=/path/to/Godot ./tests/run_tests.sh
set -euo pipefail

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"   # project root (where project.godot lives)
cd "$HERE"

if [[ ! -x "$GODOT" ]] && ! command -v "$GODOT" >/dev/null 2>&1; then
  echo "Godot not found at '$GODOT' — set GODOT=/path/to/Godot" >&2
  exit 2
fi

# Import resources first (fresh checkout / CI has no .godot/ cache yet).
"$GODOT" --headless --import >/dev/null 2>&1 || true

# --quit-after is a hang safety-net; the runner quits itself with the right code first.
out="$("$GODOT" --headless --fixed-fps 60 --quit-after 3000 res://tests/TestRunner.tscn 2>&1)" && code=0 || code=$?

echo "$out" | grep -E "^(===|  [✓✗]|SUITE:| {4}✗)|SCRIPT ERROR|Parse Error" || true

if echo "$out" | grep -q "^SUITE: PASS" && [[ "$code" -eq 0 ]]; then
  exit 0
fi
echo "run_tests.sh: FAILED (exit $code)" >&2
exit 1
