**Archivos:** `scripts/PatternController.gd` (`spawns_at` / timeline de First Light).
**Cambio:** en vez de 1 encuentro por compás siempre: intro/outro **1 cada 2 compases**; build/breakdown **1 por compás**; drop/drop2 **1 por compás + acento extra en beats 2 y 4**. La fuente de verdad es la energía de la sección del chart, no números hardcodeados.
**Verificar:** E2E (actualizar conteos esperados) + pasada completa jugable: se siente más vacío al principio y más lleno en drop2, y sigue completable.

- [ ] Implementar (cadencia por sección leída del chart)
- [ ] Verificar: E2E ajustado PASS + run completo sobrevivible
- [ ] Commit local

