# REPORTE SOLO UI — ABSTRACT PULSE
> Documento de estudio enfocado ÚNICAMENTE en la interfaz (UI). Nada de lógica de juego.
> Motor: Godot 4.7 · Resolución: 1280×720 · Estética: neón/abstracta

---

## 1. LA IDEA EN UNA FRASE

La UI es todo lo que el jugador **ve y toca fuera de la acción**: el menú principal, las barras del juego (vida, progreso), el puntaje y las pantallas de pausa y resultados. En Godot, **toda la UI está hecha con nodos tipo `Control`** (botones, etiquetas, contenedores, barras) organizados en un árbol jerárquico.

---

## 2. LAS 3 "PANTALLAS" DEL JUEGO (escenas)

| Escena | Es la pantalla de... | Tipo de nodo raíz |
|---|---|---|
| `MainMenu.tscn` | Menú principal (lo primero que se ve) | `Control` (pura UI) |
| `Gameplay.tscn` | Juego en acción (tiene la UI encima del juego) | `Node2D` (mundo) + capas de UI |
| ~~`Main.tscn`~~ | (eliminada en la rama simplify-ui) | — |

La escena que arranca al abrir el juego es `MainMenu.tscn` (configurado en `project.godot` como `run/main_scene`).

---

## 3. LOS PIEZAS DE UI QUE EXISTEN EN GODOT (y cómo se llaman acá)

### 3.1 Grupos de columnas/filas (contenedores) — el "layout automático"
Estos nodos **acomodan solos** a sus hijos; no hay que posicionar nada a mano:
- **`VBoxContainer`** → apila los hijos **uno abajo del otro** (columna).
- **`HBoxContainer`** → apila los hijos **uno al lado del otro** (fila).
- **`GridContainer`** → coloca los hijos en una **grilla** de columnas (acá se usa con 2 columnas en Configuración).
- **`PanelContainer`** → una **caja con fondo/borde** que centra a su hijo dentro (acá = los paneles de Pausa y Resultados).

> Concepto clave: con contenedores, si la ventana cambia de tamaño, **todo se reacomoda solo** (UI responsiva).

### 3.2 Controles básicos (los elementos visibles)
- **`Label`** → texto. Ej: título "ABSTRACT PULSE", "PUNTAJE: 0 | COMBO: x0", "RÉCORD PERSONAL: 12500 PTS".
- **`Button`** → botón clicable. Ej: "JUGAR / CANCIONES", "▶ INICIAR NIVEL", "CONTINUAR".
- **`HSlider`** → barra deslizante horizontal. Ej: los 3 sliders de volumen (Master, Música, SFX).
- **`CheckButton`** → interruptor encendido/apagado. Ej: "Pantalla Completa".
- **`ProgressBar`** → barra de progreso. Ej: progreso de la canción (0→100%).
- **`TextureProgressBar`** → barra con textura/color. Ej: **barra de vida** de la nave (100→0).
- **`ColorRect`** → rectángulo de color sólido. Ej: fondo oscuro del overlay ("Dim"), el preview de color de nave, el cursor de prueba.
- **`HSeparator`** → línea separadora horizontal.

### 3.3 Cómo se posiciona un Control
- **Dentro de un contenedor:** no se posiciona, el contenedor lo ubica. (`layout_mode = 2`)
- **Con anclas (anchors):** fracciones del padre. Dos usos importantes en este proyecto:
  - Anclas en 0 y 1 (`anchors_preset = 15`) → el nodo **ocupa toda la pantalla** del padre. Se usa para fondos, el `Dim` oscuro de los overlays y el HUD.
  - Anclas en 0.5 (`anchors_preset = 8`) → el nodo queda **centrado**. Se usa para el panel de Pausa (360×320) y el de Resultados (400×300): quedan flotando en el medio de la pantalla.

### 3.4 Capas (CanvasLayer) — orden de dibujo
Un `CanvasLayer` decide **qué se dibuja arriba de qué**, sin importar la cámara:
- `BackgroundLayer` con `layer = -1` → el fondo queda **atrás de todo**.
- `HUDLayer` con `layer = 10` → el HUD (puntaje, barras, overlays) queda **siempre adelante**, aunque la nave se mueva por el medio.
- Los overlays de Pausa/Resultados viven **dentro** de `HUDLayer`, así tapan todo cuando aparecen.

