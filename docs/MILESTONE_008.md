# Milestone 008: The Research Complex

Status date: 2026-11-06. **Nothing in this milestone is implemented yet.** This is the audit-based plan. Legend: **Implemented**, **Partial**, **Documented only**, **Verified** (a test or screenshot was run), **Not tested**.

## 1. Project direction (from the owner)
- Milestone 12 completes the full game's content.
- Milestone 13 is the graphics and asset-quality overhaul.
- Milestone 14 is optimization, QA and release preparation.
- Therefore Milestone 8 is gameplay, layout, missions, encounters and atmosphere. Environments are built from modular scenes so that Milestone 13 can replace the art without rebuilding the region. The result must still be readable and playable, not an empty grey box.

## 2. Dependency that is not met yet
The brief says to use "the existing region and scene-management architecture". **That architecture does not exist.** Milestone 7 (Dead Coast and Blackwood) plans a `RegionManager`, `RegionData` resources and save version 4, and none of it is built. Outpost 17 is still assembled in code inside `Main`.
- Consequence: Milestone 8 either (a) waits for the Milestone 7 phase 1 region framework, or (b) builds that framework itself as its first stage. Recommended: build the framework once, in whichever milestone is started first, and reuse it. The plan below assumes the framework from `MILESTONE_007.md` section 2.
- Also inherited and unresolved: web load about 42 s against 30 s, desktop frame rate below 60 FPS at High on integrated graphics, no human play-through, Android never run on a device.

## 3. What can be reused (from the repository)
| Need | Existing system |
|---|---|
| Missions, objectives, optional objectives, rewards | `QuestManager`, `.tres` quests, event-driven objectives (`first_signal` has 15 objectives plus an optional log) |
| Terminals, doors, documents, switches, caches | `Terminal` (with `requires_flag`), `Door`, `LoreDocument`, `PowerSwitch`/`SequencePuzzle`, `Checkpoint`, crates and caches |
| Patrols and detection | `PatrolGroup`, `PatrolRoute`, `DetectionComponent`, suspicion and search states |
| Enemies | `Enemy` with soldier, heavy and elite configurations; `Warden extends Enemy` with a phase 2 and several attacks |
| Loot, XP, currency | `LootTable` with tiers, `Progression`, `Inventory`, unique-reward claims |
| Save | save v3 (`world`, `progression`, `inventory` sections), checkpoints, atomic writes |
| HUD and tracker | existing HUD objective tracker and pointer, `RpgNotifications` |
| Audio | procedural generator `tools/gen_sfx.gd` and `AudioManager` |

