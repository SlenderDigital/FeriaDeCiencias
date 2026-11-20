#!/usr/bin/env python3
"""Procedural JSAB-style 128 BPM / 120.000s boss soundtrack generator.

Generates `juego/assets/audio/boss_music.wav` at 22050 Hz, 16-bit signed PCM
mono, exactly 2,646,000 frames (64 bars, 256 beats, 8 phases x 15.0s).
Uses only Python stdlib + NumPy (no scipy).
"""

from __future__ import annotations

import argparse
import math
import os
import wave
from pathlib import Path

import numpy as np

SR: int = 22050
BPM: float = 128.0
BEAT_DUR: float = 60.0 / BPM  # 0.46875s
INTRO_FRAMES: int = int(round(4.0 * BEAT_DUR * SR))  # 41,344 frames (1.875s)
TOTAL_BEATS: int = 256
TOTAL_BARS: int = 64
TOTAL_DURATION: float = 120.0
TOTAL_FRAMES: int = 2_646_000  # 120.000 * 22050 exact

SILENCE_START_BEAT: int = 156
SILENCE_END_BEAT: int = 158
SHATTER_BEAT: int = 252
TAIL_SILENCE_TIME: float = 119.95

RNG = np.random.default_rng(420128)


def beat_to_sample(beat: float) -> int:
    """Convert global beat index (float) to exact sample index."""
    return int(round(beat * BEAT_DUR * SR))


def midi_to_hz(midi: float) -> float:
    """Convert MIDI note number to frequency in Hz."""
    return 440.0 * (2.0 ** ((midi - 69.0) / 12.0))


def add_clip(buf: np.ndarray, start_idx: int, clip: np.ndarray) -> None:
    """Mix clip into buf at start_idx with boundary clamping."""
    if clip.size == 0:
        return
    end_idx = start_idx + clip.size
    if end_idx <= 0 or start_idx >= buf.size:
        return
    src_start = max(0, -start_idx)
    dst_start = max(0, start_idx)
    length = min(clip.size - src_start, buf.size - dst_start)
    if length > 0:
        buf[dst_start : dst_start + length] += clip[src_start : src_start + length]


