# Milestone 011: Advanced Combat, Enemy Intelligence, Bosses and Gameplay Depth

Status date: 2026-11-07. **Nothing in this milestone is implemented yet.** This is the audit-based plan. Legend: **Implemented**, **Partial**, **Documented only**, **Verified** (a test or screenshot was run), **Not tested**.

## 1. Roadmap
Milestone 10: campaign integration. 11: this one. 12: full game completion and content verification. 13: graphics overhaul. 14: optimization, QA and release. Milestone 12 is not started by this milestone, and graphics stay out of it.

## 2. Audit: what already exists
| Area | State today (from the repository) |
|---|---|
| Player combat | state machine (free, dodge, attack, hit, dead), an input queue with buffering, a three-hit light chain, heavy and sprint/air/spin attacks, dodge with i-frames, lock-on, hit-stop, frame data in `COMBAT.md`, tests `run_tests`, `input_check`, `lockon_check`, `hitstop_check` |
| New in Milestone 6 | Combo Extension and Counterattack skills, level-based enemy scaling, one damage pipeline (`StatsResolver`) with each modifier applied once |
| Weapons | per-item `damage_multiplier` and `attack_speed`, rarity and upgrade stats, the Warden's Cleaver as a unique with its own upgrade curve; worn gear stat totals; weapon switching through the bag and equipment screen (not a hotkey during combat) |
| Enemies | `Enemy` states IDLE, CHASE, ATTACK, STAGGER, DEAD plus PATROL, SUSPICIOUS, SEARCH, RETURN and a RANGED_ATTACK state; detection with sight cone, suspicion and noise; patrol groups with a cap of four active patrollers; ally alert hook; ranged framework (pooled projectiles, cover points, `EnemyConfig`); configs for soldier, hunter, heavy, facility guards, experimental subjects, Facility Commander |
| Bosses | Warden (two phases, charge, leap, fire lines, defeat sequence), Elite Experimental Subject; the Fortress Captain and the Director are being built in Milestone 9 and are not merged yet |
| Arena | `WaveManager` with five waves and the Warden on wave 5, loot and rewards, tests in `run_tests` and `boss_check` |
| Survival | health, armor pool, medkits (the only heal), two teleport charges with a 10-minute recharge (Progression can scale the recharge), death and checkpoint respawn |
| Feedback | procedural sounds (swings, hits, hurt, dodge, heal, teleport, boss), effects pool (hit sparks, dust, rings), damage numbers, HUD health, armor, medkits, teleport, wave counter, boss bar |
| Environment | cover points for ranged enemies (placed in the Research Complex lab), a floor hazard with a warning light; **no explosive objects, no destructible cover, no elevation-based combat mechanics** |
| Regions | five exist as builders (Outpost 17, Dead Coast, Blackwood, Research Complex, plus the Iron Fortress in progress), but the brief names three for balance; Dead Coast and Blackwood must be balanced too |

**Known gaps and bugs relevant here:**
- Weapon reach, recovery and combo behaviour are probably the same for every weapon apart from damage and speed. The audit must confirm this from `AttackData` and the hitbox shapes before design.
- The old arena chain quests (Outpost 17) overlap the new campaign; they stay playable but are not part of the five acts.
- Several fairness numbers (telegraph at least 0.6 s for bosses, punish window at least 0.5 s, ranged burst spacing) exist as tests for the Warden, the Elite subject and the Commander only; regular enemies are not covered by one shared fairness table.
- The AI runs states per enemy per physics frame in `Enemy`; there is no central update scheduler or AI budget, and the patroller cap is the only limit.
- The wave counter and the arena belong to Outpost 17 only; the arena has no failure/restart screen beyond death and reload.
- Android and web performance of the AI and effects are unmeasured; desktop at High quality is below 60 FPS on integrated graphics, and web loads in about 32 to 42 s.
- The Warden, Subject Zero, the Commander, the Captain and the Director have never been fought by a person; every balance number is from formulas and bots.

