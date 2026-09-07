# REPORTE DE UI — ABSTRACT PULSE

> **Proyecto:** FeriaDeCiencias — "Abstract Pulse"
> **Motor:** Godot Engine 4.7 (renderer Forward+)
> **Finalidad:** Documento de estudio para explicar la interfaz (UI) en un examen, asumiendo que NO se conoce Godot.
> **Resolución de ventana:** 1280×720

---

## 1. IDEA GENERAL EN UNA FRASE

"Abstract Pulse" es un **juego rítmico de acción** con estética neón/abstracta: hay que mover una nave al ritmo de la música, esquivar peligros y capturar nodos. Su UI (interfaz) está 100% construida con **nodos de Godot del tipo `Control`**, organizados en **contenedores** (cajas que acomodan los elementos automáticamente), con un **tema visual global** (colores neón) y **señales** que conectan los botones con la lógica.

---

## 2. CONCEPTOS DE GODOT QUE HAY QUE SABER SÍ O SÍ (explicados para principiantes)

### 2.1 Nodo (Node)
Todo lo que existe en una escena de Godot es un **nodo**: un botón, una etiqueta de texto, una barra, la cámara, el fondo… Cada nodo tiene un **tipo** y una posición en el árbol jerárquico (padres e hijos). Ejemplo: dentro del botón "JUGAR" hay texto; el botón es padre, el texto es hijo.

### 2.2 Escena (.tscn)
Un **archivo de escena** (terminación `.tscn`, "text scene") es una *plantilla guardada* de un árbol de nodos. Piensen en una escena como "una pantalla del juego" o "un componente reutilizable". Este proyecto tiene 3 escenas:
- `MainMenu.tscn` → el menú principal
- `Gameplay.tscn` → la pantalla de juego
- `Main.tscn` → pantalla de título residual (simple)

### 2.3 El árbol de escena (SceneTree)
Cuando el juego corre, todas las escenas se combinan en un **árbol vivo**. `MainMenu.tscn` es la escena raíz que arranca (configurada en `project.godot` como `run/main_scene`).

### 2.4 Node2D vs Control (¡CLAVE!)
Godot tiene dos grandes familias de nodos:
- **`Node2D`** → para cosas del **mundo del juego** (naves, proyectiles, enemigos). Tienen posición en píxeles X/Y y se dibujan con código (`_draw()`).
- **`Control`** → para **interfaz de usuario** (botones, etiquetas, menús). Estos son los nodos "UI" propiamente dichos.

> **En este proyecto:** `Gameplay.tscn` es `Node2D` (mundo del juego) pero **contiene** capas de `Control` (el HUD). `MainMenu.tscn` es `Control` puro (todo es UI).

### 2.5 CanvasLayer — capas de dibujo
Un `CanvasLayer` le dice a Godot **en qué "piso" dibujar** algo, independientemente de la cámara:
- En Gameplay: `BackgroundLayer` (layer = -1, atrás) y `HUDLayer` (layer = 10, adelante).
- Así el HUD (marcador, barras) siempre queda visible por encima del juego, aunque la nave se mueva.

### 2.6 Contenedores (Container) — el layout automático
Los `*Container` son nodos `Control` que **acomodan a sus hijos automáticamente** (como un "flexbox" de CSS). Son la base del diseño responsive:
- **`VBoxContainer`** → apila hijos **verticalmente** (uno abajo del otro).
- **`HBoxContainer`** → apila hijos **horizontalmente** (uno al lado del otro).
- **`BoxContainer`** → clase padre de los dos anteriores.
- **`GridContainer`** → coloca hijos en **grilla** (columnas configurables).
- **`PanelContainer`** → caja con borde/fondo que recibe un solo hijo y lo centra.

> **Ventaja:** si la ventana cambia de tamaño, los contenedores redistribuyen los elementos automáticamente. No hace falta posicionar píxel a píxel.

