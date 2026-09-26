# First Light — diseño de nivel

Documento de referencia del nivel. Describe cómo el nivel está construido, qué
reglas de justicia lo sostienen, y por qué cada decisión es la que es.

- **Nivel**: First Light (único nivel completo del MVP)
- **Canción**: procedural, 128 BPM, 105 s, 56 compases, 224 beats
- **Modo por defecto**: `easy_mode` (tutorial) — 125 HP, audio y coreografía
  simplificados
- **Reloj**: el nivel se ancla al reloj real del audio
  (`AudioStreamPlayer.get_playback_position()`). El hit-stop congela la escena
  pero **nunca** el reloj musical, así que el chart no se puede desincronizar.

---

## 1. Estructura

| Sección    | Compases | Beats | Ancla                   | Comportamiento            |
| ---------- | -------- | ----- | ----------------------- | ------------------------- |
| intro      | 0–4      | 0–15  | —                       | sin peligro               |
| build      | 4–12     | 16–47 | `build_intro_v1`        | 1 barrido + mini-jabs     |
| drop       | 12–28    | 48–111| `drop_opener_v1`        | abanicos, máxima presión  |
| breakdown  | 28–36    | 112–143| `wave_breakdown_v1`    | muro de onda             |
| drop2      | 36–52    | 144–207| `climax_squeeze_v1`    | abanicos + corredor      |
| outro      | 52–56    | 208–223| `outro_rings_v1`        | anillos con hueco        |

**El mapa manda sobre la energía.** La sección de entrada y el outro son las más
calmas musicalmente y aun así tienen su setpiece: la presencia en
`SETPIECE_BY_SECTION` es lo que agenda una ancla, no un umbral de energía.

---

## 2. Los tres roles de un patrón

La coherencia visual y de juego se apoya en una jerarquía explícita, definida en
`scripts/PatternLanguage.gd`:

| Rol          | Qué es                                | Daño | Silueta         |
| ------------ | ------------------------------------- | ---- | --------------- |
| **Ancla**    | un momento del nivel, denso           | 12   | rotor / haz / banda / arco |
| **Relleno**  | proyectiles sueltos entre anclas      | 10   | engranaje / punto |
| **Puntual**  | mini-jabs: puntuación, no amenaza     | 8    | anillo / abanico mínimo |
| **Aviso**    | telegraph: nunca letal                | 0    | el mismo, tenue |

**Regla de color**: el rojo está reservado a lo letal. La decoración es siempre
de la familia fría. Esto ya se rompió una vez (el confeti de partículas usaba
`accent_color`, magenta) y ahora hay un test que lo verifica.

**Regla de dibujo**: la primera pasada ordena por `lethality` ascendente, así que
lo que más mata se dibuja encima. Un peligro nunca queda tapado por decoración.

---

## 3. Ciclo de vida de un ancla

Todo peligro pasa por cuatro estados. **Sólo `active` es letal** — por contrato.

```
telegraph (2 beats, inofensivo, INCLUIDO el hit-stop)
    ↓
active   (4-6 beats, ÚNICO estado letal)
    ↓
fade     (2 beats, inofensivo)
    ↓
done     (se elimina)
```

El telegraph es inofensivo a propósito: es el aviso. Un telegraph que lastima
no es un telegraph, es una trampa.

---

## 4. Reglas de justicia

Estas reglas existen porque el piloto automático las violó y el nivel quedó
injusto. Cada una tiene un test que la verifica.

### 4.1 Un barrido es **una** pasada

Los patrones que barren el radio completo (abanico, barrido láser) viven **≤ 5
beats activos**. Cuando se les dio la vida de sección (9 beats), el piloto died
al mismo patrón 3-4 veces seguidas — no había una esquiva posible.

*Test*: `tools/test_anchor_lifetime.gd`

### 4.2 El hueco es de al menos 75°

El contrato de justicia del abanico **no es la cantidad de radios** sino el
ÁNGULO del sector libre. La versión anterior exigía "6+ radios", lo que forzaba
un starburst sin salida visible.

*Test*: `tools/test_spoke_fan.gd` (mide el ángulo, no el conteo)

