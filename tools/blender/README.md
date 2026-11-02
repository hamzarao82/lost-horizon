# tools/blender

Scripts that generate the game's art from code (Blender 4.5 LTS, run headless). Nothing here needs external assets.

## Characters (CHAR-ART)
| File | Purpose |
|---|---|
| `char_lib.py` | Part builders (bevelled boxes, tapered limbs, spheres), 17-bone rig, vertex-colour painting, FK animation authoring, glTF export, preview renders, weapon-socket maths |
| `char_designs.py` | Geometry for `player`, `soldier`, `heavy`, `elite`, `warden` (`DESIGNS` table: builder, height, bulk) |
| `anim_clips.py` | The 22 animation clips (names and lengths are the engine contract) |
| `make_common.py`, `make_<name>.py`, `make_all.py` | Build one or all characters -> `assets/characters/<name>.glb` + `sockets.json` |
| `verify_glb.gd` | Godot headless contract check (bones, clips, facing -Z, one material, tris, height) |
| `probe.py` | Dev tool: blade direction at key frames for several blade angles (this is how the -30 degree grip was chosen) |

```
blender --background --python tools/blender/make_all.py                 # regenerate all five GLBs
blender --background --python tools/blender/make_player.py -- --render <dir>   # plus a 4-pane preview sheet
Godot_v4.7.2-stable_win64_console.exe --headless --path . -s tools/blender/verify_glb.gd
```
Blender path used here: `C:\Program Files\Blender Foundation\Blender 4.5\blender.exe`.

Modelling convention: +Z up, character faces +Y (the glTF exporter turns that into Godot's -Z), right side is +X. Details and the engine contract are in `docs/CHARACTER_ART.md`.

Other scripts in this folder (`props_*.py`, `weapons_*.py`, `env_lib.py`, `verify_weapons.gd`) belong to the weapon and environment art agents.

Note: Blender writes `tools/blender/__pycache__/` when it runs; it is generated and should be git-ignored.
