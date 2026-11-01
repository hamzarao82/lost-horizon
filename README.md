# Lost Horizon: Black Site

Single-player third-person action-adventure. Godot 4.7.2 (typed GDScript, Compatibility renderer). Targets: Windows, Web, Android.

## Run
1. Godot 4.7.2 (Standard, not .NET): `C:\Tools\Godot\4.7.2\`. Import `project.godot`, press F5.
2. Controls: WASD move, mouse look, Shift sprint, Space jump, Ctrl or C dodge, LMB light, RMB heavy, F3 stats, Esc frees the mouse.
3. Touch: left side stick (full push sprints), right side drag to look, Jump / Atk / Heavy / Dodge buttons.

## Tests
`Godot_v4.7.2-stable_win64_console.exe --headless --path . -s tests/run_tests.gd`

## Export
Web: `--headless --export-release "Web" build/web/index.html` (single-threaded; serve over http). Windows: preset "Windows Desktop". Android preset not set up yet.

## Status
Playable arena: movement, dodge with 0.18 s i-frames, light-light-heavy combo plus heavy, two soldiers with an attack token, HUD, death restart. Placeholder capsules; no animations, loot or world yet.

Planning docs: `Documents/GitHub/lost-horizon-black-site-docs`.
