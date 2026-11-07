"""Render Star Critters' music pieces and sound effects to .ogg files.

These are the same sounds as lab/mood-lab.html (Web Audio), rebuilt with numpy so Godot
can play them: one key for everything (A by default), a long soft reverb baked in, and
nothing harsh. Run:  python3 tools/make_audio.py   (needs numpy, scipy and ffmpeg)

The music is not one long track. The game layers a seamless drone loop, slow "starry
wind" swells and single low bells at random times, so it never exactly repeats.
"""
import os
import subprocess
import tempfile

import numpy as np
from scipy.io import wavfile
from scipy.signal import fftconvolve, lfilter

SR = 44100
ROOT = 220.0                 # A, the key picked in the mood lab
PENT = [0, 2, 4, 7, 9]       # major pentatonic (sound effects)
MINP = [0, 3, 5, 7, 10]      # minor pentatonic ("Deep space" music)
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio")
rng = np.random.default_rng(7)


def hz(semi):
    return ROOT * 2 ** (semi / 12)


def pent(i, sc=PENT):
    return sc[i % 5] + 12 * (i // 5)


# ------------------------------------------------------------------ building blocks
class Buf:
    def __init__(self, sec):
        self.x = np.zeros(int(SR * sec))

    def add(self, sig, t=0.0):
        i = int(t * SR)
        n = min(len(sig), len(self.x) - i)
        if n > 0:
            self.x[i:i + n] += sig[:n]


def envelope(a, peak, d):
    """Exponential attack to `peak` in `a` s, then exponential decay over `d` s (like the lab)."""
    n = int(SR * (a + d)) + 1
    t = np.arange(n) / SR
    lo = 1e-4 / max(peak, 1e-6)
    att = peak * lo ** (1 - np.clip(t / max(a, 1e-4), 0, 1))
    dec = peak * lo ** (np.clip((t - a) / d, 0, 1))
    return np.where(t < a, att, dec)


def phase_of(freq, n, f2=None, glide=None, detune=0.0):
    f = freq * 2 ** (detune / 1200)
    if f2 is None:
        fa = np.full(n, f)
    else:
        f2 = f2 * 2 ** (detune / 1200)
        t = np.arange(n) / SR
        fa = f * (f2 / f) ** np.clip(t / glide, 0, 1)
    return 2 * np.pi * np.cumsum(fa) / SR


def wave(kind, ph):
    if kind == "sine":
        return np.sin(ph)
    if kind == "triangle":
        return 2 / np.pi * np.arcsin(np.sin(ph))
    if kind == "sawtooth":
        return 2 * ((ph / (2 * np.pi)) % 1.0) - 1
    raise ValueError(kind)


def biquad(kind, f, q):
    w = 2 * np.pi * min(f, SR * 0.45) / SR
    c, s = np.cos(w), np.sin(w)
    al = s / (2 * q)
    if kind == "lowpass":
        b = [(1 - c) / 2, 1 - c, (1 - c) / 2]
    elif kind == "highpass":
        b = [(1 + c) / 2, -(1 + c), (1 + c) / 2]
    else:  # bandpass, 0 dB peak
        b = [al, 0, -al]
    a = [1 + al, -2 * c, 1 - al]
    return np.array(b) / a[0], np.array(a) / a[0]


def sweep_filter(x, kind, f0, f1, q, dur):
    """Filter whose frequency glides from f0 to f1 over `dur` s, then holds (block by block)."""
    out = np.zeros_like(x)
    zi = np.zeros(2)
    blk = 128
    for i in range(0, len(x), blk):
        t = min(i / SR / max(dur, 1e-3), 1.0)
        f = f0 * (f1 / f0) ** t
        b, a = biquad(kind, f, q)
        out[i:i + blk], zi = lfilter(b, a, x[i:i + blk], zi=zi)
    return out


# ------------------------------------------------------------------ voices (same recipes as the lab)
def bell(f, vol=0.15, dur=2.6):
    parts = [(1, 1), (2.76, 0.35), (5.4, 0.12), (2.0, 0.18)]
    n = int(SR * (dur + 0.2))
    out = np.zeros(n)
    for k, (m, a) in enumerate(parts):
        e = envelope(0.006, vol * a, dur / (1 + k * 0.9))
        s = np.sin(phase_of(f * m, len(e)))
        out[:len(e)] += s * e
    return out


def kalimba(f, vol=0.16):
    parts = [(1, 1, 1.2), (5.4, 0.25, 0.18), (3.0, 0.08, 0.4)]
    out = np.zeros(int(SR * 1.4))
    for m, a, d in parts:
        e = envelope(0.004, vol * a, d)
        out[:len(e)] += np.sin(phase_of(f * m, len(e))) * e
    return out


def tone(f, vol, a, d, kind="sine", f2=None):
    e = envelope(a, vol, d)
    return wave(kind, phase_of(f, len(e), f2, a + d)) * e


def noise(dur, kind, f0, f1, q, vol, a=0.02):
    e = envelope(a, vol, dur)
    x = rng.uniform(-1, 1, len(e))
    return sweep_filter(x, kind, f0, f1, q, dur) * e


def bowl(f, vol=0.14, dur=6.0):
    parts = [(1, 1), (1.004, 0.8), (2.71, 0.35), (5.15, 0.12)]
    out = np.zeros(int(SR * (dur + 0.2)))
    for k, (m, a) in enumerate(parts):
        e = envelope(0.04 + k * 0.02, vol * a, dur / (1 + k * 0.6))
        out[:len(e)] += np.sin(phase_of(f * m, len(e))) * e
    return out


def chord(semis, vol, a, hold, rel, kind="triangle"):
    n = int(SR * (a + hold + rel))
    t = np.arange(n) / SR
    lo = 1e-4 / vol
    env = np.where(t < a, vol * lo ** (1 - t / a), np.where(t < a + hold, vol, vol * lo ** ((t - a - hold) / rel)))
    out = np.zeros(n)
    for s in semis:
        for det in (-6, 6):
            out += wave(kind, phase_of(hz(s), n, detune=det))
    b, aa = biquad("lowpass", 1400, 0.707)
    return lfilter(b, aa, out) * env


def sparkle(buf, t, count=6, base=15, vol=0.05, spread=0.5):
    for _ in range(count):
        buf.add(bell(hz(pent(base + int(rng.integers(0, 6)))), vol, 1.4), t + rng.uniform(0, spread))


def dice(buf, t):
    tt = t
    for _ in range(5):
        f = rng.uniform(1800, 3200)
        buf.add(noise(0.025, "bandpass", f, f, 6, rng.uniform(0.12, 0.2), 0.002), tt)
        tt += rng.uniform(0.04, 0.08)
    buf.add(noise(0.05, "bandpass", 900, 800, 3, 0.18, 0.002), tt)


# ------------------------------------------------------------------ reverb
def impulse(sec=5.5, decay=2.6):
    n = int(SR * sec)
    env = (1 - np.arange(n) / n) ** decay
    ir = rng.uniform(-1, 1, (2, n)) * env
    return ir / np.sqrt(np.sum(ir ** 2) / 2)  # unit energy per channel


IR = impulse()


def with_reverb(dry, send, wet_gain=0.85):
    """Dry in the middle, a long soft stereo reverb tail around it."""
    wet = np.stack([fftconvolve(dry, IR[c]) for c in (0, 1)]) * send * wet_gain * 0.18
    out = np.zeros((2, wet.shape[1]))
    out[:, :len(dry)] += dry
    out += wet
    return out


def loop_reverb(dry, send):
    """Circular reverb for a seamless loop: the tail wraps around to the start."""
    n = len(dry)
    out = np.zeros((2, n))
    for c in (0, 1):
        ir = np.zeros(n)
        k = min(n, IR.shape[1])
        ir[:k] = IR[c, :k]
        out[c] = dry + np.real(np.fft.ifft(np.fft.fft(dry) * np.fft.fft(ir))) * send * 0.85 * 0.18
    return out


def trim(st):
    lvl = np.max(np.abs(st), axis=0)
    idx = np.where(lvl > 10 ** (-66 / 20))[0]
    end = (idx[-1] + int(0.05 * SR)) if len(idx) else SR // 10
    st = st[:, :end]
    fade = min(int(0.05 * SR), st.shape[1])
    st[:, -fade:] *= np.linspace(1, 0, fade)
    return st


def save(name, st, master=0.9):
    st = st * master
    peak = np.max(np.abs(st))
    if peak > 0.98:
        print(f"  ({name}: peak {peak:.2f}, softened)")
        st = np.tanh(st)
    os.makedirs(OUT, exist_ok=True)
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
        wavfile.write(f.name, SR, st.T.astype(np.float32))
        tmp = f.name
    dst = os.path.join(OUT, name + ".ogg")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp, "-c:a", "libvorbis", "-q:a", "5", dst], check=True)
    os.remove(tmp)


