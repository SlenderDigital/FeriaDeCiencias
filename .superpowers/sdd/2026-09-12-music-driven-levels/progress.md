# SDD ledger — plan: docs/superpowers/plans/2026-09-12-music-driven-levels.md

## Pre-flight scan (2026-09-12)
- Tasks 1-3 (analyzer + BPM/beat extraction + sections) were already implemented and verified against real audio (104/115/176 BPM) BEFORE the subagent loop started. Committed as 5ce94ba + 10217bd + bb0b2e1.
- Analyzer unit test (tools/test_analyzer.py) passes: bpm within ±6 of synth target, sections monotonic, energies [0,1].
- Ruling: synthetic click-track tempo detection is ±3-6 BPM (librosa frame grid); test tolerance set to ±6.
- Ruling: commit .ogg + .analysis.json; .wav sources gitignored (build-time input, 89MB).

## Tasks complete
Task 1: complete (analyzer scaffold — committed 5ce94ba, review: self-verified via test)
Task 2: complete (BPM/beat extraction — verified 104/115/176 on real audio)
Task 3: complete (section detection — verified energies + monotonic sections)

## Task 4 — ChartData (in review)
- BASE bb0b2e1, impl b8f1ac9 (scripts/ChartData.gd, 45 lines, transcribed from brief)
- Implementer: DONE, no concerns
- Review dispatched: deleg_35f8b39f (sa-0-c3c223d6)

## Task 4 — review verdict (deleg_35f8b39f)
- Spec compliance: ⚠️ (contract met) — but 2 Important code-quality defects found in the brief's own code, transcribed verbatim:
  1. Malformed JSON → JSON.parse_string returns null → `var analysis: Dictionary = null` then `.is_empty()` → runtime error (intended guard unreachable). ChartData.gd:35-37
  2. Untyped Array (Dictionary.get) assigned to typed Array[float]/Array[Dictionary] members → Godot 4 runtime type error on load. ChartData.gd:36-39
- Ruling: plan-mandated code has a real runtime defect; spec intent is a ROBUST loader. Fix both Important items (null guard + typed-array reconstruction). Minor items (validate-only-warns, trailing newline, skipped Step 2) → deferred to ledger, not in fix loop.

## Task 4 — COMPLETE
- Fix round 1/5: 2 addressed, 0 open (commits b8f1ac9..800a6b4)
- Re-review (deleg_129a08ad): APPROVED, no new breakage
- Minors deferred: validate-only-warns, untyped key access in _validate, skipped Step2 test, trailing newline
- Task 4: complete (commits bb0b2e1..800a6b4, review clean)

## Task 5 + Task 6 — COMPLETE
- BASE 800a6b4, impl aeb04f1. Verified headless (godot --headless --quit → exit 0, no script errors).
- Review (deleg_2e28a509): Spec ✅, Quality Approved.
- 2 Important findings (empty-pool `randi()%0`, unhandled pattern name → silent []): both have NO runtime trigger in current data (3 authored files never pass empty pool / unknown pattern).
- Ruling: defer both to Task 7 (first consumer) as one-line guards, rather than a separate fix round. This is efficient + the reviewer's own bottom line ("non-blocking, worth a one-line guard in T7"). Cost if wrong: none — guards are self-contained; if T7 forgets them, downstream authoring could crash on empty pool, recoverable.
- Minors ledgered: missing trailing newline (3 json + PatternController.gd), O(n) _current_section scan (negligible), level_sections end not validated.
- Task 5: complete (commits 800a6b4..aeb04f1, review clean)
- Task 6: complete (commits 800a6b4..aeb04f1, review clean, 2 findings deferred to T7)