### 3.5 Tema (Theme / .tres) — los colores neón globales
El archivo `resources/neon_theme.tres` define los estilos de toda la UI. Cada nodo puede **anular** su estilo puntual con:
- `theme_override_colors/font_color` → color del texto (cyan `#00F0FF`, dorado, magenta).
- `theme_override_font_sizes/font_size` → tamaño de fuente (título 42px, headers 22px...).
- `theme_override_constants/separation` → espacio entre hijos de un contenedor (ej. 20px).

---

## 4. UI DEL MENÚ PRINCIPAL (`MainMenu.tscn`) — la más importante

```
MainMenu (Control = raíz, ocupa toda la pantalla, con Theme aplicado)
├── Background (Control) — fondo animado neón (grilla + partículas)
└── Layout (VBoxContainer) — divide la pantalla en 2 bloques verticales
    ├── Header (HBoxContainer) — fila superior
    │   ├── TitleContainer (VBoxContainer)
    │   │   ├── Title (Label "ABSTRACT PULSE", 42px, cyan) — "late" al ritmo
    │   │   └── Subtitle (Label "RHYTHM ACTION // FERIA DE CIENCIAS 2026")
    └── Content (HBoxContainer) — fila principal: barra lateral + panel central
        ├── SideNav (VBoxContainer, ancho 300) — la barra de navegación
        │   ├── BtnNavPlay (Button "JUGAR / CANCIONES")
        │   ├── BtnNavSettings (Button "CONFIGURACIÓN")
        │   └── BtnNavExit (Button "SALIR DEL JUEGO")
        └── Panels (PanelContainer) — panel central que muestra 1 de 2 pantallas
            ├── SongSelectPanel (Control) — VISIBLE por defecto
            │   └── VBox (VBoxContainer)
            │       ├── Header (Label "SELECCIÓN DE CANCIÓN", 22px)
            │       ├── TrackButtons (VBoxContainer) — 4 botones ESTÁTICOS:
            │       │     BtnTrack0..3 (Nivel Procedural MVC / Cyber Genesis /
            │       │     Neon Rush / Overdrive Pulse)
            │       ├── HSeparator — línea divisoria
            │       └── Details (VBoxContainer)
            │           ├── TrackTitle (Label, 26px)
            │           ├── TrackInfo (Label: artista | BPM | duración)
            │           ├── TrackDesc (Label descripción, con autowrap)
            │           ├── HighScoreLabel (Label "RÉCORD PERSONAL: X PTS", dorado)
            │           └── BtnPlayLevel (Button "▶ INICIAR NIVEL", alto 54)
            └── SettingsPanel (Control) — OCULTO: GridContainer de 2 columnas
                → 3 HSlider (Master 0.8 / Música 0.8 / SFX 0.9) + CheckButton fullscreen
```

> **Simplificación aplicada (rama simplify-ui):** se eliminaron los paneles de
> Controles (MediaPipe), Upgrades y Créditos, junto con sus botones de la barra
> lateral. Ahora la barra tiene 3 botones y el panel central alterna entre
> Selección de Canción y Configuración.

### Cómo funciona la navegación entre paneles (el corazón de la UI del menú)
Es un **sistema de pestañas**: hay 2 paneles apilados, todos en el mismo lugar. El script tiene un método `_show_panel(panel)` que hace:
- El panel elegido → `visible = true`
- El otro → `visible = false`

Cada botón de la barra lateral llama a `_show_panel(panel_correspondiente)`.

> **Simplificación:** ahora los botones de canciones **sí están en el editor** como
> nodos `Button` estáticos (`BtnTrack0`..`BtnTrack3`) dentro de `TrackButtons`.
> Antes se creaban por código con `Button.new()`; ahora cada uno tiene su conexión
> `pressed` estática en el `.tscn` que llama a `_on_btn_track_N_pressed()`.

---

---

## 5. UI DURANTE EL JUEGO (`Gameplay.tscn`) — HUD + Overlays

Solo la parte de interfaz (el juego en sí es `Node2D`, no es UI):

