class_name BossScore
extends RefCounted

# 256-beat (64-bar, 120.0s @ 128 BPM) data-driven choreography score for "The Architect".
# Every cue declares:
#   { "phase": int, "impact_beat": float, "lead_beats": float, "kind": StringName, "params": Dictionary }
# Coordinates are authored in 1152x648 reference space (BossConstants.ARENA_REF) and scaled
# dynamically to the live viewport inside BossChoreographer.

const BEAT: float = BossConstants.BEAT_DURATION


static func build_score() -> Array[Dictionary]:
	var cues: Array[Dictionary] = []
	_append_phase_1(cues)
	_append_phase_2(cues)
	_append_phase_3(cues)
	_append_phase_4(cues)
	_append_phase_5(cues)
	_append_phase_6(cues)
	_append_phase_7(cues)
	_append_phase_8(cues)

	for i: int in range(cues.size()):
		var c: Dictionary = cues[i]
		c["trigger_beat"] = float(c["impact_beat"]) - float(c["lead_beats"])
		c["order"] = i

	cues.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ta: float = float(a["trigger_beat"])
		var tb: float = float(b["trigger_beat"])
		if absf(ta - tb) > 0.0001:
			return ta < tb
		var pa: int = int(a.get("priority", 0))
		var pb: int = int(b.get("priority", 0))
		if pa != pb:
			return pa < pb
		return int(a["order"]) < int(b["order"])
	)
	return cues


static func _add(
	cues: Array[Dictionary],
	phase: int,
	impact_beat: float,
	lead_beats: float,
	kind: StringName,
	params: Dictionary = {},
	priority: int = 0
) -> void:
	cues.append({
		"phase": phase,
		"impact_beat": impact_beat,
		"lead_beats": lead_beats,
		"kind": kind,
		"params": params,
		"priority": priority,
	})


# ------------------------------------------------------------------------------
# PHASE 1 (Beats 0-31, 0-15s): COCKY_CONDUCTOR / CONDUCTOR — Musical Onboarding
# Bar 0 (0-3): 0 hazards — only visual conductor snaps on beats 1, 2, 3.
# Beats 4 & 8: ONE horizontal pointer beam at a time (lead_beats=2.5) — teaches beams cleanly.
# Beats 12, 14, 16: 3 cleanly spaced filling circles (lead_beats=2.5) — zero overlap.
# Beat 20: ONE solo parryable expanding shockwave ring (lead_beats=2.5, travel_time=1.75s).
# Beat 25: ONE clean lower-lane horizontal rocket fist (lead_beats=2.5, dash_time=0.68s).
# Beat 29: ONE gentle 8-bullet radial ring from boss (speed=195.0) — handoff to Phase 2.
# ------------------------------------------------------------------------------
static func _append_phase_1(cues: Array[Dictionary]) -> void:
	_add(cues, 1, 0.0, 0.0, &"phase_transition", {
		"acting": 0, # COCKY_CONDUCTOR
		"form": 0, # CONDUCTOR
		"target": Vector2(576.0, 152.0),
		"move_speed": 7.5,
	}, -10)

	# Bar 0 visual-only conductor finger snaps (zero hazards)
	_add(cues, 1, 1.0, 0.0, &"conductor_snap", {"is_left": true, "strength": 0.45})
	_add(cues, 1, 2.0, 0.0, &"conductor_snap", {"is_left": false, "strength": 0.55})
	_add(cues, 1, 3.0, 0.0, &"conductor_snap", {"both": true, "strength": 0.72})

	# Beats 4 & 8: Two solo horizontal pointer beams with generous 2.5-beat telegraphs
	_add(cues, 1, 4.0, 2.5, &"hand_pointer", {
		"is_left": true, "pos": Vector2(180.0, 324.0), "angle": 0.0, "hold_time": 0.80,
	})
	_add(cues, 1, 4.0, 2.5, &"sweeping_beam", {
		"origin": Vector2(576.0, 324.0), "angle": 0.0, "beam_count": 1,
		"width": BossConstants.BEAM_WIDTH, "active_time": 0.42,
	})

	_add(cues, 1, 8.0, 2.5, &"hand_pointer", {
		"is_left": false, "pos": Vector2(972.0, 220.0), "angle": PI, "hold_time": 0.80,
	})
	_add(cues, 1, 8.0, 2.5, &"sweeping_beam", {
		"origin": Vector2(576.0, 220.0), "angle": 0.0, "beam_count": 1,
		"width": BossConstants.BEAM_WIDTH, "active_time": 0.42,
	})

	# Beats 12, 14, 16: 3 cleanly spaced filling circles (nothing overlapping!)
	_add(cues, 1, 12.0, 2.5, &"filling_circle", {"pos": Vector2(280.0, 230.0), "radius": 52.0, "fill_mode": 0})
	_add(cues, 1, 14.0, 2.5, &"filling_circle", {"pos": Vector2(576.0, 360.0), "radius": 52.0, "fill_mode": 1})
	_add(cues, 1, 16.0, 2.5, &"filling_circle", {"pos": Vector2(872.0, 480.0), "radius": 52.0, "fill_mode": 2})
	_add(cues, 1, 16.0, 0.0, &"body_move", {"target": Vector2(450.0, 158.0), "speed": 6.0})

	# Beat 20: ONE solo parryable expanding shockwave ring (teaches rings & dodge/parry cleanly!)
	_add(cues, 1, 20.0, 2.5, &"shockwave_ring", {
		"origin": Vector2(576.0, 165.0), "start_radius": 34.0, "end_radius": 820.0,
		"thickness": 28.0, "travel_time": 1.75, "parryable": true,
	})
	_add(cues, 1, 22.0, 0.0, &"body_move", {"target": Vector2(690.0, 158.0), "speed": 6.0})

	# Beat 25: ONE clean horizontal rocket fist sweeping lower lane (eliminates AFK safe corner!)
	_add(cues, 1, 25.0, 2.5, &"hand_dash", {
		"is_left": false, "from": Vector2(1060.0, 565.0), "to": Vector2(64.0, 565.0),
		"dash_time": 0.68, "style": 0, # FIST_ROCKET sweeping across (100, 580)
	})
	_add(cues, 1, 27.0, 0.0, &"body_move", {"target": Vector2(576.0, 152.0), "speed": 6.5})

	# Beat 29: ONE gentle 8-bullet radial ring from boss — smooth handoff to Phase 2
	_add(cues, 1, 29.0, 0.0, &"bullet_ring", {
		"from_boss": true, "count": 8, "speed": 195.0, "angle_offset": 0.15, "shape": &"orb",
	})


