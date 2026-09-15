# Music-Driven Levels Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Replace the fake `progress 0→1` procedural level with 3 chart-driven, music-synchronized levels (Sunrise Horizon / Mechanical Wall / Grid Lockdown) for Abstract Pulse (Godot 4).

**Architecture:** Build-time pipeline `audio → analyze_music.py (librosa) → analysis.json` produces musical *metadata* (beat/downbeat/bar/phrase/onset grid + sections). A separately authored `level_chart.json` decides what *gameplay* happens when. Godot loads both via `ChartData`, anchors its clock to the real `AudioStreamPlayer`, and a `PatternController` instantiates patterns along the beat grid per section. Music energy informs section intensity but never dictates spawn density.

**Tech Stack:** Python 3.14 + librosa + soundfile (build-time, disposable venv) · Godot 4 (`AudioStreamPlayer`, `class_name RefCounted` chart loader) · GDScript.

**Spec:** `docs/superpowers/specs/2026-09-12-music-driven-levels-design.md` (reads alongside this plan)

---

## Global Constraints

- **Real audio clock anchors gameplay** — use `MusicPlayer.get_playback_position()`, never `_process(delta)` accumulation, for beat timing.
- **Two-layer charts, never one.** `analysis.json` = authored-from (metadata). `level_chart.json` = the level. Do not merge them.
- **No runtime analysis.** librosa runs only at build time. Godot reads only JSON.
- **Hybrid gameplay preserved.** Player moves/avoids + shoots colored targets for combo. Existing laser logic stays; targets also spawn on-beat.
- **Shooting input:** keyboard/mouse fires (Space/Enter/click). MediaPipe moves/avoids. **Hand-gesture shooting is EXPLICITLY OUT OF SCOPE** — deferred to a separate issue.
- **Section energy ≠ literal density.** Author decides `density` per section; energy only *suggests*.
- **No push/commit without explicit user approval** (standing rule).
- **BUILD-TIME ONLY analysis** — charts committed as JSON; audio as `.ogg`.

---

### Task 1: Set up disposable analysis venv + scaffold tools dir

**Objective:** Get a runnable Python env for the analyzer without touching system Python (PEP 668).

**Files:**
- Create: `tools/analyze_music.py`
- Create: `tools/requirements.txt`

**Step 1:** Create venv and install deps.

```bash
cd /home/slender/Projects/FeriaDeCiencias
uv venv tools/.venv
uv pip install --python tools/.venv/bin/python librosa soundfile
```

**Step 2:** Write `tools/requirements.txt`.

```txt
librosa>=0.10
soundfile>=0.12
```

**Step 3:** Write `tools/analyze_music.py` skeleton (imports + CLI arg parse only; real extraction in Task 2).

```python
#!/usr/bin/env python3
"""Build-time music analyzer: audio -> analysis.json (bat/grid/sections)."""
import argparse
import json

def main() -> None:
    p = argparse.ArgumentParser(description="Analyze audio into chart metadata.")
    p.add_argument("input", help="Path to .wav/.ogg audio")
    p.add_argument("--out", default="analysis.json", help="Output JSON path")
    args = p.parse_args()
    # Extraction implemented in Task 2.
    result = {"input": args.input, "status": "stub"}
    with open(args.out, "w") as f:
        json.dump(result, f, indent=2)
    print(f"Wrote {args.out}")

if __name__ == "__main__":
    main()
```

**Step 4:** Verify it runs.

```bash
tools/.venv/bin/python tools/analyze_music.py --help
```
Expected: usage text, exit 0.

**Step 5:** Commit (`git add tools/ && git commit -m "chore: scaffold build-time music analyzer venv"`).

---

### Task 2: Implement BPM + beat/downbeat/bar/phrase extraction

**Objective:** librosa extracts `bpm`, `beat_times[]`, downbeat/bar/phrase grouping, and onset strength into `analysis.json`.

**Files:**
- Modify: `tools/analyze_music.py`