def sfx(name, sec, build, send=0.4):
    b = Buf(sec)
    build(b)
    save(name, trim(with_reverb(b.x, send)))


# ------------------------------------------------------------------ sound effects
def make_sfx():
    # notes that climb: placing critters, winning rolls in a row
    for i in range(4, 15):
        sfx(f"note_{i}", 1.5, lambda b, i=i: b.add(kalimba(hz(pent(i)), 0.13)))
    sfx("click", 1.2, lambda b: b.add(kalimba(hz(pent(14)), 0.07)))
    sfx("popup", 1.8, lambda b: (b.add(noise(0.45, "lowpass", 400, 2600, 0.7, 0.05)), b.add(bell(hz(pent(12)), 0.05, 1.5), 0.12)))
    sfx("invalid", 1.0, lambda b: (b.add(tone(hz(-12), 0.22, 0.01, 0.25, "sine", hz(-14))), b.add(kalimba(hz(pent(4)), 0.05), 0.02)))
    sfx("turn", 3.6, lambda b: [b.add(bell(hz(pent(i)), 0.11, 3), k * 0.22) for k, i in enumerate([5, 7, 10])])

    def news(b):
        sparkle(b, 0, 7, 12, 0.045, 1.0)
        b.add(bell(hz(pent(5)), 0.06, 4))
    sfx("news", 4.5, news)

    def rush(b):
        for k in range(9):
            b.add(bell(hz(pent(5 + k)), 0.06, 1.6), k * 0.09)
        b.add(chord([0, 7, 16], 0.03, 0.4, 0.6, 2.5), 0.8)
    sfx("rush", 4.5, rush)
    sfx("done", 1.6, lambda b: (b.add(kalimba(hz(pent(9)), 0.1)), b.add(kalimba(hz(pent(5)), 0.1), 0.18)))
    sfx("tick", 0.6, lambda b: (b.add(tone(hz(pent(12)), 0.12, 0.002, 0.07, "triangle")),
                                 b.add(noise(0.03, "bandpass", 2500, 2500, 4, 0.05))))
    sfx("placeall", 1.8, lambda b: [b.add(kalimba(hz(pent(5 + k)), 0.09), k * 0.06) for k in range(6)])

    def offer(b):
        sparkle(b, 0, 4, 13, 0.04, 0.4)
        b.add(bell(hz(pent(10)), 0.06, 2.5), 0.1)
    sfx("offer", 3, offer)

    def city(b):
        b.add(chord([0, 7, 14, 16], 0.035, 0.25, 0.5, 2.5))
        b.add(bell(hz(pent(12)), 0.1, 3), 0.3)
        b.add(bell(hz(pent(14)), 0.08, 3), 0.55)
    sfx("city", 4, city)
    sfx("harvest", 2.4, lambda b: (b.add(bell(hz(pent(10)), 0.07, 2)), b.add(bell(hz(pent(12)), 0.07, 2), 0.16)))

    def citylost(b):
        for k, i in enumerate([9, 7, 5]):
            b.add(kalimba(hz(pent(i)), 0.09), k * 0.2)
        b.add(noise(0.8, "lowpass", 600, 150, 0.7, 0.05))
    sfx("citylost", 2.2, citylost)
    sfx("select", 1.2, lambda b: b.add(kalimba(hz(pent(10)), 0.09)))
    sfx("hop", 1.8, lambda b: (b.add(noise(0.55, "bandpass", 350, 1600, 1.4, 0.09)), b.add(kalimba(hz(pent(8)), 0.07), 0.5)))

    def claim(b):
        b.add(tone(hz(pent(7)), 0.1, 0.02, 0.5, "sine", hz(pent(10))))
        b.add(bell(hz(pent(12)), 0.09, 2.5), 0.18)
        sparkle(b, 0.2, 3, 14, 0.035, 0.3)
    sfx("claim", 3, claim)

    def gift(b):
        sparkle(b, 0, 8, 12, 0.045, 0.6)
        b.add(bell(hz(pent(9)), 0.06, 2), 0.05)
    sfx("gift", 2.6, gift)
    sfx("dance", 6.5, lambda b: b.add(bowl(hz(-5), 0.12, 6)))
    for v in range(3):
        sfx(f"dice_{v}", 1.0, lambda b: dice(b, 0))
    sfx("lose", 1.4, lambda b: (b.add(kalimba(hz(pent(4)), 0.08)), b.add(tone(hz(-12), 0.07, 0.01, 0.3))))

    def capture(b):
        for k, i in enumerate([5, 7, 9, 10, 12]):
            b.add(bell(hz(pent(i)), 0.09, 3), k * 0.1)
        b.add(chord([0, 7, 16], 0.03, 0.3, 0.6, 3), 0.4)
    sfx("capture", 4.6, capture)
    sfx("defend", 4.3, lambda b: (b.add(bell(hz(pent(0)), 0.12, 4)), b.add(bell(hz(pent(2)), 0.08, 3.5), 0.25)))
    sfx("runaway", 1.8, lambda b: (b.add(noise(0.6, "bandpass", 1400, 300, 1.2, 0.07)), b.add(kalimba(hz(pent(6)), 0.06), 0.1),
                                    b.add(kalimba(hz(pent(4)), 0.06), 0.3)))
    sfx("ask", 2.8, lambda b: (b.add(bell(hz(pent(7)), 0.1, 2)), b.add(bell(hz(pent(9)), 0.1, 2.4), 0.3)))

    def friends(b):
        b.add(bell(hz(pent(7)), 0.09, 3))
        b.add(bell(hz(pent(9)), 0.07, 3))
        b.add(bell(hz(pent(12)), 0.09, 3.5), 0.25)
        sparkle(b, 0.3, 4, 14, 0.035, 0.5)
    sfx("friends", 4, friends)
    sfx("nothanks", 1.6, lambda b: (b.add(kalimba(hz(pent(8)), 0.09)), b.add(kalimba(hz(pent(7)), 0.08), 0.25)))
    sfx("friendend", 5.2, lambda b: b.add(bell(hz(pent(2)), 0.09, 5)))

    def card(b):
        b.add(noise(0.25, "highpass", 2000, 5000, 0.7, 0.04))
        sparkle(b, 0.1, 5, 13, 0.04, 0.4)
    sfx("card", 2.2, card)
    sfx("rocket", 1.6, lambda b: (b.add(noise(1.1, "bandpass", 250, 3200, 1.2, 0.1)),
                                   b.add(tone(hz(pent(5)), 0.05, 0.05, 1.0, "sine", hz(pent(15))))))

    def luckydice(b):
        dice(b, 0)
        dice(b, 0.05)
        sparkle(b, 0.4, 3, 14, 0.04, 0.3)
    sfx("luckydice", 2.2, luckydice)

    def shield(b):
        for d in (0, 2.5):
            b.add(tone(hz(pent(12)) + d, 0.05, 0.3, 1.8))
        sparkle(b, 0, 3, 15, 0.03, 0.6)
    sfx("shield", 2.6, shield)
    sfx("mystery", 2.2, lambda b: [b.add(kalimba(hz(pent(i)), 0.09), k * 0.09) for k, i in enumerate([5, 7, 9, 12, 9, 12, 14])])
    sfx("meteor", 2.8, lambda b: [b.add(bell(hz(pent(17 - k)), 0.045, 1.6), k * 0.11) for k in range(10)])
    sfx("comet", 3, lambda b: (b.add(noise(2.2, "bandpass", 3000, 500, 2, 0.06, 0.4)),
                                b.add(tone(hz(pent(17)), 0.04, 0.3, 1.8, "sine", hz(pent(10))))))
    sfx("bloom", 1.8, lambda b: [b.add(tone(hz(pent(8 + k)), 0.05, 0.02, 0.25, "sine", hz(pent(9 + k))), k * 0.12) for k in range(6)])
    sfx("glow", 4, lambda b: (b.add(chord([7, 14, 19], 0.025, 0.6, 0.8, 2.5)), b.add(bell(hz(pent(12)), 0.07, 3), 0.3)))

    def gloomgrow(b):
        n = int(SR * 3.3)
        x = wave("sawtooth", phase_of(hz(-24), n))
        t = np.arange(n) / SR
        cut = np.interp(t, [0, 1.5, 3, 3.3], [120, 380, 120, 120])
        out = np.zeros(n)
        zi = np.zeros(2)
        for i in range(0, n, 128):
            bb, aa = biquad("lowpass", cut[i], 0.707)
            out[i:i + 128], zi = lfilter(bb, aa, x[i:i + 128], zi=zi)
        env = np.where(t < 1.5, 0.18 * (1e-4 / 0.18) ** (1 - t / 1.5), 0.18 * (1e-4 / 0.18) ** np.clip((t - 1.5) / 1.7, 0, 1))
        b.add(out * env)
    sfx("gloomgrow", 4, gloomgrow)
    sfx("gloomtake", 4.5, lambda b: (b.add(noise(1.6, "lowpass", 260, 90, 0.8, 0.14, 0.3)),
                                      b.add(bell(hz(pent(-3, MINP)), 0.09, 4), 0.2)))

    def gloomchase(b):
        b.add(noise(1.2, "highpass", 300, 4000, 0.7, 0.05, 0.2))
        for k, i in enumerate([5, 7, 10, 12]):
            b.add(bell(hz(pent(i)), 0.08, 2.5), 0.4 + k * 0.12)
    sfx("gloomchase", 3.6, gloomchase)
    sfx("storm", 5.2, lambda b: (b.add(noise(3, "bandpass", 200, 700, 1.5, 0.09, 1)), b.add(bowl(hz(-17), 0.1, 5))))

    def win(b):
        b.add(bowl(hz(0), 0.1, 7))
        for k in range(11):
            b.add(bell(hz(pent(5 + k)), 0.07, 3), 0.2 + k * 0.11)
        b.add(chord([-12, 0, 7, 14, 16], 0.035, 1.2, 2, 4), 0.2)
    sfx("win", 8, win)

    def loseall(b):
        b.add(chord([-15, -3, 4, 9], 0.03, 1.5, 1.5, 4))
        for k, i in enumerate([9, 7, 5, 4]):
            b.add(bell(hz(pent(i)), 0.07, 3.5), 0.6 + k * 0.5)
    sfx("loseall", 7.5, loseall)
    sfx("out", 3.8, lambda b: [b.add(bell(hz(pent(i)), 0.08, 3), k * 0.35) for k, i in enumerate([7, 5, 4])])
    sfx("bounce", 2, lambda b: (b.add(tone(hz(pent(2)), 0.1, 0.02, 0.4, "sine", hz(pent(7)))),
                                 [b.add(kalimba(hz(pent(i)), 0.1), 0.3 + k * 0.1) for k, i in enumerate([7, 9, 12])]))


