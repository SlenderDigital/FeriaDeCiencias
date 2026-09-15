#!/usr/bin/env python3
"""Analyzer unit test: synthesize a known-BPM click track, assert tempo/beat recovery."""
import sys
import numpy as np
import soundfile as sf

sys.path.insert(0, ".")
from analyze_music import _analyze  # noqa: E402


def _synth_clicks(bpm=140.0, seconds=16.0, sr=22050):
    beat = 60.0 / bpm
    n = int(seconds * sr)
    y = np.zeros(n, dtype=np.float32)
    for i in range(0, int(seconds / beat)):
        idx = int(i * beat * sr)
        y[idx:idx + int(0.05 * sr)] = 0.8
    return y, sr


def main():
    y, sr = _synth_clicks(140.0, 16.0)
    sf.write("/tmp/clicks.wav", y, sr)
    res = _analyze(y, sr)
    assert abs(res["bpm"] - 140.0) < 6.0, f"BPM off: {res['bpm']} (target 140, librosa tolerance ±6)"
    assert res["n_beats"] >= 30, f"too few beats: {res['n_beats']}"
    # sections must cover full duration, energies in [0,1]
    secs = res["sections"]
    assert secs, "no sections"
    assert secs[0]["start"] < 2.0, f"first section too late: {secs[0]['start']}"
    assert abs(secs[-1]["end"] - res["duration"]) < 0.5, f"last section end off"
    # sections must be monotonic
    for i in range(1, len(secs)):
        assert secs[i]["start"] > secs[i - 1]["start"], "sections not monotonic"
    for s in secs:
        assert 0.0 <= s["energy"] <= 1.0, f"energy out of range: {s['energy']}"
    print(f"PASS bpm={res['bpm']:.2f} beats={res['n_beats']} sections={len(secs)}")


if __name__ == "__main__":
    main()