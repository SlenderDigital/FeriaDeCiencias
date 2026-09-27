# Análisis del Proyecto — Abstract Pulse

Respuestas al formulario de la Feria de Ciencias.

> **Referente**: Bautista Prieto
> **Repositorio**: https://github.com/SlenderDigital/FeriaDeCiencias.git
> **Nombre del proyecto**: Abstract Pulse

---

## 1. Definir de qué trata el juego o app

Es un juego rítmico de acción con estética minimalista, abstracto y neón. El jugador controla una nave o personaje luminoso con ambas manos mediante MediaPipe, esquivando obstáculos al ritmo de la música. No hay disparos: todo lo que aparece es peligro (esquiva pura) y la única defensa es el escudo de emergencia. Cada canción define la dificultad, la velocidad de los ataques y la intensidad visual del nivel.

## 2. Definir las condiciones de victoria / derrota o finalización

- **Victoria**: el jugador sobrevive hasta que termina la canción.
- **Derrota**: la barra de vida llega a 0.
- El progreso del nivel depende de aguantar toda la canción sin perder toda la vida.
- **Finalización**: el MVP tiene un solo nivel completo (First Light, procedural de 1:45); el progreso se mide en % de canción sobrevivida con récord personal.

## 3. Definir el loop general (cómo inicia, qué hace cuando termina)

El juego inicia con la selección de una canción o nivel. Cuando empieza la música, el jugador entra al escenario y debe moverse siguiendo un punto fijo de referencia con sus manos. Si una mano se desvía, el personaje se desplaza hacia esa posición. Con la otra mano, o con la misma, se define la rotación de la nave.

Durante la canción aparecen patrones, proyectiles y obstáculos cada vez más complejos. Al finalizar la canción, el nivel termina y se muestra el progreso alcanzado con el récord.

## 4. Definir el "Upgrade" (qué mejora o castiga cuando finaliza)

Las distintas mejoras existentes serán principalmente visuales, por ejemplo:

- cambios de color o brillo del personaje,
- estelas neón,
- escudo visual temporal,
- animaciones de impacto,
- transformaciones estéticas según el rendimiento.

## 5. Definir la mecánica principal

La mecánica central es movimiento por manos con MediaPipe:

- una mano define el desplazamiento,
- la otra define la orientación de la nave,
- el jugador debe esquivar obstáculos al ritmo de la canción,
- el escudo de emergencia (espacio/click/puño) da invulnerabilidad breve para atravesar peligros.

## 6. Definir qué recursos físicos son necesarios para la feria

- 1 monitor grande
- parlantes o salida de audio (recurso propio)
- aproximadamente 2x2 m a 3x3 m de espacio libre para que el jugador se mueva frente a la cámara
- mesa o soporte para el equipo
- zapatilla para conectar todo

## 7. Definir si será multiplayer

**No**

## 8. Definir si será competitivo (Ranking)

**No**

## 9. Definir qué lo hará divertido

- la combinación de música, reflejos y movimiento corporal,
- la detección de manos como forma de control original,
- la dificultad progresiva según la canción,
- los visuales,
- la sensación de sincronizarse con el ritmo mientras se esquivan ataques.

## 10. Definir si se vincula con proyectos de electrónica

**No**

## 11. Qué dispositivos electrónicos se vincularán con el juego o App?

Pueden cambiar cosas del proyecto, pero la idea en general no.
