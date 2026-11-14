#!/usr/bin/env bash
# Headless checks: syntax, speed, and "no ghost pixels" replay test.
cd "$(dirname "$0")/.." || exit 1
B=${BASH:-/opt/homebrew/bin/bash}
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
"$B" -n src/game.sh && echo "syntax ok" || exit 1
"$B" src/game.sh --bench 120 | tail -1
AUTO=lazy SPAWN_EVERY=40 RENDER_OUT=$T/out.txt "$B" src/game.sh --snapshot 700 "$T/snap.txt" >/dev/null
python3 tests/replay_check.py "$T/out.txt" "$T/snap.txt"
