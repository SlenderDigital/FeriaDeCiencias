# Plan: Que el nivel siga de cerca a la canción

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. **NOTA:** este es un plan NO técnico de prioridades y comportamiento esperado. Al ejecutar, traducir cada tarea a pasos TDD concretos (test → código → verify → commit).

**Goal:** que cada golpe de la canción se note en el nivel y cada sección musical se sienta distinta — mejorar la canción y el comportamiento del nivel.

**Arquitectura (resumen):** la canción se compone en el motor (`ProceduralSong.gd`) y del mismo dato sale el chart que coreografía el nivel (`ChartData` → `PatternController` → `Gameplay.gd`). El reloj del juego es la posición real del audio.

**Spec:** pedido de Bauti, 2026-09-24: *"Make the level match with the song more, improving song and level behavior"* — plan no técnico.

---

## Cómo funciona hoy (resumen)

- La canción no es un archivo de audio: el juego la compone al arrancar (chiptune 128 BPM, ~1:45) con estructura fija: intro (4 compases) → build (8) → drop (16) → breakdown (8) → drop2 (16) → outro (4).
- Los mismos números que generan la canción generan el nivel: cada beat el juego pregunta "¿qué spawnea ahora?"; cada downbeat puede salir un muro; cada 16 beats un setpiece (láser o perímetro que se cierra).
- El reloj del nivel es la posición real del audio, así que los spawns están anclados a la música.
- Los visuales (flash de bombo, anillos de caja, franjas del muro que desfilan) usan la misma matemática de beats.

## Huecos encontrados (por qué existe este plan)

1. **Bug real:** el fondo (`NeonBackground`) lleva su propio metrónomo aparte — deriva respecto de la canción y encima agrega un golpe grave extra: se escucha un "doble bombo" que no está en la música.
2. First Light spawnea **1 encuentro por compás siempre**: la intro tranquila y el clímax final están igual de llenos. La energía de la sección no cambia ni la cadencia ni la velocidad de los peligros.
3. Peligros no anclados al beat: la advertencia del láser dura 1.3 s (≈2.8 beats a 128 BPM → el rayo **dispara fuera de compás**); las sierras cruzan la pantalla en ~6 s (≈13 beats y fracción → llegan "cuando llegan").
4. La coreografía del nivel usa **rangos de compás hardcodeados** (bar<12, bar<28…) que duplican la estructura de la canción: si la canción cambia, el nivel se desincroniza en silencio.
5. La canción es plana en partes: sin sidechain (nada "late" con el bombo), sin redoble antes de los drops (solo riser), intro casi vacía (solo pad + bombo espaciado).
6. Todas las secciones **se ven igual**: mismo flash, mismo fondo, pase lo que pase en la música.
7. Bonus: el juego ya tiene el cerebro "energía → dificultad" (pools y densidad por sección) pero First Light lo saltea por completo — es código muerto para el único nivel publicado.

## Reglas globales

- Un solo nivel: First Light, procedural, 128 BPM.
- **Sin push a remotos.** Commit local por tarea, libre.
- First Light es el tutorial: **siempre debe poder completarse de punta a punta**. Toda tarea que toque dificultad se valida con una pasada completa real antes de cerrarse.
- El E2E headless (`tools/e2e_chart_drive.gd`) debe terminar PASS al cierre de cada tarea.
- Se mantiene easy_mode (HP 125, i-frames 2 s, warning de muro 2.5 beats).
- Verificación estándar: `godot --headless` + corrida real con screenshots y logs — no solo sintaxis.

---

## Tareas (en orden)

### Fase 1 — Un solo reloj

### Tarea 1: El fondo late con la canción
**Archivos:** `scripts/NeonBackground.gd`, `scripts/Gameplay.gd`.
**Cambio:** el fondo deja de acumular su propio timer y pulsa con la posición real del audio (la misma que ya usa Gameplay para los spawns). Se elimina el sonido de beat duplicado durante el gameplay — la canción ya tiene su propio bombo.
**Verificar:** corrida real de ~30 s: los anillos del fondo caen clavados con el bombo de la canción; no se escucha doble golpe. E2E PASS.

- [x] Implementar (fondo lee el reloj real de la canción; quitar thump duplicado)
- [x] Verificar: corrida real + E2E headless PASS
- [x] Commit local

### Tarea 2: El láser dispara en un beat
**Archivos:** `scripts/PatternController.gd` (`_laser_telegraph`).
**Cambio:** la advertencia pasa de 1.3 s fijos a **exactamente 3 beats** (a 128 BPM ≈ 1.41 s), para que el rayo pegue sobre un golpe audible de la música.
**Verificar:** log en corrida real: el disparo ocurre con el reloj de canción alineado al beat (resto ≈ 0). E2E PASS.

- [x] Implementar (telegraph en beats, no en segundos fijos)
- [x] Verificar: disparo on-beat en log + E2E PASS
- [x] Commit local

