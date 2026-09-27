# REPORTE DE UI — ABSTRACT PULSE (actualizado)

> **Proyecto:** FeriaDeCiencias — "Abstract Pulse"
> **Motor:** Godot Engine 4.7 (renderer Forward+)
> **Finalidad:** Documento de estudio para explicar la interfaz (UI) en un examen, asumiendo que NO se conoce Godot.
> **Resolución de ventana:** 1280×720

---

## 1. IDEA GENERAL EN UNA FRASE

"Abstract Pulse" es un **juego rítmico de acción** con estética neón/abstracta: hay que mover una nave al ritmo de la música y esquivar peligros (esquiva pura, sin disparos). Su UI está 100% construida con **nodos de Godot del tipo `Control`**, organizados en **contenedores** (cajas que acomodan los elementos automáticamente), con un **tema visual global** (colores neón) y **señales** que conectan los botones con la lógica.

---

## 2. CONCEPTOS DE GODOT QUE HAY QUE SABER SÍ O SÍ (explicados para principiantes)

### 2.1 Nodo (Node)
Todo lo que existe en una escena de Godot es un **nodo**: un botón, una etiqueta de texto, una barra, la cámara, el fondo… Cada nodo tiene un **tipo** y una posición en el árbol jerárquico (padres e hijos).

### 2.2 Escena (.tscn)
Un **archivo de escena** (terminación `.tscn`) es una *plantilla guardada* de un árbol de nodos. Piensen en una escena como "una pantalla del juego". Este proyecto tiene 2 escenas:
- `MainMenu.tscn` → el menú principal
- `Gameplay.tscn` → la pantalla de juego

### 2.3 El árbol de escena (SceneTree)
Cuando el juego corre, todas las escenas se combinan en un **árbol vivo**. `MainMenu.tscn` es la escena raíz que arranca (configurada en `project.godot` como `run/main_scene`).

### 2.4 Node2D vs Control (¡CLAVE!)
- **`Node2D`** → cosas del **mundo del juego** (nave, sierras, rayos). Se dibujan con código (`_draw()`): acá **no hay sprites**, todo es gráfica vectorial.
- **`Control`** → **interfaz de usuario** (botones, etiquetas, menús).

> **En este proyecto:** `Gameplay.tscn` es `Node2D` (mundo) pero **contiene** capas de `Control` (el HUD). `MainMenu.tscn` es `Control` puro (todo es UI).

### 2.5 CanvasLayer — capas de dibujo
Un `CanvasLayer` le dice a Godot **en qué "piso" dibujar** algo:
- En Gameplay: `BackgroundLayer` (layer = -1, atrás) y `HUDLayer` (layer = 10, adelante). El HUD siempre queda visible por encima del juego.

### 2.6 Contenedores (Container) — el layout automático
Nodos `Control` que **acomodan a sus hijos automáticamente** (como un "flexbox" de CSS):
- **`VBoxContainer`** → apila hijos **verticalmente**.
- **`HBoxContainer`** → apila hijos **horizontalmente**.
- **`GridContainer`** → coloca hijos en **grilla** (acá: 2 columnas en Configuración).
- **`PanelContainer`** → caja con borde/fondo que recibe un solo hijo y lo centra.

### 2.7 Anclas (Anchors)
Cuando un `Control` NO está en un contenedor, se posiciona por **anclas** (fracciones del padre):
- Anclas 0→1 (`anchors_preset = 15`) → ocupa TODO el padre (fondos, overlays).
- Anclas en 0.5 (`anchors_preset = 8`) → **centrado** (paneles de pausa/resultados, 360×320 y 400×300).

### 2.8 Señales (Signals)
Un **evento** que un nodo emite y otro escucha. El botón emite `pressed`; el script la conecta a `_on_...`. En el `.tscn`:
```
[connection signal="pressed" from="Layout/Content/SideNav/BtnNavPlay" to="." method="_on_btn_nav_play_pressed"]
```

