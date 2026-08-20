# Product

<!-- impeccable:product-schema 1 -->

## Platform

desktop

## Users

Visitors who walk up to the Abstract Pulse booth at the Feria de Ciencias 2026 — mostly curious students, peers, judges, and family members. They stand in a ~2x2m to 3x3m free space in front of a camera and a single large monitor. The job: understand in seconds that their hands are the controller, pick a song, and survive it. Secondary users: the referente (Bautista Prieto) and fair staff who keep the booth running. Register is playful and energetic; the menu should feel like a stage, not a settings panel.

## Product Purpose

A rhythm action game where the player's own hands are the controller. One hand drives the ship's movement, the other aims and fires. The music sets the difficulty, speed, and visual intensity of the level. Success = survive the full song with HP above zero. The menu's job is to make a stranger believe, within five seconds, that this is something worth stepping up to.

## Positioning

The mechanism no neighboring science-fair project could truthfully claim is hand-tracking-as-controller plus per-song color identity: each track owns a palette, a BPM, and a difficulty that together define the visual and physical intensity of that level. The product is not "a rhythm game with neon UI" — it is a kiosk where the visitor's body is the input.

## Operating Context

A science-fair kiosk: one large monitor, speakers, a webcam for MediaPipe hand tracking, a desk or stand, and roughly 2x2m of clear floor in front of the camera. Default input is keyboard + mouse; MediaPipe is the stretch control mode that, when it works, is the whole point. Visitors have short attention spans and will abandon if the first screen doesn't earn them. Sessions are single-song; there is no multiplayer, no ranking, no saved progression beyond a per-track high score held in memory.

## Capabilities and Constraints

Three named tracks drive the whole game: Cyber Genesis (Principiante, 128 BPM, 2:15), Neon Rush (Intermedio, 145 BPM, 2:40), Overdrive Pulse (Avanzado, 170 BPM, 3:10). Four ship palettes are the visual upgrade path: Cyan Neon, Cyber Magenta, Gold Flare, Emerald Matrix. Two control modes toggle from the menu: MediaPipe hand tracking and Keyboard + Mouse. Audio is fully procedural (synthesized synth SFX in SoundManager). High scores persist only in memory per session (GameManager dict).

Technical constraints: Godot 4.7, GDScript, no custom font shipped (Godot default only unless a font asset is provided later), no external art assets (all visuals must be Godot-drawn primitives or vector `_draw`). UI must remain fully usable with mouse and keyboard alone — MediaPipe is a stretch input, never a dependency for menu navigation.

Explicitly undecided: no procedural track generation is committed (Analysis leaves "finalización: completar todos los niveles si no se generan de forma procedural" open). Per-track content beyond the prototype beat-spawner is undecided.

## Brand Commitments

Name: "Abstract Pulse". UI language: Spanish. Event framing: Feria de Ciencias 2026. The former neon-cyberpunk visual identity (cyan perspective grid, magenta secondary, dark synth gradient, glow-bordered panels) was explicitly retired by the owner on 2026-08-20 — it read as category-templated ("AI slop") and is not a binding commitment. No surviving visual asset is authoritative.

## Evidence on Hand

- Three authored tracks with names, artists (SynthPulse / CyberWave / Neural Beat), BPMs, difficulties (1-3 stars), durations, colors, and descriptions — in `scripts/GameManager.gd` const `TRACKS`.
- Four authored palettes with main + glow colors — in `GameManager.gd` const `SHIP_PALETTES`.
- A working BPM-synced background renderer (`scripts/NeonBackground.gd`) that already emits pulse rings on the beat and re-themes its grid to the selected track color via the `track_selected` signal.
- A procedural audio system (`scripts/SoundManager.gd`) generating hover/click/launch/beat synth tones.
- A prototype level (`scenes/Gameplay.tscn` + `Gameplay.gd`) with player ship, beat targets, projectiles, score/combo, health, pause and results overlays.
- High-score dict per track id (`GameManager.gd`).

Absences future work must not fabricate: no real song audio, no MediaPipe integration code yet (only control-mode flagging), no user testing data, no published export builds, no custom typeface.

## Product Principles

1. The menu must make a stranger want to step up to the booth within five seconds — the primary action is always obvious and inviting, never buried.
2. The player's body is the input; the interface should never pretend otherwise or hide behind a generic desktop-app shell.
3. Each track is a distinct identity (color + BPM + difficulty); the menu and the level should both wear that identity, not a single global chrome.
4. The beat is the product — rhythmic motion belongs to one authored moment, not ambient flicker everywhere.
5. Everything must work with mouse and keyboard; the hand-tracking mode is a gift, not a gate.

## Accessibility & Inclusion

Keyboard parity is required for all menu navigation and the primary action (mouse is the documented fallback control mode). A distinct focus indicator (not identical to hover) is required. Visitors at a fair booth may have no prior context — iconography must be labeled or self-evident. Color carries identity but must not be the only code for difficulty/selection (star pips and labels accompany hue).
