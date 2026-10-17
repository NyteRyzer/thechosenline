#!/usr/bin/env python3
"""Generates the game's original audio: room ambience, title music and sound effects.

Everything is synthesized here from sine waves and filtered noise, so there are no
third-party samples. Loops are rendered circularly (FFT filtering, wrapped note
tails) so they repeat without a seam. Output is 22.05 kHz mono 16-bit WAV.

Usage:  python3 tools/generate_audio.py      (requires numpy)
"""
import wave
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets/audio"
SR = 22050
RNG = np.random.default_rng(7)


def t_axis(seconds):
    return np.arange(int(SR * seconds)) / SR


def save(path, signal, peak=0.8):
    signal = np.asarray(signal, np.float64)
    top = np.max(np.abs(signal)) or 1.0
    data = np.int16(np.clip(signal / top * peak, -1, 1) * 32767)
    path = OUT / path
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(SR)
        f.writeframes(data.tobytes())
    print("wrote", path.relative_to(ROOT), "%.1fs" % (len(data) / SR))


def spectral_noise(n, low, high, tilt=0.0):
    """Periodic band-limited noise (seamless when looped)."""
    spectrum = np.fft.rfft(RNG.standard_normal(n))
    freqs = np.fft.rfftfreq(n, 1 / SR)
    shape = ((freqs >= low) & (freqs <= high)).astype(float)
    shape *= np.where(freqs > 0, (np.maximum(freqs, 1) / 100.0) ** -tilt, 0)
    out = np.fft.irfft(spectrum * shape, n)
    return out / (np.max(np.abs(out)) or 1)


def circular_reverb(signal, seconds=1.6, mix=0.35):
    n = len(signal)
    ir_len = int(SR * seconds)
    ir = RNG.standard_normal(ir_len) * np.exp(-np.arange(ir_len) / (SR * seconds / 5))
    ir = np.concatenate([ir, np.zeros(n - ir_len)]) if ir_len < n else ir[:n]
    wet = np.fft.irfft(np.fft.rfft(signal) * np.fft.rfft(ir), n)
    wet /= np.max(np.abs(wet)) or 1
    return signal * (1 - mix) + wet * mix * np.max(np.abs(signal))


def linear_reverb(signal, seconds=1.4, mix=0.3):
    ir_len = int(SR * seconds)
    ir = RNG.standard_normal(ir_len) * np.exp(-np.arange(ir_len) / (SR * seconds / 5))
    wet = np.convolve(signal, ir)[: len(signal) + ir_len]
    wet = np.pad(wet, (0, len(signal) + ir_len - len(wet)))
    wet /= np.max(np.abs(wet)) or 1
    dry = np.concatenate([signal, np.zeros(ir_len)])
    return dry * (1 - mix) + wet * mix * np.max(np.abs(signal))


def envelope(n, attack, release):
    env = np.ones(n)
    a, r = int(SR * attack), int(SR * release)
    if a:
        env[:a] = np.linspace(0, 1, a)
    if r:
        env[-r:] *= np.linspace(1, 0, r)
    return env


def note_freq(name):
    names = {"C": 0, "C#": 1, "D": 2, "D#": 3, "E": 4, "F": 5, "F#": 6, "G": 7, "G#": 8, "A": 9, "A#": 10, "B": 11}
    pitch, octave = name[:-1], int(name[-1])
    return 440.0 * 2 ** ((names[pitch] + 12 * (octave + 1) - 69) / 12)


def piano(freq, seconds):
    t = t_axis(seconds)
    tone = np.zeros_like(t)
    for k, amp in enumerate([1.0, 0.45, 0.25, 0.12, 0.06], start=1):
        f = freq * k * (1 + 0.0004 * k * k)  # slight string inharmonicity
        tone += amp * np.sin(2 * np.pi * f * t) * np.exp(-t * (1.2 + 0.9 * k))
    return tone * envelope(len(t), 0.004, 0.05)


# ---------------------------------------------------------------------------
# Ambience loops
# ---------------------------------------------------------------------------

def ambience_house():
    seconds = 16
    t = t_axis(seconds)
    n = len(t)
    rumble = spectral_noise(n, 25, 220, tilt=1.0)  # distant traffic
    swell = 0.55 + 0.45 * np.sin(2 * np.pi * t / seconds) ** 2
    car = np.exp(-((t - 9.5) / 1.6) ** 2)  # one car passing outside
    hiss = spectral_noise(n, 600, 3000, tilt=0.5)  # wind through the broken window
    hum = sum(a * np.sin(2 * np.pi * f * t) for f, a in [(60, 1.0), (120, 0.5), (180, 0.15)])  # fridge, from the kitchen
    mix = rumble * swell * 0.55 + rumble * car * 0.6 + hiss * (0.12 + 0.08 * np.sin(2 * np.pi * 2 * t / seconds)) + hum * 0.05
    save("ambience/house.wav", mix, 0.5)


def ambience_kitchen():
    seconds = 16
    t = t_axis(seconds)
    n = len(t)
    hum = sum(a * np.sin(2 * np.pi * f * t) for f, a in [(60, 1.0), (120, 0.7), (180, 0.3), (240, 0.15)])
    buzz = spectral_noise(n, 400, 900) * 0.08  # compressor
    rumble = spectral_noise(n, 25, 200, tilt=1.0) * 0.35
    tick = np.zeros(n)
    click = spectral_noise(int(SR * 0.012), 1500, 6000) * np.exp(-np.arange(int(SR * 0.012)) / 40)
    for second in range(seconds):  # wall clock
        start = second * SR
        tick[start:start + len(click)] += click * (0.9 if second % 2 else 0.6)
    save("ambience/kitchen.wav", hum * 0.22 + buzz + rumble + tick * 0.25, 0.5)