## 3. Dependencies
Milestone 9 must be merged first for the Fortress enemies, the Captain and the Director. Milestone 10 (campaign integration) is not a prerequisite for combat work, but difficulty balancing across the regions needs the mission order from Milestone 10's mission table. A human playtest is the only way to judge "feels responsive", and it has not happened.

## 4. Plan by area
| Area | Plan | Notes |
|---|---|---|
| Audit | read the combat code and write `docs/COMBAT_AUDIT.md` with measured numbers: startup, active and recovery frames per attack, ranges, hitbox sizes per weapon, input latency, duplicate hit protection, invalid-state guards | evidence first; the plan below changes after it |
| Player combat | weapon-aware combos: per-weapon chain length, reach (hitbox size), recovery and cancel window as data fields on `AttackData`/weapon resources, not code branches; attack-while-moving with reduced turn speed during active frames; knockback and stagger values per attack; guard against attacks in invalid states; buffered input rules documented and tested | keep the existing three-hit default for the starting blade |
| Weapon identity | a data table (reach, speed, recovery, heavy behaviour, stagger) for knife, blade, sword, katana, claymore, machete, Warden's Cleaver; fast light weapons stagger less, heavy ones stagger more; resistance (armored enemies reduce light damage) through the existing damage pipeline | no new weapons; numbers asserted from data |
| Enemy AI | add a shared **AI scheduler** (staggered think intervals, 0.1 to 0.3 s by distance and importance), tactical modes as configuration: flank slot assignment so melee enemies take different approach angles, spacing to avoid crowding, defensive stance for guards (block reduces damage but has a fixed vulnerability window), retreat at low health for non-boss enemies, reinforcement calls through the ally alert hook with a cap | all through `EnemyConfig`; no new AI class per enemy |
| Encounter design | an `EncounterDirector`: patrol, guarded area, ambush and arena encounters share spawn timing, reinforcement caps and a difficulty profile; replace ad-hoc spawn code where it exists | persistence stays with `PersistentIds` |
| Bosses | review every boss against one fairness table (telegraph, punish, damage once per use, no trap loops) and add missing audio and visual telegraph cues; add a `BossFairness` test shared by Warden, Subject Zero, Captain, Director; verify rewards and flags | no new phases unless a test shows a boss lacks learnable patterns |
| Arena | rebuild the wave flow around an explicit state machine (IDLE, SPAWNING, ACTIVE, CLEARED, TRANSITION, COMPLETE, FAILED); dead enemies never count; reward granted once per run via a saved claim; a restart option after failure; tests for every transition including stuck-wave recovery | wave composition table per wave as data |
| Environment | explosive barrels (area damage to enemies and the player with a visible fuse and radius, one-shot, persists as destroyed), destructible low cover, a narrow-passage ambush layout and one elevated firing platform in Outpost 17, tied to the arena and the Research Complex; hazards keep a warning phase | each object has a gameplay role and a test |
| Survival | audit and test the damage path (armor absorbs first, then health); medkit use rules (no use at full health, one use per animation, cooldown), teleport rules (two charges, 10-minute recharge preserved, invalid destinations refused, recharge persisted); no change to the limits | tests prove the numbers stay the same |
| Feedback | per-weapon hit effects and sounds, armor-break cue, boss telegraph audio cue, enemy-attack sounds distinct by archetype, low-health warning, damage direction indicator, reward and wave notifications through the existing notification layer | procedural audio only, unheard until a person listens |
| Animation | map existing clips to every attack id and state; add blend or transition timing so attacks and movement do not pop; no new clips unless Blender work is approved | the ranged shot still reuses a cast pose |
| UI | enemy health bars above elites, a boss telegraph indicator on the HUD, armor and health consistency, wave and encounter status through the existing HUD; no second HUD | layout contract tests at three sizes |
| Balance | one spreadsheet-like data file of enemy and boss health, damage and detection per region with the target time-to-kill and damage-taken per encounter; an automated simulation (bot fights each enemy with each weapon at the expected level) reports time to kill and damage taken; targets: Iron Fortress hardest through behaviour (ranged pressure, defensive guards, reinforcements), not only health | numbers come from a bot, not a human |
| Replayability | optional elite stronghold in Outpost 17 and one in each later region with a unique drop; a replayable arena mode from the main menu or the map (the unfinished "Arena Mode" idea); rewards capped to avoid grinding | persistence through `PersistentIds` |
| Performance | profile AI and effects with the existing benchmark and `stutter_bench`; cap active AI thinkers, projectile pool, particle counts by quality; web and mobile quality scaling; measure before and after | no budget claim without a measurement |