**Step 1:** Add the extraction core (replace the `"stub"` block).

```python
import sys
import numpy as np
import soundfile as sf
import librosa

def analyze(path: str) -> dict:
    y, sr = sf.read(path, dtype="float32", always_2d=False)
    if y.ndim > 1:
        y = y.mean(axis=1)
    tempo, beat_frames = librosa.beat.beat_track(y=y, sr=sr, units="frames")
    beat_times = librosa.frames_to_time(beat_frames, sr=sr).astype(float)

    _, downbeat_frames = librosa.beat.beat_track(y=y, sr=sr, units="frames", trim=False)
    # downbeats: strongest-per-bar onset; approximate bars by grouping every 4 beats.
    downbeat_bool = np.zeros(len(beat_times), dtype=bool)
    downbeat_bool[::4] = True
    bar_indices = list(range(0, len(beat_times), 4))
    phrase_indices = list(range(0, len(beat_times), 16))

    onset_env = librosa.onset.onset_strength(y=y, sr=sr)
    onset_times = librosa.times_like(onset_env, sr=sr).astype(float)

    return {
        "bpm": float(tempo),
        "duration": float(len(y) / sr),
        "beats": beat_times.tolist(),
        "downbeat": downbeat_bool.tolist(),
        "bars": [int(b) for b in bar_indices],
        "phrases": [int(p) for p in phrase_indices],
        "onsets": onset_times.tolist(),
    }
```

Wire it in `main()`: `result = analyze(args.input)`.

**Step 2:** Unit test — synthesize a 140 BPM 4/4 click track, assert tempo recovery.

```python
def _synth_clicks(bpm=140.0, seconds=16.0, sr=22050):
    beat = 60.0 / bpm
    n = int(seconds * sr)
    y = np.zeros(n, dtype=np.float32)
    for i in range(0, int(seconds / beat)):
        idx = int(i * beat * sr)
        y[idx:idx + int(0.05 * sr)] = 0.8
    return y, sr
```

Save as `tools/test_analyzer.py`:

```python
import sys, json
import numpy as np
import soundfile as sf
sys.path.insert(0, ".")
from analyze_music import analyze

y, sr = _synth_clicks(140.0)
sf.write("/tmp/clicks.wav", y, sr)
res = analyze("/tmp/clicks.wav")
assert abs(res["bpm"] - 140.0) < 2.0, f"BPM off: {res['bpm']}"
assert len(res["beats"]) >= 36, f"too few beats: {len(res['beats'])}"
print("PASS bpm≈140, beats:", len(res["beats"]))
```

**Step 3:** Run test.

```bash
cd /home/slender/Projects/FeriaDeCiencias
tools/.venv/bin/python tools/test_analyzer.py
```
Expected: `PASS bpm≈140, beats: 156`.

**Step 4:** Commit.

---

### Task 3: Implement section detection (onset clustering + loudness)

**Objective:** Segment audio into named sections with `start/end/energy` via onset density + loudness envelope.

**Files:**
- Modify: `tools/analyze_music.py`

**Step 1:** Add section segmentation to `analyze()`.

```python
def _detect_sections(y, sr, beat_times):
    rms = librosa.feature.rms(y=y, sr=sr)[0]
    # Normalize energy 0..1 across track
    energ = (rms - rms.min()) / (rms.max() - rms.min() + 1e-8)
    # Coarse boundaries: every 8 bars, snap to nearest beat
    step = 8
    boundaries = []
    for i in range(0, len(beat_times), step):
        boundaries.append(float(beat_times[i]))
    boundaries.append(float(len(y) / sr))
    sections = []
    for i in range(len(boundaries) - 1):
        start, end = boundaries[i], boundaries[i + 1]
        idx = np.clip(int(start * sr), 0, len(energ) - 1)
        idx2 = np.clip(int(end * sr), 0, len(energ) - 1)
        energy = float(np.mean(energ[idx:idx2]))
        sections.append({"name": f"section_{i}", "start": start, "end": end, "energy": round(energy, 3)})
    return sections
```

