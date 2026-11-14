#!/usr/bin/env python3
"""Convert a --snapshot dump (60x120 xterm256 numbers) to a PNG. Usage: snap2png.py dump.txt out.png"""
import sys, subprocess
W, S = 120, 8
v = [int(t) for t in open(sys.argv[1]).read().split()]
def rgb(i):
    if i >= 232: g = 8 + 10 * (i - 232); return g, g, g
    if i >= 16:
        i -= 16; f = lambda n: 0 if n == 0 else 55 + 40 * n
        return f(i // 36), f(i // 6 % 6), f(i % 6)
    return 0, 0, 0
H = len(v) // W
ppm = f"P3\n{W} {H}\n255\n" + "\n".join("%d %d %d" % rgb(c) for c in v)
subprocess.run(["magick", "ppm:-", "-scale", f"{S*100}%", sys.argv[2]], input=ppm.encode(), check=True)
