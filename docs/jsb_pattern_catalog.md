# JSB Pattern Catalog (from reference screenshots)

Source images: `/tmp/jsb_ref/level1.png`, `/tmp/jsb_ref/level2.png`, `/tmp/jsb_ref/boss.png`.
Purpose: actionable 2D bullet-hell obstacle types for Godot implementation.

Global conventions (JSB style):
- Hazard color: hot pink/magenta ≈ `#ff2d6b` (projectiles) / `#e8175d` (dark fill variants). Everything hazardous is pink; everything safe is not pink.
- Background: pure black (levels) or dark teal (boss arena), with a soft magenta radial glow behind bosses.
- Player: small cyan square ≈ `#29abe2`, with a short trailing particle streak of darker blue squares.
- All hazards flash/telegraph (thin outline or white pulse) ~0.3–0.5 s before becoming lethal.

---

## Per-image analysis

### level1.png — "Corridor"-style scrolling-wall level
1. **Obstacle types**
   - Giant diagonal-striped wall bands (3 stacked full-width bands, separated by thin black gaps). Stripes are pink parallelograms at ~65°.
   - Large rotating triangle projectile (equilateral, pink, with black ring "eye" at centroid) riding the top wall band.
   - Concentric-circle projectiles ("donut/targets"): one large top-right, one medium center. Solid ring + inner filled dot.
   - Vertical dotted stream of small pink dots descending from the progress bar area (top, center).
   - Small scattered dot particles (ambient debris).
   - One bright white diagonal beam inside the bottom wall band (flash/gap telegraph).
2. **Spawn directions**
   - Wall bands: scroll horizontally, screen-crossing (right → left).
   - Triangle: slides from left along the wall surface, rotating as it travels.
   - Circles: spawn at fixed points, scale up (expand) in place, then shrink/vanish.
   - Dot stream: top → bottom.
3. **Player appearance + hazard count**
   - 1 cyan square player, slightly rotated, with 6–8 blue trail particles.
   - On-screen hazards: 3 wall bands, 1 triangle, 2 circles, ~12 dots.
4. **Hazard colors**
   - Pink `#ff2d6b` fills; darker pink `#e8175d` for far/ambient dots; white only for the telegraph/flash; black used for stripes' background and eye rings (holes, not hazards).
5. **Notable choreography**
   - Wall bands move as a rhythmic sequence synced to the beat; the black gaps between bands are the safe lanes.
   - The white diagonal flash inside a band telegraphs where a gap will open.
   - The dotted stream drops into the gap between bands, forcing diagonal movement.

### level2.png — closing-ring + spiky-bullet-field level
1. **Obstacle types**
   - Screen-edge "teeth": ring of large spiked spheres (pink ring + dark fill) hugging all four edges, closing inward.
   - Mid-field small spiky donut bullets (~35–40) scattered across the play area, some clustered in arcs/lines.
   - One huge spiky sphere half-entered from top center (frontier element pushing the field).
   - Single vertical pink capsule bar (bottom center) = laser/beam telegraph.
2. **Spawn directions**
   - Spiked spheres: from top, bottom, left, right edges, moving inward (corner/edge fill).
   - Small spiky bullets: emitted radially into the field, drifting slowly (low speed, high count).
   - Beam: vertical, anchored to the bottom edge, fires upward after the telegraph.
3. **Player appearance + hazard count**
   - 1 cyan square top-left with small blue particle trail.
   - Hazards: ~14 large edge spheres, ~40 small bullets, 1 giant sphere, 1 beam telegraph.
4. **Hazard colors**
   - Bright pink `#ff2d6b` outlines for small bullets; darker magenta `#b3124a` fills inside edge spheres (two-tone: pink ring + dark fill). Beam telegraph is a bright pink capsule.
5. **Notable choreography**
   - Arena shrink: edge spheres tighten the safe zone over time (corner fill pressure).
   - Small bullets form loose spiral/arc chains — likely emitted in rotating radial bursts.
   - Beam telegraph (thin capsule) → full-length beam fire is the classic JSB telegraph→fire pair.

### boss.png — Barracuda-style boss arena
1. **Obstacle types**
   - Boss head: large pink circle outline with horns, angry eyes (angled brow strokes + round nose), two fangs — hanging from top center inside a magenta glow.
   - Two legs: symmetric chains of spiked balls growing from the head down to the ground, ball size increasing along the chain, ending in large spiked rings with donut (ring+dot) cores.
   - Small solid pink circles ejected near the leg feet.
   - Pizza-slice projectiles (pink triangle with dark dots) floating at various heights — hover-then-lunge hazards.
   - Teal dashed ground line + dot: safe ground guide (non-hazard).
2. **Spawn directions**
   - Boss head: descends from top center.
   - Legs: grow outward+downward symmetrically from the head (mirrored animation).
   - Feet circles: small bursts ejected downward from the feet.
   - Pizza slices: enter from left/right sides, drift/hover, then lunge at the player.
3. **Player appearance + hazard count**
   - 1 cyan square on the left ground, next to light-blue NPC characters (hide-among-NPCs mechanic: NPCs are non-pink, safe).
   - Hazards: 1 boss head, ~10 spiked balls in the legs, 2 giant foot rings, ~3 feet circles, 4 pizza slices.
4. **Hazard colors**
   - Pink `#ff2d6b` outlines/fills with dark fill `#c1165a` inside leg balls and foot rings. Magenta radial glow behind the boss. Ground/background in teal `#1d3a3a` + dark silhouettes — deliberately NOT pink = safe.
5. **Notable choreography**
   - Telegraph via color: NPCs and ground are teal/light-blue (safe); everything magenta is lethal.
   - Leg chains extend in mirrored arcs on a beat — geometric symmetry is the readable pattern.
   - Pizza slices pulse-glow before lunging (glow = telegraph).

<!-- PART2 -->
