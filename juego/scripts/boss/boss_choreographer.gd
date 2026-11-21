class_name BossChoreographer
extends RefCounted

# Continuous audio-clock lead-beat scheduler and dispatcher for "The Architect".
# Drives from song_beat = song_time / BossConstants.BEAT_DURATION so every beam snap,
# shockwave, piston slam, tidal wave, hex pattern, ceiling spike, wall slam, and
# Chromatic Glitch Wave impacts on the exact musical beat.

var executed_cues: int = 0
var seen_hazard_kinds: Dictionary = {}
var seen_forms: Dictionary = {}
var glitch_waves_spawned: int = 0
var last_beat_idx: int = -1
var last_song_beat: float = 0.0

var _level: Node2D = null
var _boss: Node = null
var _beam_container: Node2D = null
var _hex_grid: BossHexGrid = null
var _bullet_manager: BossBulletManager = null
var _arena_fx: Node2D = null
var _arena_grid: Node2D = null

var _cues: Array[Dictionary] = []
var _cursor: int = 0

var _active_wells: Array[BossGravityWell] = []
var _active_spike_rings: Array[BossSpikeRing] = []
var _active_minions: Array[BossBeatMinion] = []
var _active_glitch_waves: Array[BossGlitchWave] = []
var _orbit_spike_ring: BossSpikeRing = null


func setup(
	level: Node2D,
	boss: Node,
	beam_container: Node2D,
	hex_grid: BossHexGrid,
	bullet_manager: BossBulletManager,
	arena_fx: Node2D,
	arena_grid: Node2D
) -> void:
	_level = level
	_boss = boss
	_beam_container = beam_container
	_hex_grid = hex_grid
	_bullet_manager = bullet_manager
	_arena_fx = arena_fx
	_arena_grid = arena_grid
	reset()


func reset() -> void:
	_cues = BossScore.build_score()
	_cursor = 0
	executed_cues = 0
	seen_hazard_kinds.clear()
	seen_forms.clear()
	glitch_waves_spawned = 0
	last_beat_idx = -1
	last_song_beat = 0.0
	clear_transient_refs()
	if _boss != null and "boss_form" in _boss:
		seen_forms[int(_boss.boss_form)] = true


func clear_transient_refs() -> void:
	_active_wells.clear()
	_active_spike_rings.clear()
	_active_minions.clear()
	_active_glitch_waves.clear()
	_orbit_spike_ring = null


func get_active_gravity_wells() -> Array[BossGravityWell]:
	var alive: Array[BossGravityWell] = []
	for well: BossGravityWell in _active_wells:
		if is_instance_valid(well) and not well.is_queued_for_deletion():
			alive.append(well)
	_active_wells = alive
	return alive


func purge_active_glitch_waves() -> int:
	var purged: int = 0
	var alive: Array[BossGlitchWave] = []
	for wave: BossGlitchWave in _active_glitch_waves:
		if is_instance_valid(wave) and not wave.is_queued_for_deletion():
			alive.append(wave)
			if wave.is_hazard_active:
				wave.purge_by_parry()
				purged += 1
	_active_glitch_waves = alive
	return purged


func advance(_delta: float, song_time: float, arena_size: Vector2, player: Node2D) -> void:
	var safe_arena: Vector2 = arena_size if (arena_size.x > 0.0 and arena_size.y > 0.0) else BossConstants.ARENA_REF
	var song_beat: float = maxf(song_time, 0.0) / BossConstants.BEAT_DURATION
	last_song_beat = song_beat

	while _cursor < _cues.size():
		var cue: Dictionary = _cues[_cursor]
		var trigger_beat: float = float(cue["trigger_beat"])
		if song_beat + 0.0001 < trigger_beat:
			break
		_cursor += 1
		executed_cues += 1
		_execute_cue(cue, song_beat, safe_arena, player)

	var cur_beat_idx: int = int(floor(song_beat))
	while last_beat_idx < cur_beat_idx:
		last_beat_idx += 1
		_on_beat_tick(last_beat_idx, safe_arena, player)