### 4.3 El hueco es realmente seguro

"Acá podés estar" es una promesa. El piloto verifica su refugio contra **toda**
la geometría viva, no sólo contra el setpiece que estaba esquivando, y exige que
siga libre al llegar (predicción, no reacción).

*Test*: `tools/test_pilot.gd`, `tools/test_beatability.gd`

### 4.4 La pantalla nunca está muda

Ningún tramo de más de 8 beats en sección de alta energía puede estar vacío.
Los mini-jabs rellenan exactamente esos huecos, con máximo 1 simultáneo para no
saturar.

*Test*: `tools/test_mini_jabs.gd`

### 4.5 El daño es el que declara el enemigo

`hit_health_bonus` **es** el daño, aplicado tal cual. Hubo un bug donde se usaba
como multiplicador (`12 * abs(bonus) / 18`), lo que dividía el número del
enemigo y hacía que todo pegara ~12: la razón por la que "algunos enemigos
hacían menos daño" y otros parecían no pegar.

*Test*: `tools/test_damage_coherence.gd`

### 4.6 El tutorial perdona

Ningún enemigo cuesta más de 1/8 de la vida del tutorial, así que el jugador
aguanta **10+ golpes**. El i-frame protege **sólo al jugador**: el peligro sigue
vivo (antes se consumía en silencio durante la invulnerabilidad, que era otro
"golpea y no daña").

---

## 5. Cómo se lee un setpiece en pantalla

Cada ancla teaches lo mismo con distinta silueta:

1. **Cuerpo** — el rotor tiene un anillo translúcido con aro definido: el
   territorio letal es una *máquina*, no una viñeta.
2. **Sector seguro** — el pasillo está **dibujado en cian**, con sus dos radios
   de borde terminados en marcadores. No es la ausencia de rojo: es una forma.
3. **Telegrafía** — el aviso muestra el mismo cuerpo, más tenue, desde el
   frame 1. El slot que se va a llenar ya está a la vista.
4. **Impacto** — al activarse: trauma de cámara, flash blanco y hit-stop de
   50 ms, escalados por la energía de la sección.

---

## 6. Cómo verificar el nivel

```bash
# gate de jugabilidad (usa el MISMO PilotLogic que juega el juego real)
godot --headless --script tools/test_beatability.gd

# todo el resto
for t in tools/test_*.gd; do
  printf "%-24s " "$t"
  godot --headless --script "$t" 2>&1 | grep -E "PASS|FAIL" | head -1
done
```

**Corrida instrumentada** (verifica en el motor real, no en el arnés):

```bash
# activa el piloto + el log de golpes, y graba capturas por tag
touch /tmp/jsab_autoplay.flag /tmp/jsab_hitlog.flag
printf '30=fan_a,52=wave' > /tmp/jsab_shot_list.txt
```

⚠️ **El flag `/tmp/jsab_autoplay.flag` hace que el piloto juegue en vez de vos.**
Borralo siempre cuando termines la inspección:

```bash
rm -f /tmp/jsab_autoplay.flag /tmp/jsab_hitlog.flag /tmp/jsab_shot_list.txt
```

El piloto existe para verificar, no para jugar. Si te sentás y la nave se mueve
sola, ese archivo está.

---

## 7. Estructura de archivos

| Archivo                            | Rol                                          |
| ---------------------------------- | -------------------------------------------- |
| `scripts/PatternController.gd`     | director, builders, agendamiento              |
| `scripts/Gameplay.gd`              | runtime: estados, colisión, dibujo, HUD       |
| `scripts/PatternLanguage.gd`       | jerarquía visual (rol, lethality, silueta)    |
| `scripts/PilotLogic.gd`            | piloto automático (verificación)              |
| `scripts/ImpactFeel.gd`            | trauma, flash, hit-stop                       |
| `scripts/*Logic.gd`                | motores puros de cada setpiece                |
| `scripts/ProceduralSong.gd`        | audio + chart procedural (con caché)          |
| `tools/test_*.gd`                  | 22 contratos headless                        |

Los motores puros existen para que el test y el juego usen **la misma física**.
No hay dos implementaciones que puedan divergir.
