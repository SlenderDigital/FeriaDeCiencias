#!/usr/bin/env python3
"""Build-time music analyzer: audio -> analysis.json (beat grid / sections / quality metrics)."""
import argparse
import json

import numpy as np
import soundfile as sf
import librosa


def _analyze(y, sr):
    tempo_arr, beat_frames = librosa.beat.beat_track(y=y, sr=sr, units="frames", trim=False)
    tempo = float(np.atleast_1d(tempo_arr)[0])
    beat_times = librosa.frames_to_time(beat_frames, sr=sr).astype(float)

    interval = float(np.median(np.diff(beat_times))) if len(beat_times) > 1 else 60.0 / tempo
    # beat regularity: stdev of inter-beat intervals / mean (low = steady)
    regularity = 1.0
    if len(beat_times) > 2:
        d = np.diff(beat_times)
        regularity = float(np.std(d) / (np.mean(d) + 1e-8))

    downbeat_bool = np.zeros(len(beat_times), dtype=bool)
    downbeat_bool[::4] = True
    bar_indices = list(range(0, len(beat_times), 4))
    phrase_indices = list(range(0, len(beat_times), 16))

    onset_env = librosa.onset.onset_strength(y=y, sr=sr)
    onset_times = librosa.times_like(onset_env, sr=sr).astype(float)

    return {
        "bpm": float(round(tempo, 2)),
        "duration": float(len(y) / sr),
        "n_beats": int(len(beat_times)),
        "beat_regularity": round(regularity, 4),
        "beats": beat_times.tolist(),
        "downbeat": downbeat_bool.tolist(),
        "bars": [int(b) for b in bar_indices],
        "phrases": [int(p) for p in phrase_indices],
        "onsets": onset_times.tolist(),
        "sections": _detect_sections(y, sr, beat_times),
    }


def _detect_sections(y, sr, beat_times):
    rms = librosa.feature.rms(y=y)[0]
    ra = rms - rms.min()
    rng = rms.max() - rms.min()
    energ = ra / rng if rng > 1e-8 else np.zeros_like(ra)
    energ = np.nan_to_num(energ, nan=0.0)
    boundaries = [float(b) for b in beat_times[::8]] + [float(len(y) / sr)]
    sections = []
    for i in range(len(boundaries) - 1):
        start, end = boundaries[i], boundaries[i + 1]
        if end - start < 1.0:
            continue
        idx0 = int(librosa.time_to_frames(start, sr=sr))
        idx1 = int(librosa.time_to_frames(end, sr=sr))
        idx0 = max(0, min(idx0, len(energ) - 1))
        idx1 = max(idx0 + 1, min(idx1, len(energ)))
        energy = float(np.mean(energ[idx0:idx1]))
        sections.append({"name": f"section_{i}", "start": round(start, 3), "end": round(end, 3), "energy": round(energy, 3)})
    return sections


def main():
    p = argparse.ArgumentParser(description="Analyze audio into chart metadata.")
    p.add_argument("input", help="Path to audio (.wav/.ogg/.flac)")
    p.add_argument("--out", default=None, help="Output JSON path (default: analysis.json next to input)")
    p.add_argument("--bpm-target", type=float, default=None, help="Expected BPM to report delta (for candidate selection)")
    args = p.parse_args()

    y, sr = sf.read(args.input, dtype="float32", always_2d=False)
    if y.ndim > 1:
        y = y.mean(axis=1)

    result = _analyze(y, sr)
    if args.bpm_target and result["bpm"] > 0:
        result["bpm_error"] = round(abs(result["bpm"] - args.bpm_target), 2)

    out = args.out or (args.input.rsplit(".", 1)[0] + ".analysis.json")
    with open(out, "w") as f:
        json.dump(result, f, indent=2)
    print(f"OK  {args.input}")
    print(f"    bpm={result['bpm']}  dur={result['duration']:.1f}s  beats={result['n_beats']}  "
          f"regularity={result['beat_regularity']}  sections={len(result['sections'])}")
    last = [s for s in result["sections"] if s["start"] >= result["duration"] * 0.5]
    print(f"    2nd-half energies: {[s['energy'] for s in last][:8]}")
    if "bpm_error" in result:
        print(f"    bpm error vs target {args.bpm_target}: {result['bpm_error']}")
    print(f"    -> {out}")


if __name__ == "__main__":
    main()