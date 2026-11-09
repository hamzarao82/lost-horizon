# Stage sequence: strict steps and a stage-limited tracker and arrow

Status: implemented and covered by `tests/stage_sequence_check.gd` (32 checks). A tester who played Dead Coast reported two problems: the arrow pointed at objects from other stages or missions, and there was no proper sequence. These are the two rules that fix them.

## Rule 1: the tracker and the arrow only speak about the current stage
`QuestManager._tracker_order()` returns the active quests of the region the player is in (`RegionManager.current_region_id`), with the pinned bridge quest first only in Outpost 17. Quests of other regions never appear: in Dead Coast the old arena quests (`restore_power`, `broken_perimeter`, `final_transmission`), the first mission and the bridge quest are hidden. In a region with no active quest the tracker is empty and the arrow shows nothing, instead of pointing at another stage. `ObjectivePointer.current_objective()` uses the same order, so the arrow and the tracker always talk about the same step.

## Rule 2: strict step by step inside the later regions
Quests whose region is `dead_coast`, `blackwood`, `research_complex` or `iron_fortress` (`QuestManager.STRICT_REGIONS`), or any quest with `strict_order = true`, complete in list order. Outpost 17 keeps its free order: its quests are not strict.

- An objective is **unlocked** when every earlier *required* objective is done. Optional objectives are always unlocked and never block anything.
- **No event is lost.** Set-type events (interact, enter area, discover, flag, item, boss) are already kept in `_history` (and flags live in WorldState). An event that arrives before its turn changes nothing visible. The moment the step before completes, `_advance_strict` replays the remembered events in order, to a fixed point, so a whole mission done in reverse order finishes as soon as its first step is done. This is the no-soft-lock property, tested with a full mission played in reverse.
- **Kill and wave counters** are not replayable events, so they keep counting whatever the order and are already full when their turn comes. They are the one exception to "nothing happens before its turn", and they cannot soft-lock.

## What the player sees
- The tracker shows one required step (the first unfinished one) of the current mission.
- In the four later regions the tracker title carries a stage line, for example `Wreckage  -  Dead Coast: step 4 of 16`. The count is the current required step across every mission of the region in play order (`QuestManager.tracker_stage_line()`; missions are ordered by prerequisites and `next_quest`). Outpost 17 shows no stage line.
- The arrow aims at the current step only. Labels read as short nouns: `dead_coast_wreck_hull` shows as `Wreck Hull`, a leading `log` is dropped (`ObjectivePointer.short_label`). Area objectives that are aimed at a trigger now use the map's area name instead of a generic `Area`.

## Where the code is
`scripts/quests/quest_manager.gd` (`is_strict`, `_unlocked`, `_advance_strict`, `_replay_objective`, `_tracker_order`, `_region_chain`, `tracker_stage_line`), `scripts/quests/quest_data.gd` (`strict_order`), `scripts/ui/objective_pointer.gd` (`short_label`, labels), `scripts/ui/hud.gd` (the stage line in the title).

## Not verified
Nobody has played it. The arrow's on-screen quality and the readability of the title with the stage line at the smallest window sizes were not captured in a screenshot. Save files do not store the strict state: it is derived from the saved quest progress and history on load, so older saves with out-of-order progress keep their done flags.
