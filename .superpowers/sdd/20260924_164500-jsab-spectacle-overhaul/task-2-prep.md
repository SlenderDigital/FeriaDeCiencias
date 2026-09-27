# T2 prep: spoke fan — collision/fairness math (controller notes)

Pattern contract (from plan Task 2 + JSAB 30s/540s archetypes):
- Spawn dict: {"type": "spoke_fan", "pos": center Vector2, "radius": float px,
  "spokes": int (8), "gap_spokes": int (>=2, test-asserted),
  "rot_speed": rad/s = TAU / (beats_per_rev * beat_len), "rot_phase": rad,
  "state": "telegraph"|"active"|"fade", "state_time": float (counts UP, beat-derived),
  "telegraph_beats": 2, "active_beats": 4, "fade_beats": 2, "is_hazard": state=="active"}
- Gameplay._update_targets branch: state_time += delta; state transitions at
  2*beat_len / +4*beat_len; rotation angle = rot_phase + rot_speed * state_time
  (rotates THROUGH all states — telegraph shows the rotating dim rays so the
  player reads the sweep direction).
- Collision (active only): player polar vs hub: d = player - pos; r = d.length();
  if r < radius: ang = atan2(d.y, d.x); for each spoke k in spokes: spoke_ang =
  rotation + TAU*k/spokes; if angular distance(ang, spoke_ang) < spoke_halfwidth
  (approx radius-independent: halfwidth = atan2(spoke_w/2, max(r, 30)))
  -> hit. Gap fairness: gap_spokes >= 2 ensures arc gap >= 2 * TAU/spokes;
  at 8 spokes = 90 deg of safe arc. Player hitbox 16px vs spoke_w ~26px.
- Draw (_draw_one_target match "spoke_fan"):
  - telegraph: dim maroon rays (Color(0.55, 0.12, 0.2, 0.35)), thin (w*0.6),
    dashed hub ring; beat-pulse alpha (reuse wpulse pattern).
  - active: hot pink HDR rays via _neon_line(pos, pos + dir*radius), glow hub
    via _neon_arc; small white core dot (JSAB white-impact accent).
  - fade: alpha *= fade fraction.
- Bot-sim gate: bot must dodge — safe arc exists every frame; test asserts
  hit==false for a bot sitting in the gap arc across a full active window.

Beat locking: spawn on phrase/section beats via T1 director; state
transitions land on beats because state thresholds are beat_len multiples
(arrival/impact on beat — extends T4 quantization philosophy).
