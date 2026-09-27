# SDD ledger — plan: docs/superpowers/plans/2026-09-24-song-level-sync.md

## Execution log

FINAL REVIEW: COMPLETE — verdict CLEAN (3 minor findings, all pre-existing
or design-taste, ruled and deferred — see final-review.md). Full-run
beatability verified by simulation with the game's real mechanics (dodging
bot + shield PASSES: 6 hits, HP 17/125). Delegation was down all session
(4/4 API-timeout failures) — review done inline with runtime probes.

Task 1 (dispatch 1, deleg_853371ab): FAILED — infra. Subagent hit repeated
API timeouts ("Non-streaming API call timed out after 150s", 3 retries) and
exhausted its iteration budget before writing any code. No commit, no report.
Ruling: re-dispatch with leaner brief (deleg_02ee06d2) rather than stepping
down model — the failure was API-side, not capability-side. Cost if wrong:
one more wasted ~10 min round.

Task 1 (dispatch 2, deleg_02ee06d2): FAILED — same infra cause (API timeouts,
"timed out after 90s", 3 retries, iteration budget exhausted). No code, no
commit. Two consecutive zero-output failures.

Task 2 (dispatch 1, deleg_7b386f09): FAILED — same infra cause (API timeouts
"timed out after 90s", 3 retries, budget exhausted). No code, no commit.
Third consecutive zero-output delegation failure.

Task 1: complete (commits 347efef..cd54ae5, review pending — inline impl
per ruling). Verified: tools/test_bg_clock.gd PASS (song-clock pulses per
beat, 0 play_beat calls in song mode, menu fallback intact after clear),
e2e_chart_drive PASS (224/224 beats), boot check 0 script errors.
Test-infrastructure findings during impl (for reviewer): (1) --script
SceneTree tests must run in _initialize(), not _init — autoload identifiers
compile only after registration; (2) assert counters, not pulse ring arrays —
without a real viewport, rings cull instantly (max_radius=0). Findings are
test-side only, product behavior untouched.

Task 2: complete (commits cd54ae5..a56bd2b, review pending — inline impl per
standing ruling; delegation 3/3 dead this session, no re-dispatch attempted).
Verified: tools/test_laser_beat.gd PASS (8/8 telegraphs fire on the chart
beat grid, collected via the real spawn path with wall gates), e2e PASS
(224/224), boot 0 errors. Telegraph now 3*beat_len (1.40625s @128) vs 1.3s
fixed — +0.1s warning, beatable margin preserved.

Task 3: complete (commits d1da1bd..42ef3a0, review pending — inline impl).
Verified: tools/test_cadence.gd PASS (intro/outro emit only on even-bar
downbeats; every drop/drop2 downbeat emits; drops have snare accents; intent
helper correct at 4 probe times), E2E PASS (224/224, 172 spawns — energy-
shaped: saw 18→72 from accents, quiet sections thinned), laser PASS, bg PASS,
boot 0. Impl note: cadence (encounter gate) and accents (beats 2/4) are
independent axes — first version gated accents behind the encounter beat and
they never fired; caught by the cadence test, fixed before commit. E2E edit
that asserted nothing (cadence_ok := true) was reverted — dead code in tests
is a review defect.

Task 8: complete (commits cc72246..1dab46f, review pending — inline impl).
Verified: tools/test_structure_follow.gd PASS — the plan's exact proof:
patched chart with drop 16→8 bars, level follows (displaced breakdown gets
breakdown patterns, no walls; shortened drop still opens with its wall),
zero level edits. Full suite green (E2E 224/224 — mix shifted sensibly:
walls 10→14 from section-open teaching walls, homing 2→3 in drop2; cross
now 138 falling spawns, all on-grid). _first_light_pattern now takes
(beat_idx, t); all call sites updated; helpers _section_name_of_bar/
_section_start_bar derive from chart.level_sections only.

Task 7: complete (commits 3fb1a5e..cc72246, review pending — inline impl).
DECISION: 22kHz REJECTED per the plan's own gate — measured render is
4.4-4.7s at 12kHz (3 runs, test_render_budget.gd), 2.25x over the 2s
startup budget; doubling RATE would roughly double it. What shipped: the
measurement, a budget regression-guard test, and a ~23% mix-loop
optimization (duck LUT + inlined byte I/O). CORRECTION of a T6 claim:
"render ~2s stays" in the T6 commit message was never measured — actual
~4.5s even before T6. Ledger honestly records the debt; budget test FAILs
by design until someone optimizes the bar-loop renderers (pads/lead2/snare
fill dominate — a profile script existed but its numbers were invalidated
by out-of-bounds writes; do not trust /tmp/prof_song.gd results).
Bug found+fixed during optimization: per-sample post-sum sign fixup was
mathematically wrong (one negative buffer among four clips the mix);
restored per-buffer fixup, test_song_pulse caught it.