## Task 7 — in review (with controller-authored instant-victory fix)
- BASE aeb04f1, impl 6208953 (implementer) + 1bebd20 (controller fix).
- Implementer hit real Godot 4.7 bug mid-task: AudioStreamOggVorbis has no .load() method — switched to load(path) as AudioStream. Verified chart path live.
- User reported: instant-win on level start. Root cause: `music.finished` flips true during stream setup (before real playback) → `or music.finished` fired _trigger_victory() on frame 1.
- Controller fix (1bebd20): victory now requires song_time > 0.5 (guard against stream-setup finished race). Levels are 100-200s so no false-negative risk.
- Ruling: controller authored this fix directly (not via subagent) because it's a load-bearing user-reported bug and the implementer had already completed; it IS in the review diff (1bebd20) so it's still reviewed.
- Review dispatched: deleg_dd3b28e6 (sa-0-3f79fbe4)

## Finding (not in plan) — MainMenu off-by-one
- MainMenu.gd has 4 track buttons (_on_btn_track_0..3 -> _select_track_ui(0..3)) but TRACKS now has 3 entries (indices 0-2). Button 3 = silent no-op; 4 buttons shown for 3 levels.
- Ruling: real UX bug, belongs to same feature. Fold the fix into the Task 7 fix round (remove btn_track_3 button + handler, or re-index). Will fix after Task 7 review verdict returns.

## Task 7 — COMPLETE
- Review (deleg_dd3b28e6): Spec ✅, Quality Approved. Fix 1bebd20 verified correct + regression-free.
- 2 Minor findings (non-blocking, ledgered):
  - Issue A: clock re-anchors to delta when music.playing=false (finish/fail). Harmless (victory fires via music.finished same frame). Defer.
  - Issue B: reached_end keys off chart.duration (could diverge from real stream length); music.finished is the ground-truth and masks it. Defer.
- Independent confirm: MainMenu still has 4 track buttons (BtnTrack0..3) vs 3 tracks; BtnTrack3 -> select_track(3) no-ops -> First Light. User-visible. WILL FIX next.
- Task 7: complete (commits aeb04f1..1bebd20, review clean, 2 minors deferred)

Also completed out-of-band: mechanical_wall track swapped to Suno version (ce946e8) + re-authored level.json + duration/description fixes.

## Task 8 — COMPLETE
- tools/test_beat_alignment.py: all 3 tracks PASS (monotonic beats, in-range, drift <=1.31x, contiguous sections, finite energy). Commit ee6952c.
- tools/test_sync_contract.txt documents the audio-clock contract.

## Task 9 — COMPLETE
- tools/e2e_chart_drive.gd: headless E2E drives ChartData+PatternController with simulated clock. first_light 111 spawns (16 haz/95 tgt), mechanical_wall 195 (38/157), relentless_drive 701 (177/524). Density escalates correctly. ALL TRACKS PASS. Commit c2fa2de.

## Out-of-band work completed during plan execution (all committed)
- cbvvvv mechanical_wall track swapped to Suno version (ce946e8): new ogg/analysis/level + durations/descriptions fixed.
- MainMenu off-by-one fix + F6 debug level-jump overlay (65f356e).

## ALL TASKS COMPLETE

## FINAL WHOLE-BRANCH REVIEW — 1 Important finding, fixed
- Review (deleg_d8e00ee5): "Needs fixes" for ONE Important coherence gap: librosa beat_track w/o trim=False stripped leading silence → no spawns first 13-16s of every level (dead air despite authored intro density).
- Ruling: FIX (not "documented sign-off") — root cause is one kwargs flag; cheap, correct, verified.
- Fix c9b4065: trim=False. Result: first beat 15.0→3.6s (first_light), 13.0→3.8s (mech_wall), 16.6→2.5s (relentless). All 3 beat-alignment tests PASS, E2E PASS (more beats, density still escalates 14/45/173 hazards).
- Orphan mechanical_wall_new.analysis.json deleted.
- Deferred minors triaged by reviewer: ALL can ship (clock re-anchor after finish, reached_end vs duration, missing newlines, O(n) scan, validate-warns-only, untyped key access).
- Final: cbd79a7 .uid sidecars added (repo convention).

## PLAN COMPLETE — all 9 tasks + 2 out-of-band (track swap, MainMenu/debug menu) + final review fix. 15 commits.
