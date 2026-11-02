# Milestone 004 — Complete Vertical Slice & Gameplay Polish

**Type:** documentation only. Nothing in this package changes gameplay, scenes, assets or settings, and nothing here claims the vertical slice exists yet.
**Written:** 2026-11-03, from inspection of the repository, the three code branches and the earlier planning documents.

## 1. Label legend (used in every Milestone 004 document)

| Tag | Meaning |
|---|---|
| `[IMPLEMENTED]` | Exists in code and has automated tests or a recorded measurement. The branch it lives on is named. |
| `[PLANNED]` | Described in an earlier milestone document but not verified as built |
| `[NEW-M4]` | New requirement introduced by Milestone 004 |
| `[PROPOSED]` | A suggestion that needs human approval before it is built |
| `[UNVERIFIED]` | An assumption nobody has tested (usually device or browser behaviour) |

## 2. Where the project actually is

| Milestone | Where it lives | State |
|---|---|---|
| 001 Prototype and first playable game | branch `master` (commit `4b28467` and earlier), live at the GitHub Pages site | `[IMPLEMENTED]` and published. The **v0.1.0 release has not been created** (waiting for approval). |
| 002 Stylized visual upgrade | branch `milestone-002` (commit `f15002c`) in the OneDrive checkout | `[IMPLEMENTED]`, 16 suites passing (891 checks). **Not merged**, not tested on web or Android. |
| 003 Explorable world, quests, patrols, boss encounter, save v2 | branch `milestone-003` (commit `ccab2bc`) in `C:\Users\SCS\work\lost-horizon-m3` | `[IMPLEMENTED]`, 23 suites passing (981 checks), playthrough bot completes the main quest. **Not merged**, not tested on web or Android. |

**Consequence:** the three milestones are three separate lines of code. No single build contains the stylized characters (002) and the explorable mission (003) together. The first task of Milestone 004 is therefore integration, not new features.

Nothing built so far has been run on a physical phone. The only measured platforms are Windows (integrated graphics laptop) and desktop Chromium.

## 3. Objective
Combine the existing gameplay, visual, world and mission systems into one complete, polished vertical slice of **Outpost 17** that demonstrates the intended quality of the final game: start, explore, fight, loot, solve, defeat the Warden, finish the mission, save and continue.

## 4. Document package

| Document | Purpose |
|---|---|
| [VERTICAL_SLICE.md](VERTICAL_SLICE.md) | Definition of the slice, player journey, content inventory, definition of done |
| [STORY_AND_MISSION_FLOW.md](STORY_AND_MISSION_FLOW.md) | Opening, six acts, objectives, radio transmissions, mission results |
| [BOSS_DESIGN_WARDEN.md](BOSS_DESIGN_WARDEN.md) | Baseline, two-phase design, telegraphs, balance rules, defeat sequence |
| [PROGRESSION_AND_BALANCING.md](PROGRESSION_AND_BALANCING.md) | Equipment, loot, medkits, teleport, balance data, proposals |
| [AUDIO_AND_FEEDBACK.md](AUDIO_AND_FEEDBACK.md) | Sound inventory, gaps, mix, sourcing, combat feedback |
| [UI_UX_SPECIFICATION.md](UI_UX_SPECIFICATION.md) | Screens, HUD, input, scaling, wireframes |
| [QA_AND_ACCEPTANCE_TESTS.md](QA_AND_ACCEPTANCE_TESTS.md) | Test cases, existing suites, manual checks, regression, known limits |
| [PERFORMANCE_BUDGET.md](PERFORMANCE_BUDGET.md) | Budgets, measured baselines, device test plan |
| [RELEASE_READINESS.md](RELEASE_READINESS.md) | Checklist and go/no-go criteria |

Existing documents that this package builds on and does **not** duplicate: `GDD.md`, `ARCHITECTURE.md`, `COMBAT.md`, `QUESTS.md`, `STORY.md`, `WORLD.md`, `SAVE.md`, `TELEPORT.md`, `FX.md`, `UI_LAYOUT.md`, `PERFORMANCE.md` (a measurement log), `WEB_QA.md`, `ANDROID_QA.md`, `RELEASE.md`, `ASSETS.md`, `MILESTONE_003_REPORT.md`.

