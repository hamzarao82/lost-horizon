# Animation and character visuals

Characters are drawn by a **visual adapter** that reads the body and never calls gameplay code. Two looks exist
and the game picks one at load time:

| Look | Class | When |
|---|---|---|
| **Skinned model** (imported `.glb`, skeleton + clips) | `SkinnedVisual` | the model file exists and passes validation |
| **Procedural rig** (code-built boxes, `humanoid_rig.gd`) | `ProceduralVisual` wraps `HumanoidRig` | fallback: file missing, broken, or `SkinnedVisual.disabled = true` |

## Scene layout (node names are part of the contract: tests and gameplay scripts use them)
```
Body (CharacterBody3D: Player / Enemy / Warden)
└─ VisualRoot (Node3D: gameplay scales it, faces it, tips it over on enemy death)
   ├─ MeshInstance3D       torso box; hidden when a model loads, KEPT as the material source for hit flashes
   ├─ HumanoidRig          procedural fallback (hidden when a model loads: HumanoidRig.set_active(false))
   ├─ SkinnedVisual        adapter (scenes/characters/SkinnedVisual.tscn)  ── picks the model automatically
   │   ├─ ProceduralFallback   ProceduralVisual
   │   └─ Model               the instantiated GLB: Skeleton3D + MeshInstance3D + AnimationPlayer + AnimationTree
   │        └─ Skeleton3D ── HandSocket (Hand_R)  ── Holder ── weapon
   │                       └─ ChestSocket (Chest) ── Holder ── armor plate (player only)
   └─ WeaponPivot / Weapon / Hitbox   untouched: the hitbox is driven by combat code, not by the model
```
Model choice (`SkinnedVisual.model_path` overrides): Player -> `player.glb`; Enemy by `display_name`:
Soldier -> `soldier.glb`, Heavy -> `heavy.glb`, Hunter -> `elite.glb`; Warden -> `warden.glb` (all in `res://assets/characters/`).
Heavy/Hunter/Warden inherit `PatrolSoldier.tscn`, so one node serves all five.

## Art contract (what a model file must contain)
- One `Skeleton3D` with the bones: Hips, Spine, Chest, Neck, Head, UpperArm_L/R, LowerArm_L/R, Hand_L/R, UpperLeg_L/R,
  LowerLeg_L/R, Foot_L/R. One `AnimationPlayer`. At least one `MeshInstance3D`.
