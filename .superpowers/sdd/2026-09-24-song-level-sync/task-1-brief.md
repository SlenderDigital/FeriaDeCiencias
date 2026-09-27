**Archivos:** `scripts/NeonBackground.gd`, `scripts/Gameplay.gd`.
**Cambio:** el fondo deja de acumular su propio timer y pulsa con la posición real del audio (la misma que ya usa Gameplay para los spawns). Se elimina el sonido de beat duplicado durante el gameplay — la canción ya tiene su propio bombo.
**Verificar:** corrida real de ~30 s: los anillos del fondo caen clavados con el bombo de la canción; no se escucha doble golpe. E2E PASS.

- [ ] Implementar (fondo lee el reloj real de la canción; quitar thump duplicado)
- [ ] Verificar: corrida real + E2E headless PASS
- [ ] Commit local

