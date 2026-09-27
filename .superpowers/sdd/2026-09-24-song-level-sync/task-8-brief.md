**Archivos:** `scripts/PatternController.gd` (`_first_light_pattern`, `spawns_at_phrase`).
**Cambio:** la coreografía pregunta a la sección activa por nombre/energía (la que ya vive en el chart) en vez de rangos de compás hardcodeados. Cambiar la canción deja de romper el nivel en silencio.
**Verificar:** prueba headless: modificar la estructura de la canción (p. ej. drop de 16 → 8 compases) y confirmar que la coreografía sigue a la sección sin editar el nivel.

- [ ] Implementar (coreografía dirigida por sección del chart)
- [ ] Verificar: headless con estructura alterada sigue coherente
- [ ] Commit local

---

## Fuera de alcance

- Volver al track real de Suno: `assets/music/first_light.ogg` + `first_light.analysis.json` + `first_light.level.json` siguen sin uso (decisión del commit *"Make First Light an authored rhythm level"*).
- Niveles 2-3 (Mechanical Wall, Relentless Drive).
