**Archivos:** `scripts/PatternController.gd` (`_laser_telegraph`).
**Cambio:** la advertencia pasa de 1.3 s fijos a **exactamente 3 beats** (a 128 BPM ≈ 1.41 s), para que el rayo pegue sobre un golpe audible de la música.
**Verificar:** log en corrida real: el disparo ocurre con el reloj de canción alineado al beat (resto ≈ 0). E2E PASS.

- [ ] Implementar (telegraph en beats, no en segundos fijos)
- [ ] Verificar: disparo on-beat en log + E2E PASS
- [ ] Commit local

