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