### 2.9 Autoload (Singleton global)
Scripts que **existen siempre** (`project.godot`, sección `[autoload]`):
- `GameManager` → canción elegida, semilla, paletas, volúmenes, récords (de progreso 0–100).
- `SoundManager` → sonidos procedurales (hover, click, beat).
- `HandTrackingClient` → escucha UDP `127.0.0.1:5005` (mano: palma = posición, ángulo = rotación, puño = escudo).

### 2.10 Tema (Theme / .tres)
`resources/neon_theme.tres` define estilos globales; cada nodo puede anular con `theme_override_*` (color de texto, tamaño de fuente, separación).

### 2.11 process_mode (¡CLAVE para la pausa!)
Cuando el juego se pausa (`get_tree().paused = true`), los nodos normales se **congelan** —incluidos los botones—. Por eso la raíz de Gameplay y los dos overlays usan `process_mode = 3` (`ALWAYS`): la pausa congela el mundo pero los botones del popup siguen vivos. Sin esto, los botones de pausa no responden (bug real que tuvo el proyecto).

### 2.12 Métodos de ciclo de vida
- `_ready()` → una vez, al entrar al árbol (inicializa UI).
- `_process(delta)` → cada frame (HUD en vivo).
- `_input(event)` → cada evento de entrada (ESC = pausa, ESPACIO = escudo).
- `_draw()` + `queue_redraw()` → dibujo vectorial por código.

---

## 3. LA ESCENA `MainMenu.tscn` — árbol completo

```
MainMenu (Control — raíz, pantalla completa, tema neon, script MainMenu.gd)
├── Background (Control → NeonBackground.gd)   ← fondo animado
└── Layout (VBoxContainer — pantalla completa, separación 20)
	├── Header (HBoxContainer — fila superior, alto 80, centrado)
	│   └── TitleContainer (VBoxContainer)
	│       ├── Title (Label "ABSTRACT PULSE", 42px, cyan)   ← late al ritmo
	│       └── Subtitle (Label "RHYTHM ACTION // FERIA DE CIENCIAS 2026")
	└── Content (HBoxContainer — separación 24)
		├── SideNav (VBoxContainer — ancho 300, centrado vertical)
		│   ├── BtnNavPlay (Button "JUGAR / CANCIONES")
		│   ├── BtnNavSettings (Button "CONFIGURACIÓN")
		│   ├── BtnNavCredits (Button "CRÉDITOS Y FERIA")
		│   └── BtnNavExit (Button "SALIR DEL JUEGO")
		└── Panels (PanelContainer — expande horizontal)
			├── SongSelectPanel (Control — visible)      ← "NIVEL"
			│   └── VBox → Header (Label "NIVEL", 22px), HSeparator,
			│         Details (VBoxContainer): TrackTitle (26px),
			│         TrackInfo ("Artista | BPM | Duración"),
			│         TrackDesc (autowrap: "Esquivá TODO lo rojo…"),
			│         HighScoreLabel ("MEJOR PROGRESO: X%", dorado),
			│         LegendLabel ("ROJO = PELIGRO · ESCUDO = ESPACIO o CLIC…"),
			│         BtnPlayLevel ("▶ INICIAR NIVEL", alto 54, con pulso de escala)
			├── SettingsPanel (Control — oculto)
			│   └── VBox → Header + Grid (GridContainer 2 columnas):
			│         LabelMaster+SliderMaster (0–1, paso 0.05, 0.8),
			│         LabelMusic+SliderMusic (0.8), LabelSFX+SliderSFX (0.9),
			│         LabelFS+CheckFullscreen + TextoToggle (oculto)
			└── CreditsPanel (Control — oculto)          ← "CRÉDITOS Y FERIA"
				└── VBox → Header + ProjectLabel + AuthorLabel (ETEC Mendoza)
					  + StackLabel (Godot + MediaPipe + procedural) + ThanksLabel
```

