"""Musik + efek suara video promosi Lapor Yuk (30 detik), disintesis dengan numpy.

Tanpa sampel/lagu pihak ketiga. Waktu efek suara mengikuti adegan di
promo_video_test.dart (lihat naskah.md).

    python audio.py out.wav
"""
import sys
import wave

import numpy as np

SR = 44100
DUR = 30.0
BPM = 120
BEAT = 60 / BPM
N = int(SR * DUR)
rng = np.random.default_rng(7)

mix = np.zeros((N, 2))


def hz(m):
    return 440.0 * 2 ** ((m - 69) / 12)


def at(t):
    return int(t * SR)


def add(sig, t, gain=1.0, pan=0.0):
    """Place a mono (or stereo) signal at time t."""
    i = at(t)
    if i >= N:
        return
    if sig.ndim == 1:
        sig = np.stack([sig * (1 - max(pan, 0)), sig * (1 + min(pan, 0))], axis=1)
    j = min(N, i + len(sig))
    mix[i:j] += sig[: j - i] * gain


def tt(d):
    return np.arange(int(d * SR)) / SR


def onepole_lp(x, cutoff):
    a = np.exp(-2 * np.pi * cutoff / SR)
    y = np.empty_like(x)
    z = 0.0
    for k in range(len(x)):
        z = (1 - a) * x[k] + a * z
        y[k] = z
    return y


def hp(x):
    return np.diff(x, prepend=0.0)


def bright(n, cutoff=None):
    """High-passed noise scaled back to unit variance (diff raises it)."""
    y = hp(hp(n))
    y /= y.std() + 1e-9
    return onepole_lp(y, cutoff) if cutoff else y


def saw(f, t, harm=10):
    out = np.zeros_like(t)
    for n in range(1, harm + 1):
        if f * n > 12000:
            break
        out += np.sin(2 * np.pi * f * n * t) / n
    return out * 0.6


# ------------------------------------------------------------------ music
CHORDS = [  # (pad notes, bass) per bar: C - G - Am - F
    ([60, 64, 67], 36),
    ([59, 62, 67], 43),
    ([57, 60, 64], 45),
    ([57, 60, 65], 41),
]
BARS = int(DUR / (BEAT * 4))
groove = lambda bar: 1 <= bar <= 13  # noqa: E731

# sidechain envelope from the kick pattern
duck = np.ones(N)


def kick(t0):
    t = tt(0.45)
    f = 48 + 120 * np.exp(-t / 0.035)
    ph = 2 * np.pi * np.cumsum(f) / SR
    s = np.sin(ph) * np.exp(-t / 0.22)
    s[:120] += rng.standard_normal(120) * 0.25 * np.linspace(1, 0, 120)
    add(s, t0, 0.95)
    i = at(t0)
    d = 1 - 0.65 * np.exp(-tt(0.4) / 0.09)
    j = min(N, i + len(d))
    duck[i:j] = np.minimum(duck[i:j], d[: j - i])


def clap(t0, g=0.2):
    s = np.zeros(int(0.3 * SR))
    for k, off in enumerate([0, 0.011, 0.022]):
        n = rng.standard_normal(int(0.25 * SR))
        n = bright(n, 7000) * np.exp(-tt(0.25) / (0.012 if k < 2 else 0.11))
        i = int(off * SR)
        s[i : i + len(n)] += n[: len(s) - i]
    add(s * 0.5, t0, g, pan=0.05)


def hat(t0, open_=False, g=0.03):
    d = 0.2 if open_ else 0.05
    n = bright(rng.standard_normal(int(d * SR)), 11000) * np.exp(-tt(d) / (0.06 if open_ else 0.012))
    add(n, t0, g, pan=0.25 if open_ else -0.2)


def crash(t0, g=0.07):
    n = bright(rng.standard_normal(int(2.2 * SR)), 9000) * np.exp(-tt(2.2) / 0.6)
    add(np.stack([n, np.roll(n, 300)], axis=1), t0, g)


pad = np.zeros(N)
bass = np.zeros(N)
for bar in range(BARS):
    notes, root = CHORDS[bar % 4]
    t0 = bar * BEAT * 4
    t = tt(BEAT * 4 + 0.6)
    env = np.minimum(1, t / 0.35) * np.exp(-np.maximum(0, t - BEAT * 4) / 0.25)
    voice = sum(saw(hz(m) * (1 + det), t, 8) for m in notes for det in (-0.004, 0.0, 0.004)) / 9
    i = at(t0)
    j = min(N, i + len(t))
    pad[i:j] += (voice * env)[: j - i] * (0.55 if groove(bar) else 0.75)
    if groove(bar):
        for k in range(8):
            bt = tt(BEAT / 2)
            f = hz(root + (12 if k % 4 == 3 else 0))
            b = (np.sin(2 * np.pi * f * bt) * 0.8 + saw(f, bt, 5) * 0.5) * np.exp(-bt / 0.2)
            ii = at(t0 + k * BEAT / 2)
            jj = min(N, ii + len(b))
            bass[ii:jj] += b[: jj - ii]
