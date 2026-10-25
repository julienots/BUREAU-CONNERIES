#!/usr/bin/env python3
"""Generates every sound of OFFICE MAYHEM.

- Office SFX are synthesized with numpy (no external samples, fully reproducible).
- Funny gibberish voices are produced with espeak-ng reading nonsense syllables,
  then reshaped with sox (pitch, tempo, tremolo...) per character voice and emotion.

Usage:  python3 tools/gen_audio.py            (needs numpy, espeak-ng, sox)
Output: assets/audio/{sfx,voices,music}/*.wav
"""
import os
import random
import subprocess
import tempfile
import wave

import numpy as np

SR = 22050
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "audio")
rng = np.random.default_rng(1234)
random.seed(1234)


# ----------------------------------------------------------------- helpers
def t_axis(dur):
    return np.arange(int(dur * SR)) / SR


def noise(dur):
    return rng.uniform(-1, 1, int(dur * SR))


def env_ad(n, attack=0.005, decay=0.2, curve=4.0):
    t = np.arange(n) / SR
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    d = np.exp(-np.maximum(t - attack, 0) * curve / max(decay, 1e-4))
    return a * d


def lowpass(x, cutoff):
    # one-pole low-pass, applied twice for a gentler 12 dB/oct slope
    a = np.exp(-2 * np.pi * cutoff / SR)
    y = np.empty_like(x)
    for _ in range(2):
        acc = 0.0
        for i in range(len(x)):
            acc = (1 - a) * x[i] + a * acc
            y[i] = acc
        x = y.copy()
    return y


def lowpass_fast(x, cutoff):
    # FFT brick-ish low-pass with smooth roll-off, fast for long signals
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    X *= 1 / (1 + (f / cutoff) ** 4)
    return np.fft.irfft(X, len(x))


def highpass_fast(x, cutoff):
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    X *= 1 - 1 / (1 + (f / max(cutoff, 1)) ** 4)
    return np.fft.irfft(X, len(x))


def bandpass_fast(x, lo, hi):
    return lowpass_fast(highpass_fast(x, lo), hi)


def tone(freq, dur, kind="sine"):
    t = t_axis(dur)
    if callable(freq):
        phase = 2 * np.pi * np.cumsum(freq(t)) / SR
    else:
        phase = 2 * np.pi * freq * t
    if kind == "sine":
        return np.sin(phase)
    if kind == "square":
        return np.sign(np.sin(phase)) * 0.6
    if kind == "saw":
        return 2 * ((phase / (2 * np.pi)) % 1.0) - 1
    if kind == "tri":
        return 2 * np.abs(2 * ((phase / (2 * np.pi)) % 1.0) - 1) - 1
    raise ValueError(kind)


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[: len(p)] += p
    return out


def place(dst, src, at):
    i = int(at * SR)
    end = min(len(dst), i + len(src))
    if i < len(dst):
        dst[i:end] += src[: end - i]
    return dst


def silence(dur):
    return np.zeros(int(dur * SR))


def norm(x, peak=0.9):
    m = np.max(np.abs(x)) + 1e-9
    return x / m * peak