```
Gameplay (Node2D — mundo del juego)
├── BackgroundLayer (CanvasLayer layer -1) — fondo
└── HUDLayer (CanvasLayer layer 10) — TODA la UI del juego vive acá
    ├── HUD (VBoxContainer, pantalla completa, mouse_filter = 2 → ignora clicks)
    │   ├── TopBar (HBoxContainer) — barra superior
    │   │   ├── TrackTitle (Label "CANCIÓN: ... | BPM: 128", 20px)
    │   │   └── ScoreLabel (Label "PUNTAJE: 0 | COMBO: x0", dorado)
    │   └── BottomBar (VBoxContainer) — barra inferior
    │       ├── ProgressBar (barra de progreso de la canción)
    │       └── HealthBar (TextureProgressBar — barra de vida, valor 100)
    ├── PauseOverlay (Control, pantalla completa, OCULTO)
    │   ├── Dim (ColorRect negro 75% transparente) — oscurece el fondo
    │   └── Panel (PanelContainer 360×320 CENTRADO con anclas 0.5)
    │       └── VBox → Title "JUEGO PAUSADO" (28px) + BtnResume "CONTINUAR"
    │             + BtnRestart "REINICIAR NIVEL" + BtnMainMenu "MENÚ PRINCIPAL"
    └── ResultsOverlay (Control, pantalla completa, OCULTO)
        ├── Dim (ColorRect negro 82%)
        └── Panel (PanelContainer 400×300 CENTRADO)
            └── VBox → Title ("¡NIVEL PROCEDURAL COMPLETADO!" verde o "MISIÓN FALLIDA" rojo)
                  + ScoreDetails (Label: puntaje final + combo máximo + nuevo récord)
                  + BtnRestartRes "REINICIAR" + BtnMainMenuRes "MENÚ PRINCIPAL"
```

### Cómo se comporta el HUD
- **`mouse_filter = 2`** en el HUD → el HUD **no bloquea los clicks** del juego (los disparos pasan "a través").
- El `ScoreLabel` y las barras se actualizan **cada frame** desde el script (`_process()`): el puntaje/combo cuando pegás o fallás, la barra de progreso según el tiempo de la canción, la barra de vida cuando te golpean.
- El `TrackTitle` muestra la canción + la **fase** del nivel generado.

### Overlays (Pausa y Resultados) — el patrón clásico de UI de juego
1. **Pausa:** apretás `ESC` → aparece `PauseOverlay`: un `Dim` (ColorRect negro semi-transparente) tapa todo el juego + un `Panel` centrado con 3 botones.
2. **Resultados:** al terminar o morir → `ResultsOverlay` con el mismo patrón (Dim + panel centrado) pero con el texto de resultado (título verde "¡COMPLETADO!" o rojo "MISIÓN FALLIDA") y 2 botones.

> **Patrón para el examen:** "overlay = pantalla completa con fondo oscurecido (`ColorRect` con alpha) + panel centrado con contenido". Se usa dos veces: pausa y resultados.

---

## 6. SISTEMA DE PESTAÑAS DEL MENÚ (resumen)

El menú alterna entre **2 paneles** con el método `_show_panel(panel)`:
- `SongSelectPanel` → `visible = true`, `SettingsPanel` → `visible = false`
- o viceversa

Los 4 botones de canciones son **estáticos** (definidos en el `.tscn`), no se generan
por código. Cada uno dispara `_on_btn_track_N_pressed()` que llama a
`_select_track_ui(N)` y muestra los detalles + récord de esa canción en el panel.

---

## 7. CÓMO SE CONECTA LA UI CON EL CÓDIGO (señales)

La parte más conceptual (y probable pregunta de examen):

1. **Cada botón emite señales.** Un `Button` emite `pressed` cuando lo clickean; un `HSlider` emite `value_changed` cuando lo movés; un `CheckButton` emite `toggled` cuando lo cambias.

2. **Las señales se conectan en el archivo de escena (.tscn)** con líneas como:
```
[connection signal="pressed" from="Layout/Content/SideNav/BtnNavPlay" to="." method="_on_btn_nav_play_pressed"]
```
▶ "Cuando el botón `BtnNavPlay` emita `pressed`, llamá al método `_on_btn_nav_play_pressed()` de la raíz de la escena (`to="."`)".

3. **El script reacciona.** Los métodos `_on_..._` son los que cambian la UI. Ejemplos:
   - `_on_btn_nav_settings_pressed()` → `_show_panel(settings_panel)` → muestra Configuración.
   - `_on_btn_play_level_pressed()` → cambia a la escena de juego.
   - `_on_slider_master_value_changed(v)` → cambia el volumen.
   - `_on_check_fullscreen_toggled(on)` → pantalla completa o ventana.
   - `_on_btn_resume_pressed()` → oculta el overlay de pausa y reanuda.

