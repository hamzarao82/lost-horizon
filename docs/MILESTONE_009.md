# Milestone 009: Iron Fortress

Status date: 2026-11-07. **Nothing in this milestone is implemented yet.** This is the audit-based plan. Legend: **Implemented**, **Partial**, **Documented only**, **Verified** (a test or screenshot was run), **Not tested**.

## 1. Roadmap context
Milestones 1 to 12 complete the game's content, Milestone 13 is the graphics and asset overhaul, Milestone 14 is optimization, QA and release. This milestone is gameplay, layout, missions, encounters and the ending. Environments are modular and use current or procedural assets so Milestone 13 can replace them. Milestones 10 and 11 have no scope document yet; this plan does not assume what they contain.

## 2. Dependencies that are not met yet
| Needed by this milestone | State today |
|---|---|
| Region framework (travel, save v4, per-region state) | built and merged in local `master` (verified by `region_check`, `region_save_check`); not pushed |
| Dead Coast, Blackwood content | built in separate branches; Dead Coast merged into local `master`, Blackwood in its final fixes; neither is wired to the region manager or reachable in play yet |
| Research Complex (Milestone 8) | plan only; no content |
| "Existing ranged combat behavior" for infantry, commanders and the boss | **does not exist.** Every current enemy is melee. Milestone 8 plans a ranged attack for its Facility Commander; Iron Fortress needs the same capability (projectile, ranged attack state, cover positioning) and should share it |
| Boss framework | `Warden extends Enemy` with two phases, charge, leap, fire lines and a defeat sequence; no three-phase boss and no dialogue system |
| Ending system | the first mission has an ending credits text and a results screen; there is no campaign-completion screen or state |
| Dialogue | captions (subtitle lines) only; no dialogue trees or cutscenes |
| Stealth | patrol detection, suspicion and search states exist; no stealth takedowns |

**Inherited and unresolved:** web load about 42 s against a 30 s budget, desktop frame rate below 60 FPS at High quality on integrated graphics, no human play-through, Android never run on a device. A fortress with many enemies and large interiors will make these worse unless regions load lazily and the AI update rate is budgeted.

## 3. What can be reused
Quest architecture (`QuestManager`, event-driven objectives, optional objectives, `mission_completed`); interactables (terminals with `requires_flag`, doors, documents, switches, caches, checkpoints); the ordered power-switch puzzle generalized into multi-step puzzles; `PatrolGroup`, detection and suspicion; `Enemy` with soldier, heavy, elite and Warden configurations; loot tables by tier, XP, currency, unique-reward claims; save v4 with per-region state and `PersistentIds`; HUD tracker, boss bar, notifications, results screen; the Warden's telegraph and fairness rules (telegraph at least 0.6 s, punish window at least 0.5 s) asserted in tests.

**Hard rule for every id in this milestone:** `WorldState` keeps only saved flags made of `a-z`, `0-9` and underscore, at most 48 characters. Dotted ids are silently lost on save. All mission, puzzle, claim and campaign flags use underscores (for example `iron_fortress_gate_open`, `campaign_complete`).

## 4. Proposed structure
One region scene, `IronFortress`, loading sub-scenes lazily so only the current zone and its neighbours exist: `Approach`, `OuterPerimeter`, `Barracks`, `CommandCenter`, `InnerFortress`, `ControlFacility`. Reusable components shared with Milestone 8 where possible: `SecurityDoor` (credential level), `ResearchTerminal`/command terminal, `ContainmentControl` generalized to `MultiStepPuzzle`, `FacilityEnemySpawn`, `MissionTrigger`. Credentials are items or flags (`fortress_gate_credential`, `command_key`, `inner_access`).

## 5. Missions (existing quest architecture)
1. **The Last Stronghold:** reach the approach, investigate the perimeter, defeat or bypass outer guards, search the checkpoint, obtain gate credentials, open the outer gate (Puzzle A).
2. **Inside the Walls:** enter the barracks, investigate the armory, disable the inner lockdown step, defeat defenders, retrieve the command key, unlock the command center. Optional: Armory Recovery.
3. **Chain of Command:** enter the command center, find the archive, restore communications (Puzzle B, a terminal and power sequence), retrieve operational files, learn the antagonist's identity and objective, unlock the inner fortress. Elite guard confrontation, story documents.
4. **The Final Lockdown:** enter the inner fortress, survive elite defenses, disable the lockdown at several control points (Puzzle C), defeat the Fortress Captain (inner fortress commander), access the control facility.
5. **Black Site:** enter the control facility, read the final records, learn the whole truth, confront the Director, defeat him, trigger the campaign ending and completion state.

Side objectives (a short list, no filler): Armory Recovery, Missing Patrol (a log trail and a small camp), Classified Orders (collectible command documents), Supply Depot (a cache guarded by elites). Each pays a real reward (a unique item, materials or XP) and a story document.