func _on_beat_tick(beat_idx: int, arena_size: Vector2, player: Node2D) -> void:
	_prune_transients()
	var player_pos: Vector2 = player.global_position if (player != null and is_instance_valid(player)) else (arena_size * 0.5)

	if _boss != null and is_instance_valid(_boss):
		var in_silence: bool = (beat_idx == 156 or beat_idx == 157 or beat_idx >= 252)
		if not in_silence and _boss.has_method(&"pulse_beat"):
			var strength: float = 1.0 if (beat_idx % 4 == 0) else 0.58
			_boss.pulse_beat(strength)
		if "boss_form" in _boss:
			seen_forms[int(_boss.boss_form)] = true

	for minion: BossBeatMinion in _active_minions:
		if is_instance_valid(minion) and not minion.is_queued_for_deletion():
			minion.on_beat(beat_idx, _bullet_manager, player_pos)

	for well: BossGravityWell in _active_wells:
		if is_instance_valid(well) and not well.is_queued_for_deletion():
			if well.is_hazard_active and beat_idx % 4 == 0:
				well.pulse_beat(_bullet_manager, 14, 235.0, float(beat_idx) * 0.22)
				seen_hazard_kinds[&"boss_bullets"] = true

	if _orbit_spike_ring != null and is_instance_valid(_orbit_spike_ring) and not _orbit_spike_ring.is_queued_for_deletion():
		if _orbit_spike_ring.is_hazard_active:
			if beat_idx in [71, 77]:
				_orbit_spike_ring.release_tangential_spikes(_bullet_manager, 215.0, 3)
				seen_hazard_kinds[&"boss_bullets"] = true


func _prune_transients() -> void:
	var wells: Array[BossGravityWell] = []
	for w: BossGravityWell in _active_wells:
		if is_instance_valid(w) and not w.is_queued_for_deletion():
			wells.append(w)
	_active_wells = wells

	var rings: Array[BossSpikeRing] = []
	for r: BossSpikeRing in _active_spike_rings:
		if is_instance_valid(r) and not r.is_queued_for_deletion():
			rings.append(r)
	_active_spike_rings = rings

	var minions: Array[BossBeatMinion] = []
	for m: BossBeatMinion in _active_minions:
		if is_instance_valid(m) and not m.is_queued_for_deletion():
			minions.append(m)
	_active_minions = minions

	var waves: Array[BossGlitchWave] = []
	for gw: BossGlitchWave in _active_glitch_waves:
		if is_instance_valid(gw) and not gw.is_queued_for_deletion():
			waves.append(gw)
	_active_glitch_waves = waves

	if _orbit_spike_ring != null and (not is_instance_valid(_orbit_spike_ring) or _orbit_spike_ring.is_queued_for_deletion()):
		_orbit_spike_ring = null


func _scale_vec(arena_size: Vector2) -> Vector2:
	return Vector2(arena_size.x / BossConstants.ARENA_REF.x, arena_size.y / BossConstants.ARENA_REF.y)


func _sp(ref_pos: Vector2, s: Vector2) -> Vector2:
	return Vector2(ref_pos.x * s.x, ref_pos.y * s.y)


func _spawn_bullet_ring_fx(origin: Vector2) -> void:
	"""Emit a crisp monochrome contracting + expanding ring pulse when a bullet ring spawns."""
	if _arena_fx == null:
		return
	_arena_fx.spawn_ring(origin, 48.0, 12.0, 0.22, Color(0.86, 0.86, 0.86, 0.72), 1.6)
	_arena_fx.spawn_ring(origin, 14.0, 88.0, 0.32, Color(0.96, 0.96, 0.96, 0.85), 2.2)


