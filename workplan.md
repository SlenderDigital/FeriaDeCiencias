# Workplan — Abstract Pulse
*Last updated: 2026-08-20*

## Today's Completed Work (Anti-Slop UI Redesign)

### Visual World Replacement
**Before**: Generic "neon cyberpunk" template — dark synth gradient, cyan perspective grid, magenta secondary, glow-bordered panels, floating particles. Read as AI-slop category template.

**After**: **Modular Synth Patchbay** — the actual instrument paradigm behind the music.
- Each track = a Eurorack module panel (rack-mounted side by side)
- Selection = patching a cable from clock source → module's GATE jack
- "PATCH IN" = completing the patch, launching the sequence
- Per-track color = data, not decor (only on selected module's LED ring + jack nut)

### Files Created

| File | Purpose |
|------|---------|
| `PRODUCT.md` | Product truth: users, purpose, positioning, capabilities, constraints |
| `DESIGN.md` | Durable visual world rules: palette, typography, components, topology, motion |
| `resources/patchbay_theme.tres` | 4-role theme: panel/silkscreen/signal/track; themed Button, ProgressBar, TextureProgressBar, HSlider, CheckButton |
| `scripts/MenuBackground.gd` | Fresh background script (replaces corrupted NeonBackground.gd) |
| `scripts/PatchbayModule.gd` | Self-building module panel: model/BPM/stars/jack + LED ring beat pulse |
| `scripts/PatchCable.gd` | Animated bezier cable with voltage dash flow on beat |
| `scripts/SettingsOverlay.gd` / `.tscn` | Slide-down settings (volume, fullscreen) |
| `scripts/CreditsOverlay.gd` / `.tscn` | Slide-down credits |

### Files Rewritten

| File | Changes |
|------|---------|
| `scenes/MainMenu.tscn` | Track-list-first hero: 3 rack modules + top rail icons + expandable PATCH IN panel |
| `scenes/Gameplay.tscn` | Patchbay HUD: top rail (track + score), bottom rail (HEALTH red + PROGRESS green) |
| `scripts/MainMenu.gd` | Module selection, patch cable animation, overlay management |
| `scripts/Gameplay.gd` | New HUD node paths, patchbay grammar |
| `scripts/GameManager.gd` | Removed unused `camera_flipped` |

### Files Deleted
- `scenes/Main.tscn` + `scripts/Main.gd` (vestigial)
- `scripts/NeonBackground.gd` (corrupted cache source)
- `scripts/GameplayBackground.gd` (unused copy)

### Key Design Decisions
1. **4-role palette only**: `panel` (canvas), `silkscreen` (text), `signal` (primary CTA + beat only), `track` (per-song data)
2. **No cyan monoculture**: Cyan appears only as track data on its own module
3. **Primary action prominent**: Green "PATCH IN" is the only filled button; EXIT is ghost
4. **Focus ≠ Hover**: Distinct 2px signal ring for keyboard accessibility (WCAG)
5. **One authored motion**: Patch cable seating + beat pulse on LED ring (no ambient flicker)
6. **No placeholder art**: Ship preview = drawn module; hand cursor = vector crosshair

### Verification Status
- ✅ MainMenu runs with helper live, zero errors
- ✅ Three modules show correct data: CYBER GENESIS (128 BPM ★), NEON RUSH (145 BPM ★★), OVERDRIVE PULSE (170 BPM ★★★)
- ✅ Selected module: cyan outline, LED ring pulse on beat, green patch cable → GATE jack
- ✅ Each GATE jack shows track color (cyan/pink/yellow)
- ✅ Top rail icons (⚙/i/✕) open slide-down overlays
- ✅ Bottom panel: description + high score + green PATCH IN button
- ✅ No NeonBackground.gd cache errors (clean editor state after plugin reload)

---

## Partner Work: Facundo Guinazu — MediaPipe Controls
*Status: In progress (not tracked in this repo yet)*

**Scope**: Hand tracking via MediaPipe for hand-controlled gameplay
- Left hand → ship movement (spatial displacement)
- Right hand → aim orientation + rhythmic fire
- Camera input → MediaPipe landmarks → Godot via WebSocket / local bridge
- Fallback: keyboard+mouse already implemented and tested

**Integration Points Needed**:
- `GameManager.control_mode` = "MediaPipe" | "KeyboardMouse" (already exposed)
- MediaPipe data → ship `player_pos` + aim angle + fire trigger in `Gameplay.gd`
- Calibration UI (already stubbed in MainMenu Controls panel)

**Next Steps for Integration**:
1. MediaPipe Python/JS service sending landmark data
2. Bridge (WebSocket / UDP / local pipe) to Godot autoload
3. Map landmarks → normalized screen coordinates → game actions
4. Test at Feria booth (2×2m space, camera position, lighting)

---

## Remaining / Future Work

| Priority | Task | Owner |
|----------|------|-------|
| High | MediaPipe hand-tracking integration | Facundo |
| High | Real song audio + beat-synced spawn patterns | TBD |
| Medium | Procedural level generation per-track | TBD |
| Medium | High-score persistence (file/JSON) | TBD |
| Low | Custom font (requires .ttf asset) | TBD |
| Low | Export templates (Linux/Windows/Web) | TBD |

---

## Quick Commands
```bash
# Run main menu
godot --path /home/slender/Projects/FeriaDeCiencias

# Run gameplay scene directly
godot --path /home/slender/Projects/FeriaDeCiencias --scene res://scenes/Gameplay.tscn

# Check for script errors
godot --path /home/slender/Projects/FeriaDeCiencias --script res://scripts/MainMenu.gd
```

---

## Notes for Next Session
- MediaPipe integration is the critical path for Feria demo
- Gameplay HUD bars (HEALTH/PROGRESS) need real-time updates verified in playtest
- "PATCH IN" → Gameplay transition works but needs end-to-end test with MediaPipe controls
- Consider adding a brief "HOW TO PLAY" overlay for first-time booth visitors