### 2.7 Anclas (Anchors) y layout_mode
Cuando un nodo `Control` NO está dentro de un contenedor, se posiciona por **anclas**: fracciones del rectángulo del padre (0 = borde izquierdo/arriba, 1 = borde derecho/abajo).
- `anchors_preset = 15` con `anchor_right = 1.0` y `anchor_bottom = 1.0` → **el nodo ocupa TODO el padre** (fondo completo).
- `anchors_preset = 8` con anclas en 0.5 → **centrado en el medio** (con offsets negativos/positivos para el tamaño). Así se centran los paneles de pausa (`offset_left = -180`, `offset_right = 180` → panel de 360 px de ancho, centrado).

### 2.8 Señales (Signals) — cómo "conversan" los nodos
Una **señal** es un evento que un nodo emite y otro escucha (como un evento de JavaScript). El botón emite `pressed` cuando lo clickean; el script principal la conecta a un método `_on_...`.

**En el `.tscn` se ven así:**
```
[connection signal="pressed" from="Layout/Content/SideNav/BtnNavPlay" to="." method="_on_btn_nav_play_pressed"]
```
→ "Cuando el nodo `BtnNavPlay` emita `pressed`, llamar a `_on_btn_nav_play_pressed()` en la raíz (`to="."`)".

### 2.9 Autoload (Singleton global)
En `project.godot` hay una sección `[autoload]` que registra scripts que **existen siempre**, desde el arranque hasta el cierre, en cualquier escena:
- `GameManager` → estado global: canción elegida, modo de control, paleta de colores, volúmenes, récords. **Es la "memoria" del juego entre pantallas.**
- `SoundManager` → sonidos procedurales (hover, click, beat).
- `_mcp_game_helper` → helper del plugin Godot AI (para desarrollo, no es del juego).

> **Concepto clave para el examen:** un autoload sobrevive al cambio de escena. Por eso `GameManager` recuerda qué canción elegiste en el menú cuando entrás a Gameplay.

### 2.10 Tema (Theme / .tres)
Un `Theme` es un archivo `.tres` (recurso de texto) que define **estilos globales**: colores, fuentes, fondos de botones. El proyecto usa `resources/neon_theme.tres` aplicado a las escenas. Sobre él, cada nodo puede **anular estilos puntuales** con `theme_override_*`:
- `theme_override_colors/font_color` → color del texto
- `theme_override_font_sizes/font_size` → tamaño de fuente
- `theme_override_constants/separation` → separación entre hijos de un contenedor

### 2.11 Métodos de ciclo de vida de un script
- `_ready()` → se ejecuta **una vez**, cuando el nodo entra al árbol. Sirve para inicializar UI.
- `_process(delta)` → se ejecuta **cada frame** (delta = tiempo entre frames). Para animaciones y actualizaciones continuas.
- `_input(event)` → se ejecuta con cada evento de entrada (tecla, click).
- `_draw()` → dibujo por código (líneas, círculos). Combinado con `queue_redraw()` que pide redibujar.
- `_on_btn_x_pressed()` → métodos conectados a señales de botones (convención de nombre `_on_<nodo>_<evento>`).

### 2.12 @onready
`@onready var label: Label = $Ruta/Del/Nodo` → declara una variable que se rellena **cuando el nodo está listo** con la referencia a otro nodo por su **ruta en el árbol** (`$` = relativo a mí). Ejemplo: `$HUDLayer/HUD/Header/TrackTitle`. Es la forma estándar de "agarrar" un nodo de la UI desde el código.

---

## 3. LA ESCENA `MainMenu.tscn` (el menú principal) — árbol completo

