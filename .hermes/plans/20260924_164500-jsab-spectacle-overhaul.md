# Abstract Pulse: "Nothing happens" → JSAB-level setpiece plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Transform First Light from a passive hazard-dodger into a Just Shapes & Beats-style rhythm bullet-hell where every section delivers a spectacle moment — rotating beams, radial bursts, sweeping lasers, inverted arenas — all beat-locked to the procedural song and readable like JSAB (hot-pink danger, cyan player, big contiguous safe pockets, warning → impact).

**Problem (Bauti's words):** "the game is so lame, nothing happens" — the level spawns sparse falling hazards; the screen never fills with choreographed geometry; no setpiece ever dominates the arena.

**Reference:** `.jsab_ref/` holds 10 frames from the JSAB hardcore all-bosses run, analyzed by space-bunny (vision model via opencode): `.jsab_ref/analysis_prompt.txt` → output saved as `.jsab_ref/jsab_design_analysis.md` (per-frame breakdown + ranked techniques). Also see `docs/jsb_pattern_catalog.md` (existing catalog from earlier reference work) and `docs/superpowers/plans/2026-09-24-song-level-sync.md` (the completed music-sync plan this builds on).

**Design grammar extracted from the video (binding for all tasks):**
1. **One anchor + one field + punctuation:** every setpiece = one large anchor shape (hub, dome, face), one directional field (beams, spokes, columns), small bullets as punctuation. Never only punctuation.
2. **Telegraph → impact:** everything lethal shows a dim warning state ≥2 beats before going lethal (JSAB white/dim outline → full pink flash).
3. **Fair density:** safe space is a LARGE contiguous pocket, not pixel gaps; beam gaps wider than 2× the player hitbox.
4. **Color language (already ours):** hot-pink hazard, cyan player. JSAB adds: white = impact accents, dark-maroon = secondary/warning geometry.
5. **Beat-locked motion:** sweeps/rotations quantized to beats (arrival or phase-change on beat), extending T2/T4 of the sync plan.

**Architecture:** All new hazards live in `PatternController` as new pattern builders + spawn dicts consumed by Gameplay's existing `_update_targets`/`_draw_one_target` machinery (dict-based, no new nodes — matches the engine's current design). A new **SetpieceDirector layer** in `PatternController` sequences multi-beat choreographies (phase lists: telegraph→active→resolve) driven by the section clock, replacing the current "one-shot spawn" setpieces. Song side stays as-is (T6 already ships sidechain/fills); sections already expose energy/beat timing through `_section_intent`.

**Tech Stack:** Godot 4.7.2 GDScript, existing `_draw()` immediate-mode rendering, existing headless SceneTree test pattern (`_initialize()` not `_init`), space-bunny vision model via `opencode run` for visual verification of real-render screenshots.

**Constraints (from repo + user):**
- First Light stays beatable: every task verified with the full-mechanics bot sim (shield 1.2s/3s, iframes 2s, HP 125) — survival PASS required at commit time.
- E2E (`tools/e2e_chart_drive.gd`) + all 9 existing headless tests stay green.
- NO push. Local commit per task.
- Easy mode stays a tutorial: setpiece intensity scaled by section energy, but readability rules are absolute (never drop readability for spectacle).
- Verification standard: headless tests + real-render screenshots analyzed by space-bunny (`MCP_SHOT_LIST` env already lands tagged PNGs in /tmp) + bot sim for beatability.

---

## Phase A — Foundation: the director + 2 showpiece patterns

### Task 1: SetpieceDirector — multi-beat choreographed setpieces
**Objective:** Replace one-shot phrase setpieces with multi-beat phase scripts (telegraph N beats → active M beats → resolve), so a single "encounter" evolves across a whole 4-bar phrase instead of a single spawn.

**Files:**
- Modify: `scripts/PatternController.gd` (new section at top: `## --- SETPIECE DIRECTOR (JSAB-style) ---`)
- Test: `tools/test_setpiece_director.gd` (new, SceneTree/`_initialize()` pattern)

**Design:**
```gdscript
## Un setpiece = lista de fases con offsets en BEATS desde el beat ancla.
## Cada fase emite spawns con las claves que Gameplay ya sabe mover/dibujar.
## El director corre en spawns_at_phrase: al phrase beat, agenda el script;
## en cada beat posterior emite las fases cuyo offset cae en ese beat.
const SETPIECE_SCRIPTS: Dictionary = {
    "laser_sweep": [
        {"at": 0, "emit": "laser_telegraph", "params": {"dir_sweep": true}},
        {"at": 3, "emit": "laser_beam_sweep_active", ...},
    ],
}

func _emit_setpiece_phases(beat_idx: int, t: float) -> Array[Dictionary]:
    ## Llamado desde spawns_at en CADA beat: devuelve las fases del setpiece
    ## activo que vencen en este beat (y lo cierra si terminó).
```
- `spawns_at_phrase` picks a script by section name/energy; stores `_active_setpiece = {script_key, anchor_beat}`; `spawns_at` (every beat, cheap check) calls `_emit_setpiece_phases` when active.
- Only one setpiece at a time; phrase cadence unchanged (every 16 beats), so no timing regressions.

