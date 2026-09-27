# PLAN DE TRABAJO — Abstract Pulse (Feria de Ciencias)

> Documento pedido el 13/08: plan de trabajo con agentes de IA.
> Proyecto: juego rítmico de acción en **Godot 4 + GDScript**, control por manos
> (MediaPipe vía `tracker_server/` + `HandTrackingClient.gd`), un solo nivel
> completo (First Light, canción y chart compuestos por el motor).

## Fases y fechas

| Fase | Qué | Cuándo |
|---|---|---|
| Idea + diseño en papel | juego, victoria/derrota, loop, mecánica, recursos (`Analysis.md`) | 30/07 – 06/08 |
| UI funcional | menú, paneles, botones, sliders, fondo (`MainMenu.tscn`, créditos el 27/09) | hasta 13/08 |
| Loop jugable | iniciar → jugar → pausa/resultados → reiniciar (`Gameplay.gd`) | hasta 20/08 |
| Controladores | juego (`Gameplay`/`GameManager`), sonido (`SoundManager`, `ProceduralSong`) | hasta 27/08 |
| Mecánica + colisiones | 5 motores puros, daño = `hit_health_bonus`, escudo, i-frames | hasta 03/09 |
| Sonido + persistencia | música/SFX procedurales; récord y volúmenes en `user://abstract_pulse.cfg` | hasta 10/09 |
| Efectos + cámara + luz | `GPUParticles2D`, trauma/shake/hit-stop (`ImpactFeel`), glow HDR | hasta 17/09 |
| Nivel First Light | coreografía por sección, piloto de verificación, 25 contratos | 12 – 26/09 |
| Pulido pedido por testeo | pausa que responde, restart que spawnea, vida que baja, abanico legible | 27/09 |
| Build + Drive | ejecutable Linux + link en README | 28/09 |
| itch.io + video + stand | publicación, promoción, ambientación | hasta 05/11 |

## Estado por entrega (resumen)

06/08 idea/loop/mecánica/recursos/multiplayer/competitivo ✅ · 13/08 UI + este
plan ✅ · 20/08 loop ✅ · 27/08 controladores ✅ · 03/09 mecánica ✅ ·
10/09 sonido + persistencia ✅ · 17/09 partículas + cámara + luz ✅ ·
28/09 build + link README (pendiente al escribir esto) · 05/11 itch.io +
video + stand (calendario).
