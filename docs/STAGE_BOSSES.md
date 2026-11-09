# Stage bosses and gates

Status date: 2026-11-09. A tester played Dead Coast and reported three gaps: the stage felt incomplete, there was no gate to the next level, and there was no boss (at least two per stage were asked for). This document records what was built. Everything marked verified was run as a test; nothing here was fought or seen by a person.

## The two bosses of each stage
| Stage | Boss 1 (middle) | Boss 2 (end, before the exit) | Flags |
|---|---|---|---|
| Dead Coast | **Harbor Commander**, at the checkpoint (340 health, 40 armor) | **Cove Boss**, in the smugglers' cove (430, 60) | `dead_coast_boss_1_defeated`, `dead_coast_boss_2_defeated` |
| Blackwood | **Patrol Chief**, at the abandoned camp (350, 30) | **Site Overseer**, at the testing site (450, 70) | `blackwood_boss_1_defeated`, `blackwood_boss_2_defeated` |
| Research Complex | **Subject Zero** (already existed; flag `research_complex_elite_down`) | **Facility Commander**, in the laboratory (380, 80, ranged), now a real boss | `research_complex_boss_2_defeated` |
| Iron Fortress | the Fortress Captain | the Director | unchanged (Milestone 9) |

Outpost 17 keeps the Warden. All names and captions are original and use no names from the existing documents.

### How a boss fights
The Dead Coast and Blackwood bosses are one class, `StageBossEnemy`, built on the Research Complex mini-boss: a leaping claw, a shockwave ring and a charging rush. Each attack is telegraphed, hits once per use and leaves a punish window; the numbers are the ones in `resources/attacks/experimental_*.tres` and are asserted by `tests/stage_bosses_check.gd` (claw and ring: telegraph at least 0.6 s, punish window at least 0.5 s; charge: telegraph at least 0.8 s). What differs per boss is the **attack mix**, which is data (`extras` on the config, weights 0 to switch an attack off):

| Boss | claw | ring | charge | Feel |
|---|---:|---:|---:|---|
| Harbor Commander | 3 | 0 | 2 | leaps and charges: hit and dash |
| Cove Boss | 1 | 3 | 0 | holds the ground with rings, big and slow to get around |
| Patrol Chief | 2 | 0 | 3 | a hunter: charges first |
| Site Overseer | 2 | 3 | 1 | area control with rings, heaviest armor |

The Facility Commander keeps the ranged brain tested in Milestone 8 (three-shot burst, aim line telegraph, cover points) with more health and armor.

### Rewards and persistence
The health bar appears when the player comes within 22 m of a boss (the boss joins the group "boss" then), not from the moment it spawns.

Each boss carries one unique reward (`resources/items/dc_harbor_cap`, `dc_cove_gloves`, `bw_chief_boots`, `bw_overseer_badge`, `rc_commander_visor`; head, gloves, legs, accessory and head slots, small stats, icon generated). `StageBoss` (`scripts/regions/stage_boss.gd`) spawns the boss once per save, adds it to the group `boss` for the HUD health bar, sets the saved flag and a `PersistentIds` claim on defeat, says the intro caption when the player comes within 22 m and the defeat caption, and drops the reward unless the save already owns it. After a reload with the boss down, nothing respawns, and a reward that was never picked up is put back at the spawn point (it waits for the player to exist first, and never puts back an owned or already-lying reward). Verified with a real save and load in `stage_bosses_check`.

## The gates
`RegionGate` (`scripts/regions/region_gate.gd`) stands just beyond the forward exit trigger of Dead Coast (to Blackwood) and Blackwood (to the Research Complex). While the next region is locked it is a barricade with a "ROAD CLOSED" sign (walking up still triggers the exit's refusal); when `<next>_unlocked` is set the barricade is removed and a lit door "ROAD TO <NEXT STAGE>" appears. It keeps no state of its own, so a reload cannot desync it. The Research Complex keeps its existing underground exit and hatch (not duplicated). Verified in `tests/region_gates_check.gd`: closed until the unlock, refused at the trigger, opens when mission 3 completes, travel works, the arrow aims at it, a reload keeps it open.

## The sequence
Each stage's missions (strict step order, `STAGE_SEQUENCE.md`) now contain the boss steps: boss 1 in the middle mission (Dead Coast: after "Defeat the checkpoint's defenders"; Blackwood: after finding the camp), boss 2 in the last mission before its final steps (Dead Coast: before the Black Site link; Blackwood: before unlocking the way; the Research Complex: after the laboratory security). The unlock rule did not change: mission 3 (or 4 for the Research Complex) completing unlocks the next region. Because the bosses are required steps of those missions, **both bosses are down whenever the next region unlocks**; no separate check was added.

**The arrival step is a short road quest, not a step of mission 3.** Finishing mission 3 is what unlocks the next region, and arriving needs the unlock, so an arrival step inside mission 3 would deadlock. Instead each stage has a one-step quest that mission 3 hands over to: `dc_road_to_blackwood` (flag `blackwood_arrived`), `bw_road_to_research_complex` (`research_complex_arrived`), `rc_road_to_iron_fortress` (`iron_fortress_arrived`). `CampaignFlow` now sets `<region>_arrived` on every first arrival (it only did so for Dead Coast).

## The arrow
`ObjectivePointer` gained three rules, all in the flag branch: a boss flag points at the nearest living boss, or at the spot where the boss will stand (group `stage_boss_spawns`); an `_arrived` flag points at the nearest exit that leads to that region; (the wave rule from before is unchanged). `tests/pointer_regions_check.gd` now requires every boss step to say "Boss" and every arrival step to say "Road to …", in every region.

## Not done or not verified
- Nobody has fought these bosses, so health, damage and pacing are numbers on paper. The mixes are a first guess.
- There are no new animations or models: the bosses are the soldier model tinted and scaled, attacks are shown by the shared red windup tint and ground markers.
- The Dead Coast and Blackwood bosses melee only; only the Research Complex commander shoots.
- The closed gate ("ROAD CLOSED" barricade) and the open gate (a lit door, "ROAD TO BLACKWOOD") were seen in a screenshot of Dead Coast; the Blackwood gate and a boss telegraph were not (the boss shot had the camera pressed against a dune behind the player and shows only the health bar, "Harbor Commander"). The area behind Dead Coast boss 1 is cramped for the camera.
- No sound is specific to these bosses.
- Boss positions come from area rectangles and are verified by a physics clearance check (solid ground under the spawn, nothing solid within 2.4 m); the Patrol Chief was moved from (-40, -108) to (-44, -110) because a camp prop stood 3 m from the first spot. Nobody walked them.
- Existing tests that complete missions by firing events were updated to fire the boss flags (listed in the commit).