def fade(x, fin=0.005, fout=0.02):
    n = len(x)
    a = min(int(fin * SR), n // 2)
    b = min(int(fout * SR), n // 2)
    if a > 0:
        x[:a] *= np.linspace(0, 1, a)
    if b > 0:
        x[-b:] *= np.linspace(1, 0, b)
    return x


def loopify(x, xfade=0.25):
    """Crossfade the tail into the head so the clip loops seamlessly."""
    n = int(xfade * SR)
    head = x[:n].copy()
    tail = x[-n:].copy()
    ramp = np.linspace(0, 1, n)
    x = x[: len(x) - n].copy()
    x[:n] = head * ramp + tail * (1 - ramp)
    return x


def reverb(x, room=0.25, wet=0.25):
    out = x.copy()
    for delay, gain in [(0.029, 0.5), (0.037, 0.45), (0.041, 0.4), (0.053, 0.35), (0.067, 0.3), (0.083, 0.25)]:
        d = int(delay * SR * (0.5 + room * 2))
        if d < len(x):
            out[d:] += x[:-d] * gain * wet
    return out


def save(name, x, peak=0.9, folder="sfx"):
    path = os.path.join(ROOT, folder, name + ".wav")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    x = norm(np.nan_to_num(x), peak)
    data = (np.clip(x, -1, 1) * 32767).astype(np.int16)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())


# ----------------------------------------------------------------- building blocks
def click(freq=3000, dur=0.03, bright=1.0):
    n = noise(dur) * env_ad(int(dur * SR), 0.0005, dur * 0.3, 6)
    body = tone(freq, dur) * env_ad(int(dur * SR), 0.0005, dur * 0.2, 8)
    return highpass_fast(n * bright + body * 0.5, 800)


def thud(freq=90, dur=0.35, noise_amt=0.6, cutoff=900):
    n = int(dur * SR)
    body = tone(lambda t: freq * (1 + 0.6 * np.exp(-t * 30)), dur) * env_ad(n, 0.002, dur * 0.5, 5)
    hit = lowpass_fast(noise(dur), cutoff) * env_ad(n, 0.001, 0.06, 5) * noise_amt
    return body + hit


def resonant_hit(freqs, dur=0.5, decay=0.25, noise_amt=0.3, hp=200):
    n = int(dur * SR)
    out = np.zeros(n)
    for i, f in enumerate(freqs):
        out += tone(f, dur) * env_ad(n, 0.001, decay / (1 + i * 0.5), 5) / (1 + i)
    out += highpass_fast(noise(dur), hp) * env_ad(n, 0.0005, 0.03, 5) * noise_amt
    return out


def rustle(dur=0.6, density=60, lo=1500, hi=7000):
    n = int(dur * SR)
    x = np.zeros(n)
    for _ in range(int(density * dur)):
        s = rng.uniform(0, dur - 0.03)
        ln = rng.uniform(0.005, 0.03)
        g = rng.uniform(0.2, 1.0)
        place(x, noise(ln) * env_ad(int(ln * SR), 0.001, ln * 0.6, 4) * g, s)
    return bandpass_fast(x, lo, hi) * env_ad(n, 0.02, dur * 0.7, 2)


# ----------------------------------------------------------------- SFX catalogue
def gen_sfx():
    # Footsteps -----------------------------------------------------------
    for i in range(4):
        f = rng.uniform(70, 110)
        x = mix(thud(f, 0.18, 0.5, 600), rustle(0.12, 80, 800, 3000) * 0.3)
        save(f"step_carpet_{i}", x, 0.5)
        x = mix(resonant_hit([rng.uniform(900, 1300), rng.uniform(2200, 2600)], 0.15, 0.04, 0.8, 1500), thud(f, 0.1, 0.3) * 0.5)
        save(f"step_tile_{i}", x, 0.6)
        # Director's leather shoes: sharper, heavier "CLAC" — recognisable on purpose
        x = mix(resonant_hit([rng.uniform(1600, 1900), rng.uniform(3200, 3600)], 0.2, 0.05, 1.2, 1200), thud(f * 0.8, 0.16, 0.4) * 0.9)
        save(f"step_boss_{i}", reverb(x, 0.3, 0.3), 0.8)
    # Keys jingling (director carries keys)
    x = np.zeros(int(0.5 * SR))
    for _ in range(9):
        place(x, resonant_hit([rng.uniform(3500, 6500), rng.uniform(7000, 9000)], 0.12, 0.05, 0.2, 3000), rng.uniform(0, 0.35))
    save("keys_jingle", x, 0.5)

    # Keyboard / mouse ----------------------------------------------------
    for i in range(3):
        save(f"key_{i}", click(rng.uniform(1800, 3500), 0.035), 0.5)
    typing = silence(2.5)
    tt = 0.0
    while tt < 2.4:
        place(typing, click(rng.uniform(1800, 3800), 0.035) * rng.uniform(0.4, 1.0), tt)
        tt += rng.uniform(0.06, 0.18) if rng.random() > 0.08 else rng.uniform(0.3, 0.5)
    save("typing_loop", typing, 0.5)
    save("mouse_click", click(4500, 0.02, 0.6) + click(3000, 0.02, 0.4), 0.5)

    # Printer --------------------------------------------------------------
    dur = 2.0
    t = t_axis(dur)
    motor = tone(lambda tt: 110 + 8 * np.sin(2 * np.pi * 3 * tt), dur, "saw") * 0.3
    roller = bandpass_fast(noise(dur), 400, 2500) * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 4 * t))) * 0.6
    head = bandpass_fast(noise(dur), 2000, 6000) * (np.sin(2 * np.pi * 18 * t) > 0.6) * 0.4
    save("printer_loop", loopify(lowpass_fast(motor, 1500) + roller + head, 0.2), 0.6)
    x = mix(resonant_hit([180, 420], 0.4, 0.15, 1.0, 100), place(silence(0.6), resonant_hit([90, 300], 0.3, 0.1, 0.8, 100), 0.15))
    x = mix(x, place(silence(1.0), bandpass_fast(noise(0.5), 300, 2000) * env_ad(int(0.5 * SR), 0.01, 0.3), 0.3))
    save("printer_jam", x, 0.8)
    save("paper_eject", mix(rustle(0.35, 120, 2000, 8000), thud(200, 0.1, 0.2) * 0.3), 0.6)

    # Doors -----------------------------------------------------------------
    def creak(dur, f0, f1):
        tt = t_axis(dur)
        f = f0 + (f1 - f0) * tt / dur + 30 * np.sin(2 * np.pi * 7 * tt)
        pulses = np.sin(2 * np.pi * np.cumsum(f) / SR) ** 15
        return bandpass_fast(pulses, 300, 3000) * env_ad(len(tt), 0.05, dur * 0.8, 2)
    save("door_open", mix(creak(0.7, 260, 180) * 0.5, click(1200, 0.05) * 0.5), 0.6)
    save("door_close", mix(thud(85, 0.4, 0.7, 800), place(silence(0.4), click(2000, 0.05) * 0.6, 0.02)), 0.7)
    save("door_slam", reverb(mix(thud(70, 0.7, 1.0, 1500), resonant_hit([140, 380, 900], 0.7, 0.3, 0.8, 200) * 0.6), 0.5, 0.4), 0.95)

    # Chairs -----------------------------------------------------------------
    dur = 1.5
    t = t_axis(dur)
    roll = lowpass_fast(noise(dur), 500) * (0.7 + 0.3 * np.sin(2 * np.pi * 11 * t)) + lowpass_fast(noise(dur), 2500) * 0.15
    save("chair_roll_loop", loopify(roll, 0.2), 0.5)
    tt = t_axis(0.4)
    sq = np.sin(2 * np.pi * np.cumsum(900 + 300 * np.sin(2 * np.pi * 3 * tt)) / SR) * env_ad(len(tt), 0.05, 0.3, 2)
    save("chair_squeak", bandpass_fast(sq, 500, 4000), 0.4)
    x = mix(thud(80, 0.6, 1.0, 1200), place(silence(0.8), resonant_hit([300, 700, 1500], 0.5, 0.15, 0.6), 0.08),
            place(silence(0.8), resonant_hit([350, 800], 0.4, 0.1, 0.5), 0.25))
    save("chair_fall", reverb(x, 0.4, 0.3), 0.9)

    # Impacts by material -----------------------------------------------
    save("hit_wood_light", resonant_hit([420, 950], 0.25, 0.08, 0.5), 0.5)
    save("hit_wood_heavy", mix(thud(95, 0.4, 0.8), resonant_hit([260, 610], 0.4, 0.15, 0.5)), 0.8)
    save("hit_metal", resonant_hit([680, 1710, 2930, 4100], 0.9, 0.5, 0.4, 500), 0.7)
    save("hit_plastic", resonant_hit([900, 2100], 0.18, 0.04, 0.8, 600), 0.5)
    save("hit_cardboard", mix(thud(110, 0.3, 0.9, 700), rustle(0.15, 60, 600, 2500) * 0.4), 0.7)
    save("hit_paper", rustle(0.3, 90, 1500, 7000), 0.4)
    save("hit_ceramic", resonant_hit([1900, 3400, 5200], 0.35, 0.12, 0.5, 1000), 0.6)
    x = np.zeros(int(0.9 * SR))
    for _ in range(25):
        place(x, resonant_hit([rng.uniform(2500, 7000), rng.uniform(5000, 9000)], 0.2, 0.05, 1.0, 2500) * rng.uniform(0.3, 1), rng.uniform(0, 0.5))
    save("break_ceramic", mix(x, resonant_hit([1500, 2900], 0.3, 0.05, 1.0, 800)), 0.9)
    save("mug_clink", resonant_hit([2600, 5400], 0.3, 0.12, 0.2, 1500), 0.4)
    save("body_fall", reverb(mix(thud(60, 0.6, 1.0, 900), rustle(0.3, 50, 500, 2000) * 0.5), 0.3, 0.2), 0.9)
    tt = t_axis(0.35)
    save("slip_whoosh", bandpass_fast(noise(0.35), 600, 4000) * np.sin(np.pi * tt / 0.35) ** 2
         + np.sin(2 * np.pi * np.cumsum(500 + 1500 * tt / 0.35) / SR) * 0.3 * np.sin(np.pi * tt / 0.35), 0.6)
    save("bump", thud(130, 0.2, 0.6, 700), 0.6)

    # Paper -----------------------------------------------------------------
    save("paper_rustle", rustle(0.6, 70), 0.4)
    save("papers_fall", reverb(mix(rustle(1.4, 160, 900, 7000), thud(140, 0.3, 0.3) * 0.4), 0.3, 0.2), 0.75)
    save("boxes_crash", reverb(mix(*[place(silence(1.6), thud(rng.uniform(80, 140), 0.4, 1.0, 900), rng.uniform(0, 0.9)) for _ in range(7)],
                                rustle(1.2, 60, 600, 3000) * 0.4), 0.5, 0.3), 0.95)
    save("stamp", mix(thud(150, 0.2, 1.0, 2000), click(1500, 0.03)), 0.7)
    save("stapler", mix(click(2500, 0.03), place(silence(0.12), resonant_hit([3000, 4500], 0.08, 0.02, 1.0, 1500), 0.03)), 0.6)
    tt = t_axis(0.5)
    mk = bandpass_fast(noise(0.5), 1500, 5000) * (0.5 + 0.5 * np.sin(2 * np.pi * 6 * tt)) * env_ad(len(tt), 0.02, 0.4, 1.5)
    save("marker_squeak", mk + np.sin(2 * np.pi * np.cumsum(1800 + 400 * np.sin(2 * np.pi * 6 * tt)) / SR) * 0.2 * env_ad(len(tt), 0.02, 0.4, 1.5), 0.5)

    # Phone -----------------------------------------------------------------
    ring = silence(3.0)
    for k in range(2):
        b = silence(1.0)
        tt = t_axis(1.0)
        burst = (tone(440, 1.0, "square") + tone(480, 1.0, "square")) * (np.sin(2 * np.pi * 20 * tt) > 0)
        place(ring, lowpass_fast(burst, 3000) * 0.5, k * 1.4)
    save("phone_ring", ring, 0.6)
    save("phone_pickup", mix(click(900, 0.05), thud(200, 0.15, 0.5)), 0.5)

    # Kitchen -----------------------------------------------------------------
    dur = 3.0
    t = t_axis(dur)
    grind = bandpass_fast(noise(dur), 200, 3000) * (0.6 + 0.4 * np.sin(2 * np.pi * 37 * t)) * np.clip(1.2 - t, 0, 1)
    pour = bandpass_fast(noise(dur), 600, 2500) * np.clip((t - 1.0) * 3, 0, 1) * np.clip((2.9 - t) * 3, 0, 1) * 0.6
    hum = tone(100, dur, "saw") * 0.15
    save("coffee_machine", mix(grind, pour, lowpass_fast(hum, 400)), 0.6)
    dur = 2.0
    save("microwave_loop", loopify(lowpass_fast(tone(120, dur, "saw") * 0.4 + noise(dur) * 0.05, 800), 0.2), 0.4)
    save("microwave_ding", resonant_hit([1760, 3520], 1.2, 0.8, 0.0), 0.6)
    save("fridge_open", mix(thud(120, 0.3, 0.4), bandpass_fast(noise(0.3), 300, 1500) * env_ad(int(0.3 * SR), 0.01, 0.2)), 0.5)
    x = silence(1.2)
    for k in range(4):
        tt = t_axis(0.15)
        place(x, np.sin(2 * np.pi * np.cumsum(300 + 400 * tt / 0.15) / SR) * env_ad(len(tt), 0.01, 0.1), 0.2 + k * 0.22)
    save("water_glug", lowpass_fast(x, 2000), 0.5)
    save("drink_slurp", bandpass_fast(noise(0.6), 400, 2500) * env_ad(int(0.6 * SR), 0.05, 0.5, 2) * (np.sin(2 * np.pi * 9 * t_axis(0.6)) > 0), 0.5)

    # Gadgets -------------------------------------------------------------------
    for i in range(3):
        dur = rng.uniform(0.7, 1.3)
        tt = t_axis(dur)
        f0 = rng.uniform(70, 110)
        f = f0 + 25 * np.sin(2 * np.pi * rng.uniform(15, 30) * tt) - 20 * tt / dur
        buzz = tone(lambda q: f[: len(q)], dur, "saw")
        buzz = lowpass_fast(buzz * (0.6 + 0.4 * np.abs(np.sin(2 * np.pi * rng.uniform(6, 12) * tt))), 1200)
        save(f"fart_{i}", buzz * env_ad(len(tt), 0.02, dur * 0.8, 1.5), 0.9)
    save("confetti_pop", mix(thud(150, 0.25, 1.0, 4000), place(silence(1.2), rustle(1.0, 200, 3000, 9000), 0.05),
                             place(silence(1.2), tone(lambda q: 600 + 2000 * q, 0.4, "square") * 0.2 * env_ad(int(0.4 * SR), 0.01, 0.3), 0.05)), 0.9)
    tt = t_axis(1.2)
    save("buzzer", tone(lambda q: 220 + 40 * np.sign(np.sin(2 * np.pi * 8 * q)), 1.2, "square") * env_ad(len(tt), 0.01, 1.1, 1), 0.8)
    tt = t_axis(0.35)
    save("duck_squeak", bandpass_fast(tone(lambda q: 900 + 700 * np.sin(np.pi * q / 0.35), 0.35, "saw"), 600, 4000) * env_ad(len(tt), 0.02, 0.3, 2), 0.6)
    save("cash_register", mix(resonant_hit([2093, 2637, 3136], 0.9, 0.6, 0.0), click(1200, 0.06) * 0.6,
                              place(silence(1.0), thud(300, 0.2, 0.6), 0.05)), 0.7)
    save("light_switch", mix(click(2200, 0.03), click(1400, 0.02)), 0.5)
    save("elevator_ding", mix(resonant_hit([1318], 1.5, 1.0, 0.0), place(silence(1.6), resonant_hit([1046], 1.2, 1.0, 0.0), 0.35)), 0.6)
    tt = t_axis(0.08)
    save("clock_tick", resonant_hit([3000, 4500], 0.08, 0.02, 0.5, 1500), 0.3)
    save("spray", bandpass_fast(noise(0.6), 3000, 9000) * env_ad(int(0.6 * SR), 0.02, 0.5, 1.5), 0.5)
    save("smell_waft", bandpass_fast(noise(1.0), 200, 900) * np.sin(np.pi * t_axis(1.0)) ** 2, 0.4)
    save("whistle", tone(lambda q: 1800 + 300 * np.sin(2 * np.pi * 30 * q), 0.6) * env_ad(int(0.6 * SR), 0.02, 0.5, 1.2), 0.5)

    # Farces & Attrapes ----------------------------------------------------------
    dur = 1.1
    tt = t_axis(dur)
    horn = mix(tone(lambda q: 440 + 6 * np.sin(2 * np.pi * 7 * q), dur, "saw"), tone(lambda q: 554 + 6 * np.sin(2 * np.pi * 7 * q), dur, "saw") * 0.8,
               tone(lambda q: 659, dur, "square") * 0.4)
    save("air_horn", lowpass_fast(horn, 4000) * np.clip(tt * 30, 0, 1) * np.clip((dur - tt) * 6, 0, 1), 0.95)
    tt = t_axis(0.35)
    save("squirt", bandpass_fast(noise(0.35), 1500, 7000) * env_ad(len(tt), 0.005, 0.25, 2) + tone(lambda q: 900 - 900 * q, 0.35) * 0.1, 0.6)
    save("splash", mix(rustle(0.5, 220, 2000, 9000), thud(200, 0.2, 0.3) * 0.3), 0.6)
    tt = t_axis(0.8)
    boing = np.sin(2 * np.pi * np.cumsum(180 + 220 * np.abs(np.sin(2 * np.pi * 9 * tt)) * np.exp(-tt * 3)) / SR) * env_ad(len(tt), 0.003, 0.7, 2)
    save("boing", mix(boing, click(800, 0.04)), 0.8)
    x = np.zeros(int(0.9 * SR))
    for k in range(10):
        place(x, bandpass_fast(noise(0.05), 2500, 8000) * env_ad(int(0.05 * SR), 0.002, 0.03), k * 0.08)
    save("scratch", x, 0.5)


    # UI ---------------------------------------------------------------------
    save("ui_click", resonant_hit([1200, 2400], 0.08, 0.03, 0.2, 800), 0.4)
    save("ui_hover", resonant_hit([1800], 0.05, 0.02, 0.0), 0.2)
    save("ui_confirm", mix(resonant_hit([880], 0.2, 0.1, 0.0), place(silence(0.3), resonant_hit([1320], 0.2, 0.1, 0.0), 0.08)), 0.5)
    save("ui_error", tone(180, 0.25, "square") * env_ad(int(0.25 * SR), 0.005, 0.2, 2), 0.4)
    save("notify", mix(resonant_hit([1568], 0.4, 0.2, 0.0), place(silence(0.5), resonant_hit([2093], 0.4, 0.2, 0.0), 0.1)), 0.45)
    jingle = silence(1.4)
    for k, f in enumerate([523, 659, 784, 1046]):
        place(jingle, resonant_hit([f, f * 2], 0.6, 0.35, 0.0) * (0.7 + 0.1 * k), k * 0.11)
    save("mission_complete", reverb(jingle, 0.4, 0.3), 0.7)
    sting = silence(1.2)
    for k, f in enumerate([392, 370, 349]):
        place(sting, lowpass_fast(tone(f, 0.35, "saw"), 1500) * env_ad(int(0.35 * SR), 0.01, 0.3), k * 0.25)
    save("warning_sting", reverb(sting, 0.4, 0.3), 0.7)
    tt = t_axis(0.5)
    save("alert_sting", reverb(mix(tone(lambda q: 700 + 600 * q / 0.5, 0.5, "square") * 0.3 * env_ad(len(tt), 0.005, 0.45, 1),
                                   resonant_hit([1400, 2100], 0.5, 0.3, 0.0)), 0.3, 0.3), 0.6)
    save("suspicion_up", tone(lambda q: 300 + 200 * q, 0.3, "tri") * env_ad(int(0.3 * SR), 0.01, 0.25, 2), 0.4)

    # Ambience loops -----------------------------------------------------------
    dur = 8.0
    t = t_axis(dur)
    vent = lowpass_fast(noise(dur), 350) * 0.8 + tone(60, dur) * 0.05 + lowpass_fast(noise(dur), 1200) * 0.1
    save("ambience_vent", loopify(vent, 0.5), 0.35)
    # Distant office murmur: band-limited noise bursts shaped like speech syllables
    murmur = np.zeros(int(dur * SR))
    for _ in range(140):
        ln = rng.uniform(0.08, 0.25)
        f = rng.uniform(120, 260)
        syl = tone(f, ln, "saw") * env_ad(int(ln * SR), 0.02, ln * 0.7, 2)
        place(murmur, syl * rng.uniform(0.2, 1.0), rng.uniform(0, dur - ln))
    murmur = bandpass_fast(murmur, 250, 1100)
    for _ in range(20):
        place(murmur, click(rng.uniform(1800, 3500), 0.035) * 0.15, rng.uniform(0, dur - 0.05))
    save("ambience_office", loopify(reverb(murmur, 0.6, 0.5), 0.5), 0.3)


