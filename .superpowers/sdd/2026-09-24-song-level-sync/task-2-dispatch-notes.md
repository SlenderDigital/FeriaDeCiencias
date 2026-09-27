# Task 2 dispatch notes (controller prep)

T2: laser fires ON a beat. `tools/e2e_chart_drive.gd` doesn't check telegraph timing,
so implementer adds a headless assertion or extends E2E: for each laser_telegraph spawn,
fire_time = spawn_t + telegraph_time; assert fire_time lands on a chart beat (within
one frame tolerance) i.e. fmod on beat grid ≈ 0.

Exact values:
- beat_len @128 = 0.46875s. Telegraph = 3 * beat_len = 1.40625s (replace fixed 1.3s).
- _laser_telegraph currently sets telegraph_time/telegraph_total = 1.3 — derive from
  beat_len (PatternController has beat_len member; easy_mode already uses beat_len
  elsewhere e.g. wall warn_time = 2.5*beat_len).

Interfaces: telegraph_total used by _draw_one_target for blink urgency scaling — keep
both keys consistent (telegraph_time AND telegraph_total = 3*beat_len).