pad = onepole_lp(pad, 2400)
bass = onepole_lp(bass, 900)
mix[:, 0] += (pad * duck) * 0.3 + bass * duck * 0.5
mix[:, 1] += (pad * duck) * 0.3 + bass * duck * 0.5

# drums
for bar in range(BARS):
    t0 = bar * BEAT * 4
    if groove(bar):
        for b in range(4):
            kick(t0 + b * BEAT)
            hat(t0 + b * BEAT + BEAT / 2, open_=True)
            hat(t0 + b * BEAT + BEAT / 4)
            hat(t0 + b * BEAT + 3 * BEAT / 4)
        clap(t0 + BEAT)
        clap(t0 + 3 * BEAT)
        if bar in (3, 7, 11):  # small fill into the next phrase
            for k in range(4):
                clap(t0 + 3.5 * BEAT + k * BEAT / 8, g=0.16 + 0.05 * k)
crash(2.0)
crash(14.0, 0.14)
crash(28.0, 0.3)
kick(28.0)

# arpeggio: 16ths over chord tones, ping-pong echo
arp = np.zeros((N, 2))
for bar in range(BARS - 1):
    notes, _ = CHORDS[bar % 4]
    seq = [notes[0] + 12, notes[1] + 12, notes[2] + 12, notes[1] + 24]
    for k in range(16):
        if bar == 0 and k < 8:
            continue
        f = hz(seq[k % 4])
        t = tt(0.25)
        s = (np.sin(2 * np.pi * f * t) + 0.3 * np.sin(4 * np.pi * f * t)) * np.exp(-t / 0.09)
        ii = at(bar * BEAT * 4 + k * BEAT / 4)
        jj = min(N, ii + len(s))
        p = 0.35 if k % 2 else -0.35
        arp[ii:jj, 0] += s[: jj - ii] * (1 - max(p, 0))
        arp[ii:jj, 1] += s[: jj - ii] * (1 + min(p, 0))
delay = int(BEAT * 0.75 * SR)
echo = np.zeros_like(arp)
echo[delay:, 0] = arp[:-delay, 1] * 0.35
echo[2 * delay :, 1] = arp[: -2 * delay, 0] * 0.22
mix += (arp + echo) * 0.12

# lead hook in two phrases
HOOK = [76, 79, 81, 79, 76, 74, 72, 74, 76, 79, 84, 81, 79, 76, 79, 76]
for start in (8.0, 20.0):
    for k, m in enumerate(HOOK):
        t = tt(BEAT * 0.95)
        f = hz(m) * (1 + 0.004 * np.sin(2 * np.pi * 5.5 * t))
        ph = 2 * np.pi * np.cumsum(f) / SR
        s = (np.sin(ph) + 0.25 * np.sin(3 * ph) + 0.1 * np.sin(5 * ph)) * np.minimum(1, t / 0.02) * np.exp(-t / 0.35)
        add(s, start + k * BEAT, 0.14, pan=0.1)

# risers
for t0, d in ((0.9, 1.1), (26.9, 1.1)):
    n = rng.standard_normal(int(d * SR))
    sweep = np.linspace(0, 1, len(n))
    r = onepole_lp(n, 2500) * sweep**2
    add(r, t0, 0.12)

# ------------------------------------------------------------------ sfx


def blip(f0, f1, d=0.09, g=0.3, t0=0.0, pan=0.0):
    t = tt(d)
    f = f0 + (f1 - f0) * (t / d)
    s = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / (d / 3))
    add(s, t0, g, pan)


def pop(t0, g=0.32, pitch=1.0, pan=0.0):
    blip(420 * pitch, 980 * pitch, 0.08, g, t0, pan)


def tick(t0, g=0.12, pan=0.0):
    n = bright(rng.standard_normal(int(0.02 * SR)), 9000) * np.exp(-tt(0.02) / 0.004)
    add(n, t0, g * 0.5, pan)


def bell(f, t0, g=0.25, d=1.2, pan=0.0):
    t = tt(d)
    s = sum(a * np.sin(2 * np.pi * f * r * t) * np.exp(-t / (d * w)) for r, a, w in [(1, 1, 0.35), (2.76, 0.4, 0.15), (5.4, 0.2, 0.08)])
    add(s, t0, g, pan)


def success(t0, g=0.22):
    bell(hz(84), t0, g, 0.8)
    bell(hz(91), t0 + 0.1, g, 1.0)