# ------------------------------------------------------------------------------
# PHASE 2 (Beats 32-63, 15-30s): FROZEN_DOUBLE_TAKE / CONDUCTOR
# Beats 32-35 (Bar 8 dropout): ZERO lethal impacts!
# Beat 36 (Bar 9 HARD DROP): lead_beats=2.5 -> shallower twin outer pistons (reach=165) + 1 slow ring.
# Beats 40, 44, 48, 52: 4-beat spaced wall slams (lead_beats=2.25) with 6-8 slow bullets (speed=210).
# Beat 56: ONE clean standalone 2-way slow beam scissors (lead_beats=2.5).
# Beat 60.5: ONE clean pincer clap (lead_beats=2.25).
# ------------------------------------------------------------------------------
static func _append_phase_2(cues: Array[Dictionary]) -> void:
	_add(cues, 2, 32.0, 0.0, &"phase_transition", {
		"acting": 1, # FROZEN_DOUBLE_TAKE
		"form": 0, # CONDUCTOR
		"target": Vector2(576.0, 152.0),
		"move_speed": 7.5,
		"clear_hazards": true,
	}, -10)

	# Bar 9 HARD DROP (beat 36.0, telegraphs begin at beat 33.5; wide 822px center safe zone!)
	_add(cues, 2, 36.0, 2.5, &"piston_wall", {
		"side": &"left", "span_start": 0.0, "span_end": 648.0, "reach": 165.0,
		"slam_time": 0.14, "hold_time": 0.40, "retract_time": 0.28,
	})
	_add(cues, 2, 36.0, 2.5, &"piston_wall", {
		"side": &"right", "span_start": 0.0, "span_end": 648.0, "reach": 165.0,
		"slam_time": 0.14, "hold_time": 0.40, "retract_time": 0.28,
	})
	_add(cues, 2, 36.0, 2.5, &"shockwave_ring", {
		"origin": Vector2(576.0, 152.0), "start_radius": 34.0, "end_radius": 840.0,
		"thickness": 26.0, "travel_time": 1.65, "parryable": true,
	})

	# Cleanly spaced 4-wall slams every 4 beats (40, 44, 48, 52) with 6-8 slow bullets (speed=210)
	_add(cues, 2, 40.0, 2.25, &"wall_slam", {"is_left": true, "side": &"left", "coord": 410.0, "strength": 0.80})
	_add(cues, 2, 40.0, 0.0, &"bullet_ring", {"origin": Vector2(54.0, 410.0), "count": 8, "speed": 210.0, "angle_offset": 0.0, "shape": &"orb"})

	_add(cues, 2, 44.0, 2.25, &"wall_slam", {"is_left": false, "side": &"right", "coord": 300.0, "strength": 0.80})
	_add(cues, 2, 44.0, 0.0, &"bullet_ring", {"origin": Vector2(1098.0, 300.0), "count": 8, "speed": 210.0, "angle_offset": 0.25, "shape": &"orb"})

	_add(cues, 2, 48.0, 2.25, &"wall_slam", {"is_left": true, "side": &"bottom", "coord": 360.0, "strength": 0.84})
	_add(cues, 2, 48.0, 0.0, &"bullet_fan", {"origin": Vector2(360.0, 600.0), "dir": Vector2.UP, "count": 6, "step_angle": 0.24, "speed": 210.0, "shape": &"diamond"})

	_add(cues, 2, 52.0, 2.25, &"wall_slam", {"is_left": false, "side": &"top", "coord": 792.0, "strength": 0.84})
	_add(cues, 2, 52.0, 0.0, &"bullet_fan", {"origin": Vector2(792.0, 64.0), "dir": Vector2.DOWN, "count": 6, "step_angle": 0.24, "speed": 210.0, "shape": &"orb"})

	# Beat 56: ONE clean standalone 2-way slow beam scissors
	_add(cues, 2, 56.0, 2.5, &"sweeping_beam", {
		"origin": Vector2(576.0, 324.0), "angle": 0.38, "beam_count": 1,
		"width": BossConstants.BEAM_WIDTH, "active_time": 1.25, "angular_speed": 0.26,
	})
	_add(cues, 2, 56.0, 2.5, &"sweeping_beam", {
		"origin": Vector2(576.0, 324.0), "angle": -0.38, "beam_count": 1,
		"width": BossConstants.BEAM_WIDTH, "active_time": 1.25, "angular_speed": -0.26,
	})

	# Beat 60.5: Clean pincer clap
	_add(cues, 2, 60.5, 2.25, &"pincer", {"mid": Vector2(576.0, 360.0), "clap_time": 0.18})
	_add(cues, 2, 61.0, 0.0, &"bullet_ring", {"from_boss": true, "count": 8, "speed": 205.0, "angle_offset": 0.2, "shape": &"orb"})