```
MainMenu (Control — raíz, ocupa toda la pantalla, tema neon, script MainMenu.gd)
├── Background (Control → script NeonBackground.gd)   ← fondo animado
├── Layout (VBoxContainer — ocupa toda la pantalla, separación 20)
│   ├── Header (HBoxContainer — fila superior, alto 80)
│   │   ├── TitleContainer (VBoxContainer)
│   │   │   ├── Title (Label "ABSTRACT PULSE", 42px, cyan)          ← pulsa al ritmo
│   │   │   └── Subtitle (Label "RHYTHM ACTION // FERIA DE CIENCIAS 2026")
│   │   └── StatusContainer (VBoxContainer, alineado a la derecha)
│   │       ├── ControlBadge (Label "[ TECLADO + MOUSE ]")
│   │       └── StatusLabel (Label "● Sistema listo")
│   └── Content (HBoxContainer — fila principal, separación 24)
│       ├── SideNav (VBoxContainer — barra lateral, ancho 300, centrado vertical)
│       │   ├── BtnNavPlay (Button "JUGAR / CANCIONES")
│       │   ├── BtnNavControls (Button "CONTROLES Y CÁMARA")
│       │   ├── BtnNavUpgrades (Button "UPGRADES Y ESTÉTICA")
│       │   ├── BtnNavSettings (Button "CONFIGURACIÓN")
│       │   ├── BtnNavCredits (Button "CRÉDITOS Y FERIA")
│       │   └── BtnNavExit (Button "SALIR DEL JUEGO")
│       └── Panels (PanelContainer — panel central, expande horizontalmente)
│           ├── SongSelectPanel (Control — visible)      ← "SELECCIÓN DE CANCIÓN"
│           │   └── VBox (VBoxContainer)
│           │       ├── Header (Label "SELECCIÓN DE CANCIÓN", 22px)
│           │       ├── TrackList (VBoxContainer)        ← botones de canciones GENERADOS POR CÓDIGO
│           │       ├── HSeparator
│           │       └── Details (VBoxContainer)
│           │           ├── TrackTitle (Label, 26px, color de la canción)
│           │           ├── TrackInfo (Label: artista | BPM | duración)
│           │           ├── TrackDesc (Label descripción, autowrap)
│           │           ├── HighScoreLabel (Label "RÉCORD PERSONAL: X PTS", dorado)
│           │           └── BtnPlayLevel (Button "▶ INICIAR NIVEL", alto 54)
│           ├── ControlsPanel (Control — oculto)         ← "CONFIGURACIÓN DE CONTROLES"
│           │   └── VBox → Header, ModeContainer (HBox) con BtnMediaPipe / BtnKeyboard,
│           │         Instructions (Label), TestBoxContainer → LabelTest + TestBox (ColorRect)
│           │         + HandCursor (ColorRect 24×24, cyan)   ← cursor que sigue al mouse
│           ├── UpgradesPanel (Control — oculto)         ← "PERSONALIZACIÓN VISUAL"
│           │   └── VBox → Header, PaletteContainer (HBox) con 4 botones de paleta
│           │         (Cyan/Magenta/Gold/Emerald), PreviewContainer → LabelPreview
│           │         + ShipPreview (ColorRect 100×100 = color de la nave)
│           ├── SettingsPanel (Control — oculto)         ← "CONFIGURACIÓN DEL SISTEMA"
│           │   └── VBox → Header, Grid (GridContainer de 2 columnas):
│           │         LabelMaster+SliderMaster(HSlider 0-1, paso 0.05, valor 0.8)
│           │         LabelMusic+SliderMusic(0.8), LabelSFX+SliderSFX(0.9),
│           │         LabelFS+CheckFullscreen(CheckButton)
│           └── CreditsPanel (Control — oculto)          ← "ACERCA DEL PROYECTO"
│               └── VBox → Header (Label) + InfoText (Label multilínea con créditos)
```