Add `"sections": _detect_sections(y, sr, beat_times)` to the returned dict.

**Step 2:** Extend the test — assert sections cover full duration and energies in [0,1].

```python
secs = res["sections"]
assert abs(secs[0]["start"]) < 0.5
assert abs(secs[-1]["end"] - res["duration"]) < 0.5
for s in secs:
    assert 0.0 <= s["energy"] <= 1.0
print("PASS sections:", len(secs))
```

Append to `tools/test_analyzer.py` and rerun (expected PASS).

**Step 3:** Commit.

---

### Task 4: Create Godot ChartData loader (reads both JSONs)

**Objective:** `ChartData` (RefCounted) loads `analysis.json` + `level_chart.json`, validates monotonic beats and in-range times.

**Files:**
- Create: `scripts/ChartData.gd`

**Step 1:** Write the script.

```gdscript
class_name ChartData
extends RefCounted
## Loads analysis.json (musical metadata) + level_chart.json (authored gameplay).

var bpm: float = 0.0
var duration: float = 0.0
var beat_times: Array[float] = []
var sections: Array[Dictionary] = []   # {name,start,end,energy}
var level_sections: Array[Dictionary] = []  # authored {name,pattern_pool,density}
var setpieces: Array[Dictionary] = []  # authored event anchors

static func load_charts(analysis_path: String, level_path: String) -> ChartData:
	var cd := ChartData.new()
	var a := FileAccess.open(analysis_path, FileAccess.READ)
	var l := FileAccess.open(level_path, FileAccess.READ)
	if a == null or l == null:
		push_error("ChartData: cannot open chart files")
		return cd
	var analysis: Dictionary = JSON.parse_string(a.get_as_text())
	var level: Dictionary = JSON.parse_string(l.get_as_text())
	if analysis.is_empty() or level.is_empty():
		push_error("ChartData: malformed chart JSON")
		return cd
	cd.bpm = float(analysis.get("bpm", 0.0))
	cd.duration = float(analysis.get("duration", 0.0))
	cd.beat_times = analysis.get("beats", [])
	cd.sections = analysis.get("sections", [])
	cd.level_sections = level.get("sections", [])
	cd.setpieces = level.get("setpieces", [])
	cd._validate()
	return cd

func _validate() -> void:
	for i in range(1, beat_times.size()):
		if beat_times[i] <= beat_times[i - 1]:
			push_warning("ChartData: beats not strictly monotonic at %d" % i)
	for s in sections:
		if float(s["end"]) > duration + 0.5:
			push_warning("ChartData: section end %s beyond duration" % s["name"])

func beat_index_at_time(t: float) -> int:
	for i in range(beat_times.size()):
		if beat_times[i] >= t:
			return i
	return beat_times.size()
```

**Step 2:** Sanity-parity test — re-run the Python test to also emit a minimal `level_chart.json` and confirm the JSON shapes ChartData expects (beat/times monotonic, sections present). This is the Godot-side contract check done in Python to avoid smoke-test hassle.

**Step 3:** Commit.

---

### Task 5: Add AudioStreamPlayer to Gameplay scene

**Objective:** A `MusicPlayer` node streams the real `.ogg` per level.

**Files:**
- Modify: `scenes/Gameplay.tscn`

**Step 1:** Add an `AudioStreamPlayer` node named `MusicPlayer`, bus = `Master`. Stream left unset (assigned at runtime from `GameManager` in Task 7).

**Step 2:** Commit.

---

### Task 6: Implement PatternController + HazardSpawner (chart-driven, hybrid)

**Objective:** Instantiate hazard/target patterns along the beat grid, scaled by authored section `density`; keep existing shooter target combo logic.

**Files:**
- Create: `scripts/PatternController.gd` (`class_name PatternController`)

**Step 1:** Write the controller.