# ------------------------------------------------------------------------------
# PHASE 3 (Beats 64-95, 30-45s): FLOOR_SLAM_TANTRUM / SPIKE_ROLL
# Beat 66.0 (telegraphed for 2.0 full beats from beat 64.0): twin hand floor slam + slow shockwave ring.
# Act 3A (Beats 67-80): Spike-Roll showcase — 10-spike orbit ring (lead_beats=2.0, angular_speed=2.1)
#   + 2 clean rolling dashes on beats 70 & 76 (lead_beats=2.5, dash_time=0.72s) with gentle tangential bullets.
# Act 3B (Beats 81-94): Boss parks top; 3 rhythmic ceiling-spike curtains (beats 83, 87, 91,
#   lead_beats=2.5, fall_speed=360.0, safe_half_width=105.0) + 2 border snappers + 1 piston on beat 93.
# ------------------------------------------------------------------------------
static func _append_phase_3(cues: Array[Dictionary]) -> void:
	_add(cues, 3, 64.0, 0.0, &"phase_transition", {
		"acting": 2, # FLOOR_SLAM_TANTRUM
		"form": 0, # CONDUCTOR momentarily for twin hand slam
		"target": Vector2(576.0, 190.0),
		"move_speed": 8.0,
	}, -10)

	# Twin floor slam + shockwave ring with a full 2.0-beat (0.94s) telegraph starting at beat 64.0
	_add(cues, 3, 66.0, 2.0, &"shockwave_ring", {
		"origin": Vector2(576.0, 450.0), "start_radius": 34.0, "end_radius": 840.0,
		"thickness": 28.0, "travel_time": 1.60, "parryable": true,
	})
	_add(cues, 3, 66.0, 2.0, &"floor_slam", {"is_left": true, "target": Vector2(410.0, 455.0), "strike_time": 0.16})
	_add(cues, 3, 66.0, 2.0, &"floor_slam", {"is_left": false, "target": Vector2(742.0, 455.0), "strike_time": 0.16})
	_add(cues, 3, 66.0, 0.0, &"bullet_ring", {"origin": Vector2(576.0, 455.0), "count": 8, "speed": 210.0, "angle_offset": 0.0, "shape": &"spike"})

	# Act 3A (Beats 67-80): SPIKE_ROLL showcase (NO ceiling spikes falling at the same time!)
	_add(cues, 3, 67.0, 0.0, &"form_change", {
		"acting": 2, # FLOOR_SLAM_TANTRUM
		"form": 1, # SPIKE_ROLL
		"target": Vector2(180.0, 220.0),
		"move_speed": 8.5,
	}, -5)
	_add(cues, 3, 69.0, 2.0, &"spike_ring", {
		"mode": BossSpikeRing.RingMode.ORBIT_RING,
		"follow_boss": true, "count": 10, "start_radius": 76.0, "end_radius": 76.0,
		"spike_radius": 17.0, "angular_speed": 2.1, "duration": 11.5 * BEAT,
	})

	# 2 clean telegraphed rolling dashes on beats 70 & 76 (lead_beats=2.5, dash_time=0.72s)
	_add(cues, 3, 70.0, 2.5, &"body_lunge", {
		"from": Vector2(180.0, 220.0), "to": Vector2(972.0, 220.0), "dash_time": 0.72, "emit_slam": true,
	})
	_add(cues, 3, 76.0, 2.5, &"body_lunge", {
		"from": Vector2(972.0, 220.0), "to": Vector2(180.0, 470.0), "dash_time": 0.72, "emit_slam": true,
	})

	# Act 3B (Beats 81-94): Boss parks top; Ceiling-Spike Rain + 2 Border Snappers + 1 Piston
	_add(cues, 3, 80.5, 0.0, &"body_move", {"target": Vector2(576.0, 168.0), "speed": 7.5})

	_add(cues, 3, 83.0, 2.5, &"ceiling_spike", {
		"from_top": true, "count": 10, "safe_lane_x": 576.0, "safe_half_width": 105.0,
		"fall_speed": 360.0, "cascade_delay": 0.035,
	})
	_add(cues, 3, 85.0, 2.25, &"beat_minion", {
		"type": BossConstants.MinionType.BORDER_SNAPPER, "pos": Vector2(0.0, 350.0),
		"lifetime_beats": 6, "params": {"side": &"left", "leap_depth": 165.0, "bullet_speed": 215.0},
	})
	_add(cues, 3, 87.0, 2.5, &"ceiling_spike", {
		"from_top": true, "count": 10, "safe_lane_x": 820.0, "safe_half_width": 105.0,
		"fall_speed": 360.0, "cascade_delay": 0.035,
	})
	_add(cues, 3, 89.0, 2.25, &"beat_minion", {
		"type": BossConstants.MinionType.BORDER_SNAPPER, "pos": Vector2(1152.0, 350.0),
		"lifetime_beats": 6, "params": {"side": &"right", "leap_depth": 165.0, "bullet_speed": 215.0},
	})
	_add(cues, 3, 91.0, 2.5, &"ceiling_spike", {
		"from_top": true, "count": 10, "safe_lane_x": 340.0, "safe_half_width": 105.0,
		"fall_speed": 360.0, "cascade_delay": 0.035,
	})
	_add(cues, 3, 93.0, 2.25, &"piston_wall", {
		"side": &"bottom", "span_start": 0.0, "span_end": 1152.0, "reach": 165.0,
		"slam_time": 0.14, "hold_time": 0.38, "retract_time": 0.28,
	})