# ----------------------------------------------------------------- music
NOTE = {n: 440 * 2 ** ((i - 9) / 12) for i, n in enumerate(["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"])}


def note_f(name, octave):
    return NOTE[name] * 2 ** (octave - 4)


def epiano(f, dur, vel=0.5):
    n = int(dur * SR)
    tt = t_axis(dur)
    mod = np.sin(2 * np.pi * f * 14 * tt) * np.exp(-tt * 6) * 1.5
    x = np.sin(2 * np.pi * f * tt + mod) * env_ad(n, 0.005, dur * 0.6, 3)
    x += np.sin(2 * np.pi * f * 2 * tt) * 0.15 * env_ad(n, 0.005, dur * 0.3, 4)
    return x * vel


def gen_music():
    # Elevator / break-room radio music: cheesy bossa-ish loop, 8 bars
    bpm = 100
    beat = 60 / bpm
    bars = 8
    total = bars * 4 * beat
    out = silence(total + 1.0)
    chords = [("C", ["E", "G", "B"]), ("A", ["C", "E", "G"]), ("D", ["F", "A", "C"]), ("G", ["B", "D", "F"])] * 2
    for b, (root, notes) in enumerate(chords):
        t0 = b * 4 * beat
        place(out, epiano(note_f(root, 2), beat * 1.8, 0.6), t0)
        place(out, epiano(note_f(root, 2) * 1.5, beat * 0.9, 0.4), t0 + 2.5 * beat)
        for k in [0.0, 1.5, 2.5, 3.5]:
            for nn in notes:
                place(out, epiano(note_f(nn, 4), beat * 0.9, 0.18), t0 + k * beat)
        for k in range(8):
            place(out, highpass_fast(noise(0.05), 6000) * env_ad(int(0.05 * SR), 0.001, 0.02) * 0.25, t0 + k * beat / 2)
    melody = ["E", "G", "A", "G", "E", "D", "C", "D", "E", "E", "D", "C", "A", "C", "D", "-"]
    for k, m in enumerate(melody * 2):
        if m != "-":
            place(out, epiano(note_f(m, 5), beat * 1.2, 0.3), k * beat)
    out = out[: int(total * SR)]
    save("radio_loop", reverb(out, 0.4, 0.25), 0.6, "music")

    # Menu music: light, playful, staccato
    bpm = 118
    beat = 60 / bpm
    total = 8 * 4 * beat
    out = silence(total + 1.0)
    prog = [("F", 3), ("D", 3), ("A#", 2), ("C", 3)] * 2
    for b, (root, octv) in enumerate(prog):
        t0 = b * 4 * beat
        for k in range(4):
            place(out, lowpass_fast(tone(note_f(root, octv), beat * 0.4, "tri"), 1500) * env_ad(int(beat * 0.4 * SR), 0.005, 0.15) * 0.5, t0 + k * beat)
            place(out, thud(60, 0.2, 0.3) * 0.4 if k % 2 == 0 else highpass_fast(noise(0.08), 3000) * env_ad(int(0.08 * SR), 0.001, 0.03) * 0.3, t0 + k * beat)
        arp = [0, 4, 7, 12, 7, 4, 0, 4]
        for k, semi in enumerate(arp):
            f = note_f(root, octv + 2) * 2 ** (semi / 12)
            place(out, tone(f, beat * 0.25, "square") * env_ad(int(beat * 0.25 * SR), 0.003, 0.08) * 0.08, t0 + k * beat / 2)
    out = out[: int(total * SR)]
    save("menu_loop", reverb(out, 0.3, 0.2), 0.55, "music")

    # Tension music for the day (very discreet so surveillance sounds stay readable)
    dur = 16.0
    t = t_axis(dur)
    pad = (tone(note_f("D", 2), dur, "saw") + tone(note_f("A", 2), dur, "saw") * 0.6 + tone(note_f("F", 3), dur, "saw") * 0.3)
    pad = lowpass_fast(pad, 500) * (0.6 + 0.4 * np.sin(2 * np.pi * t / dur * 2))
    pulse = silence(dur)
    for k in range(int(dur / 0.5)):
        place(pulse, thud(55, 0.3, 0.1) * 0.4, k * 0.5)
    pluck = silence(dur)
    for k, (n, o) in enumerate([("D", 4), ("F", 4), ("A", 4), ("G", 4), ("F", 4), ("E", 4), ("D", 4), ("A", 3)] * 2):
        place(pluck, epiano(note_f(n, o), 0.8, 0.15), k * 1.0)
    save("day_loop", loopify(pad * 0.5 + pulse + pluck, 0.5), 0.45, "music")

    # SuperEssence Studio jingle
    j = silence(3.0)
    for k, (n, o) in enumerate([("C", 5), ("E", 5), ("G", 5), ("C", 6)]):
        place(j, epiano(note_f(n, o), 1.6, 0.5), 0.15 + k * 0.12)
    place(j, epiano(note_f("C", 3), 2.4, 0.6), 0.6)
    place(j, epiano(note_f("G", 3), 2.4, 0.4), 0.6)
    place(j, epiano(note_f("E", 4), 2.4, 0.3), 0.6)
    place(j, rustle(0.8, 200, 4000, 10000) * 0.15, 0.55)
    save("studio_jingle", reverb(j, 0.6, 0.4), 0.8, "music")