## 5. Work phases
| Phase | Content | Status |
|---|---|---|
| 0 | combat audit with measurements | not started |
| 1 | weapon data table and per-weapon attack data (reach, recovery, combo, stagger), tests | not started |
| 2 | player movement during attacks, invalid-state guards, knockback and stagger, regression of input and frame-data tests | not started |
| 3 | AI scheduler and tactical modes (flank, spacing, defensive, retreat, reinforcement) | not started |
| 4 | EncounterDirector and arena state machine, five-wave tuning, failure and restart | not started |
| 5 | boss fairness pass and shared `BossFairness` test; telegraph cues | not started |
| 6 | environment interactions (explosives, cover, passages, elevation) | not started |
| 7 | feedback, animation mapping and combat UI | not started |
| 8 | balance simulation and tuning across the five regions, replayable optional encounters | not started |
| 9 | performance measurement and quality scaling, full regression, screenshots, report | not started |

## 6. Acceptance tracking
Every item in the brief's "definition of done" is **not started**. Rules for this milestone: "responsive and rewarding" cannot be proven by tests and needs a person; tests prove frame data, state transitions and numbers. Android and web must be run on real devices or browsers before they are claimed.

## 7. Risks and honest limits
- Combat changes can silently break the frame-data and input-latency guarantees that the existing tests protect; every change runs `run_tests`, `input_check`, `boss_check`, `warden_design_check` first.
- Retuning enemy AI across five regions without a human playtest risks making fights worse; the balance simulation measures time to kill, not fun.
- The AI scheduler touches every enemy; it must not change behaviour at default settings (a test compares fight outcomes before and after).
- New animation clips do not exist; "improved animations" means mapping and timing only unless Blender work is added.
- The Iron Fortress and the Director do not exist in `master` yet, so cross-region balancing waits for them.
- Performance on integrated graphics already misses 60 FPS at High quality; more AI and effects need budgets, or the quality tiers must absorb the cost.

## 8. Status after implementation (2026-11-08)
**Implemented and verified (parts 6 and 8 only):** the five-wave arena is now an explicit state machine (IDLE, SPAWNING, ACTIVE, CLEARED, TRANSITION, COMPLETE, FAILED) with data-driven waves (`arena_check` 49); six defects fixed, each with a test that fails on the old behaviour (a guard outside the arena holding a wave open, an enemy falling out of the world holding it open, a completed arena restarting at wave 1 on every load, no failure state, no completion reward, teleport landing in arena coordinates in every region); survival audit (`survival_check` 38: armor then health, single death, medkit and teleport limits unchanged: two charges, 600 s recharge).

**Needs your decision:** the arena completion reward (100 XP, 120 credits, once) was chosen by the agent, not requested.

**Not started:** weapon differentiation (reach, recovery, combo per weapon), the AI scheduler and tactical modes, the encounter director, the shared boss fairness test across all bosses (each boss has its own), explosive and cover environment objects, feedback and animation mapping, combat UI additions, the balance simulation, optional elite strongholds, performance budgets for AI and effects. Milestone 11 is roughly 25% done.
