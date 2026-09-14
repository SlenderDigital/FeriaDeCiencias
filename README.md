# Abstract Pulse

Juego rítmico de acción con estética minimalista, abstracta y neón, desarrollado en **Godot 4** para la Feria de Ciencias.

El jugador controla una nave o personaje luminoso con ambas manos mediante **MediaPipe** (tracking de manos por cámara), esquivando obstáculos al ritmo de la música y usando un escudo de emergencia para atravesar lo imposible. Cada canción define la dificultad, la velocidad de los ataques y la intensidad visual del nivel.
---

## Características principales

- **Control por manos con MediaPipe**: una mano define el desplazamiento, la otra la orientación de la nave.
- **Gameplay rítmico**: los patrones, proyectiles y obstáculos se sincronizan con la canción.
- **Esquiva pura**: todo lo que aparece es peligro (sierras, enjambres, proyectiles teledirigidos, muros y láseres). No hay disparos ni puntos que recolectar.
- **Progreso como métrica**: el HUD muestra el % de la canción sobrevivida; el récord personal es el mejor progreso alcanzado.
- **Escudo de emergencia**: invulnerabilidad temporal con recarga, para atravesar muros y láseres.
- **Barra de vida con estados**: verde, ámbar y rojo pulsante según lo crítica que esté la partida.
- **Estética neón minimalista**: visuales abstractos con brillos, estelas y animaciones de impacto.
- **Dificultad progresiva**: la intensidad escala con la energía de la canción (intro → build → drop → clímax).

## Condiciones de partida

- **Victoria**: sobrevivir hasta el final de la canción (progreso 100%).
- **Derrota**: la barra de vida llega a 0 (el progreso logrado queda registrado).
- **Récord**: se guarda el mejor progreso por canción (0–100%).

## Loop general

1. Selección de canción / nivel.
2. Inicia la música y el jugador entra al escenario.
3. Moverse siguiendo un punto fijo de referencia con las manos (una mano desplaza, la otra orienta la nave); el escudo se activa con espacio/click.
4. Aparecen patrones de peligro cada vez más complejos al ritmo: sierras, enjambres, muros con hueco, láseres telegrafiados y proyectiles teledirigidos.
5. Al terminar la canción (o al perder toda la vida), se muestra el progreso alcanzado y el récord.

## Mecánica principal

Movimiento por manos con MediaPipe:

- Una mano define el desplazamiento de la nave.
- La otra define la orientación.
- Esquivar todos los obstáculos al ritmo de la canción: todo spawn es peligro.
- **Escudo de emergencia**: invulnerabilidad breve (~1.2s) que atraviesa cualquier peligro, con recarga de ~3s.
- **Progreso**: % de la canción sobrevivida; al morir se guarda como mejor progreso si supera el récord.

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

El juego **levanta solo el tracker** al abrirse (`run_tracker.sh --detach`), y si ya estaba corriendo no lo duplica. Solo conecta y listo.

1. **Correr el juego** en Godot 4.x (escena `MainMenu.tscn`). Al abrir, se levanta el tracker: abre la ventana de tracking y manda los landmarks por UDP a `127.0.0.1:5005`.
2. Arriba al centro verás la **barra de estado del control por mano**:
   - 🔵 *"Iniciando control por mano…"* → el tracker está cargando (1–8s la primera vez).
   - 🟢 *"Control por mano listo — mostrá la mano"* → tracker conectado, mové la mano.
   - 🟠 *"Tracker no instalado — corré ./run_tracker.sh una vez"* → falta la instalación única (abajo).
   - Se oculta sola cuando la mano ya controla la nave.
   - **Al cerrar el juego, el tracker se apaga solo** (libera la cámara).
3. Mové la mano frente a la cámara: la palma desplaza la nave y la rotación pulgar→índice la orienta. Activá el **escudo** con espacio/click para atravesar peligros unos instantes.

> **Instalación única de dependencias** (solo la primera vez): `cd tracker_server && uv sync` (descarga `mediapipe` y `opencv`). Se hace una vez; el juego no instala nada al abrir.
>
> Opcional — correr el tracker a mano: `./run_tracker.sh` (primer plano) o `./run_tracker.sh --detach` (segundo plano).
>
> El tracker se comunica solo con esta máquina (`127.0.0.1:5005`).

## Stack tecnológico

- **Motor**: Godot 4.x
- **Tracking de manos**: MediaPipe
- **Lenguaje**: GDScript

## Licencia

Proyecto académico para la Feria de Ciencias.