# ------------------------------------------------------------------------------
# PHASE 4 (Beats 96-127, 45-60s): ACCUSING_POINT / WHEEL_CORE
# Center lock + BORDER_CAGE BossSpikeRing patrolling perimeter (lead_beats=2.25).
# Beats 99-116: 4-way rotating laser wheel (lead_beats=2.5, angular_speed=0.42) REVERSING on Beat 112!
# Paired with readable radial bursts + high-voltage tether sweeps + 3 jaw lunges (lead_beats=2.0-2.25).
# ------------------------------------------------------------------------------
static func _append_phase_4(cues: Array[Dictionary]) -> void:
	_add(cues, 4, 96.0, 0.0, &"phase_transition", {
		"acting": 3, # ACCUSING_POINT
		"form": 2, # WHEEL_CORE
		"target": Vector2(576.0, 324.0),
		"move_speed": 8.0,
	}, -10)

	# Perimeter BORDER_CAGE patrolling all 4 walls and corners (2.25-beat telegraph)
	_add(cues, 4, 98.5, 2.25, &"spike_ring", {
		"mode": BossSpikeRing.RingMode.BORDER_CAGE,
		"margin": 42.0, "spike_radius": 18.0, "speed": 155.0, "duration": 19.5 * BEAT,
	})

	# Rotating 4-way laser wheel (2.5-beat telegraph; reverses on EXACT Beat 112.0 = 99.0 + 13.0)
	_add(cues, 4, 99.0, 2.5, &"sweeping_beam", {
		"origin": Vector2(576.0, 324.0), "angle": 0.24, "beam_count": 2,
		"width": BossConstants.WHEEL_BEAM_WIDTH, "active_time": 17.0 * BEAT,
		"angular_speed": 0.42, "reverse_at_active_time": 13.0 * BEAT,
	})

	# Readable 10-particle radial bursts on beats 100, 104, 108
	_add(cues, 4, 100.0, 0.0, &"bullet_ring", {"origin": Vector2(576.0, 324.0), "count": 10, "speed": 220.0, "angle_offset": 0.00, "shape": &"orb"})
	_add(cues, 4, 104.0, 0.0, &"bullet_ring", {"origin": Vector2(576.0, 324.0), "count": 10, "speed": 220.0, "angle_offset": 0.31, "shape": &"diamond"})
	_add(cues, 4, 108.0, 0.0, &"bullet_ring", {"origin": Vector2(576.0, 324.0), "count": 10, "speed": 225.0, "angle_offset": 0.15, "shape": &"needle"})

	# Bar 25 sweeping high-voltage tether (2.0-beat telegraph, active across beat 101..104.5 / t=47.3..49.0s)
	_add(cues, 4, 101.0, 2.0, &"tether_sweep", {"start_y": 150.0, "end_y": 500.0, "sweep_time": 3.5 * BEAT})

	# Bar 28 (Beat 112.0) Laser Wheel Reverse Drop (2.25-beat shockwave telegraph, reduced bullet overlap)
	_add(cues, 4, 112.0, 0.0, &"white_flash", {"amount": 0.72})
	_add(cues, 4, 112.0, 0.0, &"bullet_ring", {"origin": Vector2(576.0, 324.0), "count": 10, "speed": 220.0, "angle_offset": 0.0, "shape": &"spike"})
	_add(cues, 4, 112.0, 2.25, &"shockwave_ring", {
		"origin": Vector2(576.0, 324.0), "start_radius": 34.0, "end_radius": 780.0,
		"thickness": 26.0, "travel_time": 1.50, "parryable": true,
	})

	# Bar 29 pullback tether sweep (2.0-beat telegraph)
	_add(cues, 4, 116.5, 2.0, &"tether_sweep", {"start_y": 495.0, "end_y": 175.0, "sweep_time": 1.5 * BEAT})

	# Beats 118.5, 122.5, 126.0: 3 beat-synced boss jaw-lunges with 2.0-2.25 beat telegraphs
	_add(cues, 4, 118.5, 2.25, &"body_lunge", {
		"from": Vector2(160.0, 190.0), "to": Vector2(992.0, 190.0), "dash_time": 0.56, "emit_slam": true,
	})
	_add(cues, 4, 119.0, 2.25, &"sweeping_beam", {
		"origin": Vector2(576.0, 190.0), "angle": 0.0, "beam_count": 1,
		"width": 24.0, "active_time": 0.36,
	})

	_add(cues, 4, 122.5, 2.25, &"body_lunge", {
		"from": Vector2(992.0, 520.0), "to": Vector2(160.0, 520.0), "dash_time": 0.56, "emit_slam": true,
	})
	_add(cues, 4, 123.0, 2.25, &"sweeping_beam", {
		"origin": Vector2(576.0, 520.0), "angle": 0.0, "beam_count": 1,
		"width": 24.0, "active_time": 0.36,
	})

	_add(cues, 4, 126.0, 2.0, &"body_lunge", {
		"aim_player": true, "dash_time": 0.54, "emit_slam": true,
	})
	_add(cues, 4, 126.25, 2.0, &"sweeping_beam", {
		"aim_player": true, "beam_count": 1, "width": 24.0, "active_time": 0.34,
	})


