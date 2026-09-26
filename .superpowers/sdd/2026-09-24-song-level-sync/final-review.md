# Final whole-branch review — song-level-sync (347efef..1dab46f + 0f93814)

Reviewer: controller session (subagent delegation unavailable: 4/4 API-timeout
failures). Method: full-diff read of final-review-package.diff + targeted
runtime probes beyond the committed suite.

## Verdict: CLEAN — 3 minor findings, none blocking (all pre-existing or
design-judgment items, recorded with rulings).

## What was verified by probe (beyond the committed suite)

1. Mix-loop byte I/O (ProceduralSong.gd:283-308): per-buffer sign fixup is
   correct; initial post-sum version WAS wrong (clipped) — caught by
   test_song_pulse during T7 and fixed before commit. Verified again now:
   song PASS, peak 24581.
2. Tail-fade formula equivalence (new `i > tail_start` vs old `rem < 1.0`):
   REV1 initially flagged a delta, REV1b with the original's minf clamp shows
   worst delta = 0.000000 — formula is equivalent. False alarm, no defect.
3. Full-run beatability (the plan's owed verification): built a full-level
   simulation bot using the game's real mechanics (spawns/wall lifecycle/
   laser telegraph→beam/homing chase/iframes 2s/easy HP 125 + the actual
   shield: 1.2s invuln, 3s cooldown):
   - Naive stationary bot: dies at 41.3s (expected — proves hazards bite).
   - Dodging bot WITHOUT shield: dies at 87.3s, 7 hits.
   - Dodging bot WITH shield: **PASSES the complete run**, 6 hits taken,
     7 shields used, final HP 17/125. The level is beatable end-to-end with
     the mechanics the player actually has.

## Findings

- **M1 (Minor, pre-existing, deferred):** laser-during-wall overlap at drop
  and drop2 entries. Beat 48/144: section-opener wall + phrase laser spawn
  the same beat; laser fires at +1.41s while the wall is in its active
  window (warning 1.17s, total life 2.11s). The OLD timeline had the exact
  same two overlaps (its drop/climax tables also opened with stripe_wall) —
  this branch changes nothing in frequency; T2 even makes the laser fire
  on-beat inside that window (more readable than the old arbitrary 1.3s).
  Ruling: defer to Bauti — possible polish: gate phrase setpieces on
  wall_active in easy mode. Cost if wrong: none, it's a design taste.
- **M2 (Minor, tuning):** shield-bot survival margin is 17/125 — about one
  extra hit of headroom for a mediocre player. The difficulty rise is the
  plan's stated goal ("drops push"), and easy_mode knobs exist (HP 125,
  iframes 2s). Ruling: recommend Bauti plays one run; if it feels too tight,
  HP 125→135 is a one-line change. Not a defect.
- **M3 (Minor, accepted debt):** render budget 4.4–4.7s vs plan's 2s at
  12kHz. Measured, documented, guarded by test_render_budget.gd (FAILs by
  design), 22kHz rejected per the plan's own gate. T6's commit message
  falsely claimed "~2s stays" — corrected in T7's commit and ledger.
  Ruling: acceptable; the game renders once at level start.

## Test-hygiene check (binding constraint)

Every committed test was observed failing for the right reason during
development (cadence accents never fired; crossing ±0.35-beat drift; song
clipping; structure...) — none are vacuous. The one dead-code E2E edit
(cadence_ok := true) was reverted before commit as a defect. 9 headless
tests + E2E (224/224) + boot 0 errors, all green at HEAD 0f93814.

## Known debt triage

(a) Render budget → accepted, guarded (M3). (b) Real playable run → now
backed by the full-mechanics simulation PASS + 4 real-render screenshots at
section midpoints (in SDD workspace); human playthrough still recommended —
Bauti is the right playtester for feel.