- Feet at y = 0, authored height about 1.8 m (the adapter measures it), **faces -Z** (export `yaw_offset_deg = 180` if not).
- Vertex colours on one material. The adapter switches `vertex_color_use_as_albedo` on in code, so import settings do not matter.
- Clips at 30 fps, in place. Names (case and an `Armature|` prefix are ignored): idle, walk, run, sprint, jump_start, fall,
  land, light_1, light_2, light_3, heavy, sprint_attack, air_attack, spin, dodge, hit, death, guard, plus the boss
  clips slam, flurry, shockwave_cast, roar. **Attack clips have the strike at 35% of their length.**
  Looping: idle, walk, run, sprint, fall, guard (the driver forces loop modes; the exporter's flags do not matter).
- Missing clips fall back (`AnimationDriver.FALLBACKS`): sprint -> run -> walk -> idle, guard -> idle, light_2/3 -> light_1,
  boss moves -> heavy -> light_1, death -> hit -> idle. A model with no usable skeleton, clips or mesh is rejected with a
  warning and the procedural rig stays.
- Weapons: `res://assets/weapons/<item_id>.glb` (grip at the origin, blade along -Z, flat faces up/down). Armor plate:
  `res://assets/armor/warden_plate.glb` (origin at the chest). Missing files fall back to the code-built `WeaponModel` / nothing.

## How a frame is drawn (`SkinnedVisual.update`)
The adapter polls: `body.state`, `velocity`, `is_on_floor()`, and for attacks the private `_attack_idx`, `_attack_frames`,
`_chain` (Player) or `_swing`, `_attack_frames` (Enemy). The same contract `HumanoidRig` has always used.

| Body state | What plays | Driven how |
|---|---|---|
| FREE / IDLE / CHASE on the floor | idle / walk / run / sprint | **AnimationTree**, BlendSpace1D by horizontal speed (0, 2, 5, 8.5 m/s) |
| waiting enemy (CHASE, standing) | guard | tree state |
| airborne | jump_start (first 0.2 s while rising), fall; land for 0.18 s after touching down | tree states |
| HIT / STAGGER | hit | tree state |
| DEAD | death | tree state (holds the last pose) |
| ATTACK | the clip of the attack (by `AttackData.id`) | **scrubbed**: position = f(`_attack_frames`) |
| DODGE | dodge | scrubbed to `_dodge_time / dodge_duration` |
| Warden roar | roar | scrubbed to the roar timer |

**Attacks are scrubbed, never played.** Each frame the AnimationPlayer is seeked to a position computed from the combat
system's own frame counter, so the swing is locked to startup/active/recovery, hit-stop, time scale and attack speed,
and a clip can never loop or restart an attack. The mapping is strike-aligned
(`AnimationDriver.attack_clip_position`): the first active frame always lands on 35% of the clip, wherever the
startup/recovery split falls. Attack id -> clip: light_1/2/3, heavy_1 -> heavy, sprint_attack, air_attack, spin_special -> spin;
enemy_swing -> light_1, heavy_swing -> heavy, hunter_slash -> light_2, warden_slam -> slam, warden_flurry -> flurry,
warden_shockwave -> shockwave_cast.

Other behaviours:
- **Hit flash:** gameplay tints the torso node's material (white hit, red windup, blue dodge, dark death). The adapter mirrors
  any deviation from the body colour onto the model through `material_overlay` (alpha 0.55). A permanent body-colour change
  (the Warden's enrage) shows as a faint steady tint (alpha 0.2).
- **Size:** with `fit_to_gameplay_height` (default on) the model is scaled to `1.8 m x body_scale`, the figure the colliders
  and hitboxes are built around, so the Warden stays 3 m tall and his visible reach matches his hitbox. The dodge squash and the
  enemy tip-over that gameplay applies to `VisualRoot` are cancelled on the model (it has real dodge and death clips).
- **Weapon:** the held weapon lives on `Hand_R`'s `WeaponSocket` (adjustable `weapon_position`, `weapon_rotation_deg`;
  defaults 0.05 m along the hand and +90 degrees about X, measured from this skeleton's hand axes). The player's follows
  `Inventory.changed`; enemies hold a cosmetic weapon (machete, claymore, katana, Warden's Cleaver). The code-built swing weapon
  on `WeaponPivot` is hidden; the pivot and the hitbox are untouched. Armor plate: shown on `Chest` when `warden_plate` is equipped.
- **Switches:** `SkinnedVisual.disabled = true` keeps the procedural rig everywhere (A/B runs, very low-end devices);
  `align_strike`, `yaw_offset_deg`, `weapon_*`, `plate_position`, `fit_to_gameplay_height` are exports.

## What the adapter never does
Calls attack/damage/heal/equip/teleport methods, changes `AttackData`, adds physics bodies or areas, renames nodes, or opens a hitbox.
Combat stays authoritative.

## Replacing a model later (Mixamo or Blender)
Export a GLB that follows the contract above (rename bones with a Godot BoneMap or in Blender), drop it over
`assets/characters/<name>.glb`, and nothing else needs to change. Check it with `tests/anim_sync_check.gd` (it validates every
file in `assets/characters/` for bones, clips and a mesh).

## Tests
`tests/anim_sync_check.gd` (117 checks): clip mapping and strike alignment, fallbacks, missing/broken model safety, player and
enemy binding, scrub position equals the formula at several frames of light_1/heavy/enemy swings, no retrigger or combat-field
change, flash overlay, rig switch, node names, no extra physics bodies, weapon/plate sockets and swapping, real-asset validation,
unchanged damage and frame numbers. Fixture model: `tests/fixtures/make_fixture.py` (Blender script).

## Procedural fallback (HumanoidRig)
Unchanged: nine box parts (pelvis, legs, head, visor, arms, forearms) posed procedurally from the same polled state; the torso is the
existing `MeshInstance3D`; every part shares its material so hit flashes still work; `set_active(bool)` shows/hides it.
