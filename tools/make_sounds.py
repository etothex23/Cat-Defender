#!/usr/bin/env python3
"""Synthesise Meowtron's sound effects (8-bit style, 22.05 kHz mono WAV). Usage: tools/make_sounds.py
Writes sounds/<name>.wav (what the game plays) and sounds/alt/<name>_b.wav (alternates to swap in)."""
import math, os, random, struct, wave
SR = 22050
random.seed(7)
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'sounds')

def osc(kind, ph, duty=0.5):
    p = ph % 1.0
    if kind == 'square': return 1.0 if p < duty else -1.0
    if kind == 'saw': return 2 * p - 1
    if kind == 'tri': return 4 * abs(p - 0.5) - 1
    return math.sin(2 * math.pi * p)

def note(f0, f1, dur, kind='square', vol=0.5, duty=0.5, decay=3.0, vib=0.0, attack=0.004):
    n = int(SR * dur); ph = 0.0; out = []
    for i in range(n):
        t = i / n
        f = f0 + (f1 - f0) * t
        if vib: f *= 1 + vib * math.sin(2 * math.pi * 7 * i / SR)
        ph += f / SR
        env = min(1.0, i / (SR * attack + 1)) * math.exp(-decay * t)
        out.append(osc(kind, ph, duty) * vol * env)
    return out

def noise(dur, vol=0.5, decay=4.0, lp=0.5):
    n = int(SR * dur); y = 0.0; out = []
    for i in range(n):
        y += lp * (random.uniform(-1, 1) - y)
        out.append(y * vol * math.exp(-decay * i / n))
    return out

def mix(*tracks):
    n = max(len(t) for t in tracks)
    return [sum(t[i] if i < len(t) else 0 for t in tracks) for i in range(n)]

def seq(*parts):
    out = []
    for p in parts: out += p
    return out

def silence(d): return [0.0] * int(SR * d)

def save(name, samples, sub=''):
    peak = max(abs(s) for s in samples) or 1
    gain = min(1.0, 0.92 / peak)
    d = os.path.join(OUT, sub); os.makedirs(d, exist_ok=True)
    with wave.open(os.path.join(d, name + '.wav'), 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(b''.join(struct.pack('<h', int(max(-1, min(1, s * gain)) * 32767)) for s in samples))

C5, E5, G5, C6, E6 = 523.25, 659.25, 783.99, 1046.5, 1318.5

# name: (default, alternate)
sounds = {
  'throw':   (note(1100, 350, 0.09, 'square', 0.35, 0.25, 5),
              mix(noise(0.14, 0.35, 5, 0.25), note(500, 900, 0.14, 'sine', 0.15, decay=5))),
  'pop':     (mix(note(380, 1000, 0.07, 'sine', 0.6, decay=5), noise(0.02, 0.25, 6, 0.9)),
              seq(note(900, 400, 0.05, 'square', 0.35, 0.5, 5), note(1500, 600, 0.05, 'tri', 0.4, decay=5))),
  'hit':     (mix(note(260, 70, 0.32, 'saw', 0.55, decay=2.5), noise(0.25, 0.3, 4, 0.3)),
              seq(note(440, 330, 0.09, 'square', 0.45, 0.5, 2), note(330, 220, 0.09, 'square', 0.45, 0.5, 2), note(220, 110, 0.18, 'square', 0.45, 0.5, 3))),
  'rescue':  (seq(*[note(f, f, 0.075, 'square', 0.4, 0.25, 2) for f in (C5, E5, G5, C6)], note(C6, C6, 0.2, 'square', 0.4, 0.25, 4)),
              None),   # alternate is the meow, below
  'land':    (note(1900, 1700, 0.07, 'sine', 0.5, decay=6), note(1000, 1000, 0.04, 'tri', 0.5, decay=6)),
  'spazz':   (mix(noise(0.55, 0.45, 2.2, 0.35), note(180, 1600, 0.55, 'square', 0.3, 0.5, 1.8, vib=0.08)),
              seq(*[note(1200 - 90 * i, 1100 - 90 * i, 0.05, 'saw', 0.4, decay=1.5) for i in range(11)], noise(0.2, 0.3, 5, 0.3))),
  'bonus':   (seq(*[note(f, f, 0.06, 'tri', 0.55, decay=1.5) for f in (C5, E5, G5, C6, E6)], note(E6, E6, 0.25, 'tri', 0.55, decay=3)), None),
  'lost':    (seq(note(440, 420, 0.16, 'sine', 0.55, decay=1.5), note(330, 300, 0.32, 'sine', 0.55, decay=2.5, vib=0.03)), None),
  'over':    (seq(*[note(f, f * 0.98, 0.17, 'square', 0.4, 0.5, 1.2) for f in (392, 330, 262)], note(196, 150, 0.6, 'square', 0.4, 0.5, 2.5, vib=0.02)), None),
  'respawn': (seq(note(200, 900, 0.22, 'tri', 0.5, decay=0.8), note(1800, 1800, 0.05, 'sine', 0.4, decay=4), note(2400, 2400, 0.07, 'sine', 0.3, decay=4)), None),
}
# a synthetic meow: pitch arcs up then down, vibrato, a little breath
meow = mix(note(420, 900, 0.18, 'saw', 0.35, decay=0.8, vib=0.02) + note(900, 480, 0.3, 'saw', 0.35, decay=2.5, vib=0.03),
           noise(0.5, 0.06, 2, 0.15))
sounds['rescue'] = (sounds['rescue'][0], meow)

for name, (a, b) in sounds.items():
    save(name, a)
    if b is not None: save(name + '_b', b, 'alt')
print('wrote', len(os.listdir(OUT)) - 1, 'sounds to', os.path.normpath(OUT))
