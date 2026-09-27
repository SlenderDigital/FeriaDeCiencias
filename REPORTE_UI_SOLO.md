# REPORTE SOLO UI — ABSTRACT PULSE (actualizado)
> Solo interfaz. Nada de lógica de juego.
> Motor: Godot 4.7 · Resolución: 1280×720 · Estética: neón/abstracta

---

## 1. LA IDEA EN UNA FRASE

La UI es lo que el jugador **ve y toca fuera de la acción**: menú principal, barras del juego, progreso y pantallas de pausa/resultados. Todo con nodos tipo `Control` en árbol jerárquico.

---

## 2. LAS 2 "PANTALLAS" (escenas)

| Escena | Es la pantalla de... | Raíz |
|---|---|---|
| `MainMenu.tscn` | Menú principal (lo primero) | `Control` (pura UI) |
| `Gameplay.tscn` | Juego + UI encima | `Node2D` (mundo) + capas UI |

Arranca en `MainMenu.tscn` (`project.godot`, `run/main_scene`).

---

## 3. PIEZAS DE UI

### 3.1 Contenedores (layout automático)
- **`VBoxContainer`** → columna. **`HBoxContainer`** → fila.
- **`GridContainer`** → grilla (Configuración, 2 columnas).
- **`PanelContainer`** → caja con fondo que centra al hijo (paneles de Pausa/Resultados).

### 3.2 Controles
- **`Label`** → texto ("ABSTRACT PULSE", "PROGRESO: 41%", "MEJOR PROGRESO: 80%").
- **`Button`** → botón (`pressed`): JUGAR, CONFIGURACIÓN, SALIR, INICIAR, CONTINUAR, REINICIAR, MENÚ.
- **`HSlider`** → 3 volúmenes (`value_changed`). **`CheckButton`** → fullscreen (`toggled`).
- **`ProgressBar`** → progreso de la canción (0→100%).
- **`ColorRect`** → Dim oscuro de overlays.
- **`HSeparator`** → línea divisoria.

### 3.3 Posición
- En contenedor: lo ubica el padre. Con anclas: `15` = llenar todo (fondos, Dim, HUD), `8` = centrar (paneles 360×320 / 400×300).

### 3.4 Capas (CanvasLayer)
- `BackgroundLayer` (-1) atrás · `HUDLayer` (10) adelante. Pausa/Resultados viven en `HUDLayer`: tapan todo.

### 3.5 Tema
`resources/neon_theme.tres` global + `theme_override_*` puntuales (cyan `#00F0FF`, dorado, magenta).

---

## 4. MENÚ (`MainMenu.tscn`)

```
MainMenu (Control, Theme)
├── Background (fondo neón)
└── Layout (VBox)
    ├── Header (HBox, alto 80): TitleContainer → Title 42px + Subtitle
    └── Content (HBox): SideNav (4 botones, ancho 300) + Panels (PanelContainer)
        ├── SongSelectPanel (visible): "NIVEL" + HSeparator + Details
        │     TrackTitle 26px + TrackInfo + TrackDesc (autowrap)
        │     + HighScoreLabel dorado ("MEJOR PROGRESO: X%")
        │     + LegendLabel ("ROJO = PELIGRO · ESCUDO = ESPACIO o CLIC…")
        │     + BtnPlayLevel "▶ INICIAR NIVEL" (alto 54, pulso de escala)
        ├── SettingsPanel (oculto): 3 HSlider + CheckButton fullscreen
        └── CreditsPanel (oculto): "CRÉDITOS Y FERIA" (proyecto, ETEC, stack, gracias)
```

Pestañas con `_show_panel()`: el elegido `visible = true`, los otros `false` (←/→ ciclan Nivel → Config → Créditos).

> **Un solo nivel, cero botones de canción:** la selección es fija (índice 0, First Light). El panel muestra su descripción y su récord de progreso.

---

## 5. JUEGO (`Gameplay.tscn`) — solo UI