> **Un solo nivel:** no hay botones de canciones. La selección es fija (`_select_track_ui(0)`, "First Light"); el panel muestra su info y su récord de progreso.

### Señales conectadas (9, todas a `MainMenu.gd`)
| Nodo emisor | Señal | Método | Efecto |
|---|---|---|---|
| `BtnNavPlay` | `pressed` | `_on_btn_nav_play_pressed` | Muestra `SongSelectPanel` |
| `BtnNavSettings` | `pressed` | `_on_btn_nav_settings_pressed` | Muestra `SettingsPanel` |
| `BtnNavCredits` | `pressed` | `_on_btn_nav_credits_pressed` | Muestra `CreditsPanel` |
| `BtnNavExit` | `pressed` | `_on_btn_nav_exit_pressed` | `get_tree().quit()` |
| `BtnPlayLevel` | `pressed` | `_on_btn_play_level_pressed` | Cambia a `Gameplay.tscn` |
| `SliderMaster/Music/SFX` | `value_changed` | `_on_slider_*_value_changed` | Volúmenes (master → `AudioServer`) |
| `CheckFullscreen` | `toggled` | `_on_check_fullscreen_toggled` | Pantalla completa / ventana |

### Comportamiento dinámico
1. **`_ready()`**: sonidos de botones, selecciona el nivel 0, muestra su récord (`"MEJOR PROGRESO: %d%%"`) y abre `SongSelectPanel`.
2. **`_process(delta)`**: título "late" al ritmo + **pulso de escala en BtnPlayLevel** (requisito: botón Jugar animado) + cursor de palma si hay mano (clic por dwell).
3. **`_connect_audio_recursive()`**: a cada `Button` le conecta `mouse_entered → play_hover()` y `pressed → play_click()`. Todos suenan sin conectarlos uno por uno.
4. **`_show_panel(panel)`**: sistema de pestañas — el panel elegido `visible = true`, el otro `false`.

---

## 4. LA ESCENA `Gameplay.tscn` — árbol completo

```
Gameplay (Node2D — raíz, script Gameplay.gd, process_mode = ALWAYS)
├── MusicPlayer (AudioStreamPlayer)
├── BackgroundLayer (CanvasLayer, layer = -1)
│   └── Background (Control → NeonBackground.gd, pantalla completa)
└── HUDLayer (CanvasLayer, layer = 10)
	├── HUD (VBoxContainer, pantalla completa, mouse_filter = 2 → ignora clicks)
	│   ├── TopBar (HBoxContainer)
	│   │   ├── TrackTitle (Label "First Light | BPM: 128", 20px)
	│   │   └── ProgressLabel (Label "PROGRESO: 0%", dorado, 20px)
	│   └── BottomBar (VBoxContainer, expande)
	│       └── ProgressBar (ProgressBar, alto 12, sin %)  ← progreso canción
	├── PauseOverlay (Control, oculto, pantalla completa, process_mode = ALWAYS)
	│   ├── Dim (ColorRect negro 75%) + Panel (360×320 centrado)
	│   └── VBox → Title "JUEGO PAUSADO" + BtnResume + BtnRestart + BtnMainMenu
	└── ResultsOverlay (Control, oculto, pantalla completa, process_mode = ALWAYS)
		├── Dim (ColorRect negro 82%) + Panel (400×300 centrado)
		└── VBox → Title + ResultsDetails ("Progreso Final/Logrado: X%")
			  + BtnRestartRes + BtnMainMenuRes
```

> **Sin puntaje ni combo:** el HUD es progreso-only. **Sin barra de vida:** la vida es el anillo de la nave (verde/ámbar/rojo; aparece 3s tras cada golpe, lo perdido en rojo; el resto del tiempo se lee en el relleno de la flecha).