# ------------------------------------------------------------------------------
# PHASE 5 (Beats 128-159, 60-75s): FAKE_OUT_COLLAPSE / MARIONETTE
# Beat 128: white flash, clear hazards, boss collapses non-hazardous at bottom; hands dormant until b136.
# Beats 132-151: 3 spaced BossHexGrid waves + b136 hands wake + 3 THREAD_SPIDERs (8-ring) + 3 hand swipes.
# Beats 156-157 (Bar 39 b28-29): TRUE DIGITAL SILENCE (ZERO lethal hits) while 8-beam star +
#   supernova shockwave telegraph for 2.0 beats -> DETONATE ON EXACT BEAT 158.0!
# ------------------------------------------------------------------------------
static func _append_phase_5(cues: Array[Dictionary]) -> void:
	_add(cues, 5, 128.0, 0.0, &"phase_transition", {
		"acting": 4, # FAKE_OUT_COLLAPSE
		"form": 3, # MARIONETTE
		"target": Vector2(576.0, 540.0),
		"move_speed": 6.0,
		"clear_hazards": true,
		"white_flash": 1.0,
	}, -10)

	# 3 spaced, readable BossHexGrid waves (all finish cleanly before Bar 39 Beat 156 silence)
	_add(cues, 5, 132.0, 2.25, &"hex_grid", {
		"pattern": BossConstants.HexPattern.CORRIDOR_H, "active_time": 0.40, "cascade_step": 0.04,
		"params": {"safe_center": 324.0, "safe_half_width": 115.0},
	})

	# Beat 136 (Beat 8 of Phase 5): puppet-string claw hands wake!
	_add(cues, 5, 136.0, 0.0, &"phase5_wake_hands", {}, -5)

	# 3 well-spaced THREAD_SPIDER minions descending on dotted threads (built-in 8-bullet burst)
	_add(cues, 5, 137.0, 2.0, &"beat_minion", {
		"type": BossConstants.MinionType.THREAD_SPIDER, "pos": Vector2(280.0, 240.0),
		"lifetime_beats": 5, "params": {"from_top": true, "drop_y": 240.0, "burst_beat": 2, "bullet_count": 8, "bullet_speed": 195.0},
	})
	_add(cues, 5, 138.0, 2.0, &"hand_dash", {
		"is_left": true, "from": Vector2(120.0, 210.0), "to": Vector2(1032.0, 370.0),
		"dash_time": 0.56, "style": 1, # CLAW_SWIPE
	})
	_add(cues, 5, 140.0, 2.25, &"hex_grid", {
		"pattern": BossConstants.HexPattern.CHECKER_A, "active_time": 0.38, "cascade_step": 0.03,
	})
	_add(cues, 5, 143.0, 2.0, &"beat_minion", {
		"type": BossConstants.MinionType.THREAD_SPIDER, "pos": Vector2(576.0, 290.0),
		"lifetime_beats": 5, "params": {"from_top": true, "drop_y": 290.0, "burst_beat": 2, "bullet_count": 8, "bullet_speed": 195.0},
	})
	_add(cues, 5, 144.0, 2.0, &"hand_dash", {
		"is_left": false, "from": Vector2(1032.0, 210.0), "to": Vector2(120.0, 370.0),
		"dash_time": 0.56, "style": 1, # CLAW_SWIPE
	})
	_add(cues, 5, 146.0, 2.25, &"hex_grid", {
		"pattern": BossConstants.HexPattern.CHECKER_B, "active_time": 0.38, "cascade_step": 0.03,
	})
	_add(cues, 5, 149.0, 2.0, &"beat_minion", {
		"type": BossConstants.MinionType.THREAD_SPIDER, "pos": Vector2(872.0, 240.0),
		"lifetime_beats": 5, "params": {"from_top": true, "drop_y": 240.0, "burst_beat": 2, "bullet_count": 8, "bullet_speed": 195.0},
	})
	_add(cues, 5, 150.5, 2.0, &"hand_dash", {
		"is_left": true, "from": Vector2(120.0, 470.0), "to": Vector2(1032.0, 470.0),
		"dash_time": 0.54, "style": 2, # FLOOR_RAKE
	})

	# Beats 152-155: boss drifts to center inflating
	_add(cues, 5, 152.0, 0.0, &"body_move", {"target": Vector2(576.0, 324.0), "speed": 5.5})
	_add(cues, 5, 153.0, 0.0, &"silence_freeze", {"frozen": false, "inflate": 0.48, "clear_hazards": false})

	# Beats 156-157 (Bar 39 b28-29): TRUE DIGITAL SILENCE — clear all prior hazards FIRST (priority -10)!
	_add(cues, 5, 156.0, 0.0, &"silence_freeze", {"frozen": true, "inflate": 1.0, "clear_hazards": true}, -10)

	# Beat 158.0 (74.0625s) SUPERNOVA DROP — 2.0-beat telegraph starts at Beat 156.0 AFTER silence_freeze!
	_add(cues, 5, 158.0, 2.0, &"sweeping_beam", {
		"origin": Vector2(576.0, 324.0), "angle": 0.0, "beam_count": 4, # 4 through-lines = 8-beam star!
		"width": 24.0, "active_time": 0.58,
	}, 0)
	_add(cues, 5, 158.0, 2.0, &"shockwave_ring", {
		"origin": Vector2(576.0, 324.0), "start_radius": 36.0, "end_radius": 860.0,
		"thickness": 32.0, "travel_time": 1.40, "parryable": true,
	}, 0)
	_add(cues, 5, 158.0, 0.0, &"supernova_drop", {
		"origin": Vector2(576.0, 324.0), "bullet_count": 24, "bullet_speed": 235.0,
	}, 1)


