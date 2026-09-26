**Archivos:** `scripts/ProceduralSong.gd` (`render_audio`).
**Cambio:**
- (a) **Sidechain**: pad/lead/bajo duckean un instante en cada golpe de bombo — el "latido" clásico del EDM que hace que todo el tema respire con el ritmo.
- (b) **Redoble de caja** en el último compás antes de cada drop (hoy solo hay riser; el redoble lo vende).
- (c) **Intro menos vacía**: arpegio suave en los compases 3-4.
**Verificar:** re-render y escucha: el pad late con el bombo, se oye el redoble antes de cada drop. E2E PASS (la estructura del chart no cambia).

- [ ] Implementar sidechain (a)
- [ ] Implementar redoble pre-drop (b) + arpegio de intro (c)
- [ ] Verificar: escucha + E2E PASS
- [ ] Commit local

