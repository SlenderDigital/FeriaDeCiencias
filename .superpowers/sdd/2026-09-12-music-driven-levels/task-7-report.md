# Task 7 Report — Wire Gameplay to real audio clock + charts

## Summary
Gameplay now streams the real `.ogg` per level, loads `analysis.json` + `level.json` via
`ChartData`, anchors its clock to `MusicPlayer.get_playback_position()`, and spawns
hazards/targets from the chart's `beat_times` through `PatternController`. The procedural
fallback path is preserved for track_data without chart keys. Headless load exits 0 with no
script/parse errors.

## Changes per file

### scripts/GameManager.gd
- Replaced the 4-entry `TRACKS` const with the 3 real levels (First Light, Mechanical Wall,
  Relentless Drive). Each Dictionary carries `id, name, artist, bpm, difficulty,
  difficulty_stars, duration, color, secondary_color, description, audio, analysis, level`.
- Updated `high_scores` dict keys to `level_first_light` / `level_mechanical_wall` /
  `level_relentless_drive`.
- Everything else (signals, control modes, palettes, volume, get_current_track, select_track,
  change_scene) unchanged.

### scripts/Gameplay.gd
- Added `@onready var music: AudioStreamPlayer = $MusicPlayer`.
- Added `var chart: ChartData`, `var controller: PatternController`, `var next_beat_idx: int = 0`.
- `_ready()`: when track_data has `audio`/`analysis`/`level`, loads charts + controller, sets
  `music.stream = load(track_data["audio"]) as AudioStream`, `bpm = chart.bpm`,
  `total_song_duration = chart.duration`, then `music.play()`.
- `_process()`: when `chart != null and music.playing`, `song_time = music.get_playback_position()`;
  chart-driven spawn loop walks `chart.beat_times` up to `song_time`, appending
  `controller.spawns_at(t, track_color)` results. Victory triggers on
  `music.finished` or `song_time >= chart.duration`. Procedural branch (delta clock +
  `beat_interval`/`beat_timer` + `_spawn_procedural_wave`) retained as the fallback when
  `chart == null`.

### scripts/PatternController.gd
- `spawns_at`: guard `if pool.is_empty(): return []` before `randi() % pool.size()`.
- `_build_pattern`: added `_` default match branch with
  `push_warning("PatternController: unknown pattern '%s'" % pattern)` returning `[]`.

## Headless verification

`godot --headless --quit` → exit 0, clean (no script/parse errors):
```
[GameManager] Inicializado correctamente.
[SoundManager] Generador de audio procedural listo.
[GameManager] Canción seleccionada: First Light
```

Direct Gameplay scene run confirms the chart path executes:
```
[Gameplay] Nivel iniciado: First Light (bpm=104.17, chart=true)
```
(exit 124 there is only `timeout` killing a live game loop — expected, not an error.)

## Concerns / Notes
- **API correction:** `AudioStreamOggVorbis.load()` no longer exists in Godot 4.7. The brief's
  snippet (`st.load(path)`) raised `Invalid call ... 'load'` at runtime. Replaced with
  `music.stream = load(track_data["audio"]) as AudioStream`, which loads the imported stream
  resource correctly.
- **MainMenu index off-by-one (out of scope):** `MainMenu.gd` still calls
  `select_track(1/2/3)`; with 3 tracks valid indices are 0/1/2, so index 3 falls through
  (no-op via the bounds guard). The brief says level selection is driven by MainMenu later —
  flagging for that task.
- **Chart/audio timing:** chart `bpm` (e.g. 104.17) is used for real-time spawn timing; the
  TRACKS `bpm` (104/115/176) remains the display/difficulty value. `first_light.analysis.json`
  has ~122 beats starting ~15s and `duration` ~99.8s; victory keys off `chart.duration` +
  `music.finished`, so the long lead-in is handled.
- Fallback path (`chart == null`, e.g. GameManager absent) is unchanged and still fully functional.