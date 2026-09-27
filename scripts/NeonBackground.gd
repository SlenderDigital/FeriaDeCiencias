extends Control
## NeonBackground — Animated Cyber Neon Visuals for Abstract Pulse UI
## Draws an animated 2D perspective grid, rhythm pulse rings, and glowing floating particles.

@export var bpm: float = 128.0
## T9 (space-bunny review): la grilla es DECORADO, no peligro. Con alpha
## 0.18 era la forma más brillante y grande del frame — más que los rojos
## que matan. El ojo iba a la parte equivocada de la pantalla. Ahora la grilla se
## siente pero no se lee, y el rojo/blanco queda reservado para lo letal.
@export var grid_color: Color = Color(0.35, 0.72, 0.85, 0.055)
@export var accent_color: Color = Color(1.0, 0.0, 0.55, 0.10)
@export var pulse_speed: float = 1.0

var time: float = 0.0
var beat_timer: float = 0.0
var beat_interval: float = 60.0 / 128.0
var pulse_rings: Array[Dictionary] = []
var particles: Array[Dictionary] = []

# --- Song-clock mode (gameplay): pulse with the REAL audio position ---
# Gameplay feeds song_time via set_song_clock() every frame; the beat index
# is derived from the actual playback clock so rings never drift from the
# music. In song-clock mode there is NO SoundManager.play_beat(): the song
# already has its own kick.
var _song_clock_active: bool = false
var _song_time: float = 0.0
var _last_beat_idx: int = 0
# T5: mood de la sección activa (lo alimenta Gameplay vía set_section_mood).
var _section_energy: float = 0.5
var _section_is_breakdown: bool = false
# Test hooks: counters asserted by tools/test_bg_clock.gd (headless).
var song_clock_pulses: int = 0
var song_clock_sound_calls: int = 0

var _ready_is_safe: bool = false  # test hook: tools may set before add_child

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
	
	if _song_clock_active:
		# Gameplay manda: pulso derivado del reloj REAL del audio. Ningún
		# acumulador propio (el que derivaba) y ningún sonido de beat.
		if _song_time > 0.0 and beat_interval > 0.0:
			var bn: int = int(_song_time / beat_interval)
			if bn != _last_beat_idx:
				_last_beat_idx = bn
				_emit_pulse_ring()
				song_clock_pulses += 1
	else:
		beat_timer += delta
		
		if beat_timer >= beat_interval:
			beat_timer -= beat_interval
			_trigger_beat_pulse()
		
	_update_pulse_rings(delta)
	_update_particles(delta)
	queue_redraw()

## Reloj de la canción: Gameplay lo alimenta cada frame con la posición real
## del audio. Mientras se alimente, el fondo pulsa con la música (sin sonido
## propio). Deja de llamarse (p.ej. al salir del nivel) => fallback del menú.
func set_song_clock(t: float, p_beat_interval: float) -> void:
	if p_beat_interval > 0.0:
		beat_interval = p_beat_interval
	_song_time = t
	if not _song_clock_active:
		_song_clock_active = true
		_last_beat_idx = int(t / maxf(beat_interval, 0.001)) if t > 0.0 else 0

## Al salir del nivel: apagar el modo reloj para que el menú vuelva a su
## metrónomo propio (delta acumulado + sonido ambiental).
func clear_song_clock() -> void:
	_song_clock_active = false
	_song_time = 0.0
	_last_beat_idx = 0
	beat_timer = 0.0
	_section_energy = 0.5
	_section_is_breakdown = false

## T5: el estado de ánimo de la sección manda sobre el color de la grilla.
## La energía escala el brillo (intro tenue -> drop2 pleno); el breakdown
## baja a un azul frío y oscuro (la pausa se VE como pausa).
func set_section_mood(energy: float, section_name: String) -> void:
	_section_energy = clampf(energy, 0.0, 1.0)
	_section_is_breakdown = section_name == "breakdown"

func _current_grid_color() -> Color:
	var c: Color = grid_color
	if _song_clock_active:
		if _section_is_breakdown:
			# Azul profundo y frío, más tenue: el respiro del nivel.
			c = Color(0.16, 0.34, 0.62, 0.12)
		else:
			# Brillo escala con la energía, con techo bajo: la grilla es
			# ambiente, nunca compite con los rayos/rieles de los enemigos.
			var gain: float = 0.3 + 0.55 * _section_energy
			c = Color(grid_color.r * gain, grid_color.g * gain, grid_color.b * gain, 0.11)
	return c

func _emit_pulse_ring() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	var center: Vector2 = viewport_size * 0.5
	pulse_rings.append({
		"radius": 10.0,
		"max_radius": min(viewport_size.x, viewport_size.y) * 0.65,
		"alpha": 0.6,
		"color": grid_color
	})

func _trigger_beat_pulse() -> void:
	_emit_pulse_ring()
	song_clock_sound_calls += 1
	
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
	
	# 2. Animated perspective horizon grid — el color sigue el mood de la
	# sección (T5): energía escala el brillo, breakdown se enfría.
	var horizon_y: float = vp_size.y * 0.52
	var center_x: float = vp_size.x * 0.5
	var mood_col: Color = _current_grid_color()

	# Draw horizon glow line
	draw_line(Vector2(0, horizon_y), Vector2(vp_size.x, horizon_y), mood_col * 1.5, 2.0)

	# Vertical perspective lines
	var num_perspective_lines: int = 18
	for i in range(num_perspective_lines + 1):
		var t: float = float(i) / float(num_perspective_lines)
		var bottom_x: float = lerp(-vp_size.x * 0.4, vp_size.x * 1.4, t)
		var top_x: float = lerp(center_x - 120, center_x + 120, t)
		draw_line(Vector2(top_x, horizon_y), Vector2(bottom_x, vp_size.y), mood_col, 1.2)
		
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
		var line_col: Color = mood_col
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
		# T9 (space-bunny): el confeti usaba accent_color (magenta/rojo), lo
		# que rompía la regla "ROJO = LETAL": había puntos rojos por toda la
		# zona segura y el jugador ya no podía confiar en el color. Ahora la
		# decoración es SIEMPRE de la familia fría (grid/azul); el rojo queda
		# reservado a la geometría que mata.
		var col: Color = grid_color if (int(p["phase"]) % 3 == 0) else Color(0.30, 0.62, 0.80)
		col.a = alpha * 0.55
		draw_circle(p["pos"], p["size"], col)
