# Milestone 010: The Complete Campaign

Status date: 2026-11-07. **Nothing in this milestone is implemented yet.** This is the audit-based plan. Legend: **Implemented**, **Partial**, **Documented only**, **Verified** (a test or screenshot was run), **Not tested**.

## 1. Roadmap
Milestones 1 to 9: foundation, systems and five regions. 10: campaign and narrative integration (this one). 11: advanced combat, bosses and polish. 12: full game completion and content verification. 13: graphics and asset overhaul. 14: optimization, QA and release. Graphics stay out of this milestone.

## 2. Audit: what the repository really has today
| Region | Missions | State |
|---|---|---|
| Outpost 17 | `first_signal` (15 required objectives, optional log), the old arena chain (`restore_power`, `broken_perimeter`, `final_transmission`), the bridge quest `leave_outpost` | built, verified, playable; the Warden fight and the results screen exist |
| Dead Coast | `dc_wreckage`, `dc_silent_checkpoint`, `dc_lost_cargo` | built, verified by tests, reachable through `RegionManager`; never played by a person |
| Blackwood | `into_the_blackwood`, `ghost_frequency`, `experimental_site` | same; the hatch is a caption only |
| Research Complex | `rc_restricted_zone`, `rc_silent_records`, `rc_containment_breach`, `rc_project_black_site` | built and verified; never played; elite fight and boss bar built |
| Iron Fortress | none | **documents only** (`MILESTONE_009.md`): no region, no missions, no Director fight, no ending |

**Systems already in place:** the campaign unlock chain in `CampaignFlow` (flags `dead_coast_unlocked`, `*_mission_3_complete`, `*_region_complete`), a world map screen with region states and discovered landmarks, save v4 with per-region state and `PersistentIds`, a tracker that now prefers the current region's quests, captions for radio lines, document pickups with `LoreDocument`, XP/currency/unique-reward rules, and the RPG screens.

**Known gaps relevant to this milestone:**
- No campaign journal: documents are read once and not collected anywhere. The pause menu has Inventory, Character, Crafting, Gear overview and Map, but no Journal.
- No dialogue system: only captions (subtitle lines). There are no conversations, no speaker names, and no dialogue persistence.
- No narrative bible: lore is spread across `STORY_AND_MISSION_FLOW.md`, `DEAD_COAST.md`, `BLACKWOOD.md`, `RESEARCH_COMPLEX.md` and the documents inside each builder. Contradictions are unchecked.
- No campaign state in the save: act, current main mission, story events and the ending are not stored; only per-region flags exist.
- The old arena quest chain still starts after the first mission and has no place in the five-act story.
- The Iron Fortress does not exist, so the ending, the antagonist fight and "campaign complete" have nothing to attach to. This milestone cannot finish before Milestone 9 delivers the region, or it must build a minimal stand-in.
- The Research Complex exit to the next region is sealed with a placeholder caption.
- Document counts, ids and text in the regions were written by different agents and have not been reviewed together for duplication.

## 3. Dependencies
Milestone 9 (Iron Fortress, the Director, the ending trigger) is a prerequisite for acts IV and V. Milestone 11 (advanced combat) is out of scope; only balance numbers may change. Inherited unresolved items: the web load (about 32 to 42 s), desktop frame rate at High quality, no human play-through, Android untested.

## 4. Proposed architecture
| Piece | Decision |
|---|---|
| `Campaign` state (resource plus autoload-free service owned by `CampaignFlow`) | act (1 to 5), current main mission id, completed missions, story events set, side missions, collected documents, ending seen, post-campaign flag; all saved under a new `campaign` section |
| Save v5 | adds `campaign`; `_migrate_4_to_5` derives the state from existing flags (a Milestone 9 save with `first_signal` done, `dead_coast_unlocked` and so on maps to the right act); hostile data falls back to Act I |
| Mission table | one data resource listing every main mission in order with region, quest id, prerequisites, reward and the narrative beat it triggers; `CampaignFlow.CHAIN` becomes generated from it |
| Dialogue | `DialogueLine` and `DialogueSequence` resources (speaker, text, seconds, optional audio cue), played through the existing caption path with speaker names; played-once flags saved; no voice acting, procedural beep and static for radio |
| Journal | `JournalScreen` in the RPG screen style with tabs: Main (current and completed missions per act), Side, Documents (by category), Story (discoveries), Regions (completion); reads quest, flag and document data, no second quest system |
| Documents | every `LoreDocument` registers an id, title, category, region and body in a `DocumentIndex` resource; collection saved as underscore ids; duplicates detected by a test |
| Ending | `CampaignEnding` sequence after the Director: caption and dialogue beats, statistics screen (reuse the results screen), credits (reuse), then free roam; flag `campaign_complete` saved once |
| Post-campaign | all regions stay open, remaining caches and documents stay collectible, the journal shows campaign and optional completion separately |

