# Music-Driven Levels Design Spec

**Fecha:** 2026-09-12
**Estado:** Draft aprobado (Sunrise Horizon / Mechanical Wall / Grid Lockdown)
**Proyecto:** Abstract Pulse (FeriaDeCiencias, Godot 4)

## Goal

Reemplazar el nivel procedural fake (reloj `progress 0→1` sin audio real) por **3 niveles con música IA real**, donde el gameplay se sincroniza a los beats detectados de cada pista. Workflow "music-first, chart-driven".

## Tres niveles

Orden final: BPM ascendente Y dificultad ascendente.

| # | Nivel | Dificultad | Tempo (detectado) | Personalidad | Estructura energía |
|---|---|---|---|---|---|
| 1 | **Sunrise Horizon** | Principiante | ~104 BPM | Synthwave cálido de amanecer, capas claras | Teach-in → build → mini-drop → outro calm |
| 2 | **Mechanical Wall** | Intermedio | ~115 BPM | Industrial pesado, opresivo, mitad-tiempo | Intro mínima → crescendo sostenido → muro final |
| 3 | **Grid Lockdown** | Avanzado | ~140 BPM | Electro/trap agresivo, drop caótico | Intro corta → build → drop → 2do drop denso → clímax → outro |

Colores: cian amanecer / dorado-gris industrial / magenta-turquesa.

## Workflow

1. Escribir 3 prompts de música IA (analizables: 4/4, kick claro en downbeat, secciones definidas, sin capas sucias).
2. Usuario genera cada pista y la coloca en el proyecto.
3. Pipeline Python `analyze_music.py` (librosa + soundfile) extrae `chart.json`: BPM, `beat_times[]`, `sections[]{name,start,end,energy}`.
4. Godot reproduce el `.ogg` real (`AudioStreamPlayer`) y lee el chart; hazards/targets se spawnean en los beats detectados, escalados a `section.energy`.

Nada se hardcodea a BPM; todo deriva del audio real.

## Arquitectura

### Python (disposable venv)
- `tools/analyze_music.py in.<wav/ogg> --out chart.json`
  - Infiere BPM con `librosa.beat.beat_track`
  - Obtiene `beat_times` (frame → segundos reales)
  - Detecta secciones via clustering de onsets + envelope de loudness
- Instalación: `uv venv && uv pip install librosa soundfile`

### Godot
- **Nuevo** `scripts/ChartData.gd` (`class_name ChartData`, `RefCounted`)
  - Parsea `chart.json` → `bpm: float`, `beat_times: Array[float]`, `sections: Array[Dictionary]`
  - Valida: `beat_times` monotónicos, dentro de duración de audio
  - Puro / testable
- **Nuevo** en `Gameplay.tscn`: `AudioStreamPlayer` (`MusicPlayer`) que streamea el `.ogg` real
- **Modificar** `scripts/Gameplay.gd`
  - Clock real: `MusicPlayer.get_playback_position()` reemplaza `song_time` fake
  - `beat_interval = 60/bpm`, spawn en beats detectados
- **Modificar** `scripts/GameManager.gd`
  - `TRACKS` → los 3 niveles reales con `audio` + `chart` paths
- **Modificar** `scripts/ProceduralLevelGenerator.gd`
  - Consume chart en lugar de curva 0→1 hardcodeada
  - Hazards snap a `beat_times[]`
  - Densidad/spawn escala con `section.energy`
  - Secciones pueden bias del tipo de patrón (simple en intro, walls densos en climax)

**Gameplay híbrido:** shooter existente se mantiene; disparás laser a blancos para combo + esquivás hazards al ritmo. Targets también spawn on-beat.

## MVP de 3 niveles

- 3 `chart.json` (uno por pista)
- 3 `.ogg` en `res://assets/music/`
- `TRACKS` limitado a estos 3

## Testing & verificación

1. **Analyzer unit test:** sintetizar track click 140 BPM 4/4 (soundfile), correr `analyze_music.py`, assert `recovered_bpm ≈ 140` y beat count ≈ esperado.
2. **ChartData parse test:** cargar chart, verificar `beat_times` monotónicos y en rango vs duración.
3. **E2E:** drop `.ogg` real de un nivel, correr analyzer, cargar nivel, confirmar hazards en beats audibles (screenshot/console).

## Fuera de scope (YAGNI)

- Editor visual de niveles
- Multiplayer/co-op
- Modos Story/Challenge/Party
- Análisis de audio en runtime (solo build-time)