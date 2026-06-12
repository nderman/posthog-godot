#!/usr/bin/env bash
# smoke.sh — send one real event to PostHog and report whether it was accepted.
#   POSTHOG_API_KEY=phc_xxx [POSTHOG_HOST=https://eu.i.posthog.com] \
#     GODOT=/path/to/Godot ./tools/smoke.sh
# Exits 0 if PostHog returned a 2xx for the batch, non-zero otherwise.
set -euo pipefail

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$HERE"

if [[ -z "${POSTHOG_API_KEY:-}" ]]; then
  echo "Set POSTHOG_API_KEY (a phc_... project key from Project Settings → Project API Key)." >&2
  exit 2
fi
if [[ ! -x "$GODOT" ]] && ! command -v "$GODOT" >/dev/null 2>&1; then
  echo "Godot not found at '$GODOT' — set GODOT=/path/to/Godot" >&2
  exit 2
fi

"$GODOT" --headless --import >/dev/null 2>&1 || true
"$GODOT" --headless --fixed-fps 60 --quit-after 1500 res://tools/Smoke.tscn
