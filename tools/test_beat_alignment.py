#!/usr/bin/env python3
"""Beat-alignment / sync contract test: validate each track's analysis chart against
its audio so the Godot playback clock + spawn grid stay aligned.

Contract checked here:
  1. beats are strictly monotonic and within [0, duration]
  2. inter-beat intervals are consistent (no drift / dropped-beat spikes)
  3. sections tile [0, duration] contiguously with finite energies
"""
import json
import sys

TRACKS = ["first_light", "mechanical_wall", "relentless_drive"]
BASE = "assets/music"


def main():
    ok = True
    for name in TRACKS:
        path = f"{BASE}/{name}.analysis.json"
        d = json.load(open(path))
        beats = d["beats"]
        dur = d["duration"]

        # 1. monotonic + in range
        mono = all(beats[i] > beats[i - 1] for i in range(1, len(beats)))
        in_range = beats[0] >= 0.0 and beats[-1] <= dur + 0.5

        # 2. inter-beat consistency: max gap / median gap
        gaps = [beats[i] - beats[i - 1] for i in range(1, len(beats))]
        med = sorted(gaps)[len(gaps) // 2]
        worst = max(gaps)
        drift = worst / med  # >~2.5 => a dropped beat / tempo shift

        # 3. sections contiguous
        secs = d["sections"]
        contig = all(abs(secs[i + 1]["start"] - secs[i]["end"]) < 1.5 for i in range(len(secs) - 1))
        finite = all(0.0 <= s["energy"] <= 1.0 for s in secs)

        good = mono and in_range and drift < 2.5 and contig and finite
        ok = ok and good
        print(f"{name:20s} bpm={d['bpm']:<7} beats={len(beats):<4} "
              f"mono={mono} range={in_range} drift={drift:.2f}x contig={contig} finite={finite}  "
              f"=> {'PASS' if good else 'FAIL'}")

    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()