### Señales conectadas (12 en total, todas al script raíz `MainMenu.gd`)
| Nodo emisor | Señal | Método que se llama | Efecto en la UI |
|---|---|---|---|
| `BtnNavPlay` | `pressed` | `_on_btn_nav_play_pressed` | Muestra `SongSelectPanel` |
| `BtnNavControls` | `pressed` | `_on_btn_nav_controls_pressed` | Muestra `ControlsPanel` |
| `BtnNavUpgrades` | `pressed` | `_on_btn_nav_upgrades_pressed` | Muestra `UpgradesPanel` |
| `BtnNavSettings` | `pressed` | `_on_btn_nav_settings_pressed` | Muestra `SettingsPanel` |
| `BtnNavCredits` | `pressed` | `_on_btn_nav_credits_pressed` | Muestra `CreditsPanel` |
| `BtnNavExit` | `pressed` | `_on_btn_nav_exit_pressed` | `get_tree().quit()` — cierra el juego |
| `BtnPlayLevel` | `pressed` | `_on_btn_play_level_pressed` | Cambia escena a `Gameplay.tscn` |
| `BtnMediaPipe` | `pressed` | `_on_btn_mode_mediapipe_pressed` | Activa modo manos (badge naranja) |
| `BtnKeyboard` | `pressed` | `_on_btn_mode_keyboard_pressed` | Activa modo teclado (badge cyan) |
| `BtnPaletteCyan/Magenta/Gold/Emerald` | `pressed` | `_on_btn_palette_*_pressed` | Cambia color de nave en preview |
| `SliderMaster/Music/SFX` | `value_changed` | `_on_slider_*_value_changed` | Actualiza volúmenes (master también aplica a `AudioServer`) |
| `CheckFullscreen` | `toggled` | `_on_check_fullscreen_toggled` | Pantalla completa / ventana |

### Comportamiento dinámico (hecho en código, no en el editor)
1. **`_ready()`**: configura audio de botones, badge de control, genera la lista de canciones **por código** (`_populate_track_list()` crea un `Button.new()` por cada canción de `GameManager.TRACKS` y los agrega a `TrackList`), selecciona la canción 0, actualiza el preview de paleta y abre `SongSelectPanel` por defecto.
2. **`_process(delta)`**: hace "latir" el título (varía el brillo del color con `sin()` según el BPM) y, si el panel de controles está activo, mueve el `HandCursor` siguiendo el mouse dentro del `TestBox` (con `clamp()` para que no se salga).
3. **`_connect_audio_recursive()`**: recorre TODO el árbol (`get_children()`) y a cada `Button` le conecta `mouse_entered → play_hover()` y `pressed → play_click()`. Por eso **todos** los botones suenan sin conectarlos uno por uno.
4. **`_show_panel(panel)`**: el "sistema de pestañas" del menú — pone en `visible = true` solo el panel elegido y `false` a los otros 4.

> **Dato para el examen:** los botones de canción NO están en el `.tscn`; se crean en tiempo de ejecución con `Button.new()`. Es UI **generada proceduralmente**.

---

## 4. LA ESCENA `Gameplay.tscn` (el juego) — árbol completo

```
Gameplay (Node2D — raíz del mundo, script Gameplay.gd)
├── BackgroundLayer (CanvasLayer, layer = -1 → atrás de todo)
│   └── Background (Control → script NeonBackground.gd, ocupa toda la pantalla)
└── HUDLayer (CanvasLayer, layer = 10 → adelante de todo)
	├── HUD (VBoxContainer, ocupa toda la pantalla, mouse_filter = 2 → "ignora clicks")
	│   ├── Header (HBoxContainer)
	│   │   ├── TrackTitle (Label "CANCIÓN: ... | BPM: 128", 20px)
	│   │   └── ScoreLabel (Label "PUNTAJE: 0 | COMBO: x0", dorado)
	│   └── Bottom (VBoxContainer, expande 10)
	│       ├── ProgressBar (ProgressBar, alto 12, sin porcentaje)   ← progreso de la canción
	│       └── HealthBar (TextureProgressBar, valor 100)            ← vida de la nave
	├── PauseOverlay (Control, oculto, ocupa todo)
	│   ├── Dim (ColorRect negro 75% opaco)                          ← fondo oscurecido
	│   └── Panel (PanelContainer 360×320, centrado con anclas 0.5)
	│       └── VBox → Title (Label "JUEGO PAUSADO", 28px),
	│             BtnResume ("CONTINUAR"), BtnRestart ("REINICIAR NIVEL"),
	│             BtnMainMenu ("MENÚ PRINCIPAL")
	└── ResultsOverlay (Control, oculto, ocupa todo)
		├── Dim (ColorRect negro 82%)
		└── Panel (PanelContainer 400×300, centrado)
			└── VBox → Title (Label "¡NIVEL PROCEDURAL COMPLETADO!" o "MISIÓN FALLIDA"),
				  ScoreDetails (Label: puntaje + combo máximo + ¿nuevo récord?),
				  BtnRestartRes ("REINICIAR"), BtnMainMenuRes ("MENÚ PRINCIPAL")
```

