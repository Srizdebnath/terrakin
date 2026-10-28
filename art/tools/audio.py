"""Terrakin's soundtrack and sound effects, synthesised from scratch (no
samples, no third-party audio: every sound here is ours to ship).

    python3 art/tools/audio.py        # writes app/assets/audio/*.ogg

Loops are rendered twice over and the second pass kept, so reverb and
release tails wrap around and the loop point is seamless.
"""

import subprocess
import tempfile
import wave
from pathlib import Path

import numpy as np
from scipy.signal import lfilter

SR = 44100
OUT = Path(__file__).resolve().parents[2] / "app" / "assets" / "audio"
rng = np.random.default_rng(7)

# ---------------------------------------------------------------- primitives


def t_(sec):
    return np.arange(int(sec * SR)) / SR


def note(n):
    """MIDI note number -> Hz."""
    return 440.0 * 2 ** ((n - 69) / 12)


NOTES = {"C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "F": 5, "F#": 6, "Gb": 6, "G": 7, "G#": 8, "Ab": 8, "A": 9, "A#": 10, "Bb": 10, "B": 11}


def n(name):
    """'C4' -> MIDI number."""
    return 12 * (int(name[-1]) + 1) + NOTES[name[:-1]]


def env(length, a=0.005, d=0.1, s=0.7, r=0.2, hold=None):
    """ADSR envelope over [length] seconds; [hold] = time before release."""
    total = int(length * SR)
    hold = length - r if hold is None else hold
    e = np.zeros(total)
    ia, id_ = int(a * SR), int((a + d) * SR)
    ih = max(int(hold * SR), id_)
    e[:ia] = np.linspace(0, 1, ia, endpoint=False) if ia else 0
    e[ia:id_] = np.linspace(1, s, id_ - ia, endpoint=False)
    e[id_:ih] = s
    rel = total - ih
    if rel > 0:
        e[ih:] = np.linspace(s, 0, rel)
    return e


def decay(length, k):
    return np.exp(-t_(length) * k)


def sine(f, length, phase=0.0):
    return np.sin(2 * np.pi * f * t_(length) + phase)


def saw(f, length):
    x = (t_(length) * f) % 1.0
    return 2 * x - 1


def square(f, length, duty=0.5):
    return np.where((t_(length) * f) % 1.0 < duty, 1.0, -1.0)


def tri(f, length):
    return 2 * np.abs(saw(f, length)) - 1


def noise(length):
    return rng.uniform(-1, 1, int(length * SR))


def lowpass(x, cutoff):
    """One-pole low-pass with a swept cutoff (short sounds only: per sample)."""
    c = np.broadcast_to(np.asarray(cutoff, dtype=float), x.shape)
    a = 1 - np.exp(-2 * np.pi * c / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc += a[i] * (x[i] - acc)
        y[i] = acc
    return y


def lowpass_fast(x, cutoff):
    """Fixed-cutoff one-pole low-pass: y[n] = a x[n] + (1 - a) y[n-1]."""
    a = 1 - np.exp(-2 * np.pi * cutoff / SR)
    return lfilter([a], [1, a - 1], x)


def highpass(x, cutoff):
    return x - lowpass_fast(x, cutoff)


def reverb(x, mix=0.25, size=1.0):
    """Small Schroeder reverb: four combs into two all-passes."""
    out = np.zeros(len(x))
    for delay, g in [(1557, 0.84), (1617, 0.83), (1491, 0.82), (1422, 0.81)]:
        d = int(delay * size)
        a = np.zeros(d + 1)
        a[0], a[d] = 1, -g  # feedback comb: y[n] = x[n] + g y[n-d]
        out += lfilter([1], a, x)
    out /= 4
    for delay, g in [(225, 0.5), (556, 0.5)]:
        b = np.zeros(delay + 1)
        a = np.zeros(delay + 1)
        b[0], b[delay] = -g, 1  # all-pass
        a[0], a[delay] = 1, -g
        out = lfilter(b, a, out)
    return (1 - mix) * x + mix * out * 0.6


def place(buf, sig, at):
    i = int(at * SR)
    end = min(len(buf), i + len(sig))
    if i < len(buf):
        buf[i:end] += sig[: end - i]


def norm(x, peak=0.89):
    m = np.max(np.abs(x)) or 1
    return x / m * peak


def loud(x, rms=0.11):
    """Music loudness: every track at the same RMS, peaks soft-limited."""
    x = x / (np.sqrt(np.mean(x**2)) or 1) * rms
    return np.tanh(x / 0.95) * 0.95


def soft(x, drive=1.2):
    return np.tanh(x * drive) / np.tanh(drive)


# --------------------------------------------------------------- instruments


def epiano(f, length, vel=0.6):
    """Warm Rhodes-ish: sine + bell partial, quick decay."""
    tt = t_(length)
    tone = np.sin(2 * np.pi * f * tt) + 0.25 * np.sin(2 * np.pi * 2 * f * tt) * np.exp(-tt * 6)
    tone += 0.1 * np.sin(2 * np.pi * 3.01 * f * tt) * np.exp(-tt * 9)
    return vel * tone * env(length, 0.004, 0.4, 0.35, 0.3)


def pad(f, length, vel=0.35, bright=1800):
    detune = [0.995, 1.0, 1.006]
    x = sum(saw(f * d, length) for d in detune) / 3
    return vel * lowpass_fast(x, bright) * env(length, 0.6, 0.5, 0.8, 0.8)


def bell(f, length, vel=0.4):
    tt = t_(length)
    x = np.sin(2 * np.pi * f * tt) + 0.4 * np.sin(2 * np.pi * f * 2.76 * tt) * np.exp(-tt * 5)
    return vel * x * np.exp(-tt * 3.5)


def pluck(f, length, vel=0.5):
    x = lowpass_fast(saw(f, length) + 0.3 * square(f * 2, length), 2600)
    return vel * x * np.exp(-t_(length) * 7)


def kick(length=0.45, punch=1.0):
    tt = t_(length)
    f = 45 + 110 * np.exp(-tt * 30)
    x = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt * 7)
    click = noise(0.005) * 0.3
    x[: len(click)] += click
    return punch * x


def snare(length=0.25, vel=0.7):
    nz = highpass(noise(length), 1200) * np.exp(-t_(length) * 18)
    tone = sine(185, length) * np.exp(-t_(length) * 25)
    return vel * (0.75 * nz + 0.5 * tone)


def clap(vel=0.7):
    x = np.zeros(int(0.3 * SR))
    for k, off in enumerate([0, 0.009, 0.018]):
        burst = highpass(noise(0.12), 900) * np.exp(-t_(0.12) * (40 if k < 2 else 14))
        place(x, burst, off)
    return vel * x


def hat(length=0.06, vel=0.25, open_=False):
    L = 0.35 if open_ else length
    return vel * highpass(noise(L), 7000) * np.exp(-t_(L) * (9 if open_ else 60))


def cowbell(f, length=0.35, vel=0.5):
    x = square(f, length, 0.5) + square(f * 1.48, length, 0.5)
    x = highpass(lowpass_fast(x, 3800), 500)
    return vel * x * np.exp(-t_(length) * 9)


def bass808(f, length, vel=0.9, glide_from=None):
    tt = t_(length)
    if glide_from:
        freq = f + (glide_from - f) * np.exp(-tt * 18)
    else:
        freq = np.full_like(tt, f)
    x = np.sin(2 * np.pi * np.cumsum(freq) / SR)
    return vel * soft(x * 1.6, 1.5) * env(length, 0.003, 0.1, 0.85, 0.12)


def crackle(length, density=6, vel=0.05):
    x = np.zeros(int(length * SR))
    pops = rng.integers(0, len(x), int(length * density))
    x[pops] = rng.uniform(-1, 1, len(pops))
    return vel * lowpass_fast(x, 5000) + 0.012 * lowpass_fast(noise(length), 1200)


# ------------------------------------------------------------------- music


def chord(root, kind):
    iv = {"maj7": [0, 4, 7, 11], "m7": [0, 3, 7, 10], "6": [0, 4, 7, 9], "m9": [0, 3, 7, 10, 14], "7": [0, 4, 7, 10], "m": [0, 3, 7], "maj": [0, 4, 7]}[kind]
    return [n(root) + i for i in iv]


def render_loop(bars, bpm, build):
    """[build](buf, beat) fills a 2x buffer; returns the second, wrapped half."""
    beat = 60 / bpm
    length = bars * 4 * beat
    buf = np.zeros(int(2 * length * SR) + SR)
    for rep in range(2):
        build(buf, beat, rep * length)
    half = buf[int(length * SR): int(2 * length * SR)]
    return half, length


def overworld_day():
    prog = [("C4", "maj7"), ("A3", "m7"), ("F3", "maj7"), ("G3", "6")]
    melody = ["E5", "G5", "A5", "G5", "E5", "D5", "C5", "D5", "E5", "G5", "C6", "A5", "G5", "E5", "D5", "C5"]

    def build(buf, b, t0):
        for bar in range(8):
            root, kind = prog[bar % 4]
            at = t0 + bar * 4 * b
            for i, m in enumerate(chord(root, kind)):
                place(buf, epiano(note(m), 3.6 * b, 0.22), at + i * 0.012)
            place(buf, epiano(note(n(root) - 12), 3.8 * b, 0.35), at)
            for q in range(4):
                sw = 0.06 * b if q % 2 else 0
                place(buf, kick(0.4, 0.8), at + q * b) if q in (0, 2) else None
                if q in (1, 3):
                    place(buf, snare(0.22, 0.38), at + q * b)
                for e in range(2):
                    place(buf, hat(0.05, 0.12 if e else 0.08), at + q * b + e * (b / 2) + (sw if e else 0))
            for k in range(2):
                mel = melody[(bar * 2 + k) % len(melody)]
                place(buf, bell(note(n(mel)), 1.6 * b, 0.13), at + (k * 2 + 0.5) * b)
        place(buf, crackle(32 * b), t0)

    x, _ = render_loop(8, 88, build)
    return loud(reverb(lowpass_fast(x, 6500), 0.22))


def overworld_rain():
    prog = [("A3", "m7"), ("F3", "maj7"), ("C4", "maj7"), ("G3", "6")]

    def build(buf, b, t0):
        for bar in range(8):
            root, kind = prog[bar % 4]
            at = t0 + bar * 4 * b
            for m in chord(root, kind):
                place(buf, pad(note(m), 4.2 * b, 0.12, 1200), at)
            place(buf, pad(note(n(root) - 12), 4.2 * b, 0.2, 500), at)
            place(buf, kick(0.5, 0.55), at)
            place(buf, kick(0.5, 0.4), at + 2.5 * b)
            for q in range(8):
                place(buf, hat(0.04, 0.05), at + q * b / 2)
            if bar % 2:
                arp = chord(root, kind)
                for k, m in enumerate(arp):
                    place(buf, bell(note(m + 12), 1.2 * b, 0.07), at + (1 + k * 0.5) * b)
        rain = lowpass_fast(highpass(noise(32 * b), 1500), 6000) * 0.05
        place(buf, rain, t0)

    x, _ = render_loop(8, 78, build)
    return loud(reverb(x, 0.35, 1.2))


def overworld_night():
    prog = [("D3", "m9"), ("A#2", "maj7"), ("G2", "m7"), ("A2", "7")]

    def build(buf, b, t0):
        for bar in range(8):
            root, kind = prog[bar % 4]
            at = t0 + bar * 4 * b
            for m in chord(root, kind):
                place(buf, pad(note(m + 12), 4.3 * b, 0.1, 900), at)
            place(buf, epiano(note(n(root)), 4 * b, 0.3), at)
            for k, m in enumerate(chord(root, kind)[:4]):
                place(buf, bell(note(m + 24), 2 * b, 0.06), at + k * b + 0.5 * b)
            place(buf, kick(0.6, 0.35), at)
            place(buf, hat(0.08, 0.04), at + 2 * b)
        place(buf, crackle(32 * b, 3, 0.03), t0)

    x, _ = render_loop(8, 66, build)
    return loud(reverb(lowpass_fast(x, 5000), 0.4, 1.3))


def encounter():
    def build(buf, b, t0):
        for bar in range(4):
            at = t0 + bar * 4 * b
            root = [n("E2"), n("E2"), n("C2"), n("D2")][bar]
            for s in range(16):
                place(buf, pluck(note(root + (12 if s % 4 == 3 else 0)), b / 4 * 0.9, 0.35), at + s * b / 4)
                place(buf, hat(0.03, 0.07 if s % 2 else 0.11), at + s * b / 4)
            for q in range(4):
                place(buf, kick(0.3, 0.75), at + q * b)
            arp = [n("E4"), n("G4"), n("B4"), n("E5")] if bar < 2 else [n("E4"), n("A4"), n("C5"), n("F#5")]
            for k in range(8):
                place(buf, bell(note(arp[k % 4] + (bar % 2) * 2), 0.5 * b, 0.12), at + k * b / 2)
        riser = highpass(noise(16 * b), 2000) * np.linspace(0, 0.06, int(16 * b * SR))
        place(buf, riser, t0)

    x, _ = render_loop(4, 124, build)
    return loud(reverb(x, 0.15))


def battle():
    # Phonk-lite: 808s, cowbell lead, trap hats, clap on the backbeat.
    bass = ["C#2", "C#2", "A1", "B1"]
    bell_line = [(0, "G#5"), (0.75, "G#5"), (1.5, "F#5"), (2, "E5"), (2.75, "F#5"), (3.5, "C#5")]

    def build(buf, b, t0):
        for bar in range(8):
            at = t0 + bar * 4 * b
            root = n(bass[bar % 4])
            place(buf, bass808(note(root), 1.4 * b, 0.9, note(root + 7)), at)
            place(buf, bass808(note(root), 0.9 * b, 0.8), at + 1.75 * b)
            place(buf, bass808(note(root + (3 if bar % 2 else 0)), 1.2 * b, 0.8), at + 2.5 * b)
            for k in (0, 1.75, 2.5):
                place(buf, kick(0.35, 0.9), at + k * b)
            place(buf, clap(0.75), at + b)
            place(buf, clap(0.75), at + 3 * b)
            rolls = 16 if bar % 4 == 3 else 8
            for s in range(rolls):
                place(buf, hat(0.03, 0.12 if s % 2 else 0.18), at + s * 4 * b / rolls)
            if bar % 4 == 3:
                for s in range(6):
                    place(buf, hat(0.02, 0.1), at + 3.25 * b + s * b / 8)
            for off, m in bell_line:
                place(buf, cowbell(note(n(m) - (2 if bar % 4 == 2 else 0)), 0.3, 0.32), at + off * b)

    x, _ = render_loop(8, 140, build)
    return loud(lowpass_fast(soft(x, 1.05), 9000), 0.12)


# --------------------------------------------------------------------- sfx


def sfx_tap():
    return norm(sine(1400, 0.05) * decay(0.05, 80) + 0.4 * sine(2100, 0.05) * decay(0.05, 120), 0.6)


def sfx_throw():
    L = 0.45
    sweep = np.linspace(500, 4000, int(L * SR))
    x = lowpass(highpass(noise(L), 300), sweep) * env(L, 0.05, 0.1, 0.8, 0.25)
    return norm(x, 0.7)


def sfx_wobble():
    x = sine(110, 0.25) * decay(0.25, 18)
    place(x, lowpass_fast(noise(0.05), 900) * 0.5, 0)
    return norm(x, 0.7)


def sfx_catch():
    buf = np.zeros(int(1.4 * SR))
    for k, m in enumerate(["C6", "E6", "G6", "C7"]):
        place(buf, bell(note(n(m)), 1.0, 0.5), k * 0.08)
    place(buf, highpass(noise(0.8), 6000) * np.linspace(0.03, 0, int(0.8 * SR)), 0.1)
    return norm(reverb(buf, 0.3), 0.85)


def sfx_break_free():
    buf = np.zeros(int(0.6 * SR))
    place(buf, lowpass_fast(noise(0.08), 3000) * decay(0.08, 40), 0)
    tt = t_(0.4)
    f = 900 * np.exp(-tt * 4)
    place(buf, np.sin(2 * np.pi * np.cumsum(f) / SR) * decay(0.4, 6) * 0.5, 0.05)
    return norm(buf, 0.75)


def sfx_fled():
    tt = t_(0.7)
    f = 1500 * np.exp(-tt * 2.5) + 200
    return norm(np.sin(2 * np.pi * np.cumsum(f) / SR) * env(0.7, 0.01, 0.2, 0.6, 0.3), 0.6)


def sfx_hit():
    buf = np.zeros(int(0.3 * SR))
    place(buf, kick(0.25, 1.0), 0)
    place(buf, lowpass_fast(noise(0.12), 2500) * decay(0.12, 30) * 0.7, 0)
    return norm(soft(buf, 2), 0.85)


def sfx_ko():
    buf = np.zeros(int(1.0 * SR))
    place(buf, kick(0.5, 1.2), 0)
    place(buf, lowpass_fast(noise(0.3), 1800) * decay(0.3, 10), 0)
    tt = t_(0.7)
    f = 600 * np.exp(-tt * 3) + 80
    place(buf, np.sin(2 * np.pi * np.cumsum(f) / SR) * decay(0.7, 4) * 0.4, 0.1)
    return norm(reverb(soft(buf, 1.8), 0.2), 0.9)


def sfx_coin():
    buf = np.zeros(int(0.6 * SR))
    place(buf, square(note(n("B5")), 0.08) * decay(0.08, 20) * 0.3, 0)
    place(buf, square(note(n("E6")), 0.45) * decay(0.45, 8) * 0.3, 0.07)
    return norm(lowpass_fast(buf, 7000), 0.6)


def sfx_reveal():
    return norm(pluck(note(n("G5")), 0.4, 0.8) + 0.5 * bell(note(n("D6")), 0.4, 0.5), 0.6)


def sfx_crown():
    buf = np.zeros(int(2.0 * SR))
    for k, m in enumerate(["C5", "E5", "G5", "C6", "E6", "G6"]):
        place(buf, bell(note(n(m)), 1.5, 0.4), k * 0.06)
    for m in ["C4", "G4", "E5"]:
        place(buf, pad(note(n(m)), 1.6, 0.25, 3000), 0.3)
    place(buf, highpass(noise(1.5), 7000) * np.linspace(0.1, 0, int(1.5 * SR)), 0.2)
    return norm(reverb(buf, 0.35), 0.9)


def sfx_jackpot():
    buf = np.zeros(int(1.8 * SR))
    seq = ["C5", "E5", "G5", "C6", "G5", "C6", "E6", "G6"]
    for k, m in enumerate(seq):
        place(buf, square(note(n(m)), 0.12, 0.25) * decay(0.12, 14) * 0.3, k * 0.07)
    place(buf, bell(note(n("C7")), 1.2, 0.5), 0.6)
    return norm(reverb(lowpass_fast(buf, 8000), 0.25), 0.85)


def sfx_dud():
    buf = np.zeros(int(1.6 * SR))
    for k, (m, L) in enumerate([("A3", 0.35), ("G#3", 0.35), ("G3", 0.35), ("F#3", 0.7)]):
        tt = t_(L)
        vib = 1 + 0.01 * np.sin(2 * np.pi * 6 * tt) * (k == 3)
        f = note(n(m)) * vib
        x = lowpass_fast(lowpass_fast(np.sign(np.sin(2 * np.pi * np.cumsum(f) / SR)), 700), 700)
        place(buf, x * env(L, 0.02, 0.05, 0.7, 0.1) * 0.4, k * 0.35)
    return norm(buf, 0.7)


def sfx_claim():
    buf = np.zeros(int(1.2 * SR))
    place(buf, kick(0.4, 1.0), 0)
    for k, m in enumerate(["G5", "C6", "E6"]):
        place(buf, bell(note(n(m)), 0.9, 0.4), 0.08 + k * 0.07)
    return norm(reverb(buf, 0.25), 0.85)


def sfx_win():
    buf = np.zeros(int(2.0 * SR))
    for k, (m, L) in enumerate([("C5", 0.15), ("E5", 0.15), ("G5", 0.15), ("C6", 0.9)]):
        place(buf, (pluck(note(n(m)), L + 0.3, 0.6) + bell(note(n(m)), L + 0.3, 0.3)), k * 0.14)
    for m in ["C4", "E4", "G4"]:
        place(buf, pad(note(n(m)), 1.3, 0.2, 2500), 0.42)
    return norm(reverb(buf, 0.3), 0.9)


def sfx_lose():
    buf = np.zeros(int(1.8 * SR))
    for k, m in enumerate(["G4", "Eb4", "C4", "B3"]):
        place(buf, epiano(note(n(m)), 0.7, 0.6), k * 0.22)
    return norm(reverb(buf, 0.3), 0.8)


# ------------------------------------------------------------------- write


def write_ogg(name, x, quality=4):
    OUT.mkdir(parents=True, exist_ok=True)
    pcm = (np.clip(x, -1, 1) * 32767).astype(np.int16)
    with tempfile.NamedTemporaryFile(suffix=".wav") as tmp:
        with wave.open(tmp.name, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(SR)
            w.writeframes(pcm.tobytes())
        subprocess.run(
            ["ffmpeg", "-y", "-loglevel", "error", "-i", tmp.name, "-c:a", "libvorbis", "-q:a", str(quality), str(OUT / f"{name}.ogg")],
            check=True,
        )
    print(f"{name}.ogg  {len(x) / SR:5.1f}s  {(OUT / f'{name}.ogg').stat().st_size // 1024} KB")


def main():
    music = {
        "music_day": overworld_day,
        "music_rain": overworld_rain,
        "music_night": overworld_night,
        "music_encounter": encounter,
        "music_battle": battle,
    }
    sfx = {
        "sfx_tap": sfx_tap,
        "sfx_throw": sfx_throw,
        "sfx_wobble": sfx_wobble,
        "sfx_catch": sfx_catch,
        "sfx_break_free": sfx_break_free,
        "sfx_fled": sfx_fled,
        "sfx_hit": sfx_hit,
        "sfx_ko": sfx_ko,
        "sfx_coin": sfx_coin,
        "sfx_reveal": sfx_reveal,
        "sfx_crown": sfx_crown,
        "sfx_jackpot": sfx_jackpot,
        "sfx_dud": sfx_dud,
        "sfx_claim": sfx_claim,
        "sfx_win": sfx_win,
        "sfx_lose": sfx_lose,
    }
    for name, fn in sfx.items():
        write_ogg(name, fn(), 5)
    for name, fn in music.items():
        write_ogg(name, fn(), 3)


if __name__ == "__main__":
    main()
