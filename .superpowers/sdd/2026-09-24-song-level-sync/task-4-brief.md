**Archivos:** `scripts/PatternController.gd` (velocidades de saw/drifter/hazard).
**Cambio:** el tiempo de cruce se calcula para que sea un número entero de beats (p. ej. 8 beats en secciones calmas, 6 en drops), derivado del BPM real y del alto real de la pantalla. Los peligros llegan a la zona del jugador **sobre un golpe**.
**Verificar:** test headless: para cada spawn, `(llegada − salida) / beat` es entero (±2%). Corrida real: sensación "sobre rieles".

- [ ] Implementar (velocidad = distancia / (N × beat), con N por sección)
- [ ] Verificar: cuantización on-beat en test headless + run real
- [ ] Commit local