func _execute_cue(cue: Dictionary, song_beat: float, arena_size: Vector2, player: Node2D) -> void:
	var kind: StringName = cue["kind"]
	var phase: int = int(cue["phase"])
	var impact_beat: float = float(cue["impact_beat"])
	var params: Dictionary = cue["params"]
	var s: Vector2 = _scale_vec(arena_size)
	var time_to_impact: float = maxf((impact_beat - song_beat) * BossConstants.BEAT_DURATION, 0.05)
	var player_pos: Vector2 = player.global_position if (player != null and is_instance_valid(player)) else (arena_size * 0.5)
	var boss_pos: Vector2 = _boss.global_position if (_boss != null and is_instance_valid(_boss)) else (arena_size * 0.5)

	match kind:
		&"phase_transition":
			if bool(params.get("clear_hazards", false)) and _level != null and _level.has_method(&"_clear_hazards"):
				_level._clear_hazards()
			if _boss != null and _boss.has_method(&"set_phase_state"):
				var target: Vector2 = _sp(params.get("target", Vector2(576.0, 152.0)), s)
				_boss.set_phase_state(
					phase,
					int(params.get("acting", 0)),
					int(params.get("form", 0)),
					target,
					float(params.get("move_speed", 7.5))
				)
				seen_forms[int(_boss.boss_form)] = true
			if float(params.get("white_flash", 0.0)) > 0.0 and _boss != null and _boss.has_method(&"trigger_white_flash"):
				_boss.trigger_white_flash(float(params["white_flash"]))

		&"form_change":
			if _boss != null and _boss.has_method(&"set_phase_state"):
				var target: Vector2 = _sp(params.get("target", Vector2(576.0, 220.0)), s)
				_boss.set_phase_state(
					phase,
					int(params.get("acting", 0)),
					int(params.get("form", 0)),
					target,
					float(params.get("move_speed", 8.0))
				)
				seen_forms[int(_boss.boss_form)] = true

		&"body_move":
			if _boss != null and _boss.has_method(&"set_body_target"):
				_boss.set_body_target(_sp(params.get("target", Vector2(576.0, 152.0)), s), float(params.get("speed", 7.5)))

		&"conductor_snap":
			var strength: float = float(params.get("strength", 0.55))
			if _boss != null and _boss.has_method(&"pulse_beat"):
				_boss.pulse_beat(strength + 0.35)
			if _arena_grid != null and _arena_grid.has_method(&"pulse"):
				_arena_grid.pulse(strength * 0.45)
			if _arena_fx != null and _boss != null:
				var snap_both: bool = bool(params.get("both", false))
				var is_left: bool = bool(params.get("is_left", true))
				if snap_both:
					_arena_fx.spawn_ring(_boss.left_hand.global_position, 10.0, 56.0, 0.28, Color(0.92, 0.92, 0.92, 0.72), 1.8)
					_arena_fx.spawn_ring(_boss.right_hand.global_position, 10.0, 56.0, 0.28, Color(0.92, 0.92, 0.92, 0.72), 1.8)
				else:
					var h_pos: Vector2 = _boss.left_hand.global_position if is_left else _boss.right_hand.global_position
					_arena_fx.spawn_ring(h_pos, 10.0, 48.0, 0.24, Color(0.88, 0.88, 0.88, 0.65), 1.6)

		&"white_flash":
			if _boss != null and _boss.has_method(&"trigger_white_flash"):
				_boss.trigger_white_flash(float(params.get("amount", 0.8)))
			if _arena_grid != null and _arena_grid.has_method(&"pulse"):
				_arena_grid.pulse(0.62)

		&"phase5_wake_hands":
			if _boss != null and _boss.has_method(&"set_phase5_hands_awake"):
				_boss.set_phase5_hands_awake(true)
			if _arena_fx != null and _boss != null:
				_arena_fx.spawn_ring(_boss.left_hand.global_position, 12.0, 74.0, 0.36, Color(0.95, 0.95, 0.95, 0.85), 2.0)
				_arena_fx.spawn_ring(_boss.right_hand.global_position, 12.0, 74.0, 0.36, Color(0.95, 0.95, 0.95, 0.85), 2.0)

		&"silence_freeze":
			if bool(params.get("clear_hazards", false)) and _level != null and _level.has_method(&"_clear_hazards"):
				_level._clear_hazards()
			if _boss != null and _boss.has_method(&"set_silence_freeze"):
				_boss.set_silence_freeze(bool(params.get("frozen", true)), float(params.get("inflate", 1.0)))

		&"supernova_drop":
			if _boss != null:
				if _boss.has_method(&"set_silence_freeze"):
					_boss.set_silence_freeze(false, 0.0)
				if _boss.has_method(&"trigger_white_flash"):
					_boss.trigger_white_flash(1.25)
				if _boss.has_method(&"trigger_mouth_flare"):
					_boss.trigger_mouth_flare(0.65)
			var origin: Vector2 = _sp(params.get("origin", Vector2(576.0, 324.0)), s)
			if _bullet_manager != null:
				_bullet_manager.spawn_ring(
					origin,
					int(params.get("bullet_count", 24)),
					float(params.get("bullet_speed", 295.0)),
					0.0,
					BossConstants.BULLET_RADIUS,
					7.5,
					&"spike"
				)
				seen_hazard_kinds[&"boss_bullets"] = true
			if _arena_fx != null:
				_arena_fx.spawn_ring(origin, 28.0, 310.0, 0.55, Color(1.0, 1.0, 1.0, 0.95), 3.0)
				_arena_fx.spawn_burst(origin, 28, 360.0, Color(0.96, 0.96, 0.96, 1.0), 0.45, 13.0, 2.2)
			if _arena_grid != null and _arena_grid.has_method(&"pulse"):
				_arena_grid.pulse(0.95)
			if _level != null and _level.has_method(&"trigger_screen_shake"):
				_level.trigger_screen_shake(5.2, 0.28)
			BossConstants.play_sfx(_level, &"boss_phase", 0.0)

		&"silent_shatter":
			if _boss != null and _boss.has_method(&"enter_silent_shatter"):
				_boss.enter_silent_shatter()
				if "boss_form" in _boss:
					seen_forms[int(_boss.boss_form)] = true
			if _level != null and _level.has_method(&"_clear_hazards"):
				_level._clear_hazards()

		&"hand_pointer":
			if _boss != null and _boss.has_method(&"command_hand_pointer"):
				_boss.command_hand_pointer(
					bool(params.get("is_left", true)),
					_sp(params.get("pos", Vector2(180.0, 324.0)), s),
					float(params.get("angle", 0.0)),
					maxf(float(params.get("hold_time", 0.70)), time_to_impact + 0.12)
				)

		&"hand_dash":
			if _boss != null and _boss.has_method(&"command_hand_dash"):
				_boss.command_hand_dash(
					bool(params.get("is_left", true)),
					_sp(params.get("from", Vector2(120.0, 324.0)), s),
					_sp(params.get("to", Vector2(1032.0, 324.0)), s),
					time_to_impact,
					float(params.get("dash_time", 0.48)),
					int(params.get("style", 0))
				)

		&"floor_slam":
			if _boss != null and _boss.has_method(&"command_hand_floor_slam"):
				var strike_t: float = minf(float(params.get("strike_time", 0.16)), time_to_impact * 0.65)
				var tele_t: float = maxf(time_to_impact - strike_t, 0.04)
				_boss.command_hand_floor_slam(
					bool(params.get("is_left", true)),
					_sp(params.get("target", Vector2(576.0, 455.0)), s),
					tele_t,
					strike_t,
					int(params.get("impact_mode", 1))
				)

		&"wall_slam":
			if _boss != null and _boss.has_method(&"command_wall_slam"):
				var side: StringName = StringName(params.get("side", &"left"))
				var raw_coord: float = float(params.get("coord", 324.0))
				var scaled_coord: float = raw_coord * (s.y if (side == &"left" or side == &"right") else s.x)
				var strike_t: float = minf(float(params.get("strike_time", 0.16)), time_to_impact * 0.35)
				var windup_t: float = maxf(time_to_impact - strike_t, 0.04)
				_boss.command_wall_slam(
					bool(params.get("is_left", true)),
					side,
					scaled_coord,
					windup_t,
					strike_t,
					float(params.get("strength", 0.82))
				)

		&"pincer":
			if _boss != null and _boss.has_method(&"command_pincer"):
				var clap_t: float = minf(float(params.get("clap_time", 0.18)), time_to_impact * 0.35)
				var tele_t: float = maxf(time_to_impact - clap_t, 0.04)
				_boss.command_pincer(_sp(params.get("mid", Vector2(576.0, 360.0)), s), tele_t, clap_t)

		&"claw_orbit":
			if _boss != null and _boss.has_method(&"command_claw_orbit"):
				_boss.command_claw_orbit(float(params.get("duration", 0.70)), float(params.get("angular_speed", 3.8)))

		&"tether_sweep":
			if _boss != null and _boss.has_method(&"command_tether_sweep"):
				_boss.command_tether_sweep(
					float(params.get("start_y", 155.0)) * s.y,
					float(params.get("end_y", 495.0)) * s.y,
					time_to_impact,
					float(params.get("sweep_time", 1.2))
				)

		&"body_lunge":
			if _boss != null and _boss.has_method(&"command_body_lunge"):
				var from_p: Vector2 = boss_pos if bool(params.get("aim_player", false)) else _sp(params.get("from", Vector2(180.0, 220.0)), s)
				var to_p: Vector2 = player_pos if bool(params.get("aim_player", false)) else _sp(params.get("to", Vector2(972.0, 220.0)), s)
				_boss.command_body_lunge(from_p, to_p, time_to_impact, float(params.get("dash_time", 0.50)), bool(params.get("emit_slam", true)))

		&"teleport":
			if _boss != null and _boss.has_method(&"command_teleport"):
				_boss.command_teleport(_sp(params.get("to", Vector2(576.0, 140.0)), s), float(params.get("arrival_grace", 0.35)))
			if params.has("cannon_angle") and _boss != null and _boss.has_method(&"set_cannon_angle"):
				_boss.set_cannon_angle(float(params["cannon_angle"]))

		&"triple_cannon_burst":
			if _boss != null and _bullet_manager != null and _boss.has_method(&"get_triple_cannon_muzzles"):
				if params.has("cannon_angle") and _boss.has_method(&"set_cannon_angle"):
					_boss.set_cannon_angle(float(params["cannon_angle"]))
				var muzzles: Array = _boss.get_triple_cannon_muzzles()
				var fan_count: int = int(params.get("fan_count", 3))
				var step_angle: float = float(params.get("step_angle", 0.22))
				var speed: float = float(params.get("speed", 285.0))
				var shape: StringName = StringName(params.get("shape", &"needle"))
				for m: Dictionary in muzzles:
					var m_pos: Vector2 = Vector2(m["pos"])
					var m_ang: float = float(m["angle"])
					_bullet_manager.spawn_fan(m_pos, Vector2.from_angle(m_ang), fan_count, step_angle, speed, BossConstants.BULLET_RADIUS, 7.5, shape)
				seen_hazard_kinds[&"boss_bullets"] = true
				if _boss.has_method(&"trigger_mouth_flare"):
					_boss.trigger_mouth_flare(0.28)
				BossConstants.play_sfx(_level, &"enemy_fire", -4.0)

		&"mouth_burst":
			if _boss != null and _boss.has_method(&"trigger_mouth_flare"):
				_boss.trigger_mouth_flare(0.32)
			if _bullet_manager != null:
				_bullet_manager.spawn_ring(
					boss_pos,
					int(params.get("count", 8)),
					float(params.get("speed", 285.0)),
					float(params.get("angle_offset", 0.0)),
					BossConstants.BULLET_RADIUS,
					7.0,
					StringName(params.get("shape", &"diamond"))
				)
				_spawn_bullet_ring_fx(boss_pos)
				seen_hazard_kinds[&"boss_bullets"] = true
				BossConstants.play_sfx(_level, &"enemy_fire", -5.0)

		&"bullet_ring":
			if _bullet_manager != null:
				var origin: Vector2 = boss_pos if bool(params.get("from_boss", false)) else _sp(params.get("origin", Vector2(576.0, 324.0)), s)
				_bullet_manager.spawn_ring(
					origin,
					int(params.get("count", 12)),
					float(params.get("speed", 265.0)),
					float(params.get("angle_offset", 0.0)),
					float(params.get("radius", BossConstants.BULLET_RADIUS)),
					7.5,
					StringName(params.get("shape", &"orb"))
				)
				_spawn_bullet_ring_fx(origin)
				seen_hazard_kinds[&"boss_bullets"] = true
				BossConstants.play_sfx(_level, &"enemy_fire", -6.0)

		&"bullet_fan":
			if _bullet_manager != null:
				var origin: Vector2 = boss_pos if bool(params.get("from_boss", false)) else _sp(params.get("origin", Vector2(576.0, 324.0)), s)
				var dir: Vector2 = (player_pos - origin).normalized() if bool(params.get("aim_player", false)) else Vector2(params.get("dir", Vector2.DOWN))
				_bullet_manager.spawn_fan(
					origin,
					dir,
					int(params.get("count", 5)),
					float(params.get("step_angle", 0.24)),
					float(params.get("speed", 285.0)),
					float(params.get("radius", BossConstants.BULLET_RADIUS)),
					7.5,
					StringName(params.get("shape", &"diamond"))
				)
				seen_hazard_kinds[&"boss_bullets"] = true
				BossConstants.play_sfx(_level, &"enemy_fire", -6.0)

		&"sweeping_beam":
			if _beam_container != null:
				var beam: BossSweepingBeam = BossSweepingBeam.new()
				_beam_container.add_child(beam)
				var origin: Vector2 = boss_pos if bool(params.get("aim_player", false)) else _sp(params.get("origin", Vector2(576.0, 324.0)), s)
				var angle: float = (player_pos - origin).angle() if bool(params.get("aim_player", false)) else float(params.get("angle", 0.0))
				var follow: Node2D = (_boss as Node2D) if bool(params.get("follow_boss", false)) else null
				beam.configure(
					origin,
					angle,
					int(params.get("beam_count", 1)),
					float(params.get("width", BossConstants.BEAM_WIDTH)),
					time_to_impact,
					float(params.get("active_time", 0.42)),
					float(params.get("angular_speed", 0.0)),
					Vector2(params.get("sweep_velocity", Vector2.ZERO)),
					float(params.get("reverse_at_active_time", -1.0)),
					follow,
					float(params.get("length", 2600.0)),
					bool(params.get("parryable", false))
				)
				seen_hazard_kinds[&"sweeping_beam"] = true

		&"shockwave_ring":
			if _beam_container != null:
				var ring: BossShockwaveRing = BossShockwaveRing.new()
				_beam_container.add_child(ring)
				var origin: Vector2 = boss_pos if bool(params.get("from_boss", false)) else _sp(params.get("origin", Vector2(576.0, 324.0)), s)
				var max_scale: float = maxf(s.x, s.y)
				ring.configure_ring(
					origin,
					float(params.get("start_radius", 34.0)) * max_scale,
					float(params.get("end_radius", 840.0)) * max_scale,
					float(params.get("thickness", 26.0)),
					time_to_impact,
					float(params.get("travel_time", 1.30)),
					bool(params.get("parryable", true))
				)
				seen_hazard_kinds[&"shockwave_ring"] = true

		&"tidal_wave":
			if _beam_container != null:
				var wave: BossShockwaveRing = BossShockwaveRing.new()
				_beam_container.add_child(wave)
				var side: StringName = StringName(params.get("side", &"left"))
				var is_h: bool = (side == &"left" or side == &"right")
				var perp_scale: float = s.y if is_h else s.x
				var gap_center: float = float(params.get("gap_center", 324.0)) * perp_scale
				var gap_size: float = maxf(float(params.get("gap_size", 152.0)) * perp_scale, BossShockwaveRing.MIN_TIDAL_GAP)
				wave.configure_tidal_wave(
					arena_size,
					side,
					float(params.get("thickness", 30.0)),
					gap_center,
					gap_size,
					time_to_impact,
					float(params.get("travel_time", 1.38)),
					bool(params.get("parryable", true))
				)
				seen_hazard_kinds[&"tidal_wave"] = true
				seen_hazard_kinds[&"shockwave_ring"] = true

		&"piston_wall":
			if _beam_container != null:
				var piston: BossPistonWall = BossPistonWall.new()
				_beam_container.add_child(piston)
				var side: StringName = StringName(params.get("side", &"left"))
				var is_h: bool = (side == &"left" or side == &"right")
				var span_scale: float = s.y if is_h else s.x
				var reach_scale: float = s.x if is_h else s.y
				var slam_t: float = float(params.get("slam_time", 0.14))
				piston.configure(
					arena_size,
					side,
					float(params.get("span_start", 0.0)) * span_scale,
					float(params.get("span_end", 648.0 if is_h else 1152.0)) * span_scale,
					float(params.get("reach", 200.0)) * reach_scale,
					time_to_impact,
					slam_t,
					float(params.get("hold_time", 0.36)),
					float(params.get("retract_time", 0.26)),
					bool(params.get("parryable", false))
				)
				seen_hazard_kinds[&"piston_wall"] = true

		&"hex_grid":
			if _hex_grid != null:
				_hex_grid.set_arena_size(arena_size)
				var hp: Dictionary = (params.get("params", {}) as Dictionary).duplicate()
				var pat: int = int(params.get("pattern", BossConstants.HexPattern.WAVE_LR))
				var corridor_scale: float = s.y if pat == BossConstants.HexPattern.CORRIDOR_H else s.x
				if hp.has("origin"):
					hp["origin"] = _sp(Vector2(hp["origin"]), s)
				if hp.has("safe_center"):
					hp["safe_center"] = float(hp["safe_center"]) * corridor_scale
				if hp.has("safe_half_width"):
					hp["safe_half_width"] = maxf(float(hp["safe_half_width"]) * corridor_scale, BossHexGrid.MIN_CORRIDOR_HALF_WIDTH)
				_hex_grid.trigger_pattern(
					pat,
					time_to_impact,
					float(params.get("active_time", 0.40)),
					float(params.get("cascade_step", 0.04)),
					hp
				)
				seen_hazard_kinds[&"hex_grid"] = true

		&"gravity_well":
			if _beam_container != null:
				var well: BossGravityWell = BossGravityWell.new()
				_beam_container.add_child(well)
				var min_s: float = minf(s.x, s.y)
				well.configure(
					_sp(params.get("origin", Vector2(576.0, 324.0)), s),
					float(params.get("core_radius", 24.0)),
					float(params.get("pull_radius", 460.0)) * min_s,
					float(params.get("max_pull_offset", 76.0)) * min_s,
					float(params.get("pull_speed", 145.0)) * min_s,
					time_to_impact,
					float(params.get("duration", 11.25))
				)
				_active_wells.append(well)
				seen_hazard_kinds[&"gravity_well"] = true

		&"spike_ring":
			if _beam_container != null:
				var ring: BossSpikeRing = BossSpikeRing.new()
				_beam_container.add_child(ring)
				var mode: int = int(params.get("mode", BossSpikeRing.RingMode.ORBIT_RING))
				var min_s: float = minf(s.x, s.y)
				if mode == BossSpikeRing.RingMode.BORDER_CAGE:
					ring.configure_border_cage(
						arena_size,
						float(params.get("margin", 40.0)) * min_s,
						float(params.get("spike_radius", BossConstants.SPIKE_RADIUS)),
						float(params.get("speed", 175.0)),
						time_to_impact,
						float(params.get("duration", 9.0))
					)
					seen_hazard_kinds[&"border_cage"] = true
				else:
					var follow: Node2D = (_boss as Node2D) if bool(params.get("follow_boss", false)) else null
					var center_p: Vector2 = boss_pos if follow != null else _sp(params.get("origin", Vector2(576.0, 324.0)), s)
					ring.configure_orbit(
						center_p,
						int(params.get("count", 10)),
						float(params.get("start_radius", 76.0)) * min_s,
						float(params.get("end_radius", 76.0)) * min_s,
						float(params.get("spike_radius", BossConstants.SPIKE_RADIUS)),
						float(params.get("angular_speed", 2.6)),
						time_to_impact,
						float(params.get("duration", 6.5)),
						follow
					)
					_orbit_spike_ring = ring
				_active_spike_rings.append(ring)
				seen_hazard_kinds[&"spike_ring"] = true

		&"ceiling_spike":
			if _beam_container != null:
				var curtain: BossCeilingSpike = BossCeilingSpike.new()
				_beam_container.add_child(curtain)
				curtain.configure_curtain(
					arena_size,
					bool(params.get("from_top", true)),
					int(params.get("count", 11)),
					float(params.get("safe_lane_x", 576.0)) * s.x,
					float(params.get("safe_half_width", 88.0)) * s.x,
					time_to_impact,
					float(params.get("fall_speed", 540.0)),
					float(params.get("cascade_delay", 0.035)),
					float(params.get("spike_radius", 15.0))
				)
				seen_hazard_kinds[&"ceiling_spike"] = true

		&"beat_minion":
			if _beam_container != null:
				var minion: BossBeatMinion = BossBeatMinion.new()
				_beam_container.add_child(minion)
				var m_type: int = int(params.get("type", BossConstants.MinionType.THREAD_SPIDER))
				var mp: Dictionary = (params.get("params", {}) as Dictionary).duplicate()
				if mp.has("drop_y"):
					mp["drop_y"] = float(mp["drop_y"]) * s.y
				if mp.has("orbit_center"):
					mp["orbit_center"] = _sp(Vector2(mp["orbit_center"]), s)
				if mp.has("orbit_radius"):
					mp["orbit_radius"] = float(mp["orbit_radius"]) * minf(s.x, s.y)
				if mp.has("leap_depth"):
					mp["leap_depth"] = float(mp["leap_depth"]) * minf(s.x, s.y)
				minion.configure(
					m_type,
					_sp(params.get("pos", Vector2(576.0, 250.0)), s),
					arena_size,
					time_to_impact,
					int(params.get("lifetime_beats", 8)),
					mp
				)
				_active_minions.append(minion)
				seen_hazard_kinds[&"beat_minion"] = true
				seen_hazard_kinds[minion.hazard_kind] = true

		&"glitch_wave":
			if _beam_container != null:
				var wave: BossGlitchWave = BossGlitchWave.new()
				_beam_container.add_child(wave)
				var gw_dir: Vector2 = Vector2(params.get("direction", Vector2.RIGHT))
				var gw_norm: Vector2 = gw_dir.normalized() if gw_dir.length_squared() > 0.0001 else Vector2.RIGHT
				var gw_perp_scale: float = Vector2(absf(gw_norm.y) * s.x, absf(gw_norm.x) * s.y).length()
				var gw_gap_size: float = maxf(float(params.get("gap_size", 152.0)) * gw_perp_scale, BossGlitchWave.MIN_GAP_SIZE)
				var gw_gap_wobble: float = maxf(float(params.get("gap_wobble", 62.0)) * gw_perp_scale, 0.0)
				wave.configure(
					arena_size,
					gw_dir,
					time_to_impact,
					float(params.get("sweep_time", 1.65)),
					float(params.get("wave_thickness", 74.0)),
					float(params.get("gap_center_ratio", 0.5)),
					gw_gap_size,
					gw_gap_wobble,
					bool(params.get("parryable", true))
				)
				_active_glitch_waves.append(wave)
				glitch_waves_spawned += 1
				seen_hazard_kinds[&"glitch_wave"] = true

		&"filling_circle":
			if _level != null and _level.has_method(&"spawn_circle"):
				var circle: Area2D = _level.spawn_circle(
					_sp(params.get("pos", Vector2(576.0, 324.0)), s),
					float(params.get("radius", 52.0)),
					int(params.get("fill_mode", 0)),
					time_to_impact,
					float(params.get("active_time", 0.34))
				)
				if circle != null:
					circle.add_to_group("boss_filling_circle")
				seen_hazard_kinds[&"filling_circle"] = true