All flag and id names use only `a-z`, `0-9` and underscore, at most 48 characters, because `WorldState` drops anything else on load.

## 5. Narrative bible plan
One document `docs/NARRATIVE_BIBLE.md` consolidating: the protagonist, the island history, the military organization, Project Black Site, the research operations, the containment failure, the Director, a timeline, the main characters and the major revelations by act. It is written after reading every existing story document and every in-game text; contradictions found are listed in `docs/CAMPAIGN_AUDIT.md` with the decision taken. Acts: I discovery (Outpost 17), II investigation (Dead Coast, Blackwood), III experiments (Research Complex), IV confrontation (Iron Fortress approach to command), V consequences (the Director and the ending).

## 6. Work phases
| Phase | Content | Status |
|---|---|---|
| 0 | Campaign audit (missions, transitions, contradictions, quest dependencies, rewards, persistence) as a document plus automated checks that every mission's prerequisites, rewards and flags resolve | not started |
| 1 | Narrative bible and story continuity pass over all documents (edit text, no new mechanics) | not started |
| 2 | Campaign state, mission table, save v5 with migration and tests | not started |
| 3 | Dialogue sequences and the speaker-name caption path; radio beats at region transitions | not started |
| 4 | Journal screen and the document index | not started |
| 5 | Map additions (five regions, main mission locations, optional activity markers) | not started |
| 6 | Reward and balance review across regions (numbers only) | not started |
| 7 | Ending sequence, post-campaign state, statistics (depends on Milestone 9) | not started |
| 8 | A full automated campaign bot across all five regions with a save and reload in each act, screenshots, honest report | not started |

## 7. Acceptance tracking
Every checklist item of the brief is **not started**. The brief itself says that if a full automated play-through is impractical, the document must state exactly which parts were tested manually and which are unverified: that rule applies here, and nobody has played any region by hand yet.

## 8. Risks and honest limits
- The main risk is the missing fifth region: acts IV and V cannot be real until Milestone 9 exists.
- Story consistency has never been reviewed by a person; agents wrote the documents of three regions independently.
- Balance across five regions is formulas only, with no human playtest.
- Adding a journal and dialogue UI repeats the screen-testing burden; overlap and touch layouts must be tested at three sizes.
- A save version bump (v5) is another migration to protect: the earlier fixture saves (v2, v3, v4) must all still load.
- Audio for dialogue is placeholder only; nothing was listened to.

## 10. Status after implementation (2026-11-08)
**Implemented and verified:** narrative bible and campaign audit with a read-only continuity test (`story_continuity_check` 571 checks, 0 broken dependencies, 11 contradictions listed and none edited); dialogue system (`dialogue_check` 25) with three example sequences; document index (65 documents: Outpost 17 7, Dead Coast 13, Blackwood 12, Research Complex 16, Iron Fortress 17) and the journal screen with five tabs, J key, layouts at three sizes, collection persistence through a real save and load (`journal_check` 85); the campaign ending (`campaign_ending_check` 53): starts once from `campaign_complete`, seven closing captions, statistics with campaign and optional completion separate, credits, Continue Exploring or Main Menu, post-campaign tracker line; the old arena ending no longer launches mid-campaign (contradiction 1 fixed).

**Not done:** the campaign save section and mission table (save v5, migration), the map additions for main mission locations, dialogue sequences are not called from the game, replaying the ending from the main menu is not wired, the real scene change to the main menu was never run (tested with it switched off), five contradictions need an owner decision (notably the first mission's terminal pointing at the Research Complex while the next destination is Dead Coast), the protagonist's backstory beat in the ending is a proposal needing approval, document categories are a keyword heuristic, nobody has played the ending.