## 4. Gaps for this milestone
- **Ranged enemies:** the Facility Commander needs ranged attacks and positioning. The existing enemies are melee only. This is new combat code (a projectile and a ranged attack state) built on the existing `Enemy`, not a new AI.
- **Experimental Subject and Elite Experimental Subject:** distinct movement and attacks need new `AttackData` and enemy configurations; no suitable animation clips exist (clip reuse and mapping like the Warden's charge and leap).
- **Environmental hazards** (electrified floors, gas vents) do not exist.
- **Containment override puzzle** (multi-terminal) needs a reusable multi-step puzzle component; the three-switch ordered puzzle exists and can be generalized.
- **Audio logs:** no audio-log system exists; story delivery uses documents and terminals, plus the radio caption lines.
- **Region transition into and out of the complex** depends on the region framework.
- **Underground exit** needs a discoverable route (a hidden hatch opened by the final mission) leading to the next region's entry point; the next region does not exist, so it ends at a stub entry with a "to be continued" gate.

## 5. Proposed structure
Modular scenes, each under `scenes/regions/research_complex/`: `Perimeter`, `AdminWing`, `MedicalWing`, `ContainmentSector`, `CentralLab`, `UndergroundExit`, joined by door and stair transitions inside one `ResearchComplex` region scene that loads sub-scenes lazily, so only the current wing and its neighbours are in memory. Reusable scene components: `ResearchTerminal`, `SecurityDoor` (credential level), `AccessPanel`, `PowerSwitch`, `ContainmentControl`, `ResearchDocument`, `FacilityEnemySpawn`, `MissionTrigger`. Credentials are item or flag based (`credential_admin`, `credential_medical`, `credential_lab`) so doors reuse the same check.

## 6. Missions (existing quest architecture)
1. **The Restricted Zone:** find the entrance, defeat or avoid perimeter guards, search the checkpoint, obtain the admin credential, unlock the administration wing. One combat encounter, one optional supply cache.
2. **Silent Records:** find the archive, restore archive power, retrieve classified records, investigate the medical wing, find evidence of experimentation. Terminal, locked-room challenge, optional documents.
3. **Containment Breach:** enter containment, restore emergency access (Puzzle C), investigate chambers, survive an experimental-subject encounter, defeat the Elite Experimental Subject, recover the incident report.
4. **Project Black Site:** reach the central lab, solve the power and security puzzle (Puzzle B), defeat lab security including the Facility Commander, reach the final chamber, retrieve the data, discover the next lead, escape through the underground exit.

Puzzles: A security access (credentials), B laboratory power sequence (a different rule from Outpost 17's order B, A, C, with wrong input only resetting), C containment override (three terminals plus a lockdown release). No puzzle may be saveable into a softlock: each puzzle's state is saved as a flag per step and resets the step, not the whole region, on a wrong input.

## 7. Enemy configurations
| Enemy | Basis | Difference |
|---|---|---|
| Research Security Guard | soldier | facility palette, new loot tier |
| Heavy Facility Guard | heavy | more armor, slower, shield-bash style attack |
| Experimental Subject | new configuration of `Enemy` | fast close-range lunge, short telegraph at least 0.4 s, no patrol, aggro by proximity |
| Elite Experimental Subject | new configuration like `Warden` | unique attack set, telegraph at least 0.6 s, punish window at least 0.5 s, durability above the Warden's phase 1 |
| Facility Commander | soldier plus a ranged attack | keeps distance, fires telegraphed shots, repositions between cover points |

Fairness rules from the Warden design apply to the new elite and the commander and are asserted in tests.

## 8. Rewards and persistence
XP and currency per mission on the existing curves, a unique weapon or armor reward for the Elite Experimental Subject (claimed once via `unique_claimed`), medical supplies in the medical wing, region-tagged loot tables. Persistence in the region state from the framework: collected records, credentials, puzzle step flags, defeated mini-boss, cleared encounters, region id. Every reward needs a saved id and a reload test.

## 9. Work phases
| Phase | Content | Status |
|---|---|---|
| 0 | Region framework (shared with Milestone 7 phase 1), save v4, transition and loading screen | not started |
| 1 | Perimeter and Administration Wing, missions 1 and 2 start, Puzzle A, credentials, guards | not started |
| 2 | Medical Wing, documents, archive terminal, locked-room challenge, mission 2 complete | not started |
| 3 | Containment Sector, experimental subjects, hazards, Puzzle C, elite subject, mission 3 | not started |
| 4 | Central Lab, Facility Commander (ranged), Puzzle B, final chamber, underground exit, mission 4 | not started |
| 5 | Audio (facility hum, alarms, door and terminal sounds), HUD checks, full-flow bot through the region, save/load tests, screenshots, performance measurement | not started |

## 10. Acceptance tracking
All items in the brief's acceptance checklist (world, missions, gameplay, persistence, quality) are **not started**. Rows will be filled with test names and counts as phases complete. A mission is not marked complete because its quest file exists; the bot test must play it.

## 11. Risks and honest limits
- Two milestones (7 and 8) both depend on a region framework that is not built.
- Ranged combat and two new enemy behaviours are new code with fairness and balance risk and no human playtest.
- Without new animation clips the new enemies will reuse existing clips and may look repetitive.
- Interiors have been the weakest visual area (bare boxes even after dressing); this milestone will reuse the dressing kit and add modular lab props, and the interiors will still read as placeholder art until Milestone 13.
- Inherited performance misses (web load, desktop frame rate) will get worse with more content unless the lazy sub-scene loading works as planned; it must be measured.
- The mission text and story documents will be written to fit existing lore (Project Black Site, the Director, the Warden as an earlier experiment); contradictions will be checked against `STORY_AND_MISSION_FLOW.md` by hand.

## 13. Status update (2026-11-07)
Built and merged in the Milestone 8 branches: the ranged combat framework and Facility Commander, the facility components and puzzles, the four melee enemy configurations, and **the region itself** (`docs/RESEARCH_COMPLEX.md`): six areas, four missions, sixteen story entries, enemy placement, the elite with the HUD boss bar, the laboratory power puzzle and the containment override, the sealed underground exit, map data and region persistence. Phases 0 to 5 are built; their automated results are in `RESEARCH_COMPLEX.md` section 7. **Still not done:** a human play-through, balance, new animation clips, facility-specific audio (alarms, door and terminal sounds), a final-quality look (Milestone 13), and the Iron Fortress behind the sealed road. Acceptance checklist items that need a person or a device (feel, difficulty, web, Android) are **not verified**.

## 13. Status after implementation (2026-11-07)
All 69 suites pass on the merged `master`, zero script errors. **Implemented and verified by tests:** ranged combat (pooled projectiles, ranged brain, `EnemyConfig`; 23 checks) and the Facility Commander (32), facility components and puzzles (95), Research Security Guard, Heavy Facility Guard, Experimental Subject and Elite Experimental Subject (47), and the region itself: six areas, four missions, three puzzles, a fair floor hazard, Subject Zero with the HUD boss bar, the Commander with cover points, sixteen story entries, reached through real travel (79, 75 and 38 checks; a physics probe walks the route with gates opening by credentials; persistence through a real save and load including mid-puzzle).

**Seen in screenshots:** zone-coloured interiors and a boss telegraph. **Visible defects:** the admin wing is washed out to pale blue; the zone banner overlaps the boss bar; one perimeter frame measured 168 draw calls against a 150 budget.

**Not done:** nobody has played the ambush, Subject Zero or the Commander fight, so balance is unjudged; no alarm, door or terminal sounds; no new animation clips (ranged shots reuse a spell-cast pose); art is flat vertex-coloured boxes; web and Android untested; the exit toward the Iron Fortress is sealed because that region does not exist.

## 14. Latest status (2026-11-13, after Milestone 12 work)
The Research Complex now also has one stage-wide wave encounter and an "Enemies left" counter outside it, on the same footing as the other three later regions (see `MILESTONE_012.md`). Its own two bosses (Subject Zero and the Facility Commander) already existed from this milestone; the Milestone 12 "boss-opens-the-road" rule applies to it the same way, so the Iron Fortress unlocks when both are down even if a mission step is unfinished.
