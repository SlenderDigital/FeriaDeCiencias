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

