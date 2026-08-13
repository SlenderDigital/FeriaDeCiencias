extends Control
## NeonBackground — Animated Cyber Neon Visuals for Abstract Pulse UI
## Draws an animated 2D perspective grid, rhythm pulse rings, and glowing floating particles.

@export var bpm: float = 128.0
@export var grid_color: Color = Color(0.0, 0.94, 1.0, 0.18)
@export var accent_color: Color = Color(1.0, 0.0, 0.55, 0.25)
@export var pulse_speed: float = 1.0

var time: float = 0.0
var beat_timer: float = 0.0
var beat_interval: float = 60.0 / 128.0
var pulse_rings: Array[Dictionary] = []
var particles: Array[Dictionary] = []

const MAX_PARTICLES: int = 35

func _ready() -> void:
	beat_interval = 60.0 / bpm
	_init_particles()
	
	if GameManager and GameManager.has_signal("track_selected"):
		GameManager.track_selected.connect(_on_track_selected)

func _on_track_selected(track_data: Dictionary) -> void:
	if track_data.has("bpm"):
		bpm = track_data["bpm"]
		beat_interval = 60.0 / bpm
	if track_data.has("color"):
		grid_color = track_data["color"]
		grid_color.a = 0.18

func _init_particles() -> void:
	particles.clear()
	var viewport_size: Vector2 = get_viewport_rect().size
	if viewport_size == Vector2.ZERO:
		viewport_size = Vector2(1280, 720)
		
	for i in range(MAX_PARTICLES):
		particles.append({
			"pos": Vector2(randf_range(0, viewport_size.x), randf_range(0, viewport_size.y)),
			"vel": Vector2(randf_range(-15, 15), randf_range(-40, -10)),
			"size": randf_range(2.0, 6.0),
			"alpha": randf_range(0.2, 0.8),
			"phase": randf_range(0.0, TAU)
		})

func _process(delta: float) -> void:
	time += delta * pulse_speed
	beat_timer += delta
	
	if beat_timer >= beat_interval:
		beat_timer -= beat_interval
		_trigger_beat_pulse()
		
	_update_pulse_rings(delta)
	_update_particles(delta)
	queue_redraw()

func _trigger_beat_pulse() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	var center: Vector2 = viewport_size * 0.5
	pulse_rings.append({
		"radius": 10.0,
		"max_radius": min(viewport_size.x, viewport_size.y) * 0.65,
		"alpha": 0.6,
		"color": grid_color
	})
	
	if SoundManager:
		SoundManager.play_beat()

func _update_pulse_rings(delta: float) -> void:
	var to_remove: Array[int] = []
	for i in range(pulse_rings.size()):
		var ring: Dictionary = pulse_rings[i]
		ring["radius"] += delta * 240.0
		ring["alpha"] = lerp(ring["alpha"], 0.0, delta * 3.5)
		if ring["alpha"] <= 0.01 or ring["radius"] >= ring["max_radius"]:
			to_remove.append(i)
			
	to_remove.reverse()
	for idx in to_remove:
		pulse_rings.remove_at(idx)

func _update_particles(delta: float) -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	for p in particles:
		p["pos"] += p["vel"] * delta
		p["phase"] += delta * 2.0
		
		# Wrap around screen edges
		if p["pos"].y < -20:
			p["pos"].y = viewport_size.y + 10
			p["pos"].x = randf_range(0, viewport_size.x)
		if p["pos"].x < -20:
			p["pos"].x = viewport_size.x + 20
		elif p["pos"].x > viewport_size.x + 20:
			p["pos"].x = -20

func _draw() -> void:
	var vp_size: Vector2 = get_viewport_rect().size
	if vp_size == Vector2.ZERO:
		vp_size = Vector2(1280, 720)
		
	# 1. Base dark synth gradient
	draw_rect(Rect2(Vector2.ZERO, vp_size), Color(0.04, 0.04, 0.07, 1.0))
	
	# 2. Animated perspective horizon grid
	var horizon_y: float = vp_size.y * 0.52
	var center_x: float = vp_size.x * 0.5
	
	# Draw horizon glow line
	draw_line(Vector2(0, horizon_y), Vector2(vp_size.x, horizon_y), grid_color * 1.5, 2.0)
	
	# Vertical perspective lines
	var num_perspective_lines: int = 18
	for i in range(num_perspective_lines + 1):
		var t: float = float(i) / float(num_perspective_lines)
		var bottom_x: float = lerp(-vp_size.x * 0.4, vp_size.x * 1.4, t)
		var top_x: float = lerp(center_x - 120, center_x + 120, t)
		draw_line(Vector2(top_x, horizon_y), Vector2(bottom_x, vp_size.y), grid_color, 1.2)
		
	# Horizontal grid lines moving downwards
	var grid_offset: float = fmod(time * 60.0, 40.0)
	var num_horizontal_lines: int = 12
	for j in range(num_horizontal_lines):
		var raw_y: float = float(j) * 40.0 + grid_offset
		if raw_y <= 0:
			continue
		var norm_y: float = raw_y / (num_horizontal_lines * 40.0)
		norm_y = clamp(norm_y, 0.0, 1.0)
		
		# Quadratic spacing for 3D perspective effect
		var line_y: float = horizon_y + (vp_size.y - horizon_y) * (norm_y * norm_y)
		var alpha_factor: float = norm_y * (1.0 - norm_y * 0.3)
		var line_col: Color = grid_color
		line_col.a *= alpha_factor
		
		var margin: float = (1.0 - norm_y) * 200.0
		draw_line(Vector2(margin, line_y), Vector2(vp_size.x - margin, line_y), line_col, 1.5)
		
	# 3. Concentric pulse rings
	var center: Vector2 = Vector2(vp_size.x * 0.5, vp_size.y * 0.4)
	for ring in pulse_rings:
		var c: Color = ring["color"]
		c.a = ring["alpha"]
		draw_arc(center, ring["radius"], 0, TAU, 48, c, 2.5)
		
	# 4. Floating particles
	for p in particles:
		var alpha: float = p["alpha"] * (0.6 + 0.4 * sin(p["phase"]))
		var col: Color = grid_color if (int(p["phase"]) % 2 == 0) else accent_color
		col.a = alpha
		draw_circle(p["pos"], p["size"], col)
