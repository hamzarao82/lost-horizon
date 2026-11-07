# Arena and Survival (Milestone 11, parts 6 and 8)

Tested by `tests/arena_check.gd` (49 checks) and `tests/survival_check.gd` (38 checks). Numbers below are from those runs; feel and balance were not judged by a person.

## Arena state machine
`WaveManager.State`: IDLE, SPAWNING, ACTIVE, CLEARED, TRANSITION, COMPLETE, FAILED. The public API and the three original signals (`wave_started`, `wave_cleared`, `all_cleared`) are unchanged; added: `state`, `state_changed`, `arena_failed`, `reward_granted`, `active_enemy_count()`, `replay()`, `state_name()`.

| From | To | When |
|---|---|---|
| IDLE | TRANSITION | `start_wave_at()` (the first wave waits `start_delay`) |
| TRANSITION | SPAWNING | the rest window ends |
| SPAWNING | ACTIVE | every enemy of the wave exists |
| ACTIVE | CLEARED | no active arena enemy (polled every 0.5 s) |
| CLEARED | TRANSITION | waves remain (rest window from the data) |
| CLEARED | COMPLETE | wave 5 cleared: flag, one-time reward, autosave |
| any running state | FAILED | the player dies |

Wave composition is data: `resources/arena/waves.tres` (`ArenaWaveSet`: enemies, spawn spacing, rest window). `WaveManager.WAVES` stays as a constant mirror because other scripts read its size; a test fails if they drift. Default numbers are unchanged: 5 waves (2 soldiers; 2 soldiers + hunter; heavy + hunter + soldier; heavy + 2 hunters; the Warden), 0.12 s spacing, 3.0 s rest. Difficulty rises by enemy mix (asserted by a weight sum).

## Defects found and fixed
1. **A guard outside the arena held a wave open forever.** The old clear rule waited for the whole `enemies` group to be empty, so any patroller or boss elsewhere in the world blocked the wave. Only enemies the manager spawned now count. Proved: with the old rule the test fails ("a patrolling guard outside the arena does not hold wave 1 open").
2. **An enemy that fell out of the world held the wave open.** Arena enemies below y = -30 are now removed.
3. **A completed arena restarted at wave 1 on every load.** `arena_complete` (a saved WorldState flag) now makes a loaded game start COMPLETE with no waves and no second Warden; `replay()` is the explicit way to run it again.
4. **No completion reward and no claim.** Clearing wave 5 now grants 100 XP and 120 credits once (`arena_reward_claimed`, saved with the world). A reload or a replay pays nothing more. The amounts are small on purpose (a grunt kill is worth about 8 XP; the first mission 400).
5. **No FAILED state.** The player's death now stops spawning, clearing and rewards; the scene reload that follows death builds a new arena that resumes at the checkpoint wave with no leftover enemies (tested).
6. **Teleport landed in arena coordinates in every region.** See below.

Not changed: the 3 s rest window, the checkpoint wave save, the autosave per wave, the signals and the enemy lists.

Measured with a bot that kills through `receive_hit` (headless, short rest windows): wave 1 about 2.0 s, waves 2 to 4 about 1.1 s, wave 5 (the Warden) about 4.3 s. Real play will be much slower; these only show nothing stalls.

## Survival (tests only, limits unchanged)
- Armor absorbs first, then health; `damaged` reports the full incoming amount; zero and negative damage do nothing; death fires once; a dead character cannot be healed or damaged further.
- Medkit: refused at full health or when dead or when none are held, and never consumed on a refusal; one medkit per heal; heals `potion_heal` (40); input buffer 0.8 s; cap 99.
- Teleport: exactly two charges; 600 s per charge; skills can only shorten it; a third use is refused; one second early gives nothing and the full time returns one charge; a spent charge survives a reload; a clock set back never means waiting longer than one recharge.
- **Defect fixed:** outside Outpost 17 the landing spot was still chosen from arena coordinates (±26 around the world origin), so in Dead Coast, Blackwood or the Research Complex it could land the player in the sea, in the void or in geometry, and the charge was spent. The landing spot is now searched 8 to 18 m around the player with ground within 3 m of their height and room for the capsule; when there is none the teleport is refused with "No safe landing here" and the charge is kept. In Outpost 17 behaviour is unchanged. Proved: with the old logic four checks fail (30 of 30 spots found over open ground, charge spent).

## Not covered
- Death-and-respawn health and armor through the real 2-second reload were checked for progression elsewhere (`death_reload_check`); this milestone adds no new test of armor after respawn.
- The HUD wave counter shows only in Outpost 17; the arena has no on-screen FAILED or restart prompt beyond the existing death screen.
- Medkit use during an attack animation (the state rules in `Player`) is not covered; only the inventory rules and the buffer constant.
- Teleport destinations in other regions were tested on the Outpost 17 floor and over open void only, not on the real Dead Coast, Blackwood or Research Complex terrain.
- Nothing here was played by a person.