# ----------------------------------------------------------------- gibberish voices
CONS = ["b", "p", "m", "f", "v", "t", "d", "n", "l", "k", "g", "z", "ch", "j", "r", "bl", "gr", "pl", "fr", "kr", "sn", "w"]
VOW = ["a", "o", "ou", "i", "é", "eu", "u", "on", "an", "oi"]
FUNNY = ["blorp", "mouik", "pataplouf", "gnagna", "brouzouf", "zoubida", "flonflon", "patati", "bidule", "chouchou",
         "badaboum", "tchoupi", "glouglou", "pouet", "zigouigoui", "frouf", "blabla", "mimimi", "toutouyoutou", "kss kss"]

EMOTIONS = {
    # name: (syllable count range, punctuation, sox effects, extra words)
    "neutral": ((2, 4), ".", [], []),
    "happy": ((2, 4), " !", ["tempo", "1.1"], ["youpi", "ouiii"]),
    "laugh": ((0, 0), "", ["tempo", "1.15"], []),
    "angry": ((2, 4), " !!", ["overdrive", "6", "tempo", "1.15", "gain", "-4"], ["grmbl", "rhaaa"]),
    "panic": ((3, 5), " !", ["tempo", "1.45", "tremolo", "9", "40"], ["aaah", "ouh la la"]),
    "surprised": ((1, 3), " ?!", ["tempo", "0.95"], ["hein", "ouah", "quoi"]),
    "suspicious": ((2, 4), " ?", ["tempo", "0.8"], ["hmmmm", "mmh mmh"]),
    "embarrassed": ((1, 3), "...", ["tempo", "0.9", "gain", "-6"], ["euh", "hihi"]),
}