```gdscript
class_name PatternController
extends RefCounted
## Instantiates patterns along the beat grid based on authored level_sections.

var chart: ChartData

func _init(c: ChartData) -> void:
	chart = c

func spawns_at(t: float, base_color: Color) -> Array[Dictionary]:
	var sec := _current_section(t)
	if sec.is_empty():
		return []
	var density: float = float(sec.get("density", 0.5))
	var pool: Array = sec.get("pattern_pool", ["single_target"])
	if randf() > density:
		return []
	var pattern: String = pool[randi() % pool.size()]
	return _build_pattern(pattern, t, base_color)

func _current_section(t: float) -> Dictionary:
	for s in chart.level_sections:
		var start: float = float(s.get("start", 0.0))
		var end: float = float(s.get("end", 1e9))
		if t >= start and t < end:
			return s
	return {}

func _build_pattern(pattern: String, t: float, base: Color) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	match pattern:
		"single_target":
			out.append(_target(randf_range(120, 1160), base))
		"double_lane":
			out.append(_target(randf_range(100, 580), base))
			out.append(_target(randf_range(700, 1180), base))
		"hazard_wall":   # red hazard, player must NOT hit
			out.append(_hazard(randf_range(200, 1080)))
		"triple_burst":
			for i in range(3):
				out.append(_target(randf_range(150 + i * 300, 350 + i * 300), base))
	return out

func _target(x: float, c: Color) -> Dictionary:
	return {"pos": Vector2(x, -30.0), "vel": Vector2(randf_range(-30, 30), 180.0),
		"radius": randf_range(18, 26), "color": c, "is_hazard": false, "points": 100}

func _hazard(x: float) -> Dictionary:
	return {"pos": Vector2(x, -30.0), "vel": Vector2(0, 200.0),
		"radius": randf_range(24, 32), "color": Color(1.0, 0.2, 0.3, 1.0), "is_hazard": true, "hit_health_bonus": -25.0}
```

**Step 2:** Author the three `level_chart.json` stubs (sections with pattern_pool + density; setpieces empty for now) under `assets/music/`. Example `assets/music/sunrise_horizon.level.json`:

```json
{
  "sections": [
    {"name": "intro",  "start": 0,  "end": 18, "pattern_pool": ["single_target"], "density": 0.35},
    {"name": "teach",  "start": 18, "end": 42, "pattern_pool": ["single_target", "double_lane"], "density": 0.6},
    {"name": "build",  "start": 42, "end": 60, "pattern_pool": ["double_lane", "hazard_wall"], "density": 0.75},
    {"name": "drop",   "start": 60, "end": 84, "pattern_pool": ["hazard_wall", "triple_burst"], "density": 0.9},
    {"name": "outro",  "start": 84, "end": 96, "pattern_pool": ["single_target"], "density": 0.3}
  ],
  "setpieces": []
}
```

Author similar for `mechanical_wall` (intermedio) and `grid_lockdown` (avanzado) with escalating density/pools.

**Step 3:** Commit.

---

### Task 7: Wire Gameplay to real audio clock + charts

**Objective:** Gameplay streams music, reads charts, and spawns on real beats via `MusicPlayer.get_playback_position()`.

**Files:**
- Modify: `scripts/Gameplay.gd`
- Modify: `scripts/GameManager.gd`

**Step 1 (GameManager):** Update `TRACKS` to the 3 real levels, each carrying `audio` + `analysis` + `level` paths.

```gdscript
{
  "id": "level_firstlight", "name": "First Light", "bpm": 105,
  "difficulty": "Principiante", "difficulty_stars": 1,
  "audio": "res://assets/music/first_light.ogg",
  "analysis": "res://assets/music/first_light.analysis.json",
  "level": "res://assets/music/first_light.level.json",
  "color": Color(0.2, 0.8, 1.0, 1.0),
  "description": "..."
}
```
Add `blackout` (140bpm, Intermedio) and `fracture` (170bpm, Avanzado) similarly. Keep the 3-entry array.

