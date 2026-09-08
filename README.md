# Abstract Pulse

Juego rítmico de acción con estética minimalista, abstracta y neón, desarrollado en **Godot 4** para la Feria de Ciencias.

El jugador controla una nave o personaje luminoso con ambas manos mediante **MediaPipe** (tracking de manos por cámara), esquivando obstáculos, apuntando y disparando al ritmo de la música. Cada canción define la dificultad, la velocidad de los ataques y la intensidad visual del nivel.
---

## Características principales

- **Control por manos con MediaPipe**: una mano define el desplazamiento, la otra la orientación y el disparo.
- **Gameplay rítmico**: los patrones, proyectiles y obstáculos se sincronizan con la canción.
- **Estética neón minimalista**: visuales abstractos con brillos, estelas y animaciones de impacto.
- **Dificultad progresiva**: la intensidad escala según la canción seleccionada.
- **Mejoras visuales (Upgrades)**: cambios de color/brillo del personaje, estelas neón, disparos vistosos, escudo visual temporal, transformaciones estéticas según el rendimiento.

## Condiciones de partida

- **Victoria**: sobrevivir hasta el final de la canción.
- **Derrota**: la barra de vida llega a 0.
- **Finalización**: completar todos los niveles (si no se generan de forma procedural).

## Loop general

1. Selección de canción / nivel.
2. Inicia la música y el jugador entra al escenario.
3. Moverse siguiendo un punto fijo de referencia con las manos (una mano desplaza, la otra apunta/dispara).
4. Aparecen patrones, proyectiles y obstáculos cada vez más complejos al ritmo.
5. Al terminar la canción, se muestra el resultado y se pasa al siguiente desafío.

## Mecánica principal

Movimiento y apuntado por manos con MediaPipe:

- Una mano define el desplazamiento.
- La otra define la orientación y el disparo.
- Esquivar obstáculos al ritmo de la canción.
- Disparar para interactuar con ciertos elementos del nivel.

## Requisitos para la feria

https://drive.google.com/drive/folders/1jKupoyUeg05_fikUqCsfOjz1TXjJIltl?usp=drive_link

| Recurso                       | Detalle                                              |
| ----------------------------- | ---------------------------------------------------- |
| Monitor                       | 1 monitor grande                                     |
| Audio                         | Parlantes o salida de audio (recurso propio)        |
| Espacio libre                 | ~2x2 m a 3x3 m para moverse frente a la cámara      |
| Mobiliario                    | Mesa o soporte para el equipo                        |
| Electricidad                  | Zapatilla para conectar todo                          |


## Configuración del proyecto

1. Clonar el repositorio:

   ```bash
   git clone https://github.com/SlenderDigital/FeriaDeCiencias.git
   ```

2. Abrir el proyecto con **Godot 4.x** (Godot Engine ≥ 4.0).

3. Ejecutar la escena principal desde el editor o exportar el proyecto según la plataforma destino.

> El proyecto usa Godot 4; los archivos `.godot/` e `.import/` están ignorados por git.

## Control por mano — cómo correrlo

El control por manos **no depende de ningún proyecto externo**: su lógica vive dentro de este repositorio en dos partes que se comunican por UDP:

1. `tracker_server/` — un servicio **Python** (MediaPipe + OpenCV) que captura la cámara, detecta los 21 puntos (landmarks) de la mano y los manda por **UDP a `127.0.0.1:5005`**. Es el reimplementación del `Player.cpp` original.
2. `scripts/HandTrackingClient.gd` — autoload de Godot que escucha ese puerto y expone `has_hand`, `get_palm_center()` y `get_hand_angle_deg()` para mover y rotar la nave.

### Que pasa si el juego no detecta la mano

`HandTrackingClient` cae automáticamente al control por **teclado (flechas / WASD)** cuando no recibe datos del tracker — así el juego siempre es jugable, con mano o sin ella.

### Requisitos para el tracking por mano

- **Python ≥ 3.12** y `uv` (Arch: `sudo pacman -S uv`).
- Una **webcam** (el tracker usa la cámara `/dev/video0`).
- En el primer arranque se descargan `mediapipe` y `opencv` automáticamente.

### Pasos para jugar con la mano

1. **Correr el juego** en Godot 4.x (escena `MainMenu.tscn`). Al abrirse, el autoload `HandTrackingClient` **levanta solo el tracker**: captura la cámara y manda los landmarks por UDP al puerto `5005`. No hay que correr nada a mano.
   - La primera vez se descargan `mediapipe` y `opencv` (necesita unos segundos e internet).
   - Al cerrar el juego, el tracker se apaga solo.
2. Al abrir, verás arriba al centro una **barra de estado del control por mano**: *"Instalando control por mano (primera vez)…"* → *"Iniciando…"* → *"Listo — mostrá la mano"* (verde). Se oculta sola cuando la mano ya controla la nave; así nunca parece que no anda: si algo falla muestra un aviso en rojo en vez de quedarse en silencio.
3. Mové la mano frente a la cámara: la palma desplaza la nave y la rotación pulgar→índice la orienta. Tirá disparos con espacio/click o con la otra mano.

> Opcional — correr el tracker a mano (por ejemplo para ver la ventana de tracking):
> ```bash
> ./run_tracker.sh
> ```
> Si ya está en marcha (lo levantó el juego), el script sale solo y no duplica la cámara.

> El tracker se comunica solo con esta máquina (`127.0.0.1:5005`), así que Godot y el tracker deben correr en el mismo equipo (cosa que ocurre cuando el juego lo auto-levanta).

## Stack tecnológico

- **Motor**: Godot 4.x
- **Tracking de manos**: MediaPipe
- **Lenguaje**: GDScript

## Licencia

Proyecto académico para la Feria de Ciencias.