Task 6: complete (commits 7549a4f..3fb1a5e, review pending — inline impl).
Verified: tools/test_song_pulse.gd PASS (duck curve exact at hit/mid/1-beat +
full-mix A/B vs sc_depth=0 shows the offbeat band ducked; fill crescendo per
quarter 4027→4458 and beats previous bar; intro arp A/B; peak 24583 no clip;
chart 224 beats unchanged). Full suite green, boot 0. Rulings: (a) test first
measured the post-kick window dominated by the (unducked) kick itself —
replaced with direct duck-curve assertions + A/B against sc_depth=0 render;
(b) fill loudness raised 0.35→0.55 base after measurement showed it inaudible
over the mix floor; (c) fill comparison window: bar-6 baseline was wrong
(same-energy bar 10 is the honest A/B), kept crescendo assertion too.

Task 5: complete (commits 684355f..7549a4f, review pending — inline impl).
Verified: tools/test_section_mood.gd PASS (grid brightness monotonic with
energy across all 6 sections, breakdown cold/dimmer, clear restores menu
color), cross PASS updated for 5.5-beat drop2 + corrected probes, E2E/
cadence/laser/bg PASS, boot 0, real-render run captured 4 on-time screenshots
(intro 5.01s, drop 30.02s, breakdown 55.01s, drop2 80.01s) via new
MCP_SHOT_LIST env — saved in SDD workspace. Rulings: (a) drop2 push done as
5.5-beat crossing (equivalent +8.5% speed) instead of a separate velocity
multiplier — keeps T4's quantization; still lands on the audible 8th-note
grid the song renders in drops. (b) vision_analyze unavailable on this
provider (multimodal disabled) — pixel-percentile heuristics proved unable
to isolate grid lines from hazards, so the mood CONTRACT is verified
headless (test_section_mood) and the 4 real-render screenshots are archived
for Bauti's own eyes. Real-run playability check still owed (plan asks for a
full beatable run; headless E2E green so far).

Task 4: complete (commits 42ef3a0..684355f, review pending — inline impl).
Verified: tools/test_crossing_beats.gd PASS (helper exact at 6 probes, 147/147
real spawns land on integer beats), E2E/cadence/laser/bg PASS, boot 0. Impl
note: first version quantized from a fixed -50px baseline; lane saws spawn
at -45/-85 and broke quantization (test caught ±0.35-beat drift) — fixed by
passing the real spawn y (_quantized_vy_from). Gameplay-speed ruling: saws
~218px/s in drops (was 120) — acceptable because crossing time stays 6 beats
(2.8s reaction), unchanged wall timings, and T3 halved quiet-section
encounters; First Light remains beatable per plan constraint (real-run
verification still owed at T5 with 3 screenshots).

Branch: single-level-mvp. Plan is a non-technical priorities doc; each task's
dispatch brief must translate to concrete TDD steps. No reachable spec beyond
the user request ("Make the level match with the song more, improving song and
level behavior") — rulings made without one are provisional.

Pre-flight scan table (file/interface overlaps):

| Pair | Produce/Consume | Finding |
|---|---|---|
| T1↔T5 | Both touch NeonBackground.gd + Gameplay.gd _draw | T1 retimes the pulse to the audio clock; T5 scales intensity by section energy. Independent axes (time vs amplitude); T5 must read the audio clock introduced by T1. Ruling: dispatch T5 after T1 merges, carry the interface. |
| T2↔T3 | Both touch PatternController.gd | T2 changes _laser_telegraph timing; T3 changes spawn cadence in spawns_at. Independent functions; no conflict. |
| T3↔T4 | Both touch PatternController.gd | T3 changes how often spawns happen; T4 changes their speed. Both read section energy; must share one section→intent helper, not duplicate. Ruling: T3 introduces the section-intent helper, T4 consumes it. |
| T3↔T8 | Both replace first-light timeline logic | T8 supersedes part of T3's work (hardcoded bar ranges → section-driven). Ruling: T3 already reads section energy as source of truth (plan text says so); T8 extends to phrase/setpiece choreography. No contradiction. |
| T4↔T5 | T4 sets travel speeds; T5 adds +10-15% speed in drop2 | T5's speed boost multiplies on top of T4's quantized speeds. Ruling: T5 applies its multiplier to the final speed, not to the beats-count N, so quantization survives. |
| T6↔T7 | Both touch ProceduralSong.gd render_audio | T7 (optional) changes RATE 12k→22k; T6 adds sidechain+fill+arp. Same file, sequential dispatch, no conflict. |
| Self: T2 | telegraph 3 beats at 128 BPM = 1.40625s; brief must derive from chart.beat_len, not hardcode 1.41 | consistent |
| Self: T4 | "arrival on-beat": spawn y=-50, player zone y≈0.78h; travel distance ≈ 0.78h+50. Quantize to integer beats via beat_len. | consistent |
| Self: T6 | sidechain ducking at kick positions; kick positions are bar_t + k*beat_interval — computable before mixing. | consistent |

Global constraints carried into every dispatch:
- First Light must remain beatable end-to-end (easy_mode, HP 125, 2s iframes, wall warn 2.5 beats).
- tools/e2e_chart_drive.gd must PASS after every task.
- NO push to remotes. One local commit per task minimum.
- Verification = godot --headless E2E + real run with screenshots/logs.
