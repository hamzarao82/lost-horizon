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

## Milestone 1 world flow

```
Beach spawn (0,0.1,64)
  -> radio hut (-7,58): "Use radio" sets radio_heard and plays the hint
  -> three breakers (puzzle "restore electrical power"):
       switch_1 behind the wreck (-17.5, 41.5)
       switch_2 on the east perimeter fence (34.5, 49)
       switch_3 at the foot of the watchtower (-30.5, 57)
     all three thrown => flag power_on
  -> south gate (z=30, 8 m wide) opens; its collider is removed
  -> ArenaTrigger (courtyard just inside the gate) starts WaveManager once
  -> five waves ending with the Warden => all_cleared => flag arena_cleared
  -> Warden's keycard drops at the arena centre => flag has_keycard
  -> command terminal on the north side (0,-27.6) unlocks => flag command_terminal_used
```

Supply crates `crate_1` (11,58) and `crate_2` (-26,46) give a medkit plus a knife / light armor once each.

### Code map
| File | Role |
|---|---|
| `scripts/core/world_state.gd` (autoload `WorldState`) | Boolean flags, `interacted(id)`, `area_entered(id)`, `to_dict/from_dict/reset`. Survives scene reloads, so a death restart keeps the puzzle |
| `scripts/world/world_flow.gd` (`World` node in Main.tscn) | Builds beach colliders, scenery (one merged mesh), interactables, trigger; wires flags; places the player |
| `scripts/world/interactor.gd` | Attached to the Player at runtime; nearest interactable within its radius; one press = one interaction (0.3 s cooldown) |
| `scripts/world/interactables/*.gd` | `Interactable` base, `BreakerSwitch`, `SupplyCrate`, `WorldGate`, `Keycard` |
| `scripts/ui/touch_controls.gd` | Contextual "Use" button at offset (-60,-290), shown only while something is in reach |

### Rules and decisions
- The arena (size, obstacles, spawn clamp +-26) is unchanged. `WallS` is now two 26 m halves (x=-17 and x=17) leaving the 8 m gate gap; the beach adds `BeachFloor`, four boundary walls and two fence stubs, all on layer 1.
- The player starts on the beach only in real play. Headless runs (tests) keep the player at the arena origin, because every suite assumes that; `WorldFlow.start_on_beach` / `place_player()` control it.
- `WaveManager.autostart` is false in Main.tscn. The courtyard trigger calls `start()`; `has_started()` was added for the guard. An arena already won (`arena_cleared`) never restarts.
- Teleport (`teleport.gd`): while the player is on the beach side (z > 31) and `power_on` is not set, destinations are chosen only on the beach, so teleporting cannot skip the gate. Arena behaviour is unchanged.
- Captions: `WorldFlow` shows its own short captions unless the flag `story_captions` is set, in which case the story layer owns them.
- Flags in use: `radio_heard`, `switch_1..3`, `power_on`, `gate_open`, `crate_1_taken`, `crate_2_taken`, `arena_cleared`, `has_keycard`, `command_terminal_used`.
- Controls: interact = E, gamepad X, or the touch "Use" button.

## Warden encounter in Area D (Milestone 3 step 7)
`BossIntro` (child of `Outpost17`) runs the introduction with the **existing** Warden scene: no new boss code, so every pattern, phase and loot rule is the arena one. The Warden also stays wave 5 in the courtyard (Arena Mode untouched).

- **First entry into Area D** (`area_entered(area_d_command)`, boss not yet defeated): a sealing collider closes the doorway behind the player (z = -62.6), a caption plays, the Warden spawns in the middle of the command building (0, 0.1, -75) with physics off, the camera looks at him through `CameraController.set_lock_target` for 3 s, then he is released and `aggro()`ed. The HUD boss bar appears on its own (group `boss`).
- **Flags:** `warden_intro_done` (full introduction played once), `boss_warden_defeated` (ANY Warden died, including wave 5), `warden_d_defeated` (the Area D fight was won).
- **Victory:** the seal is removed and a caption plays; his normal loot drop is unchanged.
- **Already defeated:** entering Area D spawns nothing and shows a caption.
- **Dying in the fight:** the scene reloads (checkpoint respawn if one exists); on returning to Area D the Warden is back with a 1.2 s introduction and the door seals again.
- **Never locked in:** the seal is only a collider created after the player is inside; it is removed on victory, on reload (it is not saved), and by a 0.5 s safety check if the Warden is dead or gone.
- Tests: `tests/boss_intro_check.gd` (20 checks).

## Set dressing (Milestone 3 step 2)
Built by `scripts/world/area_dressing.gd` (called from `Outpost17._ready` before the greybox mesh is finished), so all dressing boxes are merged into the one `OutpostGreybox` mesh: **+4 draw calls** in the benchmark (148 -> 152). Primitive boxes only; the Milestone 2 kit is not on this branch. Every prop is recorded in `AreaDressing.props` (unique, stable names; repeats become `Name_2`, `Name_3`).

**Keep-clear rules** (enforced by `tests/dressing_check.gd`): no solid prop in the research-wing patrol corridor (x -3.5..1.5, z -58..-36), at either door opening (B-C at x 12, C-D at x 0), or in the boss arena zone (x -12..12, z -90..-72). The existing M1 cover crates sit at the corridor edges (x -3.2 and 1.2); the patrol walks x = -1.

| Area | Props (decorative unless marked SOLID) |
|---|---|
| A beach | guard booth (SOLID `BoothA`), raised boom, sign gantry with Label3D 'OUTPOST 17 - NO ENTRY' (SOLID posts `SignPostAL/AR`), three sandbag stacks (SOLID `SandbagsA1-3`), burnt-out jeep (SOLID `JeepWreckA`, cab and wheels decorative), crates (SOLID `CrateA1`), warning sign |
| B courtyard (walls only) | watch post (SOLID `WatchPostBaseB`, deck, posts, roof), barrel stack (SOLID `BarrelStackB`), wrecked radio mast piece |
| C research wing | overturned chairs, tipped box, three scorch marks (flat), shattered monitor wall on the east wall, warning-stripe decals at both doors (flat), three security cameras, **hidden cache `cache_c_hidden`** behind the storage room's back wall (SOLID crate body), tarp |
| D command | map table (SOLID `MapTableD`), wall screens and banner on the side walls, **hidden cache `cache_d_hidden`** in the east back corner (SOLID crate body), crates, tarp |

SOLID colliders added: BoothA, SignPostAL, SignPostAR, SandbagsA1, SandbagsA2, SandbagsA3, JeepWreckA, CrateA1, WatchPostBaseB, BarrelStackB, MapTableD, plus the two cache crate bodies (13 in total).

**Caches:** `cache_c_hidden` (medkit + katana) and `cache_d_hidden` (medkit + heavy combat armor) are normal `SupplyCrate`s: opened once, remembered by the flag `<id>_taken`.

**Reachability test method:** a 1 m grid over each area; a cell is free when a 0.5 m radius sphere at height 0.9 overlaps nothing on the world layer; a 4-connected flood fill starts just inside each area's entrance and a target counts as reachable if a visited cell is within 1.8 m. Cells 1 m apart guarantee a path at least 1.0 m wide. A negative control fences in a cache and checks the test reports it unreachable.

Tests: `tests/dressing_check.gd` (30 checks).