# ------------------------------------------------------------------------------
# PHASE 6 (Beats 160-191, 75-90s): HOLLOW_REBIRTH / TRIPLE_CANNON
# Center BossGravityWell (b162-186, pulsing rings every 4 beats).
# 4-beat teleports (b160, 164, 168, 172, 176, 180, 184, 188) + Triple-Cannon bursts + 24-rings.
# 6 ORBIT_SPECTER minions orbiting perimeter + edge piston accents.
# ------------------------------------------------------------------------------
static func _append_phase_6(cues: Array[Dictionary]) -> void:
	_add(cues, 6, 160.0, 0.0, &"phase_transition", {
		"acting": 5, # HOLLOW_REBIRTH
		"form": 4, # TRIPLE_CANNON
		"target": Vector2(576.0, 132.0),
		"move_speed": 8.0,
	}, -10)

	# Center BossGravityWell (active beats 162..186 = 24 beats = 11.25s)
	_add(cues, 6, 162.0, 2.0, &"gravity_well", {
		"origin": Vector2(576.0, 324.0), "core_radius": 24.0, "pull_radius": 460.0,
		"max_pull_offset": 72.0, "pull_speed": 135.0, "duration": 24.0 * BEAT,
	})

	# 6 ORBIT_SPECTER minions spaced 60 deg around arena (2.0-beat telegraph, fair bullet speed)
	for i: int in range(6):
		var start_a: float = float(i) * TAU / 6.0
		var spawn_p: Vector2 = Vector2(576.0, 324.0) + Vector2.from_angle(start_a) * 265.0
		_add(cues, 6, 164.0, 2.0, &"beat_minion", {
			"type": BossConstants.MinionType.ORBIT_SPECTER, "pos": spawn_p,
			"lifetime_beats": 22, "params": {
				"orbit_center": Vector2(576.0, 324.0), "orbit_radius": 265.0,
				"start_angle": start_a, "angular_step": PI / 6.0, "angular_speed": 0.42,
				"bullet_speed": 235.0, "aim_player": (i % 2 == 0),
			},
		})

	# Beat-cut teleports on 4-beat cuts + Triple-Cannon rotations & unison bursts
	var anchors: Array[Vector2] = [
		Vector2(576.0, 132.0), # b160
		Vector2(960.0, 176.0), # b164
		Vector2(960.0, 480.0), # b168
		Vector2(576.0, 516.0), # b172
		Vector2(192.0, 480.0), # b176
		Vector2(192.0, 176.0), # b180
		Vector2(576.0, 144.0), # b184
		Vector2(576.0, 324.0), # b188
	]
	for idx: int in range(anchors.size()):
		var cut_beat: float = 160.0 + float(idx) * 4.0
		var cannon_ang: float = float(idx) * 0.55
		if idx > 0:
			_add(cues, 6, cut_beat, 0.0, &"teleport", {
				"to": anchors[idx], "arrival_grace": 0.35, "cannon_angle": cannon_ang,
			})
		# Triple-cannon unison burst 2 beats after each teleport (fair 240 px/s speed)
		_add(cues, 6, cut_beat + 2.0, 0.0, &"triple_cannon_burst", {
			"cannon_angle": cannon_ang + 0.28, "fan_count": 3, "step_angle": 0.24,
			"speed": 240.0, "shape": &"needle",
		})
		# 24-particle ring bursts on beats 168.5, 176.5, 184.5 (fair 230 px/s speed)
		if idx in [2, 4, 6]:
			_add(cues, 6, cut_beat + 0.5, 0.0, &"bullet_ring", {
				"from_boss": true, "count": 20, "speed": 230.0, "angle_offset": cannon_ang, "shape": &"orb",
			})

	# Edge piston accents during Phase 6 (2.25-beat telegraphs)
	_add(cues, 6, 170.0, 2.25, &"piston_wall", {
		"side": &"left", "span_start": 0.0, "span_end": 324.0, "reach": 175.0,
		"slam_time": 0.14, "hold_time": 0.35, "retract_time": 0.26,
	})
	_add(cues, 6, 178.0, 2.25, &"piston_wall", {
		"side": &"right", "span_start": 324.0, "span_end": 648.0, "reach": 175.0,
		"slam_time": 0.14, "hold_time": 0.35, "retract_time": 0.26,
	})
	_add(cues, 6, 186.0, 2.25, &"piston_wall", {
		"side": &"bottom", "span_start": 280.0, "span_end": 872.0, "reach": 160.0,
		"slam_time": 0.14, "hold_time": 0.35, "retract_time": 0.26,
	})