def env_fade(sig: np.ndarray, attack_s: float = 0.003, release_s: float = 0.005) -> np.ndarray:
    """Apply smooth raised-cosine attack/release fades to prevent clicks."""
    n = sig.size
    if n == 0:
        return sig
    out = sig.copy()
    att = min(int(round(attack_s * SR)), n // 2)
    rel = min(int(round(release_s * SR)), n // 2)
    if att > 1:
        u = np.linspace(0.0, np.pi, att, endpoint=False)
        out[:att] *= 0.5 * (1.0 - np.cos(u))
    if rel > 1:
        u = np.linspace(0.0, np.pi, rel, endpoint=False)
        out[-rel:] *= 0.5 * (1.0 + np.cos(u))
    return out


def fft_bandpass(sig: np.ndarray, low_hz: float, high_hz: float) -> np.ndarray:
    """Zero-phase FFT bandpass filter using pure NumPy."""
    if sig.size < 8:
        return sig
    freqs = np.fft.rfftfreq(sig.size, d=1.0 / SR)
    spec = np.fft.rfft(sig)
    lo = np.ones_like(freqs)
    if low_hz > 0.0:
        lo = 1.0 / np.sqrt(1.0 + (low_hz / np.maximum(freqs, 1.0)) ** 4)
        lo[0] = 0.0
    hi = 1.0 / np.sqrt(1.0 + (freqs / max(high_hz, 20.0)) ** 4)
    return np.fft.irfft(spec * lo * hi, n=sig.size)


def fft_lowpass(sig: np.ndarray, cutoff_hz: float) -> np.ndarray:
    """Zero-phase FFT lowpass filter using pure NumPy."""
    return fft_bandpass(sig, 0.0, cutoff_hz)


def bandlimited_osc(
    freq_arr: np.ndarray | float,
    n_samples: int,
    waveform: str = "saw",
    cutoff: np.ndarray | float = 6000.0,
    resonance: float = 0.0,
    phase0: float = 0.0,
    pulse_width: float = 0.25,
) -> np.ndarray:
    """Synthesize alias-free bandlimited oscillator with smooth resonant lowpass."""
    if n_samples <= 0:
        return np.zeros(0, dtype=np.float64)
    if np.ndim(freq_arr) == 0:
        f_arr = np.full(n_samples, float(freq_arr), dtype=np.float64)
    else:
        f_arr = np.asarray(freq_arr, dtype=np.float64)
    if np.ndim(cutoff) == 0:
        c_arr = np.full(n_samples, float(cutoff), dtype=np.float64)
    else:
        c_arr = np.asarray(cutoff, dtype=np.float64)

    c_arr = np.clip(c_arr, 40.0, 0.45 * SR)
    dphi = 2.0 * np.pi * f_arr / SR
    phase = phase0 + np.cumsum(dphi)

    max_f = max(float(np.min(f_arr)), 20.0)
    max_h = min(28, int(0.43 * SR / max_f))
    nyq_limit = 0.45 * SR

    out = np.zeros(n_samples, dtype=np.float64)
    for h in range(1, max_h + 1):
        if waveform in ("square", "tri") and (h % 2 == 0):
            continue
        hf = f_arr * h
        # Smooth Nyquist rolloff prevents aliasing when pitch bends up/down
        nyq_mask = np.clip((nyq_limit - hf) / (0.04 * SR), 0.0, 1.0)
        if np.max(nyq_mask) <= 0.0:
            break

        ratio = hf / c_arr
        lp = 1.0 / np.sqrt(1.0 + ratio ** 4)
        if resonance > 0.0:
            lp = lp + resonance * np.exp(-((ratio - 1.0) / 0.28) ** 2)

        if waveform == "saw":
            amp = ((-1.0) ** (h + 1)) / float(h)
            out += (amp * lp * nyq_mask) * np.sin(h * phase)
        elif waveform == "square":
            amp = 1.0 / float(h)
            out += (amp * lp * nyq_mask) * np.sin(h * phase)
        elif waveform == "pulse":
            amp = math.sin(h * math.pi * pulse_width) / float(h)
            out += (amp * lp * nyq_mask) * np.cos(h * phase)
        elif waveform == "tri":
            amp = ((-1.0) ** ((h - 1) // 2)) / float(h * h)
            out += (amp * lp * nyq_mask) * np.sin(h * phase)

    if waveform == "saw":
        out *= 0.62
    elif waveform == "square":
        out *= 0.72
    elif waveform == "pulse":
        out *= 0.85
    elif waveform == "tri":
        out *= 0.85
    return out


# ---------------------------------------------------------------------------
# Drum & Percussion Synthesis
# ---------------------------------------------------------------------------

def make_kick(
    dur: float = 0.28,
    start_hz: float = 155.0,
    end_hz: float = 44.0,
    pitch_tau: float = 0.026,
    decay: float = 10.5,
    drive: float = 1.85,
    click_amt: float = 0.24,
) -> np.ndarray:
    n = int(round(dur * SR))
    t = np.arange(n, dtype=np.float64) / SR
    freq = end_hz + (start_hz - end_hz) * np.exp(-t / pitch_tau)
    phase = np.cumsum(2.0 * np.pi * freq / SR)
    body = np.sin(phase) + 0.16 * np.sin(2.0 * phase)
    amp = np.exp(-t * decay)
    sig = np.tanh(body * drive) / math.tanh(drive) * amp

    # Punchy click transient
    click_n = min(n, int(0.014 * SR))
    if click_n > 4:
        ct = np.arange(click_n, dtype=np.float64) / SR
        noise = RNG.standard_normal(click_n)
        click_sig = (0.65 * np.sin(2.0 * np.pi * 1650.0 * ct) + 0.35 * noise) * np.exp(-ct * 320.0)
        sig[:click_n] += click_amt * click_sig

    return env_fade(sig, attack_s=0.001, release_s=0.012)


def make_stomp_kick() -> np.ndarray:
    """Heavy Phase 7 industrial half-time stomp."""
    sub = make_kick(
        dur=0.44,
        start_hz=140.0,
        end_hz=35.0,
        pitch_tau=0.036,
        decay=6.2,
        drive=2.6,
        click_amt=0.35,
    )
    n = sub.size
    t = np.arange(n, dtype=np.float64) / SR
    grit = fft_bandpass(RNG.standard_normal(n), 280.0, 2600.0) * np.exp(-t * 24.0)
    return env_fade(0.88 * sub + 0.28 * np.tanh(grit * 2.4), 0.001, 0.018)


def make_supernova_boom() -> np.ndarray:
    """Gigantic beat 158 supernova drop."""
    dur = BEAT_DUR * 1.95
    n = int(round(dur * SR))
    t = np.arange(n, dtype=np.float64) / SR
    freq = 32.0 + 185.0 * np.exp(-t / 0.042)
    phase = np.cumsum(2.0 * np.pi * freq / SR)
    sub = np.tanh(np.sin(phase) * 2.8) * np.exp(-t * 3.4)
    burst = fft_bandpass(RNG.standard_normal(n), 180.0, 7500.0) * np.exp(-t * 6.5)
    dist_saw = bandlimited_osc(64.0, n, "saw", cutoff=np.linspace(5500.0, 700.0, n), resonance=0.3)
    dist_saw = np.tanh(dist_saw * 2.8) * np.exp(-t * 5.0)
    mix = 0.72 * sub + 0.42 * np.tanh(burst * 2.2) + 0.34 * dist_saw
    return env_fade(mix, 0.001, 0.035)


def make_snap() -> np.ndarray:
    """Crisp cocky finger-snap / rimshot for Bar 0 countdown."""
    n = int(round(0.085 * SR))
    t = np.arange(n, dtype=np.float64) / SR
    f = 460.0 + 780.0 * np.exp(-t / 0.007)
    ph = np.cumsum(2.0 * np.pi * f / SR)
    wood = np.sin(ph) * np.exp(-t * 68.0)
    pop = fft_bandpass(RNG.standard_normal(n), 1600.0, 5600.0) * np.exp(-t * 72.0)
    sig = 0.58 * wood + 0.65 * pop
    return env_fade(sig, 0.0008, 0.008)


def make_clap() -> np.ndarray:
    """Layered crisp electro handclap."""
    n = int(round(0.18 * SR))
    t = np.arange(n, dtype=np.float64) / SR
    noise = fft_bandpass(RNG.standard_normal(n), 950.0, 5800.0)
    env = np.zeros(n, dtype=np.float64)
    for delay_ms in (0.0, 9.5, 19.0):
        idx = int(round((delay_ms / 1000.0) * SR))
        if idx < n:
            dt = np.arange(n - idx, dtype=np.float64) / SR
            env[idx:] += np.exp(-dt * 95.0)
    env += 0.55 * np.exp(-t * 22.0)
    body = np.sin(2.0 * np.pi * 185.0 * t) * np.exp(-t * 48.0)
    return env_fade(0.45 * noise * env + 0.25 * body, 0.001, 0.015)


def make_snare(tight: bool = False, metallic: bool = False) -> np.ndarray:
    dur = 0.14 if tight else (0.34 if metallic else 0.21)
    n = int(round(dur * SR))
    t = np.arange(n, dtype=np.float64) / SR
    f = 115.0 + 110.0 * np.exp(-t / 0.016)
    ph = np.cumsum(2.0 * np.pi * f / SR)
    body = np.sin(ph) * np.exp(-t * (26.0 if tight else 17.0))
    noise = fft_bandpass(RNG.standard_normal(n), 1100.0, 8800.0)
    noise_env = np.exp(-t * (22.0 if tight else (7.5 if metallic else 13.5)))
    sig = 0.58 * body + 0.62 * noise * noise_env
    if metallic:
        ring = np.zeros(n, dtype=np.float64)
        for ratio in (1.0, 1.47, 2.09, 2.86):
            ring += np.sin(2.0 * np.pi * (365.0 * ratio) * t)
        sig += 0.24 * ring * np.exp(-t * 11.0)
        sig = np.tanh(sig * 1.45)
    return env_fade(sig, 0.001, 0.014)


def make_hat(open_hat: bool = False) -> np.ndarray:
    dur = 0.18 if open_hat else 0.048
    n = int(round(dur * SR))
    t = np.arange(n, dtype=np.float64) / SR
    raw_noise = RNG.standard_normal(n)
    hp = fft_bandpass(raw_noise, 4800.0, 9800.0)
    metal = np.zeros(n, dtype=np.float64)
    for freq in (312.0, 468.0, 691.0, 935.0, 1320.0):
        metal += bandlimited_osc(freq, n, "square", cutoff=9500.0)
    decay = 16.0 if open_hat else 68.0
    sig = (0.72 * hp + 0.18 * metal) * np.exp(-t * decay)
    return env_fade(sig, 0.0008, 0.006)


def make_crash(dur: float = 1.45) -> np.ndarray:
    n = int(round(dur * SR))
    t = np.arange(n, dtype=np.float64) / SR
    noise = fft_bandpass(RNG.standard_normal(n), 2400.0, 9600.0)
    shimmer = np.zeros(n, dtype=np.float64)
    for freq in (523.0, 741.0, 1088.0, 1490.0):
        shimmer += np.sin(2.0 * np.pi * freq * t)
    sig = (0.85 * noise + 0.12 * shimmer) * np.exp(-t * 3.0)
    return env_fade(sig, 0.002, 0.04)


def make_reverse_crash(dur: float = BEAT_DUR) -> np.ndarray:
    n = int(round(dur * SR))
    t = np.arange(n, dtype=np.float64) / SR
    noise = fft_bandpass(RNG.standard_normal(n), 1800.0, 9500.0)
    rise = np.exp((t - dur) * 7.2)
    sweep_f = np.linspace(440.0, 2600.0, n)
    shimmer = bandlimited_osc(sweep_f, n, "saw", cutoff=8000.0) * 0.25
    sig = (0.82 * noise + shimmer) * rise
    return env_fade(sig, 0.015, 0.004)


def make_tom(base_hz: float = 140.0) -> np.ndarray:
    dur = 0.22
    n = int(round(dur * SR))
    t = np.arange(n, dtype=np.float64) / SR
    f = base_hz + (base_hz * 0.9) * np.exp(-t / 0.025)
    ph = np.cumsum(2.0 * np.pi * f / SR)
    sig = np.tanh(np.sin(ph) * 1.5) * np.exp(-t * 11.5)
    return env_fade(sig, 0.001, 0.012)


# ---------------------------------------------------------------------------
# Bass, Lead, Arp, Stab, Music Box & FX Synthesis
# ---------------------------------------------------------------------------

def make_bass_note(
    midi: float,
    dur: float,
    cutoff_hi: float = 2400.0,
    cutoff_lo: float = 360.0,
    drive: float = 2.1,
    sub_mix: float = 0.65,
    waveform: str = "saw",
    sidechain: bool = False,
) -> np.ndarray:
    n = max(16, int(round(dur * SR)))
    t = np.arange(n, dtype=np.float64) / SR
    f0 = midi_to_hz(midi)
    cutoff = cutoff_lo + (cutoff_hi - cutoff_lo) * np.exp(-t * 11.0)
    osc = bandlimited_osc(f0, n, waveform=waveform, cutoff=cutoff, resonance=0.35)
    sub = np.sin(2.0 * np.pi * f0 * t)
    raw = osc + sub_mix * sub
    sat = np.tanh(raw * drive) / math.tanh(drive)
    if sidechain:
        sc = 1.0 - 0.72 * np.exp(-t / 0.045)
        sat *= sc
    return env_fade(sat, attack_s=0.003, release_s=min(0.018, dur * 0.15))


def make_lead_note(
    midi: float,
    dur: float,
    detune_cents: float = 10.0,
    waveform: str = "saw",
    cutoff: float = 4800.0,
    vib_hz: float = 5.5,
    vib_cents: float = 9.0,
    octave_up: float = 0.0,
) -> np.ndarray:
    n = max(16, int(round(dur * SR)))
    t = np.arange(n, dtype=np.float64) / SR
    f0 = midi_to_hz(midi)
    vib_mod = 2.0 ** ((vib_cents * np.sin(2.0 * np.pi * vib_hz * t) * np.clip(t / 0.12, 0.0, 1.0)) / 1200.0)
    d1 = 2.0 ** (-detune_cents / 1200.0)
    d2 = 2.0 ** (detune_cents / 1200.0)
    c_env = cutoff * (0.45 + 0.55 * np.exp(-t * 6.0))
    o1 = bandlimited_osc(f0 * d1 * vib_mod, n, waveform=waveform, cutoff=c_env, resonance=0.2, phase0=0.0)
    o2 = bandlimited_osc(f0 * d2 * vib_mod, n, waveform=waveform, cutoff=c_env, resonance=0.2, phase0=1.7)
    mix = 0.52 * (o1 + o2)
    if octave_up > 0.0:
        o3 = bandlimited_osc(f0 * 2.0 * vib_mod, n, waveform="square", cutoff=min(cutoff * 1.2, 8500.0), phase0=0.7)
        mix += octave_up * o3
    amp = 1.0 - 0.25 * (1.0 - np.exp(-t * 4.5))
    return env_fade(mix * amp, attack_s=0.005, release_s=min(0.025, dur * 0.2))


def make_arp_note(midi: float, dur: float, brightness: float = 3800.0, waveform: str = "pulse") -> np.ndarray:
    n = max(16, int(round(dur * SR)))
    t = np.arange(n, dtype=np.float64) / SR
    f0 = midi_to_hz(midi)
    c_env = 700.0 + (brightness - 700.0) * np.exp(-t * 16.0)
    osc = bandlimited_osc(f0, n, waveform=waveform, cutoff=c_env, resonance=0.25)
    amp = np.exp(-t * 7.5)
    return env_fade(osc * amp, attack_s=0.002, release_s=0.008)


def make_stab(midis: list[float], dur: float = 0.24, cutoff: float = 4200.0) -> np.ndarray:
    n = max(16, int(round(dur * SR)))
    t = np.arange(n, dtype=np.float64) / SR
    c_env = 500.0 + (cutoff - 500.0) * np.exp(-t * 14.0)
    mix = np.zeros(n, dtype=np.float64)
    for i, m in enumerate(midis):
        f0 = midi_to_hz(m)
        mix += bandlimited_osc(f0 * 0.996, n, "saw", cutoff=c_env, phase0=0.3 * i)
        mix += bandlimited_osc(f0 * 1.004, n, "saw", cutoff=c_env, phase0=0.9 * i)
    mix /= max(1.0, len(midis) * 1.4)
    mix = np.tanh(mix * 1.7) * np.exp(-t * 9.5)
    return env_fade(mix, attack_s=0.002, release_s=0.015)


def make_music_box(midi: float, dur: float = 0.65) -> np.ndarray:
    n = max(16, int(round(dur * SR)))
    t = np.arange(n, dtype=np.float64) / SR
    f0 = midi_to_hz(midi)
    sig = (
        0.78 * np.sin(2.0 * np.pi * f0 * t)
        + 0.16 * np.sin(2.0 * np.pi * (f0 * 2.0) * t) * np.exp(-t * 10.0)
        + 0.08 * np.sin(2.0 * np.pi * (f0 * 3.0) * t) * np.exp(-t * 18.0)
    )
    sig *= np.exp(-t * 5.2)
    return env_fade(sig, attack_s=0.002, release_s=0.025)


def apply_bitcrush(sig: np.ndarray, hold: int = 5, levels: float = 14.0) -> np.ndarray:
    """Sample-rate decimation + bit quantization for glitch tears."""
    if sig.size == 0:
        return sig
    hold = max(1, hold)
    idx = (np.arange(sig.size) // hold) * hold
    decimated = sig[idx]
    quantized = np.round(decimated * levels) / levels
    return quantized


def make_noise_riser(dur: float, f_lo: float = 350.0, f_hi: float = 6800.0, pitch_sweep: bool = True) -> np.ndarray:
    n = max(16, int(round(dur * SR)))
    t = np.arange(n, dtype=np.float64) / SR
    u = t / dur
    noise = fft_bandpass(RNG.standard_normal(n), f_lo, f_hi)
    # Time-varying harmonic sweep
    sweep = np.zeros(n, dtype=np.float64)
    if pitch_sweep:
        f_arr = f_lo * ((f_hi / f_lo) ** (u ** 1.25))
        sweep = 0.35 * bandlimited_osc(f_arr * 0.25, n, "saw", cutoff=np.clip(f_arr * 1.5, 300.0, 9000.0))
    env = (u ** 1.8) * 0.85
    return env_fade((0.7 * noise + sweep) * env, attack_s=0.02, release_s=0.008)


# ---------------------------------------------------------------------------
# Composition Helpers
# ---------------------------------------------------------------------------

def render_drums_standard_4x4(
    drums: np.ndarray,
    bar_start: int,
    bar_count: int,
    kick_clip: np.ndarray,
    clap_or_snare: np.ndarray,
    hat_closed: np.ndarray,
    hat_open: np.ndarray,
    hat_16ths: bool = False,
    hat_gain: float = 0.28,
    backbeat_gain: float = 0.58,
) -> None:
    for b in range(bar_count):
        g_bar = bar_start + b * 4
        for q in range(4):
            beat = g_bar + q
            add_clip(drums, beat_to_sample(beat), kick_clip)
            if q in (1, 3):
                add_clip(drums, beat_to_sample(beat), clap_or_snare * backbeat_gain)
            if hat_16ths:
                for sub in range(4):
                    if sub == 0:
                        continue
                    g = hat_gain * (1.0 if sub == 2 else 0.58)
                    clip = hat_open if (sub == 2 and q == 3) else hat_closed
                    add_clip(drums, beat_to_sample(beat + sub * 0.25), clip * g)
            else:
                add_clip(drums, beat_to_sample(beat + 0.5), hat_open * hat_gain)


# ---------------------------------------------------------------------------
# Main Composition (8 Phases, 64 Bars, 256 Beats, 120.000s)
# ---------------------------------------------------------------------------

def generate_boss_track() -> tuple[np.ndarray, dict[str, float]]:
    drums = np.zeros(TOTAL_FRAMES, dtype=np.float64)
    bass = np.zeros(TOTAL_FRAMES, dtype=np.float64)
    synths = np.zeros(TOTAL_FRAMES, dtype=np.float64)
    fx = np.zeros(TOTAL_FRAMES, dtype=np.float64)

    # Pre-rendered percussion kit
    kick_electro = make_kick(dur=0.25, start_hz=150.0, end_hz=46.0, decay=11.0, drive=1.8, click_amt=0.24)
    kick_heavy = make_kick(dur=0.31, start_hz=165.0, end_hz=40.0, decay=8.8, drive=2.25, click_amt=0.30)
    kick_stomp = make_stomp_kick()
    snap = make_snap()
    clap = make_clap()
    snare = make_snare(tight=False, metallic=False)
    snare_tight = make_snare(tight=True, metallic=False)
    snare_metal = make_snare(tight=False, metallic=True)
    hat_c = make_hat(open_hat=False)
    hat_o = make_hat(open_hat=True)
    crash = make_crash(1.45)

    # D minor harmonic palette
    # Root D2=38, F2=41, G2=43, A2=45, Bb2=46, C3=48, C#3=49, D3=50
    ARP_MAIN = [62, 65, 69, 72, 74, 69, 65, 69]  # D4 F4 A4 C5 D5 A4 F4 A4
    ARP_ALT = [62, 67, 70, 74, 70, 67, 65, 64]   # D4 G4 Bb4 D5 Bb4 G4 F4 E4
    ARP_HARM = [62, 65, 69, 73, 74, 73, 69, 65]  # D4 F4 A4 C#5 D5 C#5 A4 F4

    # =========================================================================
    # PHASE 1 (0-15s, Bars 0-7, beats 0-31): "Cocky Conductor"
    # =========================================================================
    # Bar 0 (beats 0-3): crisp 4-beat finger-snap/rimshot countdown + light muted pulse (RMS ~0.09-0.12)
    for b in range(4):
        s_idx = beat_to_sample(b)
        add_clip(drums, s_idx, snap * 0.78)
        # Light muted sub pulse under each count
        pulse = make_bass_note(38, BEAT_DUR * 0.58, cutoff_hi=250.0, cutoff_lo=120.0, drive=1.15, sub_mix=0.92)
        add_clip(bass, s_idx, pulse * 0.30)
        if b >= 2:
            add_clip(drums, beat_to_sample(b + 0.5), hat_c * 0.18)

    # Bars 1-7 (beats 4-31): groovy 128 BPM bassline + bright arpeggio + claps on beats 2 & 4
    p1_bass_prog = [38, 38, 41, 43, 38, 38, 46, 45]  # D2, F2, G2, D2, Bb2, A2
    for bar in range(1, 8):
        g_beat = bar * 4
        root = p1_bass_prog[(bar - 1) % len(p1_bass_prog)]
        # Groovy 8th-note syncopated bassline
        pattern = [
            (0.0, 0.45, root, 0.78),
            (0.5, 0.35, root + 12, 0.48),
            (0.75, 0.45, root, 0.66),
            (1.5, 0.45, root, 0.74),
            (2.0, 0.45, root, 0.78),
            (2.5, 0.35, root + 7, 0.52),
            (3.0, 0.45, root, 0.72),
            (3.5, 0.40, root + 10 if bar % 2 == 0 else root + 12, 0.58),
        ]
        for off, dur_b, note, gain in pattern:
            b_clip = make_bass_note(
                note,
                dur_b * BEAT_DUR,
                cutoff_hi=1700.0 if bar < 7 else 2400.0,
                cutoff_lo=320.0,
                drive=1.8,
                sidechain=(off == 0.0),
            )
            add_clip(bass, beat_to_sample(g_beat + off), b_clip * gain * 0.48)

        # Bright 16th-note arpeggio
        arp_seq = ARP_MAIN if bar % 2 == 1 else ARP_ALT
        for step in range(16):
            note = arp_seq[step % len(arp_seq)]
            bright = 2800.0 + (step % 4) * 450.0
            a_clip = make_arp_note(note, BEAT_DUR * 0.23, brightness=bright, waveform="pulse")
            add_clip(synths, beat_to_sample(g_beat + step * 0.25), a_clip * 0.26)

        # Drums: 4-on-floor kicks + crisp claps on beats 2 & 4 (q in 1,3)
        if bar < 7:
            render_drums_standard_4x4(
                drums, g_beat, 1, kick_electro * 0.74, clap, hat_c, hat_o,
                hat_16ths=(bar >= 4), hat_gain=0.22, backbeat_gain=0.58,
            )
        else:
            # Bar 7 (beats 28-31): filter sweep + snare fill
            for q in range(4):
                add_clip(drums, beat_to_sample(g_beat + q), kick_electro * 0.74)
            add_clip(fx, beat_to_sample(g_beat), make_noise_riser(4.0 * BEAT_DUR, 500.0, 5800.0) * 0.35)
            for idx_8 in range(8):
                vel = 0.25 + 0.09 * idx_8
                add_clip(drums, beat_to_sample(g_beat + idx_8 * 0.5), snare_tight * vel)

    # =========================================================================
    # PHASE 2 (15-30s, Bars 8-15, beats 32-63): "Frozen Double-Take"
    # =========================================================================
    # Bar 8 (beats 32-35, 15.00-16.875s): dramatic record-stop dropout!
    # Beats 32-33: tape-stop dive (~0.14s) into quiet eerie low hum (RMS < 0.06)
    n_dive = int(round(0.14 * SR))
    t_dive = np.arange(n_dive, dtype=np.float64) / SR
    f_dive = 146.8 * np.exp(-t_dive * 14.0)
    tape_stop = bandlimited_osc(f_dive, n_dive, "saw", cutoff=np.linspace(1400.0, 140.0, n_dive))
    tape_stop *= np.linspace(0.24, 0.03, n_dive)
    add_clip(fx, beat_to_sample(32), env_fade(tape_stop, 0.002, 0.015))

    # Quiet eerie low hum across beats 32-33
    n_hum = beat_to_sample(34) - beat_to_sample(32)
    t_hum = np.arange(n_hum, dtype=np.float64) / SR
    hum = (
        0.065 * np.sin(2.0 * np.pi * 73.42 * t_hum)
        + 0.030 * np.sin(2.0 * np.pi * 110.0 * t_hum)
        + 0.022 * np.sin(2.0 * np.pi * 146.83 * t_hum)
    ) * (0.75 + 0.25 * np.sin(2.0 * np.pi * 3.0 * t_hum))
    add_clip(synths, beat_to_sample(32), env_fade(hum, 0.04, 0.03))

    # Beats 34-35: rising pitch/noise sweep into Beat 36
    riser_p2 = make_noise_riser(2.0 * BEAT_DUR, 350.0, 6800.0, pitch_sweep=True)
    add_clip(fx, beat_to_sample(34), riser_p2 * 0.58)
    for step in range(4):
        add_clip(drums, beat_to_sample(34 + step * 0.5), snare_tight * (0.18 + 0.14 * step))

    # Bar 9 beat 36 (16.875s): HARD BASS DROP with heavy kick + crunchy syncopated lead
    add_clip(fx, beat_to_sample(36), crash * 0.45)
    p2_bass_notes = [38, 38, 41, 38, 43, 41, 38, 37]
    p2_lead_riff = [
        (0.0, 0.5, 62), (0.75, 0.45, 65), (1.5, 0.45, 69), (2.25, 0.5, 70),
        (3.0, 0.45, 69), (3.5, 0.45, 65),
    ]
    for bar in range(9, 16):
        g_beat = bar * 4
        root = p2_bass_notes[(bar - 9) % len(p2_bass_notes)]
        # Driving distorted syncopated bass
        for step in range(8):
            off = step * 0.5
            note = root if step not in (3, 7) else (root + 12 if step == 3 else root + 10)
            bc = make_bass_note(
                note, 0.44 * BEAT_DUR, cutoff_hi=2800.0, cutoff_lo=420.0,
                drive=2.6, sidechain=(step % 2 == 0),
            )
            add_clip(bass, beat_to_sample(g_beat + off), bc * 0.50)

        # Crunchy syncopated lead
        shift = 0 if bar % 4 < 2 else (3 if bar % 4 == 2 else -2)
        for off, dur_b, m in p2_lead_riff:
            lc = make_lead_note(m + shift, dur_b * BEAT_DUR, detune_cents=12.0, cutoff=5200.0)
            lc = np.tanh(lc * 1.9) * 0.34
            add_clip(synths, beat_to_sample(g_beat + off), lc)

        if bar < 15:
            render_drums_standard_4x4(
                drums, g_beat, 1, kick_heavy * 0.86, snare, hat_c, hat_o,
                hat_16ths=True, hat_gain=0.25, backbeat_gain=0.66,
            )
        else:
            # Bar 15: 8th-note snare build
            for q in range(4):
                add_clip(drums, beat_to_sample(g_beat + q), kick_heavy * 0.84)
            for idx_8 in range(8):
                g = 0.28 + 0.085 * idx_8
                add_clip(drums, beat_to_sample(g_beat + idx_8 * 0.5), snare * g)
            add_clip(fx, beat_to_sample(g_beat), make_noise_riser(4.0 * BEAT_DUR, 600.0, 7500.0) * 0.42)

    # =========================================================================
    # PHASE 3 (30-45s, Bars 16-23, beats 64-95): "Floor-Slam Tantrum"
    # =========================================================================
    # Bar 16 beat 64 (30.00s): MASSIVE sub-impact slam + crash
    add_clip(drums, beat_to_sample(64), make_stomp_kick() * 0.95)
    add_clip(fx, beat_to_sample(64), crash * 0.62)

    p3_chords = [
        [50, 57, 62, 65],  # Dm
        [46, 53, 58, 62],  # Bb
        [48, 55, 60, 64],  # C
        [45, 52, 57, 61],  # A7
    ]
    for bar in range(16, 24):
        g_beat = bar * 4
        chord = p3_chords[(bar - 16) % len(p3_chords)]
        root = chord[0] - 12  # D2/Bb1/C2/A1

        # Driving aggressive 16th saw-bass (with smooth dominant turnaround sweep in Bar 23)
        for step in range(16):
            if bar < 23:
                note = root + (12 if step % 4 == 2 else 0)
                c_hi = 3200.0
                b_gain = 0.46
            else:
                # Bar 23 (A7 dominant turnaround into Phase 4 Dm): climb A1 -> C#2 -> E2 -> G2 -> A2
                turn_notes = [33, 33, 45, 33, 37, 37, 45, 37, 40, 40, 43, 43, 45, 45, 49, 45]
                note = turn_notes[step]
                c_hi = 2200.0 + 95.0 * step
                b_gain = 0.41 + 0.003 * step
            bc = make_bass_note(
                note, 0.23 * BEAT_DUR, cutoff_hi=c_hi, cutoff_lo=520.0,
                drive=2.8, sub_mix=0.55, sidechain=(step % 4 == 0),
            )
            add_clip(bass, beat_to_sample(g_beat + step * 0.25), bc * b_gain)

        if bar < 23:
            # Staccato synth stabs accenting beats 1 & 3 (0-indexed q=0, q=2)
            for q in (0, 2):
                stab = make_stab(chord, dur=0.58 * BEAT_DUR, cutoff=4800.0)
                add_clip(synths, beat_to_sample(g_beat + q), stab * 0.46)
            # Answer arp on beats 2 & 4
            for q in (1, 3):
                for sub in range(2):
                    ac = make_arp_note(chord[2 + sub] + 12, 0.42 * BEAT_DUR, brightness=4600.0, waveform="saw")
                    add_clip(synths, beat_to_sample(g_beat + q + sub * 0.5), ac * 0.24)
            render_drums_standard_4x4(
                drums, g_beat, 1, kick_heavy * 0.90, snare, hat_c, hat_o,
                hat_16ths=True, hat_gain=0.28, backbeat_gain=0.72,
            )
        else:
            # Bar 23: smooth transitional fill + filter sweep leading naturally into Bar 24 (Phase 4)
            stab0 = make_stab(chord, dur=0.58 * BEAT_DUR, cutoff=4400.0)
            add_clip(synths, beat_to_sample(g_beat), stab0 * 0.42)
            rise_arp_notes = [57, 61, 64, 67, 69, 73, 76, 79, 81, 85]
            for idx_a, m_a in enumerate(rise_arp_notes):
                ac = make_arp_note(
                    m_a, 0.24 * BEAT_DUR,
                    brightness=2600.0 + idx_a * 320.0,
                    waveform="saw",
                )
                add_clip(synths, beat_to_sample(g_beat + 1.5 + idx_a * 0.25), ac * (0.20 + 0.008 * idx_a))

            tom_hi = make_tom(190.0)
            tom_mid = make_tom(140.0)
            tom_lo = make_tom(95.0)
            for q in range(4):
                add_clip(drums, beat_to_sample(g_beat + q), kick_heavy * 0.82)
            # Keep crisp groove on beats 0-1, then roll toms & snares across beats 2-3 into Beat 96
            add_clip(drums, beat_to_sample(g_beat + 1.0), snare * 0.64)
            for sub_h in range(1, 8):
                add_clip(drums, beat_to_sample(g_beat + sub_h * 0.25), hat_c * 0.22)
            fill_hits = [
                (2.00, tom_hi, 0.34),
                (2.25, tom_hi, 0.38),
                (2.50, tom_mid, 0.42),
                (2.75, tom_mid, 0.46),
                (3.00, tom_lo, 0.50),
                (3.25, snare, 0.52),
                (3.50, snare, 0.56),
                (3.75, snare_metal, 0.60),
            ]
            for off_f, hit_clip, vel in fill_hits:
                add_clip(drums, beat_to_sample(g_beat + off_f), hit_clip * vel)
            add_clip(fx, beat_to_sample(g_beat + 1.0), make_noise_riser(3.0 * BEAT_DUR, 550.0, 6200.0) * 0.32)
            add_clip(fx, beat_to_sample(g_beat + 3.0), make_reverse_crash(BEAT_DUR) * 0.34)

    # =========================================================================
    # PHASE 4 (45-60s, Bars 24-31, beats 96-127): "Accusing Point / Wheel Core"
    # Continuous driving 128 BPM groove across two 4-bar tension-and-release waves:
    #   Wave 1 (Bars 24-27): Wheel Core lock-on -> smooth filter-sweep tether charge
    #                        -> rising harmonic climb -> 1-bar fill telegraphing Beat 112
    #   Wave 2 (Bars 28-31): Beat 112 Wheel-Reversal Drop -> relentless jaw-lunge
    #                        pursuit groove (Bars 29-30) -> Bar 31 overload climax riser
    #                        leading seamlessly into Beat 128 Phase 5 power-down collapse!
    # =========================================================================
    p4_bass_patterns: dict[int, list[int]] = {
        24: [38, 38, 50, 38, 38, 38, 41, 38, 38, 38, 50, 38, 45, 38, 49, 38],  # Dm
        25: [41, 41, 53, 41, 41, 41, 48, 41, 43, 43, 55, 43, 43, 43, 50, 43],  # F -> Gm filter charge
        26: [46, 46, 58, 46, 46, 46, 53, 46, 43, 43, 55, 43, 43, 43, 50, 43],  # Bb -> Gm climb
        27: [45, 45, 57, 45, 45, 45, 52, 45, 46, 46, 47, 47, 48, 48, 49, 49],  # A7 chromatic charge into b112
        28: [38, 50, 38, 50, 38, 38, 41, 38, 38, 50, 38, 50, 45, 38, 49, 50],  # Dm Wheel-Reversal Drop
        29: [43, 43, 55, 43, 43, 43, 50, 43, 46, 46, 58, 46, 46, 46, 53, 46],  # Gm -> Bb Lunge 1 groove
        30: [48, 48, 60, 48, 48, 48, 55, 48, 45, 45, 57, 45, 45, 45, 52, 45],  # C -> A7 Lunge 2 escalation
        31: [45, 45, 57, 45, 46, 46, 58, 46, 48, 48, 49, 49, 50, 50, 57, 62],  # A7 -> D3 overload climb
    }
    p4_cutoff_ranges: dict[int, tuple[float, float]] = {
        24: (2700.0, 2900.0),
        25: (1850.0, 2750.0),
        26: (2750.0, 3450.0),
        27: (3450.0, 4200.0),
        28: (3500.0, 3700.0),
        29: (2500.0, 3300.0),
        30: (3300.0, 3900.0),
        31: (3800.0, 4600.0),
    }
    p4_arp_sequences: dict[int, list[int]] = {
        24: ARP_HARM,
        25: [65, 69, 72, 74, 67, 70, 74, 77],
        26: [70, 74, 77, 81, 67, 70, 74, 79],
        27: [69, 73, 76, 81, 73, 76, 81, 85],
        28: [74, 77, 81, 85, 86, 85, 81, 77],
        29: [67, 70, 74, 79, 70, 74, 77, 82],
        30: [72, 76, 79, 84, 69, 73, 76, 81],
        31: [69, 73, 76, 81, 74, 77, 81, 86],
    }
    p4_lead_phrases: dict[int, list[tuple[float, float, int]]] = {
        24: [(0.0, 0.65, 74), (0.75, 0.45, 73), (1.5, 0.65, 74), (2.5, 0.45, 77), (3.0, 0.85, 76)],
        25: [(0.0, 0.70, 69), (1.0, 0.65, 72), (2.0, 0.70, 74), (3.0, 0.85, 76)],
        26: [(0.0, 0.70, 74), (1.0, 0.65, 77), (2.0, 0.70, 79), (3.0, 0.85, 81)],
        27: [(0.0, 0.65, 76), (0.75, 0.45, 77), (1.5, 0.65, 79), (2.5, 0.65, 81), (3.25, 0.65, 85)],
        28: [(0.0, 0.65, 74), (0.75, 0.45, 77), (1.5, 0.65, 76), (2.25, 0.50, 81), (3.0, 0.85, 79)],
        29: [(0.0, 0.70, 74), (1.0, 0.65, 77), (2.0, 0.55, 79), (2.5, 0.60, 82), (3.25, 0.65, 81)],
        30: [(0.0, 0.70, 76), (1.0, 0.65, 79), (2.0, 0.55, 81), (2.5, 0.60, 84), (3.25, 0.65, 85)],
        31: [(0.0, 0.65, 81), (1.0, 0.65, 82), (2.0, 0.65, 85), (3.0, 0.90, 86)],
    }

    for bar in range(24, 32):
        g_beat = bar * 4
        b_notes = p4_bass_patterns[bar]
        c_start, c_end = p4_cutoff_ranges[bar]
        arp_seq = p4_arp_sequences[bar]

        # Downbeat crash on Bar 24 (Phase 4 entry) and Bar 28 (Beat 112 Wheel Reversal Drop)
        if bar in (24, 28):
            add_clip(fx, beat_to_sample(g_beat), crash * (0.44 if bar == 24 else 0.50))
            stab_chord = [50, 57, 62, 65] if bar == 24 else [50, 57, 62, 69]
            add_clip(synths, beat_to_sample(g_beat), make_stab(stab_chord, dur=0.50 * BEAT_DUR, cutoff=4800.0) * 0.34)

        # Continuous driving 16th-note bass backbone across ALL 8 bars of Phase 4
        for step in range(16):
            u_step = step / 15.0
            c_hi = c_start + (c_end - c_start) * u_step
            bc = make_bass_note(
                b_notes[step],
                0.23 * BEAT_DUR,
                cutoff_hi=c_hi,
                cutoff_lo=420.0,
                drive=2.55 if bar in (25, 29) else 2.75,
                sub_mix=0.62,
                sidechain=(step % 4 == 0),
            )
            b_gain = 0.43 if bar in (25, 26, 29) else 0.45
            add_clip(bass, beat_to_sample(g_beat + step * 0.25), bc * b_gain)

        # Smooth filter-sweeping 16th-note arpeggio layer
        for step in range(16):
            u_step = step / 15.0
            m_arp = arp_seq[step % len(arp_seq)] + (12 if (bar in (27, 31) and step >= 12) else 0)
            bright = (c_start * 1.15) + ((c_end * 1.45) - (c_start * 1.15)) * u_step
            wf = "pulse" if bar in (24, 25) else "saw"
            ac = make_arp_note(m_arp, 0.22 * BEAT_DUR, brightness=min(7600.0, bright), waveform=wf)
            a_gain = 0.21 + 0.03 * u_step
            add_clip(synths, beat_to_sample(g_beat + step * 0.25), ac * a_gain)

        # Melodic lead phrase with smooth filter progression
        lead_cut = 3800.0 if bar == 25 else (4400.0 if bar in (26, 29) else 5600.0)
        oct_up = 0.15 if bar in (25, 26, 29) else 0.26
        l_gain = 0.28 if bar in (25, 26, 29) else 0.34
        for off, db, m_lead in p4_lead_phrases[bar]:
            lc = make_lead_note(m_lead, db * BEAT_DUR, detune_cents=11.0, cutoff=lead_cut, octave_up=oct_up)
            add_clip(synths, beat_to_sample(g_beat + off), lc * l_gain)

        # Syncopated jaw-lunge stab accents in Bars 29, 30, 31 (matching beats 118.5, 122.5, 126.0)
        if bar == 29:
            add_clip(synths, beat_to_sample(g_beat + 2.5), make_stab([46, 53, 58, 62], 0.45 * BEAT_DUR, 4600.0) * 0.30)
        elif bar == 30:
            add_clip(synths, beat_to_sample(g_beat + 2.5), make_stab([45, 52, 57, 61], 0.45 * BEAT_DUR, 5000.0) * 0.32)
        elif bar == 31:
            add_clip(synths, beat_to_sample(g_beat + 2.0), make_stab([45, 52, 57, 64], 0.45 * BEAT_DUR, 5400.0) * 0.34)

        # Continuous driving 4x4 drum backbone + transitional 1-bar fills on Bars 27 & 31
        if bar not in (27, 31):
            k_gain = 0.80 if bar in (25, 29) else 0.86
            bb_clip = snare_tight if bar == 25 else snare_metal
            bb_gain = 0.58 if bar in (25, 29) else 0.64
            h_gain = 0.24 if bar in (25, 29) else 0.27
            render_drums_standard_4x4(
                drums, g_beat, 1, kick_heavy * k_gain, bb_clip, hat_c, hat_o,
                hat_16ths=True, hat_gain=h_gain, backbeat_gain=bb_gain,
            )
            if bar == 25:
                # Subtle electro clap layer on beats 2 & 4 to keep Bar 25's filter groove crisp
                add_clip(drums, beat_to_sample(g_beat + 1.0), clap * 0.28)
                add_clip(drums, beat_to_sample(g_beat + 3.0), clap * 0.28)
        else:
            # Bar 27 (into Beat 112 Wheel-Reversal Drop) & Bar 31 (into Beat 128 Phase 5 Collapse):
            # Full 4-on-floor kicks + 16th hats + accelerating snare/tom build + 1-bar riser
            for q in range(4):
                add_clip(drums, beat_to_sample(g_beat + q), kick_heavy * 0.85)
                for sub_h in range(1, 4):
                    add_clip(drums, beat_to_sample(g_beat + q + sub_h * 0.25), hat_c * 0.22)
            # Beats 0-1: 8th-note snare pulse; Beats 2-3: 16th-note escalating roll
            for idx_8 in range(4):
                add_clip(drums, beat_to_sample(g_beat + idx_8 * 0.5), snare_tight * (0.24 + 0.05 * idx_8))
            for idx_16 in range(8, 16):
                vel = 0.32 + 0.036 * (idx_16 - 8)
                hit = snare if idx_16 < 14 else snare_metal
                add_clip(drums, beat_to_sample(g_beat + idx_16 * 0.25), hit * vel)
            add_clip(
                fx,
                beat_to_sample(g_beat),
                make_noise_riser(4.0 * BEAT_DUR, 550.0, 7600.0 if bar == 27 else 8200.0) * 0.36,
            )
            if bar == 27:
                add_clip(fx, beat_to_sample(g_beat + 3.0), make_reverse_crash(BEAT_DUR) * 0.36)

    # =========================================================================
    # PHASE 5 (60-75s, Bars 32-39, beats 128-159): "Fake-Out Collapse"
    # =========================================================================
    # Bar 32 beat 128: smooth overload power-down pitch dive (~1.45s) + sub-thud + residual hum bridge
    collapse_thud = make_kick(dur=0.42, start_hz=115.0, end_hz=35.0, pitch_tau=0.038, decay=6.8, drive=1.45, click_amt=0.08)
    add_clip(drums, beat_to_sample(128), collapse_thud * 0.44)
    n_pd = int(round(1.45 * SR))
    t_pd = np.arange(n_pd, dtype=np.float64) / SR
    u_pd = t_pd / 1.45
    f_pd = 293.66 * (0.125 ** (u_pd ** 0.85))  # D4 diving smoothly down 3 octaves to D1
    c_pd = 4600.0 * ((110.0 / 4600.0) ** (u_pd ** 0.75))
    pd_sig = (
        bandlimited_osc(f_pd, n_pd, "saw", cutoff=c_pd)
        + 0.65 * bandlimited_osc(f_pd * 0.5, n_pd, "saw", cutoff=c_pd * 0.65)
        + 0.45 * bandlimited_osc(f_pd * 1.5, n_pd, "square", cutoff=c_pd)
    ) * ((1.0 - u_pd) ** 1.15)
    add_clip(fx, beat_to_sample(128), env_fade(pd_sig * 0.50, 0.004, 0.05))

    # Gentle decaying transformer hum + beat-131 music-box pickup bridging Beat 129..132 into Bar 33
    n_bridge = beat_to_sample(132) - beat_to_sample(129)
    t_br = np.arange(n_bridge, dtype=np.float64) / SR
    u_br = t_br / (3.0 * BEAT_DUR)
    bridge_hum = (
        0.075 * np.sin(2.0 * np.pi * 73.42 * t_br)
        + 0.038 * np.sin(2.0 * np.pi * 110.00 * t_br)
        + 0.020 * np.sin(2.0 * np.pi * 146.83 * t_br)
    ) * (1.0 - 0.55 * u_br)
    add_clip(synths, beat_to_sample(129), env_fade(bridge_hum, 0.08, 0.06))
    add_clip(synths, beat_to_sample(131), make_music_box(69, dur=0.72) * 0.15)

    # Bars 33-37 (and beat 130-131): minimal 64 BPM sub-bass heartbeat + haunting music-box sine arp (low RMS ~0.04-0.06)
    mb_seq = [74, 81, 77, 74, 70, 77, 76, 73]  # D5 A5 F5 D5 Bb4 F5 E5 C#5
    for beat in range(130, 152, 2):
        # Double-thump heartbeat every 2 beats (64 BPM)
        hb1 = make_kick(dur=0.22, start_hz=82.0, end_hz=38.0, pitch_tau=0.025, decay=11.0, drive=1.25, click_amt=0.02)
        hb2 = make_kick(dur=0.18, start_hz=74.0, end_hz=36.0, pitch_tau=0.022, decay=13.0, drive=1.2, click_amt=0.01)
        add_clip(drums, beat_to_sample(beat), hb1 * 0.34)
        add_clip(drums, beat_to_sample(beat + 0.36), hb2 * 0.22)

    for step, beat_pos in enumerate(np.arange(132.0, 152.0, 1.0)):
        m = mb_seq[step % len(mb_seq)]
        mb = make_music_box(m, dur=0.76)
        add_clip(synths, beat_to_sample(float(beat_pos)), mb * 0.22)
        if step % 2 == 1:
            mb2 = make_music_box(m + 12, dur=0.48)
            add_clip(synths, beat_to_sample(float(beat_pos) + 0.5), mb2 * 0.11)

    # Bar 38 (beats 152-155): glitching stutter riser
    n_g5 = beat_to_sample(156) - beat_to_sample(152)
    t_g5 = np.arange(n_g5, dtype=np.float64) / SR
    u_g5 = t_g5 / (4.0 * BEAT_DUR)
    f_g5 = 146.83 * (4.0 ** (u_g5 ** 1.3))
    g5_raw = bandlimited_osc(f_g5, n_g5, "saw", cutoff=np.linspace(900.0, 7200.0, n_g5))
    g5_crush = apply_bitcrush(g5_raw, hold=6, levels=10.0)
    # Stutter gate speeding up from 8ths -> 32nds
    stutter_hz = 4.0 + 18.0 * (u_g5 ** 1.5)
    gate = (np.sin(2.0 * np.pi * np.cumsum(stutter_hz / SR)) > -0.15).astype(np.float64)
    g5_sig = (0.65 * g5_crush * gate + 0.35 * make_noise_riser(4.0 * BEAT_DUR, 500.0, 7800.0)) * (0.20 + 0.55 * u_g5)
    add_clip(fx, beat_to_sample(152), env_fade(g5_sig * 0.55, 0.01, 0.008))

    # Bar 39 beats 156-157 (73.125s - 74.0625s): TRUE DIGITAL SILENCE (zeroed after full mix too)
    # Bar 39 beat 158 (74.0625s): GIGANTIC SUPERNOVA DROP + beat 159 reverse-crash swell
    add_clip(drums, beat_to_sample(158), make_supernova_boom() * 1.15)
    add_clip(fx, beat_to_sample(158), crash * 0.52)
    add_clip(fx, beat_to_sample(159), make_reverse_crash(BEAT_DUR) * 0.78)

    # =========================================================================
    # PHASE 6 (75-90s, Bars 40-47, beats 160-191): "Hollow-Eyed Rebirth"
    # High-energy 4-bar call-and-response hyper-electro (Bars 40-43 & 44-47)
    # =========================================================================
    add_clip(fx, beat_to_sample(160), crash * 0.65)
    p6_roots = [38, 46, 48, 45]  # Dm - Bb - C - A
    p6_call = [(0.0, 0.65, 74), (0.75, 0.65, 77), (1.5, 0.45, 79), (2.0, 0.9, 81), (3.0, 0.85, 79)]
    p6_call2 = [(0.0, 0.65, 82), (0.75, 0.65, 81), (1.5, 0.45, 77), (2.0, 0.9, 76), (3.0, 0.85, 73)]

    for bar in range(40, 48):
        g_beat = bar * 4
        cycle_bar = (bar - 40) % 4
        root = p6_roots[cycle_bar]
        render_drums_standard_4x4(
            drums, g_beat, 1, kick_heavy * 0.90, snare, hat_c, hat_o,
            hat_16ths=True, hat_gain=0.30, backbeat_gain=0.72,
        )
        # Hyper-electro octave-jumping bass
        for step in range(16):
            note = root + (12 if step % 2 == 1 else 0)
            bc = make_bass_note(
                note, 0.23 * BEAT_DUR, cutoff_hi=3400.0, cutoff_lo=520.0,
                drive=2.45, sidechain=(step % 4 == 0),
            )
            add_clip(bass, beat_to_sample(g_beat + step * 0.25), bc * 0.46)

        if cycle_bar in (0, 1):
            # Call: soaring octave lead
            mel = p6_call if cycle_bar == 0 else p6_call2
            for off, db, m in mel:
                lc = make_lead_note(m, db * BEAT_DUR, detune_cents=12.0, cutoff=6200.0, octave_up=0.35)
                add_clip(synths, beat_to_sample(g_beat + off), lc * 0.38)
        else:
            # Response: hyper chiptune arpeggio + gritty stab hits
            seq = ARP_MAIN if cycle_bar == 2 else ARP_HARM
            for step in range(16):
                ac = make_arp_note(seq[step % len(seq)] + 12, 0.22 * BEAT_DUR, brightness=5400.0, waveform="square")
                add_clip(synths, beat_to_sample(g_beat + step * 0.25), ac * 0.28)
            add_clip(synths, beat_to_sample(g_beat), make_stab([root + 12, root + 19, root + 24], 0.45 * BEAT_DUR, 5200.0) * 0.38)

    # =========================================================================
    # PHASE 7 (90-105s, Bars 48-55, beats 192-223): "Exhausted Panting"
    # HALF-TIME INDUSTRIAL STOMP:
    #   Beat 0: massive weighted bass STOMP (192,196,200,204,208,212,216,220)
    #   Beat 2: razor metallic SNARE/CRASH (194,198,202,206,210,214,218,222)
    #   Odd bars beat 1.5: syncopated ghost-kick pickup (197.5, 205.5, 213.5, 221.5)
    # =========================================================================
    p7_roots = [38, 39, 38, 37]  # D1, Eb1 (Phrygian menace!), D1, C#1
    for bar in range(48, 56):
        g_beat = bar * 4
        root = p7_roots[(bar - 48) % len(p7_roots)]
        # Beat 0: MASSIVE weighted bass STOMP
        add_clip(drums, beat_to_sample(g_beat), kick_stomp * 0.96)
        stomp_bass = make_bass_note(root, 1.55 * BEAT_DUR, cutoff_hi=2200.0, cutoff_lo=210.0, drive=3.0, sub_mix=0.85)
        add_clip(bass, beat_to_sample(g_beat), stomp_bass * 0.60)

        # Odd bars (49, 51, 53, 55) at beat 1.5: syncopated ghost-kick pickup
        if bar % 2 == 1:
            add_clip(drums, beat_to_sample(g_beat + 1.5), kick_heavy * 0.68)
            ghost_b = make_bass_note(root + 12, 0.42 * BEAT_DUR, cutoff_hi=1500.0, cutoff_lo=300.0, drive=2.4)
            add_clip(bass, beat_to_sample(g_beat + 1.5), ghost_b * 0.36)

        # Beat 2: razor metallic SNARE/CRASH
        add_clip(drums, beat_to_sample(g_beat + 2), snare_metal * 0.92)
        add_clip(fx, beat_to_sample(g_beat + 2), crash * 0.36)

        # Exhausted industrial breath / muted low pulse on offbeats
        for sub_off in (0.75, 2.75, 3.5):
            pant = fft_bandpass(RNG.standard_normal(int(0.18 * SR)), 550.0, 2400.0)
            pt = np.arange(pant.size, dtype=np.float64) / SR
            pant *= np.exp(-pt * 14.0) * 0.14
            add_clip(fx, beat_to_sample(g_beat + sub_off), env_fade(pant, 0.01, 0.02))

        if bar == 55:
            # Fill into Phase 8
            for idx_8 in range(4, 8):
                add_clip(drums, beat_to_sample(g_beat + idx_8 * 0.5), snare_tight * (0.28 + 0.12 * (idx_8 - 4)))

    # =========================================================================
    # PHASE 8 (105-120s, Bars 56-63, beats 224-255): "Panic & Silent Shatter"
    # =========================================================================
    add_clip(fx, beat_to_sample(224), crash * 0.65)
    p8_roots = [38, 39, 41, 45]  # D - Eb - F - A

    # Bars 56-59: all-out climax medley, with Bar 58 (beats 232-235) BITCRUSHED / GLITCH-STUTTER synth tear
    for bar in range(56, 60):
        g_beat = bar * 4
        root = p8_roots[bar - 56]
        render_drums_standard_4x4(
            drums, g_beat, 1, kick_heavy * 0.92, snare_metal, hat_c, hat_o,
            hat_16ths=True, hat_gain=0.32, backbeat_gain=0.76,
        )
        for step in range(16):
            note = root + (12 if step % 4 in (1, 3) else 0)
            bc = make_bass_note(
                note, 0.23 * BEAT_DUR, cutoff_hi=3800.0, cutoff_lo=560.0,
                drive=2.85, sidechain=(step % 4 == 0),
            )
            add_clip(bass, beat_to_sample(g_beat + step * 0.25), bc * 0.48)

        if bar == 58:
            # Bar 58 (beats 232-235, 108.75s): BITCRUSHED / GLITCH-STUTTER synth tear accent!
            n_tear = beat_to_sample(236) - beat_to_sample(232)
            t_tear = np.arange(n_tear, dtype=np.float64) / SR
            # Wild chromatic / octave glitch tear pattern
            tear_notes = [74, 86, 75, 87, 81, 86, 73, 85]
            tear_raw = np.zeros(n_tear, dtype=np.float64)
            seg = n_tear // 16
            for i in range(16):
                s0 = i * seg
                s1 = n_tear if i == 15 else (i + 1) * seg
                m = tear_notes[i % len(tear_notes)]
                f0 = midi_to_hz(m)
                tear_raw[s0:s1] = bandlimited_osc(f0, s1 - s0, "saw", cutoff=7500.0, resonance=0.45)
                tear_raw[s0:s1] += 0.55 * bandlimited_osc(f0 * 1.498, s1 - s0, "square", cutoff=7500.0)
            # Aggressive bitcrush + rapid stutter envelope
            crushed = apply_bitcrush(tear_raw, hold=5, levels=7.0)
            stutter = (np.sin(2.0 * np.pi * 21.333 * t_tear) > -0.2).astype(np.float64)
            tear_sig = np.tanh(crushed * 1.9) * stutter * 0.48
            add_clip(synths, beat_to_sample(232), env_fade(tear_sig, 0.002, 0.01))
        else:
            for step in range(16):
                m = ARP_HARM[step % len(ARP_HARM)] + 12
                ac = make_arp_note(m, 0.22 * BEAT_DUR, brightness=6000.0, waveform="saw")
                add_clip(synths, beat_to_sample(g_beat + step * 0.25), ac * 0.30)
            mel_note = 86 if bar == 56 else (87 if bar == 57 else 85)
            lc = make_lead_note(mel_note, 1.8 * BEAT_DUR, detune_cents=14.0, cutoff=6600.0, octave_up=0.35)
            add_clip(synths, beat_to_sample(g_beat), lc * 0.36)

    # Bar 60 (beats 240-243, 112.50s): brief 4-beat eye-of-the-storm tension filter dip
    for step in range(16):
        m = ARP_HARM[step % len(ARP_HARM)]
        ac = make_arp_note(m, 0.22 * BEAT_DUR, brightness=1150.0 + step * 90.0, waveform="pulse")
        add_clip(synths, beat_to_sample(240 + step * 0.25), ac * 0.24)
    add_clip(bass, beat_to_sample(240), make_bass_note(38, 3.85 * BEAT_DUR, cutoff_hi=340.0, cutoff_lo=170.0, drive=1.5) * 0.42)
    for q in range(4):
        add_clip(drums, beat_to_sample(240 + q), kick_electro * 0.48)
        add_clip(drums, beat_to_sample(240 + q + 0.5), hat_c * 0.22)

    # Bar 61 (beats 244-247): full-throttle return
    add_clip(fx, beat_to_sample(244), crash * 0.55)
    render_drums_standard_4x4(
        drums, 244, 1, kick_heavy * 0.94, snare_metal, hat_c, hat_o,
        hat_16ths=True, hat_gain=0.32, backbeat_gain=0.78,
    )
    for step in range(16):
        note = 38 + (12 if step % 2 == 1 else 0)
        bc = make_bass_note(note, 0.23 * BEAT_DUR, cutoff_hi=4000.0, cutoff_lo=600.0, drive=2.9, sidechain=(step % 4 == 0))
        add_clip(bass, beat_to_sample(244 + step * 0.25), bc * 0.50)
        ac = make_arp_note(ARP_HARM[step % len(ARP_HARM)] + 12, 0.22 * BEAT_DUR, brightness=6400.0, waveform="saw")
        add_clip(synths, beat_to_sample(244 + step * 0.25), ac * 0.34)
    add_clip(synths, beat_to_sample(244), make_lead_note(86, 3.8 * BEAT_DUR, detune_cents=15.0, cutoff=6800.0, octave_up=0.4) * 0.40)

    # Bar 62 (beats 248-251, 116.25-118.125s): escalating 4-beat finale kick/snare/bitcrush roll rising in pitch every beat
    for b_off in range(4):
        beat = 248 + b_off
        subdiv = 2 if b_off == 0 else (3 if b_off == 1 else (4 if b_off == 2 else 6))
        pitch_base = 62 + b_off * 4  # D4 -> F#4 -> Bb4 -> D5
        for s in range(subdiv):
            t_beat = beat + s / float(subdiv)
            dur_s = BEAT_DUR / float(subdiv)
            # Rising pitch kick/snare/bitcrush hit
            k = make_kick(dur=0.18, start_hz=150.0 + b_off * 35.0, end_hz=45.0 + b_off * 8.0, decay=13.0, drive=2.4)
            add_clip(drums, beat_to_sample(t_beat), k * (0.72 + 0.06 * b_off))
            add_clip(drums, beat_to_sample(t_beat), snare_metal * (0.55 + 0.08 * b_off))
            raw_r = make_lead_note(pitch_base + s, dur_s * 0.92, detune_cents=12.0, cutoff=6800.0)
            crushed_r = apply_bitcrush(raw_r, hold=max(2, 6 - b_off), levels=10.0)
            add_clip(synths, beat_to_sample(t_beat), crushed_r * (0.36 + 0.05 * b_off))
    add_clip(fx, beat_to_sample(248), make_noise_riser(4.0 * BEAT_DUR, 700.0, 8800.0) * 0.46)

    # Bar 63 beat 252 (118.125s): FINAL SHATTER CHORD + resonant decay tail fading cleanly to 0.0 by 119.95s
    s252 = beat_to_sample(SHATTER_BEAT)
    s_tail_end = int(round(TAIL_SILENCE_TIME * SR))
    n_shatter = s_tail_end - s252
    t_sh = np.arange(n_shatter, dtype=np.float64) / SR
    # Huge impact + metallic shatter chord (D3, A3, D4, F4, A4, C#5, E5, D5)
    add_clip(drums, s252, make_supernova_boom() * 0.86)
    add_clip(fx, s252, crash * 0.72)
    shatter_notes = [50, 57, 62, 65, 69, 73, 76, 86]
    chord_sig = np.zeros(n_shatter, dtype=np.float64)
    c_sh = 7200.0 * np.exp(-t_sh * 1.8) + 320.0
    for idx_n, m in enumerate(shatter_notes):
        f0 = midi_to_hz(m)
        det = 1.0 + (idx_n - 3.5) * 0.0025
        chord_sig += bandlimited_osc(f0 * det, n_shatter, "saw", cutoff=c_sh, resonance=0.25, phase0=idx_n * 0.8)
        # Shimmer bell overtone
        chord_sig += 0.35 * np.sin(2.0 * np.pi * f0 * 2.0 * t_sh) * np.exp(-t_sh * 3.8)
    chord_sig /= len(shatter_notes) * 0.85
    # Smooth exponential decay + raised-cosine tail reaching exact 0.0 at 119.95s
    decay_env = np.exp(-t_sh * 2.3)
    tail_fade_len = int(round(0.35 * SR))
    if tail_fade_len < n_shatter:
        u_tail = np.linspace(0.0, np.pi, tail_fade_len, endpoint=True)
        decay_env[-tail_fade_len:] *= 0.5 * (1.0 + np.cos(u_tail))
    decay_env[-1] = 0.0
    add_clip(synths, s252, env_fade(chord_sig * decay_env * 1.15, attack_s=0.002, release_s=0.01))

    # =========================================================================
    # Bus Mix, Exact Silences, Soft-Clipped Mastering
    # =========================================================================
    mix = drums * 0.62 + bass * 0.44 + synths * 0.45 + fx * 0.52

    # Enforce click-free entry into Bar 39 digital silence (beats 156-157)
    s156 = beat_to_sample(SILENCE_START_BEAT)
    s158 = beat_to_sample(SILENCE_END_BEAT)
    fade_out_n = int(round(0.004 * SR))
    mix[s156 - fade_out_n : s156] *= np.linspace(1.0, 0.0, fade_out_n)
    mix[s156:s158] = 0.0

    # Enforce exact silence from 119.95s to 120.000s
    mix[s_tail_end:] = 0.0

    # Soft-clip mastering (preserves Bar 0 & Bar 8 & Phase 5 low-level dynamics cleanly)
    drive = 1.15
    mastered = np.tanh(mix * drive) / math.tanh(drive)
    peak = float(np.max(np.abs(mastered)))
    if peak > 0.94:
        mastered *= 0.94 / peak

    # Re-zero digital silence windows after mastering just to guarantee exact 0.0 samples
    mastered[s156:s158] = 0.0
    mastered[s_tail_end:] = 0.0

    # Quantize to 16-bit signed PCM
    pcm = np.clip(np.round(mastered * 32767.0), -32767, 32767).astype(np.int16)
    pcm[s156:s158] = 0
    pcm[s_tail_end:] = 0

    metrics = {
        "frames": float(pcm.size),
        "duration_s": float(pcm.size) / float(SR),
        "peak": float(np.max(np.abs(pcm.astype(np.float64) / 32768.0))),
        "overall_rms": float(np.sqrt(np.mean((pcm.astype(np.float64) / 32768.0) ** 2))),
    }
    return pcm, metrics


def write_wav(path: Path, pcm: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SR)
        wf.writeframes(pcm.tobytes())


def verify_boss_track(wav_path: Path) -> None:
    """Built-in self-verification assertions against all structural & audio specs."""
    with wave.open(str(wav_path), "rb") as wf:
        assert wf.getnchannels() == 1, f"Expected mono, got {wf.getnchannels()} channels"
        assert wf.getsampwidth() == 2, f"Expected 16-bit PCM, got {wf.getsampwidth()} bytes"
        assert wf.getframerate() == SR, f"Expected {SR} Hz, got {wf.getframerate()}"
        n_frames = wf.getnframes()
        assert n_frames == TOTAL_FRAMES, f"Expected {TOTAL_FRAMES} frames, got {n_frames}"
        raw = wf.readframes(n_frames)

    samples = np.frombuffer(raw, dtype=np.int16).astype(np.float64) / 32768.0
    assert not np.any(np.isnan(samples)), "Audio contains NaNs"
    assert not np.any(np.isinf(samples)), "Audio contains Infs"

    peak = float(np.max(np.abs(samples)))
    assert peak <= 0.96, f"Peak {peak:.4f} exceeds 0.96"

    def seg_rms(b0: float, b1: float) -> float:
        s0, s1 = beat_to_sample(b0), beat_to_sample(b1)
        return float(np.sqrt(np.mean(samples[s0:s1] ** 2)))

    def onset_peak(beat: int, win_ms: float = 90.0) -> float:
        s0 = beat_to_sample(beat)
        s1 = min(TOTAL_FRAMES, s0 + int(round((win_ms / 1000.0) * SR)))
        return float(np.max(np.abs(samples[s0:s1])))

    # Bar 0 countdown RMS (~0.09-0.12)
    bar0_rms = seg_rms(0, 4)
    assert 0.085 <= bar0_rms <= 0.125, f"Bar 0 RMS {bar0_rms:.4f} outside ~0.09-0.12"

    # Bar 8 beat 33 dropout RMS < 0.06
    b33_rms = seg_rms(33, 34)
    assert b33_rms < 0.06, f"Bar 8 beat 33 dropout RMS {b33_rms:.4f} must be < 0.06"

    # Phase 5 minimal heartbeat Bars 33-37 RMS (~0.04-0.06)
    p5_hb_rms = seg_rms(132, 152)
    assert 0.03 <= p5_hb_rms <= 0.075, f"Phase 5 heartbeat RMS {p5_hb_rms:.4f} outside minimal range"

    # Bar 39 beats 156-157 digital silence (RMS < 0.0005, exact 0.0)
    s156, s158 = beat_to_sample(156), beat_to_sample(158)
    silence_rms = float(np.sqrt(np.mean(samples[s156:s158] ** 2)))
    assert silence_rms < 0.0005, f"Bar 39 beats 156-157 RMS {silence_rms:.6f} must be < 0.0005"
    assert float(np.max(np.abs(samples[s156:s158]))) == 0.0, "Bar 39 beats 156-157 must be exact 0.0"

    # Tail silence >= 119.95s
    s_tail = int(round(TAIL_SILENCE_TIME * SR)) + 1
    assert float(np.max(np.abs(samples[s_tail:]))) == 0.0, "Tail after 119.95s must decay to exact 0.0"

    # Strong onset transients on key structural cues
    cue_beats = [4, 36, 64, 158, 160, 192, 224, 232, 252]
    cue_peaks = {}
    for b in cue_beats:
        p = onset_peak(b)
        cue_peaks[b] = p
        assert p >= 0.50, f"Weak onset transient on beat {b}: peak={p:.4f} < 0.50"

    # Verify Phase 4 continuous energy (no jarring drop-outs across Bars 24-31)
    p4_bar_rms = [seg_rms(bar * 4, (bar + 1) * 4) for bar in range(24, 32)]
    assert min(p4_bar_rms) >= 0.21, f"Phase 4 bar RMS dipped too low: {[round(x, 4) for x in p4_bar_rms]}"

    # Verify per-phase RMS summary & Bar 22-33 transition flow
    phase_rms = [seg_rms(p * 32, (p + 1) * 32) for p in range(8)]
    bars_22_33_rms = {bar: seg_rms(bar * 4, (bar + 1) * 4) for bar in range(22, 34)}
    print(f"Verified {wav_path}: frames={n_frames} ({n_frames / SR:.3f}s), peak={peak:.4f}")
    print(f"Bar 0 RMS={bar0_rms:.4f}, Beat 33 RMS={b33_rms:.4f}, Phase 5 HB RMS={p5_hb_rms:.4f}, Silence RMS={silence_rms:.6f}")
    print("Phase RMS (1..8):", ", ".join(f"P{i+1}={v:.4f}" for i, v in enumerate(phase_rms)))
    print("Bars 22..33 RMS:", ", ".join(f"Bar{b}={v:.4f}" for b, v in bars_22_33_rms.items()))
    print("Cue onset peaks:", ", ".join(f"b{b}={p:.3f}" for b, p in cue_peaks.items()))


def verify_boss_intro(wav_path: Path) -> None:
    """Verify boss_intro.wav format, exact 1-bar frame count, peak, and click-free tail."""
    with wave.open(str(wav_path), "rb") as wf:
        assert wf.getnchannels() == 1, f"Expected mono, got {wf.getnchannels()} channels"
        assert wf.getsampwidth() == 2, f"Expected 16-bit PCM, got {wf.getsampwidth()} bytes"
        assert wf.getframerate() == SR, f"Expected {SR} Hz, got {wf.getframerate()}"
        n_frames = wf.getnframes()
        assert n_frames == INTRO_FRAMES, f"Expected {INTRO_FRAMES} frames, got {n_frames}"
        raw = wf.readframes(n_frames)

    pcm = np.frombuffer(raw, dtype=np.int16)
    samples = pcm.astype(np.float64) / 32768.0
    assert not np.any(np.isnan(samples)), "Intro audio contains NaNs"
    assert not np.any(np.isinf(samples)), "Intro audio contains Infs"

    peak = float(np.max(np.abs(samples)))
    assert peak <= 0.96, f"Intro peak {peak:.4f} exceeds 0.96"
    assert int(pcm[-1]) == 0, f"Intro final frame must be 0 for click-free handoff, got {pcm[-1]}"

    s2 = beat_to_sample(2.0)
    s2_end = min(INTRO_FRAMES, s2 + int(round(0.09 * SR)))
    slam_peak = float(np.max(np.abs(samples[s2:s2_end])))
    assert slam_peak >= 0.45, f"Beat 2 slam onset too weak: {slam_peak:.4f}"
    print(
        f"Verified {wav_path}: frames={n_frames} ({n_frames / SR:.4f}s), "
        f"peak={peak:.4f}, beat2_slam_peak={slam_peak:.4f}"
    )


def generate_boss_intro(out_path: Path) -> dict[str, float]:
    """Generate 1-bar (4-beat, 1.875s) 128 BPM D-minor boss drop-in intro sting."""
    n_frames = INTRO_FRAMES
    drums = np.zeros(n_frames, dtype=np.float64)
    bass = np.zeros(n_frames, dtype=np.float64)
    synths = np.zeros(n_frames, dtype=np.float64)
    fx = np.zeros(n_frames, dtype=np.float64)

    kick_electro = make_kick(dur=0.25, start_hz=150.0, end_hz=46.0, decay=11.0, drive=1.8, click_amt=0.24)
    snare_tight = make_snare(tight=True, metallic=False)
    snap = make_snap()
    hat_c = make_hat(open_hat=False)

    # Beats 0.0 -> 2.0 (0.000s -> 0.9375s): tension build into the drop-in slam
    drone = make_bass_note(38, 2.0 * BEAT_DUR, cutoff_hi=460.0, cutoff_lo=130.0, drive=1.45, sub_mix=0.90)
    u_drone = np.linspace(0.0, 1.0, drone.size, dtype=np.float64)
    drone *= 0.32 + 0.68 * (u_drone ** 1.2)
    add_clip(bass, 0, env_fade(drone, attack_s=0.018, release_s=0.010) * 0.68)

    riser = make_noise_riser(2.0 * BEAT_DUR, f_lo=400.0, f_hi=3200.0, pitch_sweep=True)
    add_clip(fx, 0, riser * 0.34)

    for idx, b in enumerate((0.5, 1.0, 1.5)):
        add_clip(drums, beat_to_sample(b), hat_c * (0.20 + 0.08 * idx))

    for idx, (b, midi) in enumerate(((0.0, 62), (0.5, 65), (1.0, 69), (1.5, 74))):
        arp_clip = make_arp_note(midi, BEAT_DUR * 0.44, brightness=2200.0 + idx * 550.0, waveform="pulse")
        add_clip(synths, beat_to_sample(b), arp_clip * (0.30 + 0.06 * idx))

    # Beat 2.0 (0.9375s): drop-in slam
    s2 = beat_to_sample(2.0)
    add_clip(drums, s2, kick_electro * 0.92)
    add_clip(drums, s2, snare_tight * 0.32)
    sub_impact = make_bass_note(38, 1.15 * BEAT_DUR, cutoff_hi=1800.0, cutoff_lo=220.0, drive=2.2, sub_mix=0.78)
    add_clip(bass, s2, sub_impact * 0.90)
    slam_stab = make_stab([50, 57, 62, 65], dur=0.40, cutoff=4400.0)
    add_clip(synths, s2, slam_stab * 0.88)

    # Beats 2.5 -> 4.0 (1.172s -> 1.875s): hands snap accent + reverse crash & chord swell into Beat 4
    s25 = beat_to_sample(2.5)
    add_clip(drums, s25, snap * 0.88)
    rev_crash = make_reverse_crash(dur=1.5 * BEAT_DUR)
    add_clip(fx, s25, rev_crash * 0.56)

    n_swell = n_frames - s25
    u_swell = np.linspace(0.0, 1.0, n_swell, dtype=np.float64)
    c_swell = 360.0 + 3400.0 * (u_swell ** 1.6)
    swell_sig = np.zeros(n_swell, dtype=np.float64)
    swell_notes = [50, 57, 62, 65]
    for idx_n, m in enumerate(swell_notes):
        f0 = midi_to_hz(m)
        swell_sig += bandlimited_osc(f0 * 0.996, n_swell, "saw", cutoff=c_swell, resonance=0.22, phase0=0.25 * idx_n)
        swell_sig += bandlimited_osc(f0 * 1.004, n_swell, "saw", cutoff=c_swell, resonance=0.22, phase0=0.75 * idx_n)
    swell_sig /= max(1.0, len(swell_notes) * 1.5)
    swell_sig *= 0.12 + 0.88 * (u_swell ** 1.7)
    add_clip(synths, s25, env_fade(swell_sig, attack_s=0.025, release_s=0.008) * 0.72)

    mix = drums * 0.64 + bass * 0.52 + synths * 0.52 + fx * 0.52
    drive = 1.15
    mastered = np.tanh(mix * drive) / math.tanh(drive)
    peak = float(np.max(np.abs(mastered)))
    if peak > 0.94:
        mastered *= 0.94 / peak

    # Clean 5ms tail fade to exact 0.0 at final frame (41,343) for click-free transition to boss_music.wav
    tail_fade_n = min(n_frames, int(round(0.005 * SR)))
    if tail_fade_n > 1:
        u_tail = np.linspace(0.0, np.pi, tail_fade_n, endpoint=True)
        mastered[-tail_fade_n:] *= 0.5 * (1.0 + np.cos(u_tail))
    mastered[-1] = 0.0

    pcm = np.clip(np.round(mastered * 32767.0), -32767, 32767).astype(np.int16)
    pcm[-1] = 0
    write_wav(out_path, pcm)
    verify_boss_intro(out_path)

    samples = pcm.astype(np.float64) / 32768.0
    return {
        "frames": float(pcm.size),
        "duration_s": float(pcm.size) / float(SR),
        "peak": float(np.max(np.abs(samples))),
        "overall_rms": float(np.sqrt(np.mean(samples ** 2))),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate boss soundtrack and intro sting WAVs.")
    parser.add_argument(
        "--intro-only",
        action="store_true",
        help="Generate only juego/assets/audio/boss_intro.wav without overwriting boss_music.wav.",
    )
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent
    audio_dir = repo_root / "juego" / "assets" / "audio"
    out_wav = audio_dir / "boss_music.wav"
    intro_wav = audio_dir / "boss_intro.wav"

    if not args.intro_only:
        pcm, metrics = generate_boss_track()
        write_wav(out_wav, pcm)
        print(
            f"Generated {out_wav} | frames={int(metrics['frames'])} "
            f"| duration={metrics['duration_s']:.3f}s | peak={metrics['peak']:.4f} "
            f"| overall_rms={metrics['overall_rms']:.4f}"
        )
        verify_boss_track(out_wav)

    intro_metrics = generate_boss_intro(intro_wav)
    print(
        f"Generated {intro_wav} | frames={int(intro_metrics['frames'])} "
        f"| duration={intro_metrics['duration_s']:.4f}s | peak={intro_metrics['peak']:.4f} "
        f"| overall_rms={intro_metrics['overall_rms']:.4f}"
    )


if __name__ == "__main__":
    main()