### Señales conectadas (6)
| Nodo emisor | Señal | Método | Efecto |
|---|---|---|---|
| `PauseOverlay/.../BtnResume` | `pressed` | `_on_btn_resume_pressed` | `toggle_pause()` → reanuda |
| `PauseOverlay/.../BtnRestart` | `pressed` | `_on_btn_restart_pressed` | `reload_current_scene()` — reinicia el nivel |
| `PauseOverlay/.../BtnMainMenu` | `pressed` | `_on_btn_main_menu_pressed` | Vuelve a `MainMenu.tscn` |
| `ResultsOverlay/.../BtnRestartRes` | `pressed` | `_on_btn_restart_pressed` (compartido) | Reinicia |
| `ResultsOverlay/.../BtnMainMenuRes` | `pressed` | `_on_btn_main_menu_pressed` (compartido) | Menú principal |

> **Dato interesante:** los dos botones "REINICIAR" de overlays distintos comparten el **mismo método**. La señal conecta nodos diferentes a un único handler.

### Interacción con el juego (no-UI pero visibles en pantalla)
- **Pausa:** tecla `ESC` (`ui_cancel`) → `toggle_pause()` → muestra/oculta `PauseOverlay` y pone `get_tree().paused = true/false` (pausa TODO el árbol).
- **Disparo:** `ESPACIO` / `ENTER` / click izquierdo → doble láser.
- **Movimiento:** flechas / WASD → mueven `player_pos` (la nave).
- **Dibujo por código (`_draw()`)** en el `Node2D` raíz: la nave (triángulo neón con `draw_polyline`), proyectiles (líneas), targets (arcos + círculo interior), hazards (círculo rojo pulsante) y sparks (partículas que se desvanecen). **No hay sprites**: todo es dibujo vectorial procedimental.
- **HUD en vivo:** `_process()` actualiza `ProgressBar` (progreso de la canción), `ScoreLabel` ("PUNTAJE: X | COMBO: xY") y la `TextureProgressBar` de vida al golpear/fallar.
- El generador procedural (`ProceduralLevelGenerator.gd`) crea la ola de nodos/peligros según la semilla y el progreso de la canción (`get_phase_name(progress)` → nombre de fase en el título).

---

## 5. LA ESCENA `Main.tscn` (pantalla residual)

```
Main (Node2D → Main.gd)
├── Background (ColorRect 1280×720, gris oscuro)
└── Title (Label 48px "Abstract Pulse", cyan, centrado aproximadamente)
```
Una pantalla de título mínima que quedó del prototipo (no es la escena principal del juego).

---

## 6. CÓMO SE VEN LOS ARCHIVOS DE ESCENA (formato .tscn)

Un `.tscn` es texto estructurado. Tres secciones:
1. **Cabecera**: `[gd_scene load_steps=5 format=3 uid="uid://..."]` → metadatos, cantidad de recursos a cargar, formato.
2. **Recursos externos**: `[ext_resource type="Theme" path="res://resources/neon_theme.tres" id="1_theme"]` → recursos que se importan (temas, scripts). Se referencian después con `ExtResource("1_theme")`.
3. **Nodos**: `[node name="X" type="Y" parent="ruta"]` → cada nodo con sus propiedades. La indentación NO importa; la jerarquía se define con `parent="Layout/Header"`.

### Ejemplo real comentado (del MainMenu.tscn):
```
[node name="BtnNavPlay" type="Button" parent="Layout/Content/SideNav"]
layout_mode = 2                                   # modo container (lo ordena el padre)
text = "JUGAR / CANCIONES"                        # texto del botón
```
```
[node name="Layout" type="VBoxContainer" parent="."]
anchors_preset = 15                               # preset "rect completo"
anchor_right = 1.0
anchor_bottom = 1.0
offset_left = 32.0                                # márgenes internos de 32px
offset_top = 24.0
offset_right = -32.0
offset_bottom = -24.0
theme_override_constants/separation = 20          # 20px entre hijos
```