4. **Acceso a los nodos desde el script:** con `@onready var nombre: Tipo = $Ruta/Al/Nodo`. El `$` es "bajá por esta ruta desde mí". Ej: `$Layout/Content/SideNav` agarra la barra lateral. Así el código puede tocar cualquier parte de la UI por nombre.

**Señales conectadas en el proyecto (14):**

Menú (9 directas + los botones de pista):
| Botón/Control | Señal | Resultado en la UI |
|---|---|---|
| BtnNavPlay | pressed | Muestra panel Selección de Canción |
| BtnNavSettings | pressed | Muestra panel Configuración |
| BtnNavExit | pressed | Cierra el juego |
| BtnTrack0..BtnTrack3 | pressed | Selecciona la canción N y muestra sus detalles |
| BtnPlayLevel | pressed | Va a la escena de juego |
| SliderMaster/Music/SFX | value_changed | Cambia volúmenes |
| CheckFullscreen | toggled | Alterna pantalla completa |

Juego (6):
| Botón | Señal | Resultado |
|---|---|---|
| BtnResume | pressed | Reanuda (oculta overlay pausa) |
| BtnRestart | pressed | Reinicia el nivel |
| BtnMainMenu | pressed | Vuelve al menú principal |
| BtnRestartRes | pressed | Reinicia (mismo método que BtnRestart) |
| BtnMainMenuRes | pressed | Vuelve al menú (mismo método que BtnMainMenu) |

> **Detalle que suma:** los botones de Pausa y Resultados **comparten métodos** (BtnRestart y BtnRestartRes llaman al mismo `_on_btn_restart_pressed`). Y en el menú, los sonidos de todos los botones se conectan **por código recursivamente**: el script recorre el árbol (`get_children()`) y a cada Button le agrega sonido de hover (`mouse_entered`) y click (`pressed`) — por eso suenan todos sin conectar nada a mano.

---

## 8. EL FLUJO DE LA UI (historia para contar en el examen)

1. El juego abre en el **menú principal**: título neón arriba, barra lateral de 3 botones a la izquierda, panel central mostrando "SELECCIÓN DE CANCIÓN".
2. Click en los botones laterales → cambia el panel central (pestañas con `visible`, entre Canción y Configuración).
3. En la selección de canción, el jugador ve **4 botones estáticos** de nivel; al elegir uno, el panel de detalles muestra su info y récord.
4. Click en "▶ INICIAR NIVEL" → **cambio de escena** al juego: el árbol del menú se reemplaza por el de Gameplay.
5. Durante el juego, la UI (HUD en su CanvasLayer) muestra: título + fase arriba, puntaje y combo, barra de progreso y barra de vida abajo. Se actualiza en cada frame.
6. `ESC` → overlay de **pausa** (Dim + panel centrado). Botones: continuar / reiniciar / menú.
7. Al terminar o morir → overlay de **resultados** (Dim + panel centrado) con el puntaje final.
8. "MENÚ PRINCIPAL" → cambio de escena de vuelta al menú. La configuración elegida (canción, volumen) se mantiene porque vive en `GameManager`, un **autoload** (singleton global que existe siempre).

---

## 9. GLOSARIO SOLO UI (para memorizar)

