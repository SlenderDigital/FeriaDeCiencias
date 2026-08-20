# Plan de Trabajo — Abstract Pulse
*Última actualización: 2026-08-20*

## Trabajo Completado Hoy (Rediseño Anti-Slop de la UI)

### Reemplazo del Mundo Visual
**Antes**: Plantilla genérica "neon cyberpunk" — gradiente synth oscuro, cuadrícula perspectiva cian, magenta secundario, paneles con bordes brillantes, partículas flotantes. Se leía como plantilla de categoría IA.

**Después**: **Patchbay de Sintetizador Modular** — el paradigma real del instrumento detrás de la música.
- Cada pista = un panel de módulo Eurorack (montados en rack uno al lado del otro)
- Selección = parchear un cable desde la fuente de clock → jack GATE del módulo
- "PATCH IN" = completar el parche, lanzar la secuencia
- Color por pista = dato, no decoración (solo en anillo LED del módulo seleccionado + tuerca del jack)

### Archivos Creados

| Archivo | Propósito |
|---------|-----------|
| `PRODUCT.md` | Verdad del producto: usuarios, propósito, posicionamiento, capacidades, restricciones |
| `DESIGN.md` | Reglas duraderas del mundo visual: paleta, tipografía, componentes, topología, movimiento |
| `resources/patchbay_theme.tres` | Tema de 4 roles: panel/silkscreen/signal/track; Button, ProgressBar, TextureProgressBar, HSlider, CheckButton tematizados |
| `scripts/MenuBackground.gd` | Script de fondo fresco (reemplaza NeonBackground.gd corrupto) |
| `scripts/PatchbayModule.gd` | Panel de módulo auto-construido: modelo/BPM/estrellas/jack + anillo LED con pulso en beat |
| `scripts/PatchCable.gd` | Cable bezier animado con flujo de voltaje (dashes) en el beat |
| `scripts/SettingsOverlay.gd` / `.tscn` | Panel deslizante de ajustes (volumen, pantalla completa) |
| `scripts/CreditsOverlay.gd` / `.tscn` | Panel deslizante de créditos |

### Archivos Reescritos

| Archivo | Cambios |
|---------|---------|
| `scenes/MainMenu.tscn` | Hero track-list-first: 3 módulos en rack + top rail con iconos + panel PATCH IN expandible |
| `scenes/Gameplay.tscn` | HUD patchbay: top rail (pista + score), bottom rail (HEALTH rojo + PROGRESS verde) |
| `scripts/MainMenu.gd` | Selección de módulos, animación cable de parche, gestión de overlays |
| `scripts/Gameplay.gd` | Nuevos paths de nodos HUD, gramática patchbay |
| `scripts/GameManager.gd` | Eliminado `camera_flipped` sin usar |

### Archivos Eliminados
- `scenes/Main.tscn` + `scripts/Main.gd` (vestigiales)
- `scripts/NeonBackground.gd` (fuente de caché corrupto)
- `scripts/GameplayBackground.gd` (copia sin usar)

### Decisiones Clave de Diseño
1. **Paleta de 4 roles únicamente**: `panel` (canvas), `silkscreen` (texto), `signal` (CTA primario + beat), `track` (dato por canción)
2. **Sin monocultivo cian**: El cian aparece solo como dato de pista en su propio módulo
3. **Acción principal prominente**: Botón verde "PATCH IN" es el único botón relleno; SALIR es ghost
4. **Foco ≠ Hover**: Anillo signal 2px distinto para accesibilidad teclado (WCAG)
5. **Una sola animación autorada**: Animación de encaje del cable + pulso en anillo LED (sin flicker ambiental)
6. **Sin arte placeholder**: Preview nave = módulo dibujado; cursor mano = crosshair vectorial

### Estado de Verificación
- ✅ MainMenu corre con helper live, cero errores
- ✅ Tres módulos muestran datos correctos: CYBER GENESIS (128 BPM ★), NEON RUSH (145 BPM ★★), OVERDRIVE PULSE (170 BPM ★★★)
- ✅ Módulo seleccionado: borde cian, anillo LED pulsa en beat, cable verde patch cable → jack GATE
- ✅ Cada jack GATE muestra color de pista (cian/rosa/amarillo)
- ✅ Iconos top rail (⚙/i/✕) abren overlays deslizantes
- ✅ Panel inferior: descripción + récord + botón verde PATCH IN
- ✅ Sin errores de caché NeonBackground.gd (estado limpio tras reload plugin)

---

## Controles MediaPipe
*Estado: En progreso (no trackeado en este repo aún)*

**Alcance**: Tracking de manos via MediaPipe para gameplay controlado por manos
- Mano izquierda → movimiento nave (desplazamiento espacial)
- Mano derecha → orientación puntería + disparo rítmico
- Entrada cámara → landmarks MediaPipe → Godot via WebSocket / bridge local
- Fallback: teclado+ratón ya implementado y testeado

**Puntos de Integración Necesarios**:
- `GameManager.control_mode` = "MediaPipe" | "KeyboardMouse" (ya expuesto)
- Datos MediaPipe → `player_pos` nave + ángulo puntería + trigger disparo en `Gameplay.gd`
- UI calibración (ya stubbed en panel Controles MainMenu)

**Próximos Pasos para Integración**:
1. Servicio MediaPipe Python/JS enviando landmarks
2. Bridge (WebSocket / UDP / pipe local) a autoload Godot
3. Mapear landmarks → coordenadas pantalla normalizadas → acciones juego
4. Test en stand Feria (espacio 2×2m, posición cámara, iluminación)

---

## Trabajo Pendiente / Futuro

| Prioridad | Tarea |
|-----------|-------|
| Alta | Integración hand-tracking MediaPipe | 
| Alta | Audio real canciones + patrones spawn sincronizados beat |
| Media | Generación procedural niveles por pista | 
| Media | Persistencia high-scores (archivo/JSON) |
| Baja | Fuente custom (requiere asset .ttf) |
| Baja | Templates export (Linux/Windows/Web) | 

---

## Comandos Rápidos
```bash
# Ejecutar menú principal
godot --path /home/slender/Projects/FeriaDeCiencias

# Ejecutar escena gameplay directo
godot --path /home/slender/Projects/FeriaDeCiencias --scene res://scenes/Gameplay.tscn

# Verificar errores script
godot --path /home/slender/Projects/FeriaDeCiencias --script res://scripts/MainMenu.gd
```

---

## Notas para Próxima Sesión
- Integración MediaPipe es ruta crítica para demo Feria
- Barras HUD gameplay (HEALTH/PROGRESS) necesitan verificación tiempo real en playtest
- Transición "PATCH IN" → Gameplay funciona pero necesita test end-to-end con controles MediaPipe
- Considerar overlay breve "CÓMO JUGAR" para visitantes primerizos del stand
