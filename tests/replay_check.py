#!/usr/bin/env python3
"""Replay the game's terminal output onto a virtual screen and compare with the true last frame.
Usage: replay_check.py render_output.txt snapshot.txt   (see tests/run_checks.sh)"""
import re, sys
W, CH = 120, 30
data = open(sys.argv[1], encoding='utf-8').read()
truth = [int(t) for t in open(sys.argv[2]).read().split()]
screen = {}                       # (row, col) -> (top, bot), rows 1..29 of the game area
row = col = 0; fg = bg = None
for m in re.finditer(r'\x1b\[(\d+);(\d+)H|\x1b\[38;5;(\d+);48;5;(\d+)m|\x1b\[0;97;48;5;236m|▀|[^\x1b▀]+', data):
    t = m.group(0)
    if m.group(1): row, col = int(m.group(1)), int(m.group(2))     # 1-based; game row = row-1 (ORIGY=1)
    elif m.group(3): fg, bg = int(m.group(3)), int(m.group(4))
    elif t == '▀': screen[(row - 1, col - 1)] = (fg, bg); col += 1
bad = 0
for cy in range(1, CH):
    for cx in range(W):
        want = (truth[2*cy*W + cx], truth[(2*cy+1)*W + cx])
        got = screen.get((cy, cx))
        if got != want:
            bad += 1
            if bad <= 5: print(f"mismatch at row {cy} col {cx}: drew {got}, should be {want}")
print("OK: virtual screen matches final frame" if not bad else f"FAIL: {bad} cells differ")
sys.exit(1 if bad else 0)