# Each character voice: espeak base voice + variant, base pitch, speed, sox pitch (cents)
VOICES = {
    "boss":    ("fr", "m3", 30, 140, -350, ["reverb", "20"]),
    "marcel":  ("fr", "m1", 45, 165, -150, []),
    "lucie":   ("fr", "f2", 65, 175, 250, []),
    "gerard":  ("fr", "m7", 35, 150, -250, []),
    "sophie":  ("it", "f4", 60, 185, 300, []),
    "kevin":   ("fr", "m4", 55, 200, 150, []),
    "nadia":   ("fr", "f1", 55, 165, 150, []),
    "bernard": ("fi", "m2", 40, 145, -100, []),
    "chloe":   ("fr", "f5", 75, 190, 400, []),
    "player":  ("fr", "m6", 50, 175, 50, []),
}


def gibberish_text(emotion):
    (lo, hi), punct, _, extras = EMOTIONS[emotion]
    if emotion == "laugh":
        base = random.choice(["ha", "hi", "ho", "hé"])
        return " ".join([base + random.choice(["", "h"]) for _ in range(random.randint(4, 7))]) + " !"
    words = []
    for _ in range(random.randint(lo, hi)):
        if random.random() < 0.25:
            words.append(random.choice(FUNNY))
        else:
            words.append("".join(random.choice(CONS) + random.choice(VOW) for _ in range(random.randint(1, 2))))
    if extras and random.random() < 0.7:
        words.insert(random.randint(0, len(words)), random.choice(extras))
    return " ".join(words) + punct