## 6. Enemy roster as configurations of `Enemy`
| Enemy | Basis | Difference |
|---|---|---|
| Fortress Infantry | soldier | uses the new shared ranged attack, patrols in pairs |
| Elite Security Soldier | elite hunter | more health and damage, guards restricted rooms |
| Heavy Assault Unit | heavy | slow, heavy weapon, long telegraph |
| Tactical Commander | soldier plus ranged and cover repositioning | stays at range, calls nearby allies (reuse the Blackwood ally-alert hook) |
| Fortress Captain | Warden-style elite | unique attack set, telegraph at least 0.6 s, punish window at least 0.5 s, own loot |
| The Director | boss, new configuration on the Warden pattern | three phases (below) |
All stats, weapons and attack sequences are resources; no new AI class per enemy. Enemy scaling uses the existing level-based `EnemyScaling`, with a gentler curve for bosses.

## 7. Final boss: The Director
The project's first-mission document already names "the Director" as the head of Project Black Site, so this is the established antagonist; the lore documents must be reread before any dialogue is written. Plan, all assertions made in tests like the Warden's:
- **Phase 1, tactical:** ranged shots with learnable patterns, controlled movement between cover points, an occasional close-range counter after the player gets near.
- **Phase 2, aggressive (about 60% health):** more frequent attacks, new combinations (a ranged volley followed by a dash strike), shorter gaps but no shorter than 0.5 s of punish time.
- **Phase 3, final stand (about 25% health):** a distinct pattern, wide telegraphed area attacks, clear vulnerability windows after each; no unavoidable damage and no trap loops; health never gated behind huge numbers.
- Boss health bar and phase feedback through the existing boss bar and captions; a short defeat sequence; the campaign-complete flag `campaign_complete` set exactly once and saved; a reload after the boss dies never respawns him.
- Dialogue is delivered as captions during the intro, at the phase changes and at defeat (no dialogue system exists).

## 8. Ending and campaign completion
A small reusable `CampaignEnding` flow: boss defeat then caption sequence then results screen variant ("Campaign Complete", statistics, rewards, unresolved threads) then credits (reuse the existing credits text) then return to the main menu or free roam in the region. State saved as `campaign_complete`; the main menu shows it; the ending can be replayed from a credits entry without re-granting rewards.

## 9. Rewards and persistence
XP, currency and loot on the existing curves, a step above the Research Complex; a unique captain reward and a unique final reward, both claimed once through `unique_claimed`. Persistent ids per mission, puzzle step, cache, document, side objective, elite and boss, stored through `PersistentIds` and region state, each with a reload test. A failed run (player death) restarts from the last checkpoint without clearing completed puzzle steps.

## 10. Work phases
| Phase | Content | Status |
|---|---|---|
| 0 | Shared ranged attack and cover positioning (also needed by Milestone 8); finish wiring of earlier regions | not started |
| 1 | Approach and Outer Perimeter, mission 1, Puzzle A, infantry | not started |
| 2 | Barracks, mission 2, armory side objective, elite soldiers, heavy units | not started |
| 3 | Command Center, mission 3, Puzzle B, documents, Tactical Commander | not started |
| 4 | Inner Fortress, mission 4, Puzzle C, Fortress Captain | not started |
| 5 | Control Facility, mission 5, the Director (three phases), defeat sequence | not started |
| 6 | Ending flow and completion state, audio (alarms, door sounds, boss and final music placeholders), HUD checks, campaign bot test through all regions, save and load matrix, screenshots, performance measurement | not started |

## 11. Acceptance tracking
Every item of the brief's acceptance checklist is **not started**. A mission is not marked done because its quest file exists: a bot must play it through real events. The final boss fairness rules, the three phases, the single-grant of the final reward and the completion flag surviving save and reload are asserted by tests before any claim.

## 12. Risks and honest limits
- This is the last milestone in the chain and depends on four others that are plans or unmerged work (ranged combat, Research Complex, region wiring, ending flow).
- Ranged combat for infantry and a three-phase boss are new combat code with fairness and balance risk and no human playtest.
- No new animation clips exist for ranged shooting or the Director; clips will be reused and mapped, so the boss will look like a recoloured existing character until Milestone 13.
- Audio is procedural; heavy weapons, alarms and final music will be generated placeholders that nobody has listened to.
- Performance: more enemies and larger interiors on an already over-budget project; lazy loading and an AI update budget must be measured, not assumed.
- Story: continuity with Outpost 17, Dead Coast, Blackwood and the Research Complex has to be checked by hand against `STORY_AND_MISSION_FLOW.md` and the new region documents; Milestones 10 and 11 may add lore that this plan does not know.