**Steps:** write failing test (director: script chosen by section, phases emit at right beat offsets, setpiece ends) → run (FAIL) → implement → run (PASS) → E2E + boot → commit.

### Task 2: Rotating spoke fan (JSAB 30s/540s archetype)
**Objective:** The radial spoke pattern — a hub with N rotating rays, gaps ray-to-ray wide, 8-beat lifetime: 2-beat dim telegraph, 4-beat active rotation, 2-beat fade. The "anchor" the game currently lacks.

**Files:**
- Modify: `scripts/PatternController.gd` (builder `_spoke_fan(...)`, spawn type `"spoke_fan"`), `scripts/Gameplay.gd` (`_update_targets`: rotation + ray collision; `_draw_one_target`: hub + rays, dim warning → full pink)
- Test: `tools/test_spoke_fan.gd`

**Builder contract:**
```gdscript
{"type": "spoke_fan", "pos": center, "radius": 0.0..min(w,h)*0.75,
 "spokes": 8, "gap_spokes": 2 (¡SIEMPRE >= 2 rayos de gap!),
 "rot_speed": TAU / (beats_per_rev * beat_len), "rot_phase": set so gaps face a lane,
 "state": "telegraph"|"active"|"fade", "state_time": beat-derived, "is_hazard": state=="active"}
```
- Collision (Gameplay): player polar angle vs ray angles; distance < radius. Damage only in active.
- Fairness gates (test-asserted): gap >= 2 spokes; rotation completes 1/2 rev per 8 beats max; telegraph 2 beats.
- Draw: dim maroon rays in telegraph (0.35 alpha), hot pink HDR core in active, beat-pulsing hub (reuse `_neon_arc`).

**Steps:** failing test (gates: gap>=2, on-beat phase changes, collision math in active only) → implement → bot sim must survive a full drop with spoke fans → E2E → commit.

### Task 3: Screen-crossing laser SWEEP (JSAB 540s archetype)
**Objective:** Upgrade `laser_telegraph` into a sweeping beam: telegraph shows the sweep arc + start angle; beam fires on-beat (T2) and sweeps a quantized angle over 2 beats. The static laser becomes a field, not a line.

**Files:**
- Modify: `scripts/PatternController.gd` (`_laser_telegraph` gains `sweep_deg` + `sweep_beats` params), `scripts/Gameplay.gd` (beam updates `beam_dir` while `lifetime` runs; draw shows sweep trail arc)
- Test: extend `tools/test_laser_beat.gd` (sweep: fire on-beat, sweep completes on beat boundary; per-sample hit check vs sweep angle)

**Fairness:** sweep speed capped (<=90°/beat in easy mode); sweep never covers > 270° (always a rest sector); telegraph draws the FULL swept region (player sees exactly what will burn).

**Steps:** failing test → implement → bot sim → E2E → commit.

## Phase B — The wall of spectacle: fields that fill the screen

### Task 4: Waveform wall (JSAB 420s archetype)
**Objective:** Bottom-rising columns as a moving wave — a "floor is lava" moment: sin-wave of columns with amplitude following the music energy, safe channel breathing above it, quantized so crests land on beats.

**Files:** Modify `PatternController.gd` (builder `_waveform_wall`), `Gameplay.gd` (column heights over time; collision = y > wave_height(x)); Test `tools/test_waveform_wall.gd`.

**Fairness:** wave max height <= 62% screen (player zone stays above); safe channel >= 3 lane widths at all times; 2-beat telegraph (dim ghost wave rising first).

### Task 5: Bilateral squeeze corridor (JSAB 780s archetype)
**Objective:** Mirrored spiked-disc walls closing from left+right with eased tweens, leaving a central corridor ≥3 lanes wide; large slow orbs cross the corridor as punctuation. The screen FEELS full.

**Files:** Modify `PatternController.gd` (builder `_squeeze_corridor`), `Gameplay.gd` (wall positions ease in/out on beats; disc rows orbit slowly); Test `tools/test_squeeze.gd`.

**Fairness:** min corridor width 3 lanes; squeeze phase 4 beats in, 4 beats hold, 2 beats release; orbs telegraphed 1 beat ahead.

### Task 6: Expanding pulse rings (JSAB 90s/900s archetype)
**Objective:** Concentric rings expanding from an anchor with rotating gaps — readable "jump-through-the-gap" rings, radius growing beat-quantized (1 ring per bar), gaps rotate half-turn per phrase.

**Files:** Modify `PatternController.gd` (`_pulse_rings` builder), `Gameplay.gd` (ring radius per beat; collision = |dist - r| < half_width and angle in solid arc); Test `tools/test_pulse_rings.gd`.

**Fairness:** gap arc >= 2× player size; rings never stack >2 active; anchor telegraphs 2 beats.

## Phase C — Section integration: choreography that says "something happens"