## 5. Important decisions made in this package
1. **Integration comes first.** Milestones 002 and 003 are merged into one branch before any polish work. See the sequence in section 7.
2. **One region, one mission.** Outpost 17 and "The First Signal" only. The other four island regions are explicitly out of scope.
3. **Reuse before building.** The equipment, quest, save, interaction, patrol and boss systems stay; Milestone 004 adds presentation, missing screens, a stronger boss and reliability.
4. **Balance is documented separately.** Every proposed number change is listed as `[PROPOSED]` and nothing is changed without approval.
5. **No new asset downloads are assumed.** Audio and art sourcing options are listed; any non-original asset needs a recorded licence and human approval.

## 6. Dependencies between systems

```
Merge M002 + M003 ──► Mission flow acts 1-6 ──► Warden complete ──► Results + save
        │                    │                        │
        │                    ├──► Story/radio         └──► Boss audio + effects
        └──► UI screens ─────┴──► Inventory/equipment compare ──► Death/respawn polish
Combat polish ──► (measured by QA) ──► Performance pass on Windows, web, Android ──► Release
```
- The Warden redesign depends on the merged character visuals (it needs readable telegraphs on the new model).
- The mission results screen depends on a new "boss defeated and reward collected" objective (Act 5/6).
- Audio depends on the sourcing decision (extend the procedural generator, or supply licensed assets).
- Performance testing depends on the merged build existing and on access to a real Android phone.

## 7. Suggested implementation sequence (details in each document)

| # | Step | Depends on |
|---|---|---|
| 0 | Branch from `master`; merge `milestone-002` and `milestone-003`; resolve conflicts (HUD, enemy/player scenes, arena decor); all suites green | approval of merge strategy |
| 1 | Release v0.1.0 of the current `master` (so the baseline is public) | your approval |
| 2 | Mission flow: Acts 4-6 objectives, command-center content, results data | step 0 |
| 3 | Story presentation: opening polish, radio transmissions, documents | step 2 |
| 4 | Combat polish: measure, then tune telegraphs, hit reactions, feedback | step 0 |
| 5 | Warden complete encounter (two phases, new attacks, defeat sequence) | steps 0, 4 |
| 6 | Equipment and inventory screens, loot feedback | step 0 |
| 7 | Audio pass (sourcing decision first) | steps 4, 5 |
| 8 | UI screens: main menu, death screen, mission results, settings polish | steps 2, 6 |
| 9 | Save reliability pass (backup, autosave triggers, results persistence) | steps 2, 8 |
| 10 | Performance pass and device tests (Windows, Android, web) | all above |
| 11 | QA run, fixes, release candidate, release | step 10 |

## 8. Items that need human approval
1. Merge strategy for 002 + 003 (single integration branch, who resolves conflicts).
2. Publishing the v0.1.0 release (still pending from Milestone 001).
3. Warden phase 2 trigger: **40%** (this brief) versus the implemented **50%**; and the proposed new attacks.
4. Whether to add a **main menu** (none exists today; the game opens a loading screen and then the story intro).
5. Audio sourcing: extend the procedural generator, or supply licensed assets (no download is assumed).
6. Death rules (`[PROPOSED]` in PROGRESSION_AND_BALANCING.md).
7. Any balance change listed as `[PROPOSED]`.
8. Access to a physical Android phone for the device test.
9. Whether the real Redmi K80 or another device is the Android reference.

## 9. Unverified assumptions (consolidated)
- Merging 002 and 003 is possible without large rewrites (both change the HUD, the enemy and player scenes and the arena decor).
- The skinned characters from 002 hold frame rate on web and Android with the 003 areas and patrols.
- The 30-second web load measured on `master` will not regress after the merge (more areas, more resources).
- Memory on low-RAM phones (the web build used about 1 GB in Chromium).
- The procedural audio is acceptable as the final sound for the slice (nobody has judged the mix by ear).
- Touch controls are playable for the full mission (never tried on a device).

## 10. Not in this milestone
All five regions, multiplayer, accounts, backend, open-world streaming, crafting, large dialogue trees, additional bosses, procedural generation. Milestone 005 is not started.