def gen_voices():
    out_dir = os.path.join(ROOT, "voices")
    os.makedirs(out_dir, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        for vname, (lang, variant, pitch, speed, cents, extra_fx) in VOICES.items():
            for emo, (_, _, fx, _) in EMOTIONS.items():
                for take in range(3):
                    text = gibberish_text(emo)
                    raw = os.path.join(tmp, "raw.wav")
                    p = pitch + {"panic": 25, "surprised": 20, "happy": 10, "angry": -5, "laugh": 15}.get(emo, 0)
                    subprocess.run(["espeak-ng", "-v", f"{lang}+{variant}", "-p", str(max(0, min(99, p))), "-s", str(speed),
                                    "-a", "160", "-w", raw, text], check=True, capture_output=True)
                    dst = os.path.join(out_dir, f"{vname}_{emo}_{take}.wav")
                    cmd = ["sox", raw, "-r", str(SR), "-c", "1", "-b", "16", dst, "pitch", str(cents)] + fx + extra_fx + ["silence", "1", "0.02", "0.5%", "reverse", "silence", "1", "0.02", "0.5%", "reverse", "norm", "-1"]
                    subprocess.run(cmd, check=True, capture_output=True)


if __name__ == "__main__":
    gen_sfx()
    gen_music()
    gen_voices()
    n = sum(len(f) for _, _, f in os.walk(ROOT))
    print(f"generated {n} audio files in {os.path.abspath(ROOT)}")
