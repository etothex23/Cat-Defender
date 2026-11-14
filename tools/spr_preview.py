#!/usr/bin/env python3
"""Make a PNG preview sheet of sprites. Usage: spr_preview.py out.png sprites/*.spr"""
import sys, os, subprocess
S = 24  # pixel scale
pal = {}
for l in open(os.path.join(os.path.dirname(__file__), '..', 'sprites', 'palette.txt')):
    if l.strip() and not l.startswith('#'):
        c, _, hexv = l.split()[:3]; pal[c] = hexv
out, files = sys.argv[1], sys.argv[2:]
sprites = [[r for r in open(f).read().split('\n') if r and not r.startswith('#')] for f in files]
pad, W = 2, 0
x0, cmds = pad, []
H = max(len(s) for s in sprites) + 2*pad
for s in sprites:
    for y, row in enumerate(s):
        for x, ch in enumerate(row):
            if ch in pal:
                px, py = (x0+x)*S, (y+pad)*S
                cmds += ['-fill', pal[ch], '-draw', f'rectangle {px},{py} {px+S-1},{py+S-1}']
    x0 += len(s[0]) + pad
subprocess.run(['magick', '-size', f'{x0*S}x{H*S}', 'xc:#2b2b3a'] + cmds + [out], check=True)
