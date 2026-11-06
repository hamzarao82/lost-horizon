# Visual pipeline (Milestone 005 materials pass)

## Assessment (what the screenshots showed before)
1. Terrain was a vertex-colour mesh with a generated 128 px noise texture: flat orange, no detail, no normals.
2. Buildings and props were merged vertex-colour boxes with no textures at all, so surfaces read as flat colour.
3. The kit models (containers, sandbags, barrels) used one shared vertex-colour material, no roughness or normal response.
4. Lighting was a low warm sun (orange fog, orange horizon) that tinted everything the same colour, with no contrast.
5. The primary limits are materials and lighting. Geometry is also simple (boxes), which a texture pass cannot fix.
6. Renderer: Compatibility (kept). No SSAO/SSR/SDFGI. Glow and colour adjustment exist but cost frames on an integrated GPU.

## What changed
- `assets/shaders/ground_pbr.gdshader`: two CC0 ground sets (dirt, gravel) blended by a low-frequency world-space mask (no visible repeat), vertex colour kept as tint, normal map on desktop, albedo only on web/mobile.
- `scripts/world/pbr_materials.gd`: shared materials: ground, triplanar concrete (walls, floors, merged props), triplanar metal (merged kit). `lite()` (web or mobile) drops the normal map.
- `scenes/main/Main.tscn`: cooler hazy sky and fog, lower ambient, ACES tonemap with exposure 0.85, sun colour and energy 1.1 at -24 degrees. Glow and colour adjustment were tried and left OFF (cost, see below).
- `export_presets.cfg`: the Web preset excludes the normal-map files (never loaded on web).

## Measured (Intel UHD 620, 1280x720, tests/benchmark.gd, windowed)
See the table at the end of this file (filled with this session's runs).

## Known gaps
Buildings are still low-poly boxes with only surface grain added. The beach lost much of its sand look. No new vegetation or models came from this pass. Normal maps on walls are subtle. Roughness maps and anisotropic filtering were removed for cost. Nothing was measured on Android or on a real web browser frame rate.

## Measurements (2026-11-06, Intel UHD 620, 1280x720, tests/benchmark.gd, runs interleaved in one session)
| Tree | Avg FPS | 1% low | Max frame | Draw calls |
|---|---:|---:|---:|---:|
| master (unchanged) | 88.1 / 80.8 | 46.7 / 30.4 | 59 / 94 ms | 142 |
| materials pass | 59.1 / 57.4 | 23.2 / 20.5 | 109 / 105 ms | 140 |

The pass costs about 30% of the frame rate on this integrated GPU and worsens frame spikes. Tried and removed for cost: glow, colour adjustment (about 5 FPS), roughness maps and anisotropic filtering (about 20 FPS together). Web export: wasm 39.5 MB (unchanged), pck 7.1 MB (was 1.6 MB; the normal maps are excluded from the web preset). Textures on disk: 11 MB. 30 test suites pass with zero script errors.

## Worn gear models
`blender --background --python tools/blender/make_gear.py` builds `assets/armor/combat_helmet.glb`, `tactical_gloves.glb` and `field_boots.glb` with the same helpers as `weapons_armor.py` (origin at the bone head of the 1.8 m player rig, vertex colours, one material). Gloves and boots are symmetric, so one model serves both sides. Scale and attachment were checked in screenshots from a free camera.