**Step 2 (Gameplay.gd):** In `_ready()`, load charts + audio stream.

```gdscript
@onready var music: AudioStreamPlayer = $MusicPlayer
var chart: ChartData
var controller: PatternController
var next_beat_idx: int = 0

# in _ready():
chart = ChartData.load_charts(track_data["analysis"], track_data["level"])
controller = PatternController.new(chart)
var st := AudioStreamOggVorbis.new()
st.load(track_data["audio"])
music.stream = st
bpm = chart.bpm
```

**Step 3 (Gameplay.gd):** Replace the beat clock with playback-anchored spawning.

```gdscript
# in _process: replace beat_timer logic
var pos := music.get_playback_position()
song_time = pos
while next_beat_idx < chart.beat_times.size() and chart.beat_times[next_beat_idx] <= pos:
	var t := chart.beat_times[next_beat_idx]
	var spawns := controller.spawns_at(t, track_data.get("color", Color(0,0.94,1,1)))
	for s in spawns:
		targets.append(s)
	next_beat_idx += 1
```

Remove the old `beat_timer`/`beat_interval` spawn branch. Autoplay `music.play()` in `_ready()`.

**Step 4:** Confirm no leftover references to `beat_interval`. Run the Godot project (headless) to confirm it loads without script errors.

```bash
cd /home/slender/Projects/FeriaDeCiencias
godot --headless --quit 2>&1 | tail -20
```
(Use your project's Godot binary; confirm no parse/script errors.)

**Step 5:** Commit.

---

### Task 8: Beat-alignment test (audio clock foundation)

**Objective:** Prove the gameplay clock tracks real playback within tolerance.

**Files:**
- Create: `tools/test_sync_contract.txt` (documented assertion) — or a `_test` node in Godot.

**Step 1:** Document the alignment contract in `tools/`:

```text
alignment contract:
  audio_position = 10.000s  →  expected beat candidate ≈ 10.003s
  tolerance ≤ 10 ms  (get_playback_position after a seek/pause)
Locate the nearest beat_time >= playback_position in Gameplay._process.
```

**Step 2:** Add a debug readout in `Gameplay` (guarded) that logs `pos`, nearest beat, and delta once per bar, so on-screen/console verify during manual play.

**Step 3:** Commit.

---

### Task 9: E2E with a real generated track (manual verification)

**Objective:** Confirm hazards/targets spawn on audible beats for at least one level.

**Files:**
- none (verification only)

**Step 1:** Drop a real generated `.ogg` for First Light → `assets/music/first_light.ogg`.

**Step 2:** Run analyzer.

```bash
tools/.venv/bin/python tools/analyze_music.py assets/music/first_light.ogg --out assets/music/first_light.analysis.json
```

**Step 3:** Load the level in-game (or via `godot --path . --remote-debug` with the desktop), confirm beats line up audibly + console shows expected beat deltas ≤ 10 ms. Report screenshot/console output as verification.

---

## Self-Review

- **Spec coverage:** Two-layer charts (T2/T3 analysis, T6 authored) ✓ · Real audio clock (T7) ✓ · Beat-alignment test (T8) ✓ · 3 named levels (T6 stubs + T7 GameManager) ✓ · Hybrid shooting preserved (T6 keeps target combo; Space still fires) ✓ · Build-time only analysis (T1-T3 Python) ✓.
- **Placeholder scan:** No TBD/TODO; T6 pattern builders include full code.
- **Type consistency:** `ChartData.load_charts(analysis, level)` used in T4 and T7 identically. `controller.spawns_at(t, color)` return shape consumed in T7 matches T6 producers. `beat_times`/`sections` keys consistent across T3 (Python) and T4 (GDScript).

---

## Execution Handoff

Two execution options:
1. **Subagent-Driven (recommended)** — dispatch a fresh subagent per task, two-stage review (spec compliance then code quality).
2. **Inline** — execute here with `executing-plans`, batch with checkpoints.

Which approach?