# ------------------------------------------------------------------ music: "Deep space"
def make_music():
    # a seamless 32 s drone: A1 and E2, each a pair of slightly detuned sines that slowly beat.
    # Every frequency is snapped to whole cycles per loop so the loop has no click.
    L = 32.0
    n = int(SR * L)
    t = np.arange(n) / SR
    dr = np.zeros(n)
    for s in (-24, -17):
        for det in (-4, 4):
            f = round(hz(s) * 2 ** (det / 1200) * L) / L
            dr += np.sin(2 * np.pi * f * t) * 0.06
    save("drone", loop_reverb(dr, 0.7), master=0.9)
    # starry wind: band-passed noise that swells for about 13 s
    for v in range(4):
        b = Buf(14)
        b.add(noise(9, "bandpass", rng.uniform(300, 500), rng.uniform(900, 1400), 3, 0.035, 4))
        save(f"wind_{v}", trim(with_reverb(b.x, 0.7)))
    # rare low bells in A minor pentatonic
    for i in range(3, 9):
        b = Buf(6.5)
        b.add(bell(hz(pent(i, MINP)), 0.08, 6))
        save(f"mbell_{i}", trim(with_reverb(b.x, 0.7)))


if __name__ == "__main__":
    make_music()
    make_sfx()
    files = sorted(f for f in os.listdir(OUT) if f.endswith(".ogg"))
    size = sum(os.path.getsize(os.path.join(OUT, f)) for f in files)
    print(f"{len(files)} sounds written to {os.path.abspath(OUT)} ({size / 1e6:.1f} MB)")
