"""Generate Macify's original system sounds (16-bit PCM WAV, no Apple assets).

Run:  python3 assets/sounds/make_sounds.py
Sounds: chime.wav (alert), pop.wav (exclamation), glass.wav (notification)
"""
import math
import os
import struct
import wave

SR = 22050
OUT = os.path.dirname(os.path.abspath(__file__))


def write_wav(name, samples):
    path = os.path.join(OUT, name)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767)) for s in samples))
    print("wrote", path, len(samples), "samples")


def sine(freq, dur, vol=0.5, decay=3.0, delay=0.0, harm=()):
    n = int(SR * (dur + delay))
    out = [0.0] * n
    start = int(SR * delay)
    for i in range(int(SR * dur)):
        t = i / SR
        env = math.exp(-t * decay)
        v = math.sin(2 * math.pi * freq * t)
        for hf, hv in harm:
            v += hv * math.sin(2 * math.pi * freq * hf * t)
        out[start + i] += vol * env * v
    return out


def mix(*tracks):
    n = max(len(t) for t in tracks)
    out = [0.0] * n
    for t in tracks:
        for i, v in enumerate(t):
            out[i] += v
    peak = max(abs(v) for v in out) or 1.0
    return [v / peak * 0.9 for v in out]


# Alert chime: warm two-tone (E5 -> B5) with soft harmonics
chime = mix(
    sine(659.25, 0.7, vol=0.5, decay=4.0, harm=[(2, 0.25), (3, 0.1)]),
    sine(987.77, 0.8, vol=0.4, decay=3.5, delay=0.12, harm=[(2, 0.2)]),
)
write_wav("chime.wav", chime)

# Pop: short pitch-drop blip
dur, f0, f1 = 0.18, 880.0, 220.0
pop = []
for i in range(int(SR * dur)):
    t = i / SR
    f = f0 + (f1 - f0) * (t / dur)
    env = math.exp(-t * 28.0)
    pop.append(0.8 * env * math.sin(2 * math.pi * f * t))
write_wav("pop.wav", pop)

# Glass: high shimmering ping with inharmonic partials
glass = mix(
    sine(2093.0, 0.9, vol=0.5, decay=5.0),
    sine(2960.0, 0.7, vol=0.3, decay=6.0),
    sine(5232.0, 0.4, vol=0.2, decay=8.0),
)
write_wav("glass.wav", glass)
