# Mission failure and recovery rules (Milestone 12)

Death is the only hard failure. There are no timers and no escort quests, so nothing else can fail a mission; the rules below make sure nothing can silently soft-lock one.

1. **Death keeps progress.** Quest state is saved with the checkpoint save; the checkpoint respawn reloads it. Progress is never rolled back by dying.
2. **Reconcile (`QuestManager.reconcile_active()`).** Credits any open set-type step whose proof already exists in saved state: a remembered event, a set `FLAG`, a `boss_<id>_defeated` flag, or a `doc_<id>_found` flag. It respects strict order, never undoes progress, is idempotent, and runs after every game load. It exists for the case where an event happened while its quest was not active (or a save predates it).
3. **Restart (`QuestManager.restart_quest(id)`).** Puts an ACTIVE quest back to step one and replays what history and saved state still prove. Completed quests are never restarted and rewards are never paid twice (the paid list is kept).
4. **Optional steps never block.** A quest made only of optional steps completes at once.
5. **Changed quest data.** A save whose objective list no longer matches restarts that quest from history (existing behaviour in `from_dict`).

Tests: `tests/mission_failure_check.gd` (20 checks). Not covered: a step that can become physically unreachable (a kill target that no longer exists); the game has no such case today, and a human playtest is the only way to find one.
