# Design — Abstract Pulse (Modular Synth Patchbay World)

## World Commitment

The visual world is a **modular synthesizer patchbay** — the actual instrument paradigm behind the music. Eurorack panels, 3.5mm patch cables, signal flow, voltage control. The menu *is* a synth voice: three module panels (one per track) rack-mounted side by side. The beat is a clock signal. Selecting a track = patching a cable from the clock source into that module. Starting the song = the patch completes and the sequence runs.

This world is literal, not decorative. Every component maps to a real modular concept. No "cyber neon" chrome.

## Palette (4 roles, OKLCH)

| Role | OKLCH | Use |
|------|-------|-----|
| **panel** (canvas) | `0.12 0.01 260` | Module faceplates, rack rails, deep near-black with a blue bias |
| **silkscreen** (primary text) | `0.92 0.02 260` | Labels, jack names, track titles, UI text — off-white with blue tint |
| **signal** (action accent) | `0.78 0.22 142` | **Only** for: primary CTA ("PATCH IN"), active patch cable, beat flash, focused jack. Saturated green-yellow — the "gate high" voltage color. |
| **track** (per-song identity) | data-driven | Each track owns its hue from `GameManager.TRACKS[*].color` (cyan/magenta/gold). Used **only** on the selected module's LED ring, its jack nuts, and the background grid tint. Never on primary text or global chrome. |

No other colors. No magenta secondary, no cyan monoculture. `signal` is rare and means *do this now*. `track` color is data, not decor.

## Typography

- **Font**: Godot default (no custom font shipped). Weights simulated via `LabelSettings` outline + `font_size` steps.
- **Roles** (defined once in Theme, no inline overrides):
  - `display` — 36pt, outline 1px, tracking -0.02em — module model names (CYBER GENESIS)
  - `header` — 20pt, outline 1px — section heads (SELECT VOICE)
  - `body` — 16pt — descriptions, metadata
  - `mono` — 14pt, tabular nums — BPM, duration, difficulty stars
  - `micro` — 11pt, uppercase, tracking 0.08em — jack labels (GATE, CV, OUT), mode badges
- **Hierarchy**: size + weight (outline) + space. Color only for `signal` accent on primary CTA.

## Component Grammar

| Component | Visual | States |
|-----------|--------|--------|
| **Module panel** | Rectangular faceplate, 2mm silkscreen border, 4 corner screw holes (drawn), subtle rack rail top/bottom | `idle` (dim LED), `selected` (LED ring pulses `track` color on beat), `patching` (cable attached, `signal` flash) |
| **Patch jack** | 3.5mm jack socket: nut (track color when selected), tip ring sleeve visible, silkscreen label below | `empty`, `hover` (cable ghost follows cursor), `patched` (cable seated, `signal` pulse) |
| **Patch cable** | Curved bezier from source jack to target jack, `signal` color, 2px stroke, animated "voltage" dash flow on beat | `ghost` (preview), `seated` (locked), `live` (dash animates) |
| **Primary CTA** — "PATCH IN" | Full-width bar at bottom of selected module, filled `signal`, `silkscreen` text, 2px `panel` border | `idle`, `hover` (brighten), `focus` (2px `signal` inner ring), `pressed` (inset) |
| **Secondary icon button** (top rail) | 32px square, `panel` face, `silkscreen` icon, no border | `idle`, `hover` (`signal` icon), `focus` (2px `signal` ring) |
| **Overlay panel** (settings/credits) | `panel` face, 1px `silkscreen` border, 8px radius, slides from top rail | `closed`, `opening`, `open`, `closing` |
| **LED ring** | 2px stroke circle around module center, `track` color, pulses on beat (expands 0→100% alpha) | `dim`, `beat` (pulse), `patching` (solid `signal`) |

## Topology & Navigation