# ---------------------------------------------------------------------------
# Music
# ---------------------------------------------------------------------------

def music_title():
    """Sparse D-minor piano over a low drone, as the Bible's investigation music asks."""
    beat = 0.8
    melody = [("D4", 0), ("F4", 2), ("A4", 4), ("E4", 7), ("D4", 10), ("C4", 12), ("A3", 14),
              ("D4", 16), ("F4", 18), ("A4", 20), ("C5", 22), ("A#4", 24), ("A4", 26), ("E4", 28), ("D4", 30)]
    seconds = 32 * beat
    n = int(SR * seconds)
    out = np.zeros(n)
    for name, step in melody:
        tone = piano(note_freq(name), 4.0) * 0.6
        start = int(step * beat * SR)
        idx = (start + np.arange(len(tone))) % n  # wrap tails so the loop is seamless
        np.add.at(out, idx, tone)
    for name, step in [("D2", 0), ("A#1", 16)]:  # bass notes
        tone = piano(note_freq(name), 6.0) * 0.5
        idx = (int(step * beat * SR) + np.arange(len(tone))) % n
        np.add.at(out, idx, tone)
    t = t_axis(seconds)
    drone = (np.sin(2 * np.pi * note_freq("D2") * t) + 0.5 * np.sin(2 * np.pi * note_freq("A2") * t))
    drone *= 0.07 * (0.7 + 0.3 * np.sin(2 * np.pi * t / seconds))
    save("music/title.wav", circular_reverb(out + drone, 2.2, 0.4), 0.6)


# ---------------------------------------------------------------------------
# Sound effects
# ---------------------------------------------------------------------------

def sfx_pickup():
    out = np.concatenate([piano(note_freq("E5"), 0.12) * 0.7, piano(note_freq("A5"), 0.7)])
    save("sfx/pickup.wav", linear_reverb(out, 0.6, 0.25), 0.55)


def sfx_evidence():
    """Pencil scratches on a notebook page."""
    out = np.zeros(int(SR * 0.7))
    for start, length in [(0.02, 0.12), (0.18, 0.09), (0.32, 0.16), (0.52, 0.08)]:
        seg = spectral_noise(int(SR * length), 2500, 7000)
        seg *= np.sin(np.linspace(0, np.pi, len(seg))) * (0.6 + 0.4 * np.sin(np.linspace(0, 30, len(seg))))
        s = int(SR * start)
        out[s:s + len(seg)] += seg
    save("sfx/evidence.wav", out, 0.35)


def sfx_door():
    """Footsteps and a door swinging."""
    seconds = 1.1
    t = t_axis(seconds)
    out = np.zeros(len(t))
    for start in (0.0, 0.33):
        thump = spectral_noise(int(SR * 0.12), 60, 400) * np.exp(-np.arange(int(SR * 0.12)) / 500)
        s = int(SR * start)
        out[s:s + len(thump)] += thump
    creak_t = t[: int(SR * 0.6)]
    creak = np.sin(2 * np.pi * (380 + 120 * np.sin(creak_t * 9)) * creak_t) * np.sin(np.linspace(0, np.pi, len(creak_t)))
    creak *= 1 + 0.6 * np.sign(np.sin(2 * np.pi * 34 * creak_t))  # grainy hinge
    s = int(SR * 0.45)
    out[s:s + len(creak)] += creak * 0.12
    save("sfx/door.wav", out, 0.5)


def sfx_bell():
    """A single distant church bell (inharmonic partials)."""
    seconds = 5.0
    t = t_axis(seconds)
    base = 196.0
    out = sum(a * np.sin(2 * np.pi * base * r * t) * np.exp(-t * d)
              for r, a, d in [(0.5, 0.6, 0.6), (1.0, 1.0, 0.9), (1.19, 0.5, 1.2), (1.5, 0.45, 1.4),
                              (2.0, 0.35, 1.8), (2.51, 0.25, 2.4), (3.0, 0.15, 3.0)])
    out *= envelope(len(t), 0.003, 0.3)
    save("sfx/bell.wav", linear_reverb(out, 2.0, 0.45), 0.6)


def sfx_revelation():
    """Choir-like pad for an angelic revelation or a solved deduction."""
    seconds = 3.2
    t = t_axis(seconds)
    out = np.zeros(len(t))
    for name in ("D4", "F#4", "A4", "D5"):
        f = note_freq(name)
        vibrato = 1 + 0.004 * np.sin(2 * np.pi * 5.2 * t)
        out += sum(a * np.sin(2 * np.pi * f * k * vibrato * t) for k, a in [(1, 1.0), (2, 0.3), (3, 0.12)])
    out *= envelope(len(t), 0.9, 1.4)
    save("sfx/revelation.wav", linear_reverb(out, 1.8, 0.4), 0.5)


def sfx_wrong():
    seconds = 0.5
    t = t_axis(seconds)
    out = np.sin(2 * np.pi * (180 - 60 * t) * t) * np.exp(-t * 6) + 0.4 * np.sin(2 * np.pi * 120 * t) * np.exp(-t * 8)
    save("sfx/wrong.wav", out, 0.4)


def sfx_click():
    n = int(SR * 0.04)
    out = spectral_noise(n, 1200, 5000) * np.exp(-np.arange(n) / 90)
    save("sfx/click.wav", out, 0.3)


if __name__ == "__main__":
    ambience_house()
    ambience_kitchen()
    music_title()
    sfx_pickup()
    sfx_evidence()
    sfx_door()
    sfx_bell()
    sfx_revelation()
    sfx_wrong()
    sfx_click()
