The refactoring is complete and all test suites pass. Total GDScript across `juego/scripts/` dropped from **~8,334 lines** to **4,387 lines (~47% reduction)** while preserving 100% of gameplay, visual effects, audio, persistence, and hand-tracking functionality.

### Key Changes

1. **Pre-Baked Audio & Centralized [`SoundManager`](file:///home/ironowl/dev/FeriaDeCiencias/juego/scripts/sound_manager.gd)**
   - Baked all 14 procedural streams into standard `.wav` files under `juego/assets/audio/` (`music.wav` + 13 SFX) and deleted the 835-line `audio_library.gd`.
   - Simplified [sound_manager.gd](file:///home/ironowl/dev/FeriaDeCiencias/juego/scripts/sound_manager.gd) (206 lines) to preload `.wav` assets, pool SFX playback, and expose 128 BPM beat/section helpers (`get_music_section`, `get_beat_phase`, `get_beat_intensity`, `is_music_playing`).
   - Removed redundant per-scene `SfxPlayer` and `MusicPlayer` nodes.

2. **Scene-First UI & Visual Setup**
   - Moved node hierarchies, `StyleBoxFlat` themes, `GPUParticles2D` materials, `PointLight2D` gradient textures, and static polygons out of GDScript and into `.tscn` scenes:
     - [main_menu.tscn](file:///home/ironowl/dev/FeriaDeCiencias/juego/scenes/main_menu.tscn) + [main_menu.gd](file:///home/ironowl/dev/FeriaDeCiencias/juego/scripts/main_menu.gd) (654 → 224 lines)
     - [credits.tscn](file:///home/ironowl/dev/FeriaDeCiencias/juego/scenes/credits.tscn) + [credits.gd](file:///home/ironowl/dev/FeriaDeCiencias/juego/scripts/credits.gd) (233 → 59 lines)
     - [player.tscn](file:///home/ironowl/dev/FeriaDeCiencias/juego/scenes/player.tscn) + [player.gd](file:///home/ironowl/dev/FeriaDeCiencias/juego/scripts/player.gd) (605 → 294 lines)
     - [ui_style.gd](file:///home/ironowl/dev/FeriaDeCiencias/juego/scripts/ui_style.gd) (263 → 22 lines, focused purely on button hover/press scale tweens)

3. **Decomposed `Level` into Focused Responsibilities**
   - Split the 1,553-line [level.gd](file:///home/ironowl/dev/FeriaDeCiencias/juego/scripts/level.gd) into:
     - [level.gd](file:///home/ironowl/dev/FeriaDeCiencias/juego/scripts/level.gd) (705 lines): wave scheduling, hazard spawning, difficulty scaling, screen shake, and music reactivity.
     - [hud.gd](file:///home/ironowl/dev/FeriaDeCiencias/juego/scripts/hud.gd) (142 lines): attached to `$HUD` in [level.tscn](file:///home/ironowl/dev/FeriaDeCiencias/juego/scenes/level.tscn) for HP hearts, timer bar, shield bar, hand status pill, and Game Over / Level Complete panels.
     - [hand_shadow.gd](file:///home/ironowl/dev/FeriaDeCiencias/juego/scripts/hand_shadow.gd) (125 lines): attached to `$HandShadow` in [level.tscn](file:///home/ironowl/dev/FeriaDeCiencias/juego/scenes/level.tscn) for the 21-landmark constellation overlay.

4. **Dedicated Hazard Scenes & Shared [`Shapes`](file:///home/ironowl/dev/FeriaDeCiencias/juego/scripts/shapes.gd) Helper**
   - Created [shapes.gd](file:///home/ironowl/dev/FeriaDeCiencias/juego/scripts/shapes.gd) (`class_name Shapes`) for shared polygon/polyline geometry builders (`regular_polygon`, `ring_points`, `star`, `saw_blade`, `disc_points`, `pie_points`, `inset_box_points`, `circle_texture`).
   - Split the multi-hazard `light_beam` into 4 single-purpose scenes and scripts:
     - [light_beam.tscn](file:///home/ironowl/dev/FeriaDeCiencias/juego/scenes/light_beam.tscn) + [light_beam.gd](file:///home/ironowl/dev/FeriaDeCiencias/juego/scripts/light_beam.gd) (151 lines)
     - [filling_circle.tscn](file:///home/ironowl/dev/FeriaDeCiencias/juego/scenes/filling_circle.tscn) + [filling_circle.gd](file:///home/ironowl/dev/FeriaDeCiencias/juego/scripts/filling_circle.gd) (156 lines)
     - [projectile.tscn](file:///home/ironowl/dev/FeriaDeCiencias/juego/scenes/projectile.tscn) + [projectile.gd](file:///home/ironowl/dev/FeriaDeCiencias/juego/scripts/projectile.gd) (89 lines)
     - [exploder.tscn](file:///home/ironowl/dev/FeriaDeCiencias/juego/scenes/exploder.tscn) + [exploder.gd](file:///home/ironowl/dev/FeriaDeCiencias/juego/scripts/exploder.gd) (100 lines)
   - Simplified autonomous threats:
     - [saw.tscn](file:///home/ironowl/dev/FeriaDeCiencias/juego/scenes/saw.tscn) + [saw.gd](file:///home/ironowl/dev/FeriaDeCiencias/juego/scripts/saw.gd) (479 → 269 lines)
     - [closing_wall.tscn](file:///home/ironowl/dev/FeriaDeCiencias/juego/scenes/closing_wall.tscn) + [closing_wall.gd](file:///home/ironowl/dev/FeriaDeCiencias/juego/scripts/closing_wall.gd) (510 → 346 lines)
     - [enemy.tscn](file:///home/ironowl/dev/FeriaDeCiencias/juego/scenes/enemy.tscn) + [enemy.gd](file:///home/ironowl/dev/FeriaDeCiencias/juego/scripts/enemy.gd) (789 → 583 lines)

5. **Stripped Boilerplate & Updated Tests**
   - Removed `@tool`, manual `_resolve_nodes()` fallbacks, `Engine.is_editor_hint()` guards, and dynamic `has_method()` reflection across all scripts in favor of `@onready` references and direct calls.
   - Updated [test_gameplay.gd](file:///home/ironowl/dev/FeriaDeCiencias/juego/tests/test_gameplay.gd), [cli_test_runner.gd](file:///home/ironowl/dev/FeriaDeCiencias/juego/tests/cli_test_runner.gd), [test_persistence_loop.gd](file:///home/ironowl/dev/FeriaDeCiencias/juego/tests/test_persistence_loop.gd), and [test_records_menu_panel.gd](file:///home/ironowl/dev/FeriaDeCiencias/juego/tests/test_records_menu_panel.gd) to run inside the SceneTree; all 3 suites pass with 0 failures.