---

## 7. FLUJO COMPLETO DE LA UI (para contar en el examen como historia)

1. El juego arranca cargando `MainMenu.tscn` (escena principal configurada en `project.godot`). Los autoloads `GameManager` y `SoundManager` ya están vivos.
2. El menú muestra: título pulsante, barra lateral con 6 botones, y el panel "SELECCIÓN DE CANCIÓN" con sus botones de canciones generados por código y el detalle de la canción seleccionada.
3. El usuario navega entre los 5 paneles con los botones laterales (sistema `_show_panel` de visibilidad).
4. En "CONTROLES Y CÁMARA" elige modo (teclado = activo / MediaPipe = próximo). En "UPGRADES Y ESTÉTICA" elige paleta y ve el preview. En "CONFIGURACIÓN" ajusta 3 sliders y el fullscreen (se guardan en `GameManager`).
5. Presiona "▶ INICIAR NIVEL" → `GameManager.change_scene("res://scenes/Gameplay.tscn")` → **cambio de escena** (el árbol del menú se reemplaza por el del juego).
6. En Gameplay: HUD arriba (título+score) y abajo (progreso + vida). La capa `HUDLayer` (10) siempre dibuja sobre el mundo.
7. El jugador esquiva y dispara; el HUD se actualiza en tiempo real desde `_process()`.
8. `ESC` pausa → `PauseOverlay` (fondo oscurecido + panel centrado). Si muere o termina la canción → `ResultsOverlay` con resultado y récord.
9. Volver al menú = `GameManager.change_scene` de nuevo → el `GameManager` **recuerda** la configuración (el autoload nunca se destruye).

---

## 8. GLOSARIO RÁPIDO (para estudiar de memoria)

| Término | Qué es |
|---|---|
| `Node` | Unidad básica del árbol de escena |
| `Control` | Nodo de UI (botones, labels, barras) |
| `Node2D` | Nodo del mundo 2D (nave, proyectiles) |
| `CanvasLayer` | Capa de dibujo con z-order propio (HUD adelante, fondo atrás) |
| `VBoxContainer` / `HBoxContainer` | Apila hijos vertical / horizontal (layout automático) |
| `GridContainer` | Grilla de N columnas |
| `PanelContainer` | Panel con fondo que centra a su hijo |
| `Label` | Texto |
| `Button` | Botón clicable (emite `pressed`) |
| `HSlider` | Barra deslizante (emite `value_changed`) |
| `CheckButton` | Interruptor sí/no (emite `toggled`) |
| `ProgressBar` | Barra de progreso (valor 0-100) |
| `TextureProgressBar` | Barra de vida con textura |
| `ColorRect` | Rectángulo de color sólido (dim, previews, cursor) |
| `Anchor` | Posicionamiento proporcional al padre (preset 15 = llenar todo, 8 = centrar) |
| `layout_mode` | 0 = posición libre, 1 = anclas, 2 = dentro de contenedor, 3 = raíz |
| `size_flags_horizontal/vertical` | "Peso" de expansión dentro de un contenedor (3 = expandir, 10 = expandir+ocupar más) |
| `Signal` | Evento que conecta nodos (`pressed`, `value_changed`, `toggled`) |
| `ext_resource` | Recurso importado (theme, script) en el .tscn |
| `sub_resource` | Recurso definido adentro del propio .tscn |
| `Theme (.tres)` | Estilos globales de UI (colores, fuentes) |
| `theme_override_*` | Anular estilo de un nodo puntual |
| `Autoload` | Singleton global que vive siempre (GameManager, SoundManager) |
| `@onready` | Carga la referencia al nodo cuando está listo |
| `_ready()` | Corre una vez al entrar al árbol |
| `_process(delta)` | Corre cada frame |
| `_draw()` + `queue_redraw()` | Dibujo vectorial por código |
| `get_tree().paused` | Pausa global de todo el juego |
| `change_scene_to_file()` | Cambia de escena (destruye la actual) |
| `mouse_filter` | 2 = el nodo no captura clicks (HUD "transparente" al mouse) |