### Señales conectadas (5)
| Nodo emisor | Señal | Método | Efecto |
|---|---|---|---|
| `BtnResume` | `pressed` | `_on_btn_resume_pressed` | `set_paused(false)` |
| `BtnRestart` / `BtnRestartRes` | `pressed` | `_on_btn_restart_pressed` | reinicio en caliente |
| `BtnMainMenu` / `BtnMainMenuRes` | `pressed` | `_on_btn_main_menu_pressed` | vuelve al menú |

> Los dos "REINICIAR" comparten handler, igual los dos "MENÚ".

### Interacción (todo en `Gameplay.gd`)
- **Pausa:** `ESC` (`ui_cancel`) → `set_paused()` → overlay + `get_tree().paused` + `music.stream_paused` + foco en CONTINUAR. Funciona pausado gracias a `process_mode = ALWAYS`.
- **Reinicio en caliente:** `_restart_level()` resetea canción, vida, `next_beat_idx`, director y overlays sin reconstruir la escena.
- **Escudo:** ESPACIO / ENTER / clic / puño → 1.2s de invulnerabilidad (recarga 3s).
- **Movimiento:** flechas / WASD, o palma de la mano si hay datos frescos.
- **Dibujo por código:** nave, sierras, rayos del abanico, anillos, muros, láseres, sparks. Todo vectorial.
- **Daño:** cada contacto con peligro activo resta `hit_health_bonus` (8 mini-jab / 10 proyectil / 12 setpiece); i-frame corto anti-multihit (0.5s, 0.7s tutorial).

---

## 5. FLUJO COMPLETO (historia para el examen)

1. Arranca `MainMenu.tscn` (main scene). Autoloads vivos: `GameManager`, `SoundManager`, `HandTrackingClient`.
2. Menú: título pulsante + barra de 4 botones + panel "NIVEL" (info fija de First Light + récord de progreso + leyenda + INICIAR animado).
3. Botones laterales alternan 3 paneles (`_show_panel` con `visible`; ←/→ ciclan Nivel → Config → Créditos).
4. "▶ INICIAR NIVEL" → `GameManager.change_scene("res://scenes/Gameplay.tscn")`.
5. Gameplay: HUD arriba (canción + progreso) y abajo (barra de progreso). Vida en la nave.
6. `ESC` → `PauseOverlay` (Dim + panel; árbol y música pausados; botones vivos por `ALWAYS`).
7. Morir o terminar → `ResultsOverlay` con progreso y récord.
8. Volver al menú restaura todo; `GameManager` recuerda récords y volúmenes (sobrevive al cambio de escena).

---

## 6. GLOSARIO RÁPIDO

| Término | Qué es |
|---|---|
| `Node` | Unidad básica del árbol |
| `Control` | Nodo de UI |
| `Node2D` | Nodo del mundo 2D (dibujo por código) |
| `CanvasLayer` | Capa de dibujo (HUD adelante, fondo atrás) |
| `VBoxContainer` / `HBoxContainer` | Apila hijos vertical / horizontal |
| `GridContainer` | Grilla de N columnas |
| `PanelContainer` | Caja con fondo que centra a su hijo |
| `Label` / `Button` / `HSlider` / `CheckButton` | Texto / botón (`pressed`) / slider (`value_changed`) / interruptor (`toggled`) |
| `ProgressBar` | Barra de progreso (0–100) |
| `ColorRect` | Rectángulo de color (Dim, previews) |
| `Anchor` | Posición proporcional (15 = llenar, 8 = centrar) |
| `Signal` | Evento UI→código |
| `Theme (.tres)` | Estilos globales; `theme_override_*` = excepción puntual |
| `Autoload` | Singleton global (memoria entre escenas) |
| `process_mode = ALWAYS` | El nodo trabaja incluso pausado (menú de pausa) |
| `mouse_filter = 2` | El Control no bloquea clicks |
| `Overlay` | Pantalla temporal: Dim + panel centrado |

---

*Documento actualizado — código manda. Feria de Ciencias 2026.*
