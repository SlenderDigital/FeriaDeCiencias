# Task 3+ interface: section-intent helper (controller design note)

Per pre-flight scan ruling: T3 introduces ONE helper on PatternController that
T4, T5, T8 consume — no duplication across tasks.

## Helper contract (introduced by T3)

```gdscript
## Intent for the chart section active at time t. Derived from section
## energy (the chart's level_sections), never from hardcoded bar numbers.
## Returns: {
##   "name": String,            # section name from chart ("drop", "drop2", ...)
##   "energy": float,           # 0..1 from chart
##   "bars_per_encounter": int, # 2 for energy<0.45, 1 otherwise
##   "accent_beats": bool,      # true only for energy>=0.8 (drops)
## }
func _section_intent(t: float) -> Dictionary
```

Energy thresholds map the plan's cadence rule to ProceduralSong's actual
energies (intro 0.35, outro 0.3, build 0.6, breakdown 0.5, drop 0.85, drop2 0.9):
- energy < 0.45  → bars_per_encounter = 2 (intro/outro: 1 every 2 bars)
- energy >= 0.45 → bars_per_encounter = 1 (build/breakdown/drop/drop2)
- energy >= 0.8 → accent_beats = true (extra saw accent on beats 2 and 4)

## Consumers
- T3: spawns_at easy_mode gate uses bars_per_encounter (spawn only when
  bar % bars_per_encounter == 0) + accent path uses accent_beats.
- T4: crossing-beats N per section: 8 beats if energy < 0.45 else 6
  (speed = travel_dist / (N * beat_len); T5's drop2 multiplier applies to the
  final speed, NOT to N — quantization survives).
- T5: Gameplay/_draw scales flash/glow/grid color by energy; drop2 velocity
  bump ×1.10–1.15 applied after T4 quantization.
- T8: replaces _first_light_pattern's hardcoded bar ranges by keying the same
  intent (name + energy + position within section) — pattern timeline comes
  from the section, so an edited song structure still gets a coherent level.

## E2E (T3 updates)
e2e_chart_drive.gd gains a cadence assertion, e.g.: count encounters in
intro window (beats 0..15) and drop window (beats 48..111): intro_count*2
must be < drop_count per bar, and intro encounters land only on even bars.
Exact assertion left to the implementer; gates (consumed_all, no_targets,
has_variety) must still pass unchanged.