### Task 7: Map setpieces to sections (the "wow" per section)
**Objective:** First Light's chart gets a JSAB-style setpiece per section transition + energy spike, using the T8 section-driven machinery: intro→teaching spoke fan (slow), build→waveform teaser, drop entry→LASER SWEEP + wall combo (the "impact" moment T6's crash+fill now pays off), breakdown→calm pulse rings (cold-blue section mood), drop2→squeeze corridor + spoke fan (climax stack), outro→single closing ring wave.

**Files:** Modify `PatternController.gd` (`spawns_at_phrase` section-keyed script map; `spawns_at` phase pump); Test `tools/test_section_setpieces.gd` (each section's phrase beats produce the right script; no overlap of anchors; setpiece count per section).

**Also:** `spawns_at_bar` gains "mini-jabs" — one-line intensity hits (single expanding ring or 3-spoke mini fan) on high-energy bars WITHOUT active setpieces, so the screen is never idle for >2 bars. This is the direct answer to "nothing happens": between setpieces, SOMETHING always pulses.

### Task 8: Impact feedback — screen presence (JSAB white-flash/trauma)
**Objective:** Beat-scaled impact juice so every setpiece activation is FELT: (a) white flash + camera trauma (shake) on setpiece activation, decaying over 2 beats — reuse `_shake_time`; (b) CanvasLayer pulse flash on drops' downbeats (extend T5's `energy_gain` kick flash); (c) hit-stop: 0.05s pause on player hit (existing `_hit_iframes` start).

**Files:** Modify `Gameplay.gd` (`_process`: setpiece-activation hook via a `just_activated` flag on spawn dicts; extend `_draw` shake/flash; hit-stop via `Engine.time_scale` 0.0 for 3 frames guarded to never stack); Test: extend `tools/test_section_mood.gd` or new `tools/test_impact.gd` (activation flag set on setpiece spawns; time_scale restored).

**Note:** careful with `Engine.time_scale` + audio clock: hit-stop must NOT desync song_time (anchored to `get_playback_position()` — audio keeps playing; visual freeze only. Verify song_time anchor unaffected).

## Phase D — Verification as spectacle: real-render proof

### Task 9: Visual verification loop with space-bunny
**Objective:** Automated "does it look JSAB-cool" gate: real-render run captures screenshots at each setpiece moment (`MCP_SHOT_LIST`), then space-bunny (via `opencode run --model opencode/space-bunny-free`) rates each frame against a JSAB-likeness rubric (density, anchor presence, safe-space readability, color hierarchy) — PASS requires >=7/10 per frame. Analysis prompt saved in `.jsab_ref/`; the loop is a script: `tools/jsab_visual_check.sh` (extract frames via existing env → run opencode → parse verdict).

**Files:** Create `tools/jsab_visual_check.sh`; Modify `Gameplay.gd` only if shot hooks need the new setpiece tags (likely reuse as-is).

### Task 10: Full beatability + polish pass
**Objective:** The final gate: full-mechanics bot (with shield) survives the complete upgraded level at reasonable margin (HP nadir >= 40/125 — spectacle must not kill the tutorial); tune any setpiece that fails; all 9+ existing tests + new ones green; full suite run; final commit.

**Files:** Modify whatever the sim flags (likely fairness constants in builders); Test: extend the bot-sim script into `tools/test_beatability.gd` (committed this time — it proved essential in the final review).

---

## Execution notes

- **GodotPrompter**: installed via opencode.json plugin (`godot-prompter@git+https://github.com/jame581/GodotPrompter.git`) — its skills (tween-animation, particles-vfx, shader-basics, godot-code-review) auto-load for opencode subagents during execution; execution briefs should reference `using-godot-prompter` when dispatching opencode-based implementers.
- **space-bunny** is the vision model for: (a) this plan's reference analysis (done — `.jsab_ref/jsab_design_analysis.md`), (b) Task 9's automated visual gate, (c) ad-hoc "does this look cool" checks.
- **Delegation reality:** this session's Hermes `delegate_task` transport failed 4/4 with API timeouts; all 8 prior tasks went inline. Execution should attempt delegation first per task but fall back inline fast (1 failed dispatch → inline) — the ledger ruling pattern is already established.
- **Order matters:** Tasks 1→3 build the machinery; 4→6 are independent pattern builders (parallelizable in principle, but share `Gameplay._update_targets` seams — serialize); 7 wires them to the song; 8 adds feel; 9-10 are the proof.

## Risks & tradeoffs

- **Draw-call explosion:** spoke fans/rings/walls are `_draw()`-loop intensive; the fairness tests + budget discipline from the sync plan apply (60fps target; if a pattern tanks fps, simplify geometry first, never readability).
- **Difficulty cliff:** Phase C stacks setpieces; the bot-sim gate (HP nadir >= 40) is the tripwire — setpiece intensity scales DOWN via section energy rather than disabling patterns.
- **Scope:** 10 tasks is honest JSAB-scope; if time-boxed, Phase A alone (director + spoke fan + sweep) already changes "nothing happens" into "something happens every phrase" — ship Phase A first if needed.
