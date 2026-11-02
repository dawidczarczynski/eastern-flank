#!/usr/bin/env python3
"""Synthesises the vehicle and rocket sounds of TASK-123 (no suitable CC0 recording was found):
assets/audio/sfx/engine_heavy_loop.wav, engine_light_loop.wav, tracks_loop.wav, wheels_loop.wav
(8 s seamless loops: every filter is circular, every thud wraps around the loop end) and
rocket_launch_1.wav / rocket_launch_2.wav (ignition thump + decaying hiss, 1.4 s).
Deterministic (fixed seed), mono 16-bit 22.05 kHz. Prints peak / RMS / seam step per file.

Usage: python3 tools/gen_move_loops.py [out_dir]   (default assets/audio/sfx)
"""

import sys
import wave
from pathlib import Path

import numpy as np

RATE = 22050
LOOP_S = 8.0
SEED = 123


def _fft_filter(x: np.ndarray, low: float, high: float, slope: float = 2.0) -> np.ndarray:
    """Circular band-pass by FFT (smooth edges), so a loop stays seamless."""
    spectrum = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1.0 / RATE)
    gain = np.ones_like(f)
    if low > 0:
        gain *= 1.0 / (1.0 + (low / np.maximum(f, 1e-3)) ** (2 * slope))
    if high > 0:
        gain *= 1.0 / (1.0 + (f / high) ** (2 * slope))
    return np.fft.irfft(spectrum * gain, len(x))


def _noise(rng: np.random.Generator, n: int, low: float, high: float) -> np.ndarray:
    x = _fft_filter(rng.standard_normal(n), low, high)
    return x / np.abs(x).max()


def _engine(rng: np.random.Generator, firing_hz: float, body_hz: float, grit: float) -> np.ndarray:
    """Diesel idle: lumpy firing pulses (integer cycles per loop) over a low rumble."""
    n = int(RATE * LOOP_S)
    t = np.arange(n) / RATE
    cycles = round(firing_hz * LOOP_S)
    f0 = cycles / LOOP_S
    pulse = np.zeros(n)
    for k in range(1, 7):  # harmonics of the firing rate, falling off
        pulse += np.sin(2 * np.pi * f0 * k * t + rng.uniform(0, 6.28)) / k
    lump = 0.55 + 0.45 * np.sin(2 * np.pi * (f0 / 3.0 if cycles % 3 == 0 else f0 / 2.0) * t)
    rumble = _noise(rng, n, 25.0, body_hz)
    tone = _fft_filter(pulse * lump, 25.0, body_hz * 1.6)
    mix = tone / np.abs(tone).max() * 0.8 + rumble * 0.7 + _noise(rng, n, body_hz, 900.0) * grit
    return mix / np.abs(mix).max() * 0.75


def tracks(rng: np.random.Generator) -> np.ndarray:
    """Low track thuds with slight irregularity plus a faint clank and rattle."""
    n = int(RATE * LOOP_S)
    out = _noise(rng, n, 40.0, 220.0) * 0.25
    thud_len = int(0.16 * RATE)
    k = np.arange(thud_len) / RATE
    t = 0.0
    while t < LOOP_S:
        amp = rng.uniform(0.6, 1.0)
        freq = rng.uniform(55.0, 85.0)
        thud = np.sin(2 * np.pi * freq * k) * np.exp(-k * 28.0)
        clank = _noise(rng, thud_len, 500.0, 1800.0) * np.exp(-k * 55.0) * 0.18
        idx = (int(t * RATE) + np.arange(thud_len)) % n  # wraps: seamless
        out[idx] += (thud + clank) * amp
        t += 0.2 + rng.uniform(-0.025, 0.025)
    out += _noise(rng, n, 1200.0, 3500.0) * 0.04  # rattle
    return out / np.abs(out).max() * 0.75


def wheels(rng: np.random.Generator) -> np.ndarray:
    n = int(RATE * LOOP_S)
    t = np.arange(n) / RATE
    hum = _noise(rng, n, 60.0, 450.0)
    hum *= 0.85 + 0.15 * np.sin(2 * np.pi * (1.0 / LOOP_S) * 8 * t)
    return hum / np.abs(hum).max() * 0.6


def rocket(rng: np.random.Generator) -> np.ndarray:
    """Ignition burst: soft thump, fast attack, decaying hiss with a falling brightness."""
    n = int(RATE * 1.4)
    t = np.arange(n) / RATE
    thump = np.sin(2 * np.pi * (70.0 - 30.0 * t) * t) * np.exp(-t * 9.0) * 0.7
    hiss_lo = _noise(rng, n, 150.0, 1200.0) * np.exp(-t * 2.6)
    hiss_hi = _noise(rng, n, 1200.0, 5000.0) * np.exp(-t * 6.0) * 0.5
    attack = np.minimum(1.0, t / 0.02)
    out = (thump + hiss_lo + hiss_hi) * attack
    out *= np.minimum(1.0, (1.4 - t) / 0.25)  # fade-out
    return out / np.abs(out).max() * 0.8


def write(path: Path, samples: np.ndarray) -> None:
    pcm = (np.clip(samples, -1.0, 1.0) * 32767).astype("<i2")
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(pcm.tobytes())
    rms = float(np.sqrt(np.mean(samples**2)))
    step = abs(float(samples[0] - samples[-1]))
    typical = float(np.mean(np.abs(np.diff(samples))))
    print(
        "%-22s %.1f s peak %.2f rms %.3f loop step %.4f (typical %.4f)"
        % (path.name, len(samples) / RATE, np.abs(samples).max(), rms, step, typical)
    )


def main() -> None:
    out = Path(sys.argv[1] if len(sys.argv) > 1 else "assets/audio/sfx")
    out.mkdir(parents=True, exist_ok=True)
    write(out / "engine_heavy_loop.wav", _engine(np.random.default_rng(SEED), 14.0, 140.0, 0.08))
    write(out / "engine_light_loop.wav", _engine(np.random.default_rng(SEED + 1), 24.0, 260.0, 0.12))
    write(out / "tracks_loop.wav", tracks(np.random.default_rng(SEED + 2)))
    write(out / "wheels_loop.wav", wheels(np.random.default_rng(SEED + 3)))
    write(out / "rocket_launch_1.wav", rocket(np.random.default_rng(SEED + 4)))
    write(out / "rocket_launch_2.wav", rocket(np.random.default_rng(SEED + 5)))


if __name__ == "__main__":
    main()
