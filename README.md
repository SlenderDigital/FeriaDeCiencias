# Abstract Pulse

Juego rítmico de acción con estética minimalista, abstracta y neón, desarrollado en **Godot 4** para la Feria de Ciencias.

El jugador controla una nave o personaje luminoso con ambas manos mediante **MediaPipe** (tracking de manos por cámara), esquivando obstáculos, apuntando y disparando al ritmo de la música. Cada canción define la dificultad, la velocidad de los ataques y la intensidad visual del nivel.

> Referente: Bautista Prieto
> Repositorio: https://github.com/SlenderDigital/FeriaDeCiencias.git

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

## Stack tecnológico

- **Motor**: Godot 4.x
- **Tracking de manos**: MediaPipe
- **Lenguaje**: GDScript

## Licencia

Proyecto académico para la Feria de Ciencias.
