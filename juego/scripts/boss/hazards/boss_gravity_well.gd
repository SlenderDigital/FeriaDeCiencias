class_name BossGravityWell
extends Node2D

enum Phase {
	TELEGRAPH = 0,
	ACTIVE = 1,
	FADE_OUT = 2,
}

const FADE_DURATION: float = 0.35
const PULL_RAMP_TIME: float = 0.35
const PARTICLE_COUNT: int = 22

var is_hazard_active: bool = false
var parryable: bool = false
var hazard_kind: StringName = &"gravity_well"

var current_phase: int = Phase.TELEGRAPH
var phase_timer: float = 0.0
var core_radius: float = 24.0
var pull_radius: float = 460.0
var max_pull_offset: float = 76.0
var pull_speed: float = 145.0

var _warning_time: float = 0.9375
var _duration: float = 9.0
var _swirl_time: float = 0.0
var _beat_pulse: float = 0.0
var _particles: Array[Dictionary] = []
var _dust_pts: PackedVector2Array = PackedVector2Array()
var _dust_cols: PackedColorArray = PackedColorArray()
var _queued_free: bool = false


func _init() -> void:
	_dust_pts.resize(PARTICLE_COUNT * 2)
	_dust_cols.resize(PARTICLE_COUNT)
	add_to_group("boss_hazards")
	_init_particles()


func _ready() -> void:
	if not is_in_group("boss_hazards"):
		add_to_group("boss_hazards")
	queue_redraw()


func _physics_process(delta: float) -> void:
	simulate_physics(delta)


func configure(
	origin: Vector2,
	p_core_radius: float = 24.0,
	p_pull_radius: float = 460.0,
	p_max_pull_offset: float = 76.0,
	p_pull_speed: float = 145.0,
	warning_time: float = 0.9375,
	duration: float = 9.0
) -> void:
	global_position = origin
	core_radius = maxf(p_core_radius, 8.0)
	pull_radius = maxf(p_pull_radius, core_radius + 32.0)
	max_pull_offset = maxf(p_max_pull_offset, 0.0)
	pull_speed = maxf(p_pull_speed, 0.0)
	_warning_time = maxf(warning_time, 0.001)
	_duration = maxf(duration, 0.1)
	current_phase = Phase.TELEGRAPH
	phase_timer = 0.0
	_swirl_time = 0.0
	_beat_pulse = 0.0
	is_hazard_active = false
	_init_particles()
	queue_redraw()


func get_pull_displacement(player_pos: Vector2, delta: float, is_target_mode: bool) -> Vector2:
	if not is_hazard_active or current_phase != Phase.ACTIVE:
		return Vector2.ZERO
	var to_core: Vector2 = global_position - player_pos
	var dist: float = to_core.length()
	if dist <= 0.001 or dist >= pull_radius:
		return Vector2.ZERO

	var norm: float = clampf(1.0 - dist / pull_radius, 0.0, 1.0)
	var falloff: float = pow(norm, 0.85) * (0.45 + 0.55 * norm)
	var ramp: float = clampf(phase_timer / PULL_RAMP_TIME, 0.0, 1.0)
	var dir: Vector2 = to_core / dist

	if is_target_mode:
		var mag: float = minf(max_pull_offset * falloff * ramp, dist)
		return dir * mag
	var step_mag: float = minf(pull_speed * falloff * ramp * maxf(delta, 0.0), dist)
	return dir * step_mag


func pulse_beat(bullet_manager: Node, count: int = 16, speed: float = 280.0, angle_offset: float = 0.0) -> void:
	_beat_pulse = 1.0
	if bullet_manager != null and bullet_manager.has_method(&"spawn_ring"):
		bullet_manager.spawn_ring(global_position, count, speed, angle_offset)
	queue_redraw()


func simulate_physics(delta: float, player_node: Node2D = null) -> void:
	if _queued_free:
		return

	phase_timer += delta
	_swirl_time += delta
	_beat_pulse = maxf(0.0, _beat_pulse - delta * 3.6)

	_step_particles(delta)

	match current_phase:
		Phase.TELEGRAPH:
			is_hazard_active = false
			if phase_timer >= _warning_time:
				current_phase = Phase.ACTIVE
				phase_timer = 0.0
				is_hazard_active = true
				_beat_pulse = 0.85
				BossConstants.play_sfx(self, &"boss_phase", -8.0)
				_check_core_overlap(player_node)
		Phase.ACTIVE:
			is_hazard_active = true
			_check_core_overlap(player_node)
			if phase_timer >= _duration:
				current_phase = Phase.FADE_OUT
				phase_timer = 0.0
				is_hazard_active = false
		Phase.FADE_OUT:
			is_hazard_active = false
			if phase_timer >= FADE_DURATION:
				_queued_free = true
				queue_free()
				return

	queue_redraw()


func _check_core_overlap(player_node: Node2D = null) -> void:
	if not is_hazard_active:
		return
	var players: Array[Node2D] = BossConstants.collect_players(self, player_node)
	for body: Node2D in players:
		var player_r: float = BossConstants.get_player_hit_radius(body)
		var hit_r: float = core_radius + player_r
		if body.global_position.distance_squared_to(global_position) <= hit_r * hit_r:
			BossConstants.apply_player_hit(body, parryable, hazard_kind)


func _init_particles() -> void:
	_particles.clear()
	for i: int in range(PARTICLE_COUNT):
		var frac: float = float(i) / float(PARTICLE_COUNT)
		_particles.append({
			"angle": frac * TAU * 3.0,
			"radius_norm": fposmod(frac * 1.37 + 0.12, 1.0),
			"speed": 0.34 + 0.28 * fposmod(float(i) * 0.618, 1.0),
			"spin": 1.4 + 1.2 * fposmod(float(i) * 0.382, 1.0),
		})


