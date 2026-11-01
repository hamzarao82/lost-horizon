# Animation

Characters are low-poly humanoids built in code by `scripts/visual/humanoid_rig.gd` (`HumanoidRig`) and animated procedurally. No external assets, no AnimationPlayer.

## How the rig works
- Scene layout: `Body (CharacterBody3D) / VisualRoot / HumanoidRig`. VisualRoot also holds the torso `MeshInstance3D` (a box), the `WeaponPivot` and the hitbox, all untouched by the rig.
- The rig builds 9 box parts (pelvis, 2 legs, head, visor, 2 arms, 2 forearms) as `Node3D` pivots (Hips > Spine > Head/Arms, Hips > Legs). The torso is the existing `MeshInstance3D` and is re-posed onto the Spine pivot every frame, so the rest of the game still treats it as the "body mesh".
- Material: every body part shares the torso's material (`material_override` or surface override). The enemy hit-flash tints that one material, so the whole body flashes. The visor has its own emissive accent material (`accent_color`, or darkened body colour with `derive_accent`).
- Meshes are cached per size and shared between all rigs. Shadows are cast by the torso and legs only.
- Update: `_process` computes a target value per joint (`J` enum) from the body's state, then eases each joint toward it (`1 - exp(-rate * delta)`). It skips work when not visible in the tree.

## Polling contract (what the rig reads)
| Source | Used for |
|---|---|
| `body.velocity` (xz length) | walk/run cycle speed and amplitude, lean |
| `body.is_on_floor()` | air pose |
| `Player.state` / `Enemy.state` | attack, dodge, hit, dead modes |
| `_attack_frames` + `AttackData` (`Player._chain[_attack_idx]` or `Enemy._swing`) | wind-up / strike / recovery pose timing |
| `WeaponPivot.rotation.y` | spine twist during a swing |

If `_attack_frames` or the attack data are missing, the rig falls back to a default 8/4/10 frame swing.

## Animations
Idle breathing, walk and run cycle (arm/leg swing, bob, forward lean at sprint), enemy guard stance while chasing, jump rise and fall poses, dodge tuck, light attack (cock back, strike, recover), overhead slam for attacks with 16+ startup frames, hit flinch, death (player falls backwards, enemies go limp while enemy.gd tips VisualRoot).

## Replacing the rig with a Mixamo / Blender model later
1. Import the skinned `.glb`, put it under `VisualRoot` instead of `HumanoidRig`, keep the `MeshInstance3D`/`WeaponPivot` nodes (or update `enemy.gd`/`player.gd` references).
2. Add an `AnimationTree` with locomotion blend (idle/walk/run by speed), and one-shots for attack, dodge, hit and death.
3. Drive it from the same polling contract above (a small script on the model that reads `velocity`, `is_on_floor()` and `state`), and trigger hit windows from the existing frame-based `AttackData`, not from the clips.
4. Trim attack clips so startup/active/recovery match `AttackData` frames.
5. Keep the budget: about 8k triangles per character, 512 px textures, one material.