### Fase 2 — El nivel respira con la música

### Tarea 3: Cadencia de spawns según la energía
**Archivos:** `scripts/PatternController.gd` (`spawns_at` / timeline de First Light).
**Cambio:** en vez de 1 encuentro por compás siempre: intro/outro **1 cada 2 compases**; build/breakdown **1 por compás**; drop/drop2 **1 por compás + acento extra en beats 2 y 4**. La fuente de verdad es la energía de la sección del chart, no números hardcodeados.
**Verificar:** E2E (actualizar conteos esperados) + pasada completa jugable: se siente más vacío al principio y más lleno en drop2, y sigue completable.

- [x] Implementar (cadencia por sección leída del chart)
- [x] Verificar: E2E ajustado PASS + run completo sobrevivible
- [x] Commit local

### Tarea 4: Los peligros cruzan la pantalla en beats enteros
**Archivos:** `scripts/PatternController.gd` (velocidades de saw/drifter/hazard).
**Cambio:** el tiempo de cruce se calcula para que sea un número entero de beats (p. ej. 8 beats en secciones calmas, 6 en drops), derivado del BPM real y del alto real de la pantalla. Los peligros llegan a la zona del jugador **sobre un golpe**.
**Verificar:** test headless: para cada spawn, `(llegada − salida) / beat` es entero (±2%). Corrida real: sensación "sobre rieles".

- [x] Implementar (velocidad = distancia / (N × beat), con N por sección)
- [x] Verificar: cuantización on-beat en test headless + run real
- [x] Commit local

### Tarea 5: Cada sección se ve distinta
**Archivos:** `scripts/Gameplay.gd` (`_draw`), `scripts/NeonBackground.gd`.
**Cambio:** la intensidad visual escala con la energía de la sección: flash de beat, glow y color del fondo suben con la energía; el breakdown pasa a un tono más frío/oscuro; drop2 es el pico visual. Además, la velocidad de los peligros sube ~10-15 % en drop2 (sigue teniendo que ser completable).
**Verificar:** screenshots a t≈5 s (intro), t≈25 s (drop), t≈70 s (drop2): contraste claro entre los tres momentos. Run completo sobrevivible.

- [x] Implementar (energía → flash/glow/color de fondo + +vel en drop2)
- [x] Verificar: 3 screenshots contrastados + run completo
- [x] Commit local

### Fase 3 — Mejorar la canción

### Tarea 6: Bombo que respira + fill antes de los drops
**Archivos:** `scripts/ProceduralSong.gd` (`render_audio`).
**Cambio:**
- (a) **Sidechain**: pad/lead/bajo duckean un instante en cada golpe de bombo — el "latido" clásico del EDM que hace que todo el tema respire con el ritmo.
- (b) **Redoble de caja** en el último compás antes de cada drop (hoy solo hay riser; el redoble lo vende).
- (c) **Intro menos vacía**: arpegio suave en los compases 3-4.
**Verificar:** re-render y escucha: el pad late con el bombo, se oye el redoble antes de cada drop. E2E PASS (la estructura del chart no cambia).

- [x] Implementar sidechain (a)
- [x] Implementar redoble pre-drop (b) + arpegio de intro (c)
- [x] Verificar: escucha + E2E PASS
- [x] Commit local

### Tarea 7 (opcional): Mejor timbre
**Archivos:** `scripts/ProceduralSong.gd` (`RATE`).
**Cambio:** 12 kHz mono → 22 kHz con un toque de estéreo en hats/lead. Si el tiempo de render al arrancar supera ~2 s, revertir a lo actual.
**Verificar:** log del tiempo de render al arranque + escucha comparada A/B.

- [x] Implementar (medir render time)
- [x] Verificar: arranque ≤ ~2 s y suena mejor; si no, revertir
- [x] Commit local

### Fase 4 — Que el vínculo dure

### Tarea 8: El nivel lee la estructura de la canción, no una copia
**Archivos:** `scripts/PatternController.gd` (`_first_light_pattern`, `spawns_at_phrase`).
**Cambio:** la coreografía pregunta a la sección activa por nombre/energía (la que ya vive en el chart) en vez de rangos de compás hardcodeados. Cambiar la canción deja de romper el nivel en silencio.
**Verificar:** prueba headless: modificar la estructura de la canción (p. ej. drop de 16 → 8 compases) y confirmar que la coreografía sigue a la sección sin editar el nivel.

- [x] Implementar (coreografía dirigida por sección del chart)
- [x] Verificar: headless con estructura alterada sigue coherente
- [x] Commit local

---

## Fuera de alcance

- Volver al track real de Suno: `assets/music/first_light.ogg` + `first_light.analysis.json` + `first_light.level.json` siguen sin uso (decisión del commit *"Make First Light an authored rhythm level"*).
- Niveles 2-3 (Mechanical Wall, Relentless Drive).
