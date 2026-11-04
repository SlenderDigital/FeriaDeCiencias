# Shapes & Beams

Juego de acción y supervivencia 2D con estética minimalista monocromática (blanco y negro), desarrollado en **Godot 4.7** con control de movimiento y escudo por visión artificial mediante **MediaPipe** y **OpenCV** para la **Feria de Ciencias** (ETEC Mendoza — 6° Informática).

---

## De qué trata

En **Shapes & Beams**, el jugador controla un núcleo geométrico luminoso dentro de una arena cerrada y debe sobrevivir durante **45 segundos** esquivando oleadas de amenazas geométricas telegrafiadas:

- **Rayos de luz (Light Beams)**: cruzan la arena tras una fase de advertencia (telegraph).
- **Círculos expansivos (Filling Circles)**: zonas circulares que se cargan antes de detonar.
- **Proyectiles de borde (Edge Projectiles)** y **Explosivos radiales (Exploders)**: proyectiles que ingresan desde los bordes o estallan en 8 direcciones.
- **Sierras rebotadoras (Saws)**, **Muros de cierre (Closing Walls)** y **Enemigos autónomos (Autonomous Enemies)**: amenazas dinámicas reguladas por el director de oleadas para mantener cada partida intensa pero esquivable.

### Características principales

- **Control híbrido en tiempo real (Mano / Teclado / Mouse)**:
  - **Tracking por cámara (MediaPipe + UDP)**: mové la palma abierta frente a la cámara para desplazar al jugador (con sombra de los 21 puntos de la mano proyectada en el fondo de la arena) y **cerrá el puño** para activar el escudo.
  - **Fallback automático**: si no hay cámara disponible o no se detecta una mano, el juego responde en todo momento a teclado (`WASD` / Flechas + `Espacio`) y mouse.
- **Escudo de energía recargable**: mantener el escudo activo (puño cerrado, `Espacio` o clic) bloquea todo el daño entrante consumiendo energía; al soltarlo, se recarga automáticamente.
- **3 modos de dificultad**: `Easy`, `Normal` y `Hard`, que escalan la frecuencia de aparición y velocidad de las amenazas manteniendo 3 puntos de vida (HP) y 45 segundos de duración por nivel.
- **Perfil persistente e historial de récords**: guardado automático de nombre de jugador y mejor marca por dificultad (`user://save_data.tres`), con panel de **Records** en el menú principal y pantalla de **Credits**.
- **Audio 100% procedural**: música de fondo y efectos de sonido (menú, láser, explosión, impacto, activación/bloqueo/ruptura de escudo) sintetizados dinámicamente en memoria desde código (`audio_library.gd` y `sound_manager.gd`).

---

## Controles

| Acción | Control por Mano (Cámara) | Teclado / Mouse |
| :--- | :--- | :--- |
| **Moverse** | Mover la palma abierta frente a la cámara | `WASD`, Flechas o mover el cursor del mouse |
| **Escudo (mantener)** | Cerrar el puño (3+ dedos flexionados hacia la palma) | `Espacio`, `Enter`, Clic izquierdo o derecho |
| **Cerrar paneles / Volver** | — | `ESC` |

---

## Estructura del proyecto

```text
FeriaDeCiencias/
├── juego/                  # Proyecto Godot 4.7
│   ├── project.godot       # Configuración principal del motor y autoloads
│   ├── scenes/             # Escenas (main_menu, level, player, light_beam, saw, closing_wall, enemy, credits)
│   ├── scripts/            # Lógica del juego, HandTrackingClient, GameManager, SoundManager y AudioLibrary
│   ├── data/               # Recurso de datos persistentes por defecto (save_data.tres)
│   └── tests/              # Suites de pruebas automatizadas (headless CLI)
└── tracker_server/         # Servidor Python de tracking de manos (MediaPipe + OpenCV por UDP)
    ├── pyproject.toml      # Dependencias Python gestionadas con uv (mediapipe, opencv-contrib-python)
    └── src/mediapipe_py/   # Captura de cámara, inferencia de 21 landmarks y envío UDP (127.0.0.1:5005)
```

---

## Requisitos e instalación

1. **Godot Engine 4.7** (Forward Plus).
2. **Python 3.12+** y **[uv](https://docs.astral.sh/uv/)** para el servidor de cámara (`tracker_server`).
3. **Webcam** (opcional — sin cámara se juega con teclado y mouse).

### 1. Instalar el entorno del tracker de manos (una sola vez)

```bash
cd tracker_server
uv sync
```

### 2. Ejecutar el juego

Abrí `juego/project.godot` en **Godot 4.7** y presioná **Run** (`F5`), o ejecutalo desde la terminal:

```bash
godot --path juego
```

> Al iniciar, el autoload `HandTrackingClient` levanta automáticamente el subproceso de `tracker_server` en modo headless (`127.0.0.1:5005`) y lo detiene limpiamente al cerrar el juego.

### 3. Ejecutar las pruebas automatizadas

```bash
godot --headless --path juego -s res://tests/cli_test_runner.gd
godot --headless --path juego -s res://tests/test_persistence_loop.gd
godot --headless --path juego -s res://tests/test_records_menu_panel.gd
```

### 4. Generar builds para Linux y Windows (con Python + MediaPipe incluidos)

```bash
./scripts/build_release.sh all
```

Esto genera `build-linux/` (`ShapesAndBeams-linux-x86_64.zip`) y `build-win/` (`ShapesAndBeams-windows-x86_64.zip`) con un entorno portátil de Python 3.12 + MediaPipe + OpenCV preinstalado en `tracker_server/python/` (listo para jugar sin internet ni configuración previa).

---

## TODO / Próximos pasos

- [x] Exportar builds ejecutables para Linux y Windows junto con `tracker_server/`.
- [ ] Subir los archivos del juego a **itch.io** y agregar el enlace de descarga acá.
- [ ] Grabar y enlazar un **video tutorial** mostrando cómo instalar y jugar con el control por manos.

---

## Créditos

- **Desarrollado por**: Facundo Guiñazú y Bautista Prieto
- **Institución**: ETEC Universidad de Mendoza — 6° Año Informática (Feria de Ciencias)
- **Tecnologías**: Godot Engine 4.7, MediaPipe Hand Tracking, OpenCV, síntesis de audio procedural