| Término | Qué es |
|---|---|
| `Control` | Nodo base de toda UI (botones, labels, etc.) |
| `Label` | Texto en pantalla |
| `Button` | Botón clicable → emite `pressed` |
| `HSlider` | Barra deslizante → emite `value_changed` |
| `CheckButton` | Interruptor sí/no → emite `toggled` |
| `ProgressBar` | Barra de progreso (0-100) |
| `TextureProgressBar` | Barra de vida con textura |
| `ColorRect` | Rectángulo de color (fondos oscuros, previews) |
| `PanelContainer` | Caja con fondo que centra a su hijo |
| `VBoxContainer` | Apila hijos verticalmente |
| `HBoxContainer` | Apila hijos horizontalmente |
| `GridContainer` | Grilla de N columnas |
| `HSeparator` | Línea separadora |
| `CanvasLayer` | Capa de dibujo (HUD siempre adelante) |
| `Anchors` | Posición proporcional al padre (15 = llenar, 8 = centrar) |
| `Theme (.tres)` | Estilos globales de colores/fuentes |
| `theme_override_*` | Anular estilo en un nodo puntual |
| `Signal` | Evento que conecta UI con código (`pressed`, `value_changed`, `toggled`) |
| `Autoload` | Nodo global que vive siempre (GameManager = "memoria" de la UI) |
| `@onready` | Forma de agarrar un nodo de la UI por ruta (`$Ruta/Nodo`) |
| `_ready()` | Corre una vez al iniciar la escena (inicializa la UI) |
| `_process(delta)` | Corre cada frame (actualiza labels, barras, animaciones) |
| `visible` | Propiedad para mostrar/ocultar un Control (sistema de paneles) |
| `mouse_filter` | 2 = el Control no bloquea clicks |
| `Overlay` | Pantalla completa temporal (Dim + panel centrado) |

---

## 10. RESPUESTAS MODELO (probables preguntas del examen)

**Q: ¿Cómo está organizada la UI del menú principal?**
R: Es un árbol de nodos `Control` con contenedores: un `VBoxContainer` raíz con un `Header` (título) y un `Content` (`HBoxContainer`) que tiene una barra lateral de 3 botones (`VBoxContainer`) y un panel central (`PanelContainer`). El panel central muestra 2 sub-pantallas (Selección de Canción y Configuración) que se alternan con `visible`.

**Q: ¿Cómo funciona el cambio entre paneles?**
R: Método `_show_panel()`: pone el panel elegido en `visible = true` y el otro en `false`. Es un sistema de pestañas. Cada botón lateral está conectado por señal `pressed` al método que muestra su panel.

**Q: ¿Por qué la UI se ve bien en cualquier resolución?**
R: Porque usa contenedores (VBox/HBox/Grid) que acomodan los hijos automáticamente, `size_flags` para expandir, y anclas para los paneles centrados. No hay posiciones fijas en píxeles salvo márgenes.

**Q: ¿Cómo se mantiene el HUD encima del juego?**
R: El HUD está dentro de un `CanvasLayer` con `layer = 10` y el fondo en otro con `layer = -1`. Las capas garantizan el orden de dibujo siempre.

**Q: ¿Cómo se crean los botones de canciones?**
R: Son **4 botones `Button` estáticos** definidos directamente en el `.tscn` (`BtnTrack0`..`BtnTrack3`) dentro del contenedor `TrackButtons`. Cada uno tiene su conexión `pressed` que llama a `_on_btn_track_N_pressed()`, que a su vez llama a `_select_track_ui(N)` para mostrar los detalles y récord de esa canción. No se generan por código: son visibles y editables en el editor.

**Q: ¿Cómo funciona la pausa desde la UI?**
R: `ESC` → se muestra el `PauseOverlay`: un `ColorRect` negro semi-transparente (Dim) que tapa todo, y un `PanelContainer` centrado con 3 botones (Continuar / Reiniciar / Menú). Además se pausa el árbol del juego (`get_tree().paused`).

**Q: ¿Qué es el Dim de los overlays?**
R: Es un `ColorRect` que ocupa toda la pantalla con un color negro al 75-82% de opacidad. Su función es oscurecer el juego de atrás para que el panel centrado (pausa/resultados) tenga foco visual.

**Q: ¿Cómo sabe el menú qué canción elegí cuando vuelvo del juego?**
R: La selección se guarda en `GameManager`, un autoload (singleton global que nunca se destruye entre escenas). La UI del menú llama a `GameManager.select_track(i)` y el juego lee `GameManager.get_current_track()`.

**Q: ¿Qué hace `theme_override_colors/font_color`?**
R: Anula el color de texto de un `Control` puntual (por ejemplo cyan neón para el título, dorado para el récord), por encima del `Theme` global. Es lo que da la paleta neón.

**Q: ¿Cómo es el patrón de los overlays de pausa y resultados?**
R: Ambos siguen el mismo patrón: un Control invisible de pantalla completa con un ColorRect oscuro (Dim) + un PanelContainer centrado con anclas en 0.5 que contiene un VBox con título, labels y botones. Se muestran con `visible = true`.

---

*Documento SOLO UI — Feria de Ciencias 2026. 💡*