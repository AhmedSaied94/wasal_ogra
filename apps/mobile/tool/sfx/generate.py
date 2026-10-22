#!/usr/bin/env python3
"""Writes the trip's stand-in sound effects (specs/008-m02-trip-screen,
research R18, contracts/trip-view.md "Stand-in effects").

Each effect is a short mono WAV, 22,050 Hz, 16-bit, at most 0.6 s, made from
sines and noise. Running the script twice writes byte-identical files, and CI
checks that the committed files are exactly what it writes.

Only IEEE basic arithmetic is used (no math.sin or math.exp, whose last bit
can differ between C libraries), and the noise comes from a seeded
random.Random, so every machine writes the same bytes.

Usage (from apps/mobile): python3 tool/sfx/generate.py
"""

import random
import struct
import wave
from pathlib import Path

RATE = 22050
MAX_SECONDS = 0.6
FADE_SECONDS = 0.005
PEAK = 0.8
SEED = 20261022

OUT = Path(__file__).resolve().parents[2] / "assets" / "audio" / "sfx"

Samples = list[float]

PI = 3.141592653589793
TWO_PI = 2 * PI


def sin(x: float) -> float:
    """sin(x) by a Taylor series after reducing x to [-pi, pi]."""
    x = x - TWO_PI * round(x / TWO_PI)
    x2 = x * x
    term = x
    total = x
    for n in range(1, 10):
        term = -term * x2 / ((2 * n) * (2 * n + 1))
        total += term
    return total


def silence(seconds: float) -> Samples:
    return [0.0] * int(RATE * seconds)


def tone(
    freq_from: float,
    seconds: float,
    freq_to: float | None = None,
    harmonics: tuple[float, ...] = (1.0,),
) -> Samples:
    """A sine sweeping linearly from freq_from to freq_to, with optional
    harmonics given as their amplitudes (1st, 2nd, ...)."""
    freq_to = freq_from if freq_to is None else freq_to
    count = int(RATE * seconds)
    out = []
    phase = 0.0
    for i in range(count):
        freq = freq_from + (freq_to - freq_from) * i / max(count - 1, 1)
        phase += TWO_PI * freq / RATE
        value = 0.0
        for k, amplitude in enumerate(harmonics, start=1):
            value += amplitude * sin(phase * k)
        out.append(value)
    return out


def noise(rng: random.Random, seconds: float, smoothing: float) -> Samples:
    """White noise through a one-pole low-pass: 0 keeps it white, values
    near 1 make it darker."""
    out = []
    last = 0.0
    for _ in range(int(RATE * seconds)):
        last = smoothing * last + (1 - smoothing) * (rng.random() * 2 - 1)
        out.append(last)
    return out


def decay(samples: Samples, speed: float) -> Samples:
    """Multiplies by an exponential-like decay, one multiplication per
    sample."""
    factor = 1.0
    step = 1 - speed / RATE
    out = []
    for value in samples:
        out.append(value * factor)
        factor *= step
    return out


def mix(*parts: Samples) -> Samples:
    length = max(len(part) for part in parts)
    return [sum(part[i] for part in parts if i < len(part)) for i in range(length)]


def gain(samples: Samples, amount: float) -> Samples:
    return [value * amount for value in samples]


def finish(samples: Samples) -> Samples:
    """Trims to the maximum length, fades both ends, and scales to PEAK."""
    samples = samples[: int(RATE * MAX_SECONDS)]
    fade = int(RATE * FADE_SECONDS)
    count = len(samples)
    shaped = []
    for i, value in enumerate(samples):
        envelope = 1.0
        if i < fade:
            envelope = i / fade
        elif i >= count - fade:
            envelope = (count - 1 - i) / fade
        shaped.append(value * envelope)
    loudest = max(abs(value) for value in shaped) or 1.0
    return [value * PEAK / loudest for value in shaped]


def effects(rng: random.Random) -> dict[str, Samples]:
    return {
        # Two bright pings.
        "coin": decay(tone(2600, 0.08), 20) + decay(tone(3400, 0.08), 20),
        # A paper rustle.
        "note_pass": decay(noise(rng, 0.12, 0.55), 8),
        # Two rising tones, a passenger calling before a stop.
        "call": tone(660, 0.15) + tone(880, 0.15),
        # A square-ish horn.
        "horn": mix(
            tone(340, 0.4, harmonics=(1.0, 0.0, 0.33, 0.0, 0.2)),
            tone(420, 0.4, harmonics=(1.0, 0.0, 0.33, 0.0, 0.2)),
        ),
        # A low buzz with grit.
        "fight": mix(
            tone(110, 0.35, harmonics=(1.0, 0.5, 0.33, 0.25)),
            gain(noise(rng, 0.35, 0.3), 0.35),
        ),
        # A soft rising chime.
        "thanks": decay(tone(880, 0.3, freq_to=1320, harmonics=(1.0, 0.3)), 4),
        # A falling tone.
        "wrong": tone(440, 0.25, freq_to=220, harmonics=(1.0, 0.25)),
        # A low thud.
        "bump": decay(mix(tone(60, 0.2), gain(noise(rng, 0.2, 0.85), 0.6)), 12),
        # Three short beeps.
        "alert": tone(1000, 0.06)
        + silence(0.06)
        + tone(1000, 0.06)
        + silence(0.06)
        + tone(1000, 0.06),
    }


def write(path: Path, samples: Samples) -> None:
    frames = b"".join(struct.pack("<h", round(value * 32767)) for value in samples)
    with wave.open(str(path), "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(frames)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    rng = random.Random(SEED)  # noqa: S311 (a fixed seed, not a secret)
    for name, samples in effects(rng).items():
        write(OUT / f"{name}.wav", finish(samples))


if __name__ == "__main__":
    main()