func _step_particles(delta: float) -> void:
	var pull_mult: float = 1.0 if current_phase == Phase.ACTIVE else 0.45
	for p: Dictionary in _particles:
		var rn: float = float(p["radius_norm"]) - float(p["speed"]) * pull_mult * delta
		if rn <= 0.04:
			rn = 1.0
		p["radius_norm"] = rn
		p["angle"] = float(p["angle"]) + (float(p["spin"]) + (1.0 - rn) * 3.2) * delta


func _draw() -> void:
	match current_phase:
		Phase.TELEGRAPH:
			var progress: float = clampf(phase_timer / maxf(_warning_time, 0.001), 0.0, 1.0)
			BossConstants.draw_dashed_circle(
				self,
				Vector2.ZERO,
				pull_radius,
				Color(0.65, 0.65, 0.65, lerpf(0.10, 0.30, progress)),
				1.3,
				40,
				0.5,
				_swirl_time * 0.4
			)
			var inward_r: float = lerpf(pull_radius * 0.65, core_radius, progress)
			draw_arc(Vector2.ZERO, inward_r, 0.0, TAU, 48, Color(0.88, 0.88, 0.88, 0.25 + 0.55 * progress), 1.6, true)
			draw_circle(Vector2.ZERO, core_radius * lerpf(0.3, 1.0, progress), Color(0.06, 0.06, 0.06, 0.75 * progress))
			draw_arc(Vector2.ZERO, core_radius, 0.0, TAU, 32, Color(0.92, 0.92, 0.92, 0.40 + 0.55 * progress), 2.0, true)

		Phase.ACTIVE:
			var contract: float = 1.0 - 0.14 * _beat_pulse
			# Outer pull boundary
			BossConstants.draw_dashed_circle(
				self,
				Vector2.ZERO,
				pull_radius,
				Color(0.58, 0.58, 0.58, 0.22 + 0.12 * _beat_pulse),
				1.2,
				44,
				0.48,
				-_swirl_time * 0.32
			)

			# Swirling monochrome accretion arcs
			for ring_i: int in range(4):
				var frac: float = float(ring_i + 1) / 4.0
				var r: float = lerpf(core_radius * 1.45, pull_radius * 0.62, frac) * contract
				var rot: float = _swirl_time * (2.6 - frac * 1.5) * (1.0 if ring_i % 2 == 0 else -1.0)
				var alpha: float = (0.58 - frac * 0.34) + 0.18 * _beat_pulse
				for arc_k: int in range(3):
					var a0: float = rot + float(arc_k) * TAU / 3.0
					draw_arc(Vector2.ZERO, r, a0, a0 + 1.15, 16, Color(0.86, 0.86, 0.86, clampf(alpha, 0.08, 0.95)), 1.8 - frac * 0.5, true)

			# Inward spiraling dust streaks (batched)
			var p_count: int = _particles.size()
			if _dust_pts.size() != p_count * 2:
				_dust_pts.resize(p_count * 2)
				_dust_cols.resize(p_count)
			for i: int in range(p_count):
				var p: Dictionary = _particles[i]
				var rn: float = float(p["radius_norm"])
				var a: float = float(p["angle"])
				var r_now: float = lerpf(core_radius * 1.1, pull_radius * 0.88, rn)
				var r_prev: float = minf(r_now + 16.0 + 14.0 * (1.0 - rn), pull_radius * 0.92)
				_dust_pts[i * 2] = Vector2.from_angle(a) * r_now
				_dust_pts[i * 2 + 1] = Vector2.from_angle(a - 0.10) * r_prev
				var p_alpha: float = clampf(sin(rn * PI) * 0.72, 0.05, 0.80)
				_dust_cols[i] = Color(0.84, 0.84, 0.84, p_alpha)
			if _dust_pts.size() >= 2:
				draw_multiline_colors(_dust_pts, _dust_cols, 1.4, true)

			# Beat pulse shock echo
			if _beat_pulse > 0.02:
				var pulse_r: float = core_radius * (1.1 + (1.0 - _beat_pulse) * 2.4)
				draw_arc(Vector2.ZERO, pulse_r, 0.0, TAU, 36, Color(1.0, 1.0, 1.0, _beat_pulse * 0.75), 2.4 * _beat_pulse, true)

			# Pitch-black singularity core + bright photon rim
			var draw_core_r: float = core_radius * (1.0 + 0.10 * _beat_pulse)
			draw_circle(Vector2.ZERO, draw_core_r * 1.28, Color(0.92, 0.92, 0.92, 0.20 + 0.25 * _beat_pulse))
			draw_circle(Vector2.ZERO, draw_core_r, Color(0.03, 0.03, 0.03, 1.0))
			draw_arc(Vector2.ZERO, draw_core_r, 0.0, TAU, 36, Color(1.0, 1.0, 1.0, 0.98), 2.6 + 1.4 * _beat_pulse, true)

		Phase.FADE_OUT:
			var fade_t: float = clampf(phase_timer / maxf(FADE_DURATION, 0.001), 0.0, 1.0)
			var inv: float = 1.0 - fade_t
			draw_circle(Vector2.ZERO, core_radius * inv, Color(0.05, 0.05, 0.05, inv * 0.9))
			draw_arc(Vector2.ZERO, core_radius * (1.0 + fade_t * 1.4), 0.0, TAU, 32, Color(0.88, 0.88, 0.88, inv * 0.8), 2.0 * inv, true)
