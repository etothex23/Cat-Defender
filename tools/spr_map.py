#!/usr/bin/env python3
"""Labelled cell map of sprites so you can say 'trim C4'. Usage: spr_map.py out.png a.spr [b.spr ...]"""
import sys, os, subprocess
S = 56
pal = {}
for l in open(os.path.join(os.path.dirname(__file__), '..', 'sprites', 'palette.txt')):
    if l.strip() and not l.startswith('#'):
        c, _, hx = l.split()[:3]; pal[c] = hx
def lum(h): r, g, b = (int(h[i:i+2], 16) for i in (1, 3, 5)); return .3*r + .59*g + .11*b
out, files = sys.argv[1], sys.argv[2:]
cmd, x0 = [], 30
for f in files:
    rows = [r for r in open(f).read().split('\n') if r and not r.startswith('#')]
    w, h = len(rows[0]), len(rows)
    cmd += ['-fill', 'white', '-pointsize', '18', '-annotate', f'+{x0}+22', os.path.basename(f)]
    for x in range(w):
        cmd += ['-fill', 'white', '-pointsize', '16', '-annotate', f'+{x0+x*S+20}+{50}', str(x)]
    for y, row in enumerate(rows):
        cmd += ['-fill', 'white', '-pointsize', '16', '-annotate', f'+{x0-22}+{60+y*S+34}', 'ABCDEFGHIJ'[y]]
        for x, ch in enumerate(row):
            px, py = x0 + x*S, 60 + y*S
            col = pal.get(ch, '#1c1c28')
            cmd += ['-fill', col, '-stroke', '#555566', '-strokewidth', '1', '-draw', f'rectangle {px},{py} {px+S-1},{py+S-1}']
            tc = 'black' if ch in pal and lum(col) > 110 else '#aab'
            cmd += ['-stroke', 'none', '-fill', tc, '-pointsize', '15', '-annotate', f'+{px+14}+{py+34}', 'ABCDEFGHIJ'[y] + str(x)]
    x0 += w*S + 60
total_w = x0
subprocess.run(['magick', '-font', os.environ.get('SPR_FONT', '/System/Library/Fonts/Helvetica.ttc'), '-size', f'{total_w}x{60+6*S+20}', 'xc:#2b2b3a'] + cmd + [out], check=True)
