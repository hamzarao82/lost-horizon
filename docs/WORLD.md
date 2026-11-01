# World dressing (Dead Coast + Outpost 17)

`scripts/world/arena_decor.gd` (node `Decor` in `scenes/main/Main.tscn`) builds all scenery at load from code. No external assets, no decor collision.

## Layout
| Side | What the player sees |
|---|---|
| North (z < -30) | Corrugated metal fence (WallN), barbed fence at z = -36, "OUTPOST 17" sign, four huts, watchtower (-28,-40), radio mast + dish (16,-40), burned-out truck, sandbags, barrels, crates |
| South (z > 30) | Rope fence replaces the invisible WallS, sloping beach, shipwreck at (-12,38) with torn sail and planks, crates, barrels, sea beyond z ~ 42 |
| East / West | WallE/WallW textured as rock (triplanar) with a jagged rock skyline, palms and boulders behind |
| Arena | Sand terrain with a generated noise texture; Box1 red and Box2 blue cargo containers (corrugated shader, same colliders) |

Sky: warm ProceduralSkyMaterial, light fog, filmic tonemap, late-afternoon directional light (warm, soft shadows, 40 m shadow range). Nine billboard clouds drift slowly (Medium/High only).

## Gameplay-relevant facts
- Colliders are unchanged: Floor (top at y = 0), Box1 (8,1,-6), Box2 (-8,0.5,-4), four walls at +-30. **WaveManager's OBSTACLES list is still correct.**
- Decor has no collision, so every prop lies outside the walls or hugs them, except the rope fence posts on the south edge (visual only; the invisible WallS collider still stops the player).
- Hidden on purpose: `Floor/MeshInstance3D` (replaced by the Terrain mesh) and `WallS/MeshInstance3D`.
- Camera SpringArm still collides with the (invisible) south wall.

## Cost
Merged meshes: `Terrain` (1 draw), `Props` (1: palms, rocks, fences, wreck, outpost, truck), `Sea` (1), `Clouds` (1 MultiMesh), plus the existing container/wall meshes. No decor casts shadows. About 6 k triangles for the whole scene. Textures: three 128x128 generated noise textures.

## Quality (Settings autoload)
`ArenaDecor.set_quality(level)` (0 Low, 1 Medium, 2 High) is called when `Settings.changed` fires and rebuilds the decor: Low = 8 palms, no clouds, still water; Medium = 14 palms; High = 20 palms.

## Editing
Positions are constants/loops in `_add_*` functions; the layout uses a fixed RNG seed so it is stable between runs.