# ------------------------------------------------------------------------------
# PHASE 7 (Beats 192-223, 90-105s): EXHAUSTED_PANTING / STOMP_COLOSSUS
# Half-Time Industrial Stomp Groove:
#   - Every Beat 0 (192, 196, 200, 204, 208, 212, 216, 220) = HEAVY STOMP:
#     alternating H/V BossShockwaveRing TIDAL_WAVE (gap=160px, parryable) + pistons/wall slams.
#   - Every Beat 2 (194, 198, 202, 206, 210, 214, 218, 222) = CRISP SNARE:
#     BossHexGrid CORRIDOR_H/V / CHECKER + claw swipes / pincer + surgical 4-way beam snaps.
#   - Odd-bar beat 1.5 pickup (197.5, 205.5, 213.5, 221.5): 8-particle mouth burst (235 px/s).
# ------------------------------------------------------------------------------
static func _append_phase_7(cues: Array[Dictionary]) -> void:
	_add(cues, 7, 192.0, 0.0, &"phase_transition", {
		"acting": 6, # EXHAUSTED_PANTING
		"form": 5, # STOMP_COLOSSUS
		"target": Vector2(576.0, 168.0),
		"move_speed": 6.8,
	}, -10)

	var tidal_sides: Array[StringName] = [&"left", &"top", &"right", &"bottom", &"left", &"bottom", &"right", &"top"]
	var tidal_gaps: Array[float] = [324.0, 576.0, 240.0, 760.0, 440.0, 380.0, 280.0, 620.0]
	var slam_sides: Array[StringName] = [&"left", &"right", &"bottom", &"top"]
	var hex_cycle: Array[int] = [
		BossConstants.HexPattern.CORRIDOR_H,
		BossConstants.HexPattern.CORRIDOR_V,
		BossConstants.HexPattern.CHECKER_A,
		BossConstants.HexPattern.CORRIDOR_H,
		BossConstants.HexPattern.CORRIDOR_V,
		BossConstants.HexPattern.CHECKER_B,
		BossConstants.HexPattern.CORRIDOR_H,
		BossConstants.HexPattern.WAVE_TB,
	]

	for bar: int in range(8):
		var b0: float = 192.0 + float(bar) * 4.0
		var b2: float = b0 + 2.0
		var side: StringName = tidal_sides[bar]
		var gap_c: float = tidal_gaps[bar]

		# BEAT 0: HEAVY STOMP -> Parryable Tidal Wave + Piston or Wall Slam
		_add(cues, 7, b0, 2.0 if bar > 0 else 1.75, &"tidal_wave", {
			"side": side, "thickness": 30.0, "gap_center": gap_c, "gap_size": 160.0,
			"travel_time": 1.48, "parryable": true,
		})
		if bar % 2 == 0:
			var p_side: StringName = &"left" if (bar % 4 == 0) else &"right"
			_add(cues, 7, b0, 2.0 if bar > 0 else 1.75, &"piston_wall", {
				"side": p_side, "span_start": 160.0, "span_end": 520.0, "reach": 175.0,
				"slam_time": 0.14, "hold_time": 0.34, "retract_time": 0.26,
			})
		else:
			var ws_idx: int = (bar / 2) % 4
			var ws_side: StringName = slam_sides[ws_idx]
			var ws_coord: float = 340.0 if (ws_side == &"left" or ws_side == &"right") else 576.0
			_add(cues, 7, b0, 1.75, &"wall_slam", {
				"is_left": (ws_idx % 2 == 0), "side": ws_side, "coord": ws_coord, "strength": 0.88,
			})

		# BEAT 2: CRISP SNARE -> HexGrid + Hand Strike / 4-way Beam Snap
		var h_pat: int = hex_cycle[bar]
		var h_params: Dictionary = {}
		if h_pat == BossConstants.HexPattern.CORRIDOR_H:
			h_params = {"safe_center": 324.0 if (bar % 4 == 0) else 440.0, "safe_half_width": 102.0}
		elif h_pat == BossConstants.HexPattern.CORRIDOR_V:
			h_params = {"safe_center": 576.0 if (bar % 4 == 1) else 380.0, "safe_half_width": 102.0}
		_add(cues, 7, b2, 2.0, &"hex_grid", {
			"pattern": h_pat, "active_time": 0.38, "cascade_step": 0.035, "params": h_params,
		})

		if bar % 2 == 0:
			_add(cues, 7, b2, 1.75, &"sweeping_beam", {
				"origin": Vector2(576.0, 324.0), "angle": 0.0 if (bar % 4 == 0) else PI * 0.25,
				"beam_count": 2, "width": 24.0, "active_time": 0.38,
			})
		else:
			if bar == 3:
				_add(cues, 7, b2, 1.75, &"pincer", {"mid": Vector2(576.0, 360.0), "clap_time": 0.18})
			else:
				var ws_idx_odd: int = (bar / 2) % 4
				var dash_left: bool = (ws_idx_odd % 2 != 0) # Opposite hand from bar's b0 wall_slam!
				_add(cues, 7, b2, 1.75, &"hand_dash", {
					"is_left": dash_left,
					"from": Vector2(110.0, 340.0) if dash_left else Vector2(1042.0, 480.0),
					"to": Vector2(1042.0, 340.0) if dash_left else Vector2(110.0, 480.0),
					"dash_time": 0.52, "style": 1 if (bar != 7) else 2,
				})

		# Odd-bar beat 1.5 syncopated pickup (197.5, 205.5, 213.5, 221.5): 8-particle mouth burst
		if bar % 2 == 1:
			_add(cues, 7, b0 + 1.5, 0.0, &"mouth_burst", {
				"count": 8, "speed": 235.0, "angle_offset": float(bar) * 0.35, "shape": &"diamond",
			})