---

## 9. POSIBLES PREGUNTAS DE EXAMEN Y SUS RESPUESTAS

**Q: ¿Cómo está estructurada la UI del menú?**
R: Es un árbol de nodos `Control`: un `VBoxContainer` raíz que divide la pantalla en Header (título + estado) y Content (HBoxContainer con SideNav de 6 botones y un PanelContainer central que muestra 5 paneles intercambiables mediante `visible`).

**Q: ¿Cómo se conectan los botones con la lógica?**
R: Con **señales**. Cada botón emite `pressed`; en el `.tscn` hay `[connection ...]` que las enlaza a métodos `_on_..._pressed()` del script de la escena. Además, el script conecta por código sonidos de hover/press a TODOS los botones de forma recursiva.

**Q: ¿Cómo se hace el menú escalable/responsive?**
R: Usando contenedores (`VBoxContainer`, `HBoxContainer`, `GridContainer`) que acomodan los hijos automáticamente, más `size_flags` para expansión y anclas para los paneles centrados. Si cambia la resolución, el layout se redistribuye solo.

**Q: ¿Cómo se mantiene el HUD siempre visible en Gameplay?**
R: El HUD vive en un `CanvasLayer` con `layer = 10` (z alto), y el fondo en otro con `layer = -1`. Las capas se dibujan siempre por encima/debajo del mundo 2D, con `mouse_filter = 2` para que no bloqueen los clicks del juego.

**Q: ¿Cómo pasa la información del menú al juego?**
R: A través del **autoload `GameManager`**: cuando seleccionás una canción, `select_track()` guarda el índice y emite la señal `track_selected`; `Gameplay.gd` lee `GameManager.get_current_track()`. El autoload persiste entre escenas porque es un singleton global.

**Q: ¿Los botones de canciones existen en el editor?**
R: No. Se crean en runtime con `Button.new()` en `_populate_track_list()`, recorriendo el array `TRACKS` de `GameManager`. Es UI generada proceduralmente, y cada botón conecta su señal `pressed` a `_select_track_ui(idx)` con un closure (captura el índice).

**Q: ¿Qué hace exactamente `queue_redraw()`?**
R: Marca el nodo para ser redibujado en el próximo frame; Godot entonces ejecuta `_draw()`. Se usa cada frame en `_process()` para animar el fondo neón (grilla en perspectiva, anillos de pulso, partículas) y la nave/proyectiles.

**Q: ¿Cómo se pausa el juego desde la UI?**
R: `ESC` dispara `_input()` → `toggle_pause()`: alterna `get_tree().paused` (que congela el procesamiento de todos los nodos) y muestra el `PauseOverlay` (un `ColorRect` oscuro + panel centrado con 3 botones cuyas señales van a `_on_btn_resume/restart/main_menu_pressed`).

**Q: ¿Qué es un Theme y cómo se usa acá?**
R: Es un recurso `.tres` con estilos globales (`resources/neon_theme.tres`). Se asigna a la escena entera (`theme = ExtResource(...)`) y los nodos particulares lo anulan puntualmente con `theme_override_colors/font_color` y `theme_override_font_sizes/font_size` para lograr la paleta neón (cyan #00F0FF, magenta, dorado).

**Q: ¿Cómo se dibuja la nave si no hay imagen?**
R: En `_draw()` del nodo raíz `Node2D` se usa `draw_polyline()` con 3 puntos para formar el triángulo de la nave, `draw_circle()` para el núcleo, y bucles sobre arrays de diccionarios (`projectiles`, `targets`, `spark_effects`) para dibujar proyectiles, nodos rítmicos y partículas. Todo es gráfica vectorial en tiempo real.

---

*Documento generado para estudio — Feria de Ciencias 2026. Suerte en el examen 🎮*