```
Gameplay (Node2D, process_mode = ALWAYS)
├── BackgroundLayer (-1) — fondo
└── HUDLayer (10)
    ├── HUD (pantalla completa, mouse_filter = 2 → no tapa clicks)
    │   ├── TopBar: TrackTitle ("First Light | BPM: 128") + ProgressLabel dorado
    │   └── BottomBar: ProgressBar (progreso canción)
    ├── PauseOverlay (oculto, ALWAYS): Dim 75% + Panel 360×320
    │     Title "JUEGO PAUSADO" + CONTINUAR / REINICIAR NIVEL / MENÚ PRINCIPAL
    └── ResultsOverlay (oculto, ALWAYS): Dim 82% + Panel 400×300
          Title + ResultsDetails ("Progreso Final/Logrado: X%") + REINICIAR / MENÚ
```

- **Sin score/combo, sin barra de vida.** HUD = progreso-only; vida = anillo de la nave (aparece 3s tras el golpe, lo perdido en rojo; el resto del tiempo, el relleno de la flecha).
- **Pausa:** `ESC` → overlay + árbol y música pausados + foco en CONTINUAR. Los botones responden pausados gracias a `process_mode = ALWAYS` (antes se congelaban: bug real).
- Patrón overlay = Dim (`ColorRect` negro 75–82%) + panel centrado.

---

## 6. SEÑALES (14)

Menú (9): 4 nav + INICIAR (`pressed`), 3 sliders (`value_changed`), fullscreen (`toggled`).
Juego (5): CONTINUAR (reanuda), 2× REINICIAR (mismo método: reinicio en caliente), 2× MENÚ (mismo método).
Extra: sonidos de hover/click conectados **por código recursivamente** a todos los botones.

Acceso desde script: `@onready var x: Tipo = $Ruta/Al/Nodo`.

---

## 7. FLUJO

Menú (título + 4 botones + panel NIVEL) → pestañas (Nivel/Config/Créditos) → INICIAR → cambio de escena → HUD (progreso) + vida en nave → `ESC` pausa (Dim + panel) → fin/muerte resultados → MENÚ de vuelta (autoload `GameManager` conserva récords/volúmenes).

---

## 8. GLOSARIO

`Control` (base UI) · `Label` · `Button→pressed` · `HSlider→value_changed` · `CheckButton→toggled` · `ProgressBar` · `ColorRect` (Dim) · `PanelContainer` · `VBox/HBoxContainer` · `GridContainer` · `HSeparator` · `CanvasLayer` (orden) · `Anchors` (15 llena / 8 centra) · `Theme` + `theme_override_*` · `Signal` · `Autoload` (memoria entre escenas) · `@onready ($Ruta)` · `_ready / _process` · `visible` (pestañas) · `mouse_filter=2` (no bloquea) · `process_mode=ALWAYS` (vivo en pausa) · `Overlay` (Dim + panel).

---

## 9. RESPUESTAS MODELO

**Q: ¿Cómo está organizada la UI del menú?**
R: Árbol `Control` con contenedores: `VBoxContainer` raíz (Header con título + Content con barra de 4 botones y panel central que alterna 3 sub-pantallas con `visible`).

**Q: ¿Por qué se ve bien en cualquier resolución?**
R: Contenedores + `size_flags` + anclas; sin posiciones fijas salvo márgenes.

**Q: ¿Cómo queda el HUD encima?**
R: `CanvasLayer layer = 10` (fondo en -1), con `mouse_filter = 2` para no tapar clicks.

**Q: ¿Dónde están los botones de canciones?**
R: No existen: un nivel fijo. La UI muestra su info y récord de progreso.

**Q: ¿Cómo funciona la pausa?**
R: `ESC` → `PauseOverlay` (Dim + panel centrado) + `get_tree().paused`; overlay y raíz con `process_mode = ALWAYS` para que los botones respondan.

**Q: ¿Dónde está la vida?**
R: En la nave: anillo que sale 3s tras cada golpe (perdido en rojo) + relleno de la flecha como medidor permanente.

---

*Código manda. Feria de Ciencias 2026.*