# ------------------------------------------------------------------------------
# PHASE 8 (Beats 224-255, 105-120s): TEMPLE_CLUTCH_PANIC / OVERDRIVE_PANIC -> SILENT_SHATTER
# Beats 224-239: tightening BossSpikeRing + 6-beam wheel + 4-wall pinball slams + BORDER_RING hex.
# Bar 58 (Beat 232.0, telegraphed b230.0): CHROMATIC GLITCH WAVE #1 (L->R)!
# Beats 240-243 (Bar 60 dip): sweeping tether + 16-particle spiral breathing pocket.
# Beats 244-247: rapid 4-wall slams + hex wave.
# Bar 62 Finale (Beats 248-251): 4 escalating parryable shockwaves + CHROMATIC GLITCH WAVE #2 (R->L)!
# Beat 252 (118.125s): SILENT_SHATTER — clear ALL active hazards!
# ------------------------------------------------------------------------------
static func _append_phase_8(cues: Array[Dictionary]) -> void:
	_add(cues, 8, 224.0, 0.0, &"phase_transition", {
		"acting": 7, # TEMPLE_CLUTCH_PANIC
		"form": 6, # OVERDRIVE_PANIC
		"target": Vector2(576.0, 324.0),
		"move_speed": 9.0,
	}, -10)

	# Tightening outer BossSpikeRing orbit cage (1.75-beat telegraph starting at b224.0)
	_add(cues, 8, 225.75, 1.75, &"spike_ring", {
		"mode": BossSpikeRing.RingMode.ORBIT_RING,
		"origin": Vector2(576.0, 324.0), "follow_boss": false, "count": 12,
		"start_radius": 325.0, "end_radius": 242.0, "spike_radius": 17.0,
		"angular_speed": 1.25, "duration": 13.5 * BEAT,
	})

	# 6-beam rotating panic wheel (2.0-beat telegraph, smooth 0.34 rad/s rotation)
	_add(cues, 8, 226.0, 2.0, &"sweeping_beam", {
		"origin": Vector2(576.0, 324.0), "angle": 0.12, "beam_count": 3,
		"width": BossConstants.WHEEL_BEAM_WIDTH, "active_time": 12.0 * BEAT,
		"angular_speed": 0.34,
	})

	# 4-wall pinball slams + radial bursts + BORDER_RING hex squeezes
	_add(cues, 8, 226.0, 1.75, &"wall_slam", {"is_left": true, "side": &"left", "coord": 260.0, "strength": 0.90})
	_add(cues, 8, 228.0, 1.75, &"wall_slam", {"is_left": false, "side": &"right", "coord": 420.0, "strength": 0.90})
	_add(cues, 8, 228.0, 0.0, &"bullet_ring", {"origin": Vector2(576.0, 324.0), "count": 20, "speed": 245.0, "angle_offset": 0.0, "shape": &"orb"})
	_add(cues, 8, 228.0, 2.0, &"hex_grid", {
		"pattern": BossConstants.HexPattern.BORDER_RING, "active_time": 0.42, "cascade_step": 0.03,
		"params": {"depth": 1},
	})

	# SIGNATURE SPECIAL #1 — Bar 58 (Beat 232.0, 108.75s, telegraphed at b230.0): CHROMATIC GLITCH WAVE L->R!
	_add(cues, 8, 232.0, 2.0, &"glitch_wave", {
		"direction": Vector2.RIGHT, "sweep_time": 1.65, "wave_thickness": 74.0,
		"gap_center_ratio": 0.52, "gap_size": 156.0, "gap_wobble": 58.0, "parryable": true,
	})

	_add(cues, 8, 234.0, 1.75, &"wall_slam", {"is_left": true, "side": &"top", "coord": 440.0, "strength": 0.92})
	_add(cues, 8, 236.0, 0.0, &"bullet_ring", {"origin": Vector2(576.0, 324.0), "count": 20, "speed": 250.0, "angle_offset": 0.18, "shape": &"spike"})
	_add(cues, 8, 236.0, 2.0, &"hex_grid", {
		"pattern": BossConstants.HexPattern.BORDER_RING, "active_time": 0.42, "cascade_step": 0.03,
		"params": {"depth": 1},
	})
	_add(cues, 8, 238.0, 1.75, &"wall_slam", {"is_left": false, "side": &"bottom", "coord": 710.0, "strength": 0.92})

	# Bar 60 (Beats 240-243) eye-of-the-storm dip: sweeping tether (1.75-beat telegraph) + 16-particle spirals
	_add(cues, 8, 240.5, 1.75, &"tether_sweep", {"start_y": 170.0, "end_y": 490.0, "sweep_time": 1.75 * BEAT})
	_add(cues, 8, 240.0, 0.0, &"bullet_ring", {"origin": Vector2(576.0, 324.0), "count": 16, "speed": 235.0, "angle_offset": 0.12, "shape": &"diamond"})
	_add(cues, 8, 242.0, 0.0, &"bullet_ring", {"origin": Vector2(576.0, 324.0), "count": 16, "speed": 240.0, "angle_offset": 0.36, "shape": &"orb"})

	# Bar 61 (Beats 244-247): rapid 4-wall slams (1.65-beat telegraphs) + hex wave
	_add(cues, 8, 244.0, 1.65, &"wall_slam", {"is_left": true, "side": &"left", "coord": 360.0, "strength": 0.94})
	_add(cues, 8, 245.0, 1.65, &"wall_slam", {"is_left": false, "side": &"right", "coord": 360.0, "strength": 0.94})
	_add(cues, 8, 245.0, 2.0, &"hex_grid", {
		"pattern": BossConstants.HexPattern.WAVE_LR, "active_time": 0.36, "cascade_step": 0.032,
	})
	_add(cues, 8, 246.0, 1.65, &"wall_slam", {"is_left": true, "side": &"bottom", "coord": 420.0, "strength": 0.94})
	_add(cues, 8, 247.0, 1.65, &"wall_slam", {"is_left": false, "side": &"top", "coord": 730.0, "strength": 0.96})

	# Bar 62 Finale Countdown (Beats 248-251): 4 escalating parryable shockwaves + CHROMATIC GLITCH WAVE #2 (R->L)!
	_add(cues, 8, 248.0, 2.0, &"glitch_wave", {
		"direction": Vector2.LEFT, "sweep_time": 1.60, "wave_thickness": 74.0,
		"gap_center_ratio": 0.44, "gap_size": 156.0, "gap_wobble": 58.0, "parryable": true,
	})
	for k: int in range(4):
		_add(cues, 8, 248.0 + float(k), 1.75, &"shockwave_ring", {
			"origin": Vector2(576.0, 324.0), "start_radius": 34.0, "end_radius": 860.0,
			"thickness": 26.0 + float(k) * 2.0, "travel_time": 1.35, "parryable": true,
		})

	# Beat 252.0 (118.125s): SILENT_SHATTER — clear ALL active hazards immediately!
	_add(cues, 8, 252.0, 0.0, &"silent_shatter", {}, -10)