**First viewport** (MainMenu):
```
┌─────────────────────────────────────────────────────────────┐
│  [≡]  ABSTRACT PULSE                          [⚙] [i] [✕]  │  ← Top rail: menu, settings, credits, exit
├─────────────────────────────────────────────────────────────┤
│                                                             │
│    ┌──────────────┐   ┌──────────────┐   ┌──────────────┐   │  ← Three module panels (rack)
│    │  CYBER       │   │  NEON        │   │  OVERDRIVE   │   │     Each: model name, BPM, ★, jack
│    │  GENESIS     │   │  RUSH        │   │  PULSE       │   │
│    │  128 BPM  ★  │   │  145 BPM ★★  │   │  170 BPM ★★★ │   │
│    │  [GATE]  ◉   │   │  [GATE]  ○   │   │  [GATE]  ○   │   │     ◉ = selected (LED ring pulses)
│    └──────────────┘   └──────────────┘   └──────────────┘   │
│                                                             │
│                    ┌────────────────────────┐               │  ← Selected module expands down
│                    │   PATCH IN  ▸          │               │     Shows: description, high score, CTA
│                    └────────────────────────┘               │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**Navigation**:
- ←/→ or click: select adjacent module (cable ghost follows)
- Enter/Space/click on "PATCH IN": launch level
- Top rail icons: open overlay (Settings / Credits / Exit confirm)
- ESC: close overlay, or from module selection → no-op (already at root)

**Gameplay HUD** (minimal, same world):
- Top rail: track name + BPM (left), score/combo (right) — `header` + `mono`
- Bottom rail: health (LED bar, `signal`→`track` color gradient), progress (patch cable thin line)
- Pause/Results overlays: same `panel` + `silkscreen` grammar

## Controls & States

- **Keyboard**: ←/→ select module, Enter patch in, ESC close overlay
- **Mouse**: click module, click CTA, hover shows cable ghost
- **Focus**: distinct 2px `signal` inner ring on all interactive elements (never = hover)
- **Beat pulse**: `NeonBackground` emits `beat` signal → selected module's LED ring expands; `PATCH IN` button gets a subtle `signal` flash (not the title flicker)

## Responsive / Adaptation

Single target: 1280×720 fullscreen kiosk. No responsive reflow needed. If windowed, rack scales uniformly (min 960×540). Modules keep aspect.

## Motion

**One authored moment**: the patch cable seating. When a module is selected:
1. Cable ghost appears from clock source (top rail left) to module's GATE jack
2. On "PATCH IN" press: cable snaps into jack with `signal` flash, dash animation starts
3. Scene transition: screen wipes along cable path (left→right)

No other motion. No hover wiggles, no ambient flicker. The beat pulse on the LED ring is the only continuous motion.

## Contrast Floor

All text on `panel` meets 4.5:1 (`silkscreen` on `panel`). `signal` on `panel` meets 3:1 for UI elements. `track` colors only on decorative LED/jack nuts — never sole carrier of information (always accompanied by label, star pips, position).

## Prohibitions (enforced by this world)

- No gradient text
- No glass/blur
- No colored borders on panels (only 1px `silkscreen` rule)
- No magenta anywhere (retired)
- No cyan as global accent (only as track data on its module)
- No title flicker (the old `_process` sin wobble)
- No placeholder ColorRects (ship preview = drawn module mini; hand cursor = crosshair)
- No inline `theme_override_*` — all roles in Theme

## Token Mapping (for Theme resource)

```
panel_bg          = panel
panel_border      = silkscreen @ 0.3
text_primary      = silkscreen
text_secondary    = silkscreen @ 0.7
text_mono         = silkscreen
accent_signal     = signal
accent_track      = (data-driven, not a token)
jack_nut_idle     = silkscreen @ 0.4
jack_nut_selected = track color
cable_signal      = signal
cable_ghost       = signal @ 0.3
focus_ring        = signal
```

## Build Checklist

- [ ] Delete `resources/neon_theme.tres`
- [ ] Create `resources/patchbay_theme.tres` with all roles above
- [ ] Restructure `MainMenu.tscn` → rack + 3 modules + top rail + expandable CTA
- [ ] New `scripts/PatchbayModule.gd` (module panel logic: selection, LED pulse, cable ghost)
- [ ] New `scripts/PatchCable.gd` (bezier cable with dash animation)
- [ ] Rewire `MainMenu.gd` → module selection, beat pulse, patch-in launch
- [ ] `NeonBackground.gd` → expose clean `beat` signal, keep grid but tint by selected track
- [ ] `Gameplay.tscn` HUD → patchbay grammar (top/bottom rails, themed bars)
- [ ] Delete `Main.tscn` (vestigial)
- [ ] Remove `GameManager.camera_flipped`
- [ ] Verify focus≠hover, exit confirm, keyboard parity
