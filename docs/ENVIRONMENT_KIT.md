# Environment kit (Milestone 002, Step 7)

Modular, original low-poly pieces for the Outpost 17 dressing. Nothing here has collision: the arena colliders stay in `Main.tscn` / `WorldFlow`.

## Files
| Path | What |
|---|---|
| `tools/blender/env_lib.py` | Blender helper (boxes, beams, frustums, blobs, extrusions, vertex-colour painting, GLB export) |
| `tools/blender/props_env_kit.py` | Defines every piece and writes the GLBs and the manifest |
| `assets/environments/kit/*.glb` | 28 pieces (about 0.5 MB total) |
| `assets/environments/kit_manifest.json` | name, triangles, size, bounds, bytes per piece |
| `scripts/world/outpost_kit.gd` | `OutpostKit`: lazy loader, `instance()`, `multimesh()`, `Batch` (merge into one draw call) |
| `scripts/world/arena_decor.gd` | places the pieces (`_kit_jungle/_kit_beach/_kit_courtyard/_kit_outpost`), falls back to the old primitive builders |
| `tools/env_kit_sheet.gd` | windowed contact sheet of the kit (`godot --path . -s tools/env_kit_sheet.gd -- <dir>`) |
| `tests/env_kit_check.gd` | 42 headless checks |

Regenerate: `blender --background --python tools/blender/props_env_kit.py -- <project_root> [piece ...]` then `godot --headless --path . --import`.

## Conventions
- 1 unit = 1 m, origin at the base centre, +Y up, **front faces -Z** (rotate by PI to face +Z, toward the arena from the north outpost).
- One mesh, **one vertex-colour material** per piece (`COLOR_0`). The palette is fed in unconverted, the same convention as the older decor, so colours read bright and warm. Wear is baked as per-face brightness variation and ground darkening.
- Budget: at most 2500 triangles and 150 KB per piece, kit under 3 MB. All pieces are far below that.
- Blender note: the colour layer must be a **float colour attribute marked active** and exported with `export_vertex_color="ACTIVE"`, or the glTF exporter writes a white default into `COLOR_0`.

## Pieces
| Piece | Tris | Size (x, y up, z) m | Used for |
|---|---:|---|---|
| container_red / blue / green | 528 | 4.0 x 2.0 x 1.95 | Two side by side over each 4 x 2 x 4 m obstacle collider; stacks in the compound |
| watchtower | 538 | 4.8 x 9.6 x 4.8 | North compound |
| barracks | 316 | 14.9 x 6.2 x 4.4 | North compound |
| warehouse | 308 | 12.6 x 5.4 x 8.6 | North compound |
| hut_small / hut_olive | 112 | 5.7 x 4.0 x 4.6 | North compound huts |
| fence_section | 276 | 6.0 x 2.8 x 0.5 | Compound enclosure |
| fence_wire | 252 | 4.7 x 2.2 x 0.4 | Chain-link front fence |
| sandbag_stack / sandbag_corner | 216 / 180 | 2.3 x 0.6 x 0.8 / 2.4 x 0.6 x 2.1 | Courtyard north wall, compound |
| barricade_concrete / barricade_wire | 64 / 140 | 3.0 x 0.9 x 0.7 / 4.0 x 1.2 x 1.2 | Compound |
| palm_a / palm_b | 172 / 182 | 6.8 x 5.8 x 6.1 / 6.7 x 6.7 x 6.8 | Jungle and beach |
| bush | 320 | 1.9 x 1.0 x 1.6 | Beach flanks and jungle |
| rocks_a / b / c | 240 | 2.5 x 1.6 x 1.6 and similar | Cliff skyline on the east/west walls, scattered |
| crate / barrel | 108 / 132 | 1 m cube / 0.8 x 1.0 | Beach, compound |
| radio_mast | 156 | 10 x 13 x 10 | North compound |
| truck_wreck / boat_wreck | 196 / 190 | 4.7 x 2.4 x 2.1 / 7.8 x 4.5 x 2.6 | Compound / beach wreck |
| sign_outpost_17 | 124 | 3.6 x 4.4 x 0.3 | North fence |
| tent / generator | 80 / 108 | 4.2 x 1.5 x 3.6 / 1.2 x 1.5 x 0.8 | Compound |

## How the decor uses it
- Placements are merged into **four chunks** (`Kit_courtyard`, `Kit_beach`, `Kit_outpost`, `Kit_jungle`): four draw calls in total. The courtyard chunk casts shadows; the others do not. Chunks have `visibility_range_end` (0 / 170 / 190 / 210 m).
- Containers: the plain `Box1`/`Box2` meshes are hidden; two containers sit side by side (offset +-1.0 m on Z) so the visual footprint equals the 4 x 4 collider.
- Quality levels: Low skips bushes, the compound enclosure, containers, tents, barricades, sandbags and clutter and uses 8 palms; Medium uses 14 palms and 10 bushes; High uses 20 palms and 18 bushes.
- Layout is seeded (`SEED`), so a rebuild reproduces the same positions.
- If a GLB is missing, or `ArenaDecor.allow_kit = false`, the previous code-built primitive decor is used unchanged.

## Not changed
Arena size and boundaries, collider sizes and positions (`Box1` 8,1,-6; `Box2` -8,0.5,-4; walls), `WaveManager.OBSTACLES` and the +-26 spawn bounds, the gate, interactable placements, the sand, sea, sky, fog and clouds.
