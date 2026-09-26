**Archivos:** `scripts/ProceduralSong.gd` (`RATE`).
**Cambio:** 12 kHz mono → 22 kHz con un toque de estéreo en hats/lead. Si el tiempo de render al arrancar supera ~2 s, revertir a lo actual.
**Verificar:** log del tiempo de render al arranque + escucha comparada A/B.

- [ ] Implementar (medir render time)
- [ ] Verificar: arranque ≤ ~2 s y suena mejor; si no, revertir
- [ ] Commit local