def whoosh(t0, d=0.5, g=0.4):
    n = rng.standard_normal(int(d * SR))
    t = np.arange(len(n)) / len(n)
    cut = 300 + 5000 * np.sin(np.pi * t) ** 2
    y = np.empty_like(n)
    z = 0.0
    for k in range(len(n)):
        a = np.exp(-2 * np.pi * cut[k] / SR)
        z = (1 - a) * n[k] + a * z
        y[k] = z
    y *= np.sin(np.pi * t) ** 1.5
    y /= np.abs(y).max() + 1e-9
    add(np.stack([y * (1 - t * 0.6), y * (0.4 + t * 0.6)], axis=1), t0 - d * 0.35, g * 0.45)


def shutter(t0, g=0.45):
    for off in (0.0, 0.065):
        n = bright(rng.standard_normal(int(0.03 * SR)), 8000) * np.exp(-tt(0.03) / 0.006)
        add(n, t0 + off, g * 0.35)
    blip(180, 90, 0.08, g * 0.6, t0)


def sparkle(t0, g=0.12):
    for k, m in enumerate([96, 100, 103, 108]):
        bell(hz(m), t0 + k * 0.045, g, 0.6, pan=(-0.3 + k * 0.2))


def scribble(t0, d=0.7, g=0.18):
    n = rng.standard_normal(int(d * SR))
    t = tt(d)
    am = 0.5 + 0.5 * np.sin(2 * np.pi * 9 * t) ** 2
    add(onepole_lp(bright(n), 2500) * am * np.minimum(1, t / 0.05) * np.minimum(1, (d - t) / 0.1), t0, g * 0.5)


def boom(t0, g=0.8):
    t = tt(1.4)
    f = 40 + 60 * np.exp(-t / 0.15)
    s = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.5)
    add(s, t0, g)


# intro
pop(0.15, 0.4, 0.8)
bell(hz(91), 1.0, 0.2, 1.5)
sparkle(1.45)
# transitions
for t0 in (3, 7, 12, 15, 19, 22, 25, 28):
    whoosh(t0)
# 01 kamera
shutter(4.5)
for k, t0 in enumerate((5.35, 5.6, 5.85)):
    pop(t0, 0.28, 1 + k * 0.12, pan=(-0.4, 0.4, 0.3)[k])
# 02 lapor kegiatan
for k in range(18):
    tick(7.8 + k * 1.2 / 18, 0.14, pan=0.1 * ((k % 3) - 1))
pop(9.3, 0.3, 1.3)
for k, t0 in enumerate((9.8, 10.02, 10.24)):
    pop(t0, 0.3, 0.9 + k * 0.15)
tick(10.78, 0.3)
success(11.0)
sparkle(11.05, 0.08)
pop(11.25, 0.25)
# 03 rekap
scribble(13.2)
pop(13.85, 0.3)
tick(14.18, 0.3)
success(14.3, 0.18)
# 04 chat
for k, t0 in enumerate((15.4, 16.0, 16.6, 17.6)):
    pop(t0, 0.3, 1.0 + 0.1 * (k % 2), pan=(-0.3 if k in (0, 2) else 0.3))
pop(17.1, 0.25, 1.6)
bell(hz(88), 17.3, 0.12, 0.6)
pop(18.0, 0.3, 0.85)
tick(18.38, 0.3)
success(18.45, 0.18)
# 05 story
for k in range(5):
    pop(19.1 + k * 0.08, 0.18, 1.0 + k * 0.1, pan=-0.6 + k * 0.3)
tick(19.85, 0.3)
whoosh(20.15, 0.4, 0.25)
pop(21.2, 0.25, 1.2)
# 06 pesan suara
pop(22.1, 0.35, 0.8)
blip(660, 880, 0.12, 0.25, 22.3)
blip(880, 660, 0.12, 0.2, 23.85)
whoosh(24.0, 0.35, 0.2)
pop(24.35, 0.25, 1.1)
pop(24.5, 0.28, 0.95, pan=-0.3)
# 07 photostrip
whoosh(25.1, 0.4, 0.2)
for k in range(4):
    shutter(25.6 + k * 0.38, 0.35)
pop(27.15, 0.3)
sparkle(27.2, 0.1)
# outro
boom(28.0)
sparkle(28.2, 0.14)
for k in range(6):
    pop(28.45 + k * 0.09, 0.18, 1.0 + k * 0.08, pan=-0.5 + k * 0.2)
pop(29.0, 0.32, 0.9)

# ------------------------------------------------------------------ master
fade = np.ones(N)
fade[-int(0.6 * SR) :] = np.linspace(1, 0, int(0.6 * SR))
fade[: int(0.05 * SR)] = np.linspace(0, 1, int(0.05 * SR))
out = mix * fade[:, None]
out /= np.max(np.abs(out))
out = np.tanh(out * 1.6) / np.tanh(1.6)
out *= 0.89 / np.max(np.abs(out))
pcm = (out * 32767).astype("<i2")
with wave.open(sys.argv[1], "wb") as w:
    w.setnchannels(2)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes(pcm.tobytes())
print("ok", sys.argv[1], f"peak={np.max(np.abs(out)):.2f}")
