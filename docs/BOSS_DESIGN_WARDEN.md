# Boss Design — The Warden

Tags are explained in [MILESTONE_004.md](MILESTONE_004.md). Source of the baseline: `scripts/ai/warden.gd`, `resources/attacks/warden_*.tres`, `tests/boss_check.gd` and `tests/boss_intro_check.gd` on the `milestone-003` branch.

## 1. Confirmed baseline (do not change without approval)

| Property | Value | Status |
|---|---|---|
| Health | 420 | `[IMPLEMENTED]` |
| Movement speed | 2.6 (phase 2: x1.35) | `[IMPLEMENTED]` |
| Stagger resistance | 0.85; only attacks with at least 0.5 s stagger (the heavy finisher) interrupt him, for about 0.09 s | `[IMPLEMENTED]` |
| Phase 1 attacks | **Slam** (36 startup / 8 active / 40 recovery frames, 22 damage, knockback 9); **Shockwave** every third attack (expanding ring to 5.5 m over 0.5 s, 14 damage, avoided by jumping or dodge i-frames) | `[IMPLEMENTED]` |
| Phase 2 trigger | **50%** health | `[IMPLEMENTED]` (the brief asks for ~40%) |
| Phase 2 behaviour | 1.5 s roar (invulnerable, camera shake); speed x1.35; cooldowns x0.6; **Flurry** chained after each slam (14/5/20 frames, 12 damage); shockwave every second attack; summons two soldiers once | `[IMPLEMENTED]` |
| Reward | `warden_loot` table: Warden's Cleaver (x2.30 damage, 0.95 speed), Warden Plate (140 armor points), medkits; verified by `boss_check` | `[IMPLEMENTED]` |
| Encounters | wave 5 in the courtyard, and the Area D encounter (sealed door, 3 s introduction) | `[IMPLEMENTED]` (`milestone-003`) |
| Boss bar | top of screen while a `boss` exists | `[IMPLEMENTED]` |
| Ground telegraph (floor wedge/ring) | red wedge and ring | `[IMPLEMENTED]` on `milestone-002` |

The Warden does not patrol and never receives patrol states (tested by `patrol_check`).

## 2. Design goals for Milestone 004
1. Teach the player to read telegraphs, dodge through them and punish recoveries (the brief: not just more health or damage).
2. Make the boss readable on the new character model (`milestone-002`), with clear windup poses.
3. Give phase 2 a **different tactical problem**, not only faster versions of phase 1.
4. Keep the fight fair, winnable with the starting kit plus the loot found on the way, and short enough to retry.

## 3. Phase 1 — "The Warden holds the line" (100% to the phase threshold)
| Attack | Telegraph (`[PROPOSED]` durations) | Danger | Punish window after |
|---|---|---|---|
| Slam (existing) | raised cleaver, red tint (existing), ground wedge fills over the 36-frame startup | frontal arc | recovery 40 frames (0.67 s): two light hits or one heavy |
| Shockwave (existing, every 3rd attack) | cleaver planted, ring begins at his feet with a brief lift | ring to 5.5 m | 0.6 s; jump or dodge through it |
| **Charge** (`[NEW-M4]`) | 0.8 s crouch and brace, two ground arrows toward the player | straight rush, 18 damage, stops at walls (**stunned 1.5 s on impact with a wall or container**) | wall stun = long punish window; rewarding positioning |
| Heavy swipe combo (`[PROPOSED]`) | existing slam can be followed by a slower horizontal sweep when the player is behind him | wide arc | 0.8 s |

Phase 1 rule set: attacks are always telegraphed at least **0.6 s** (36 frames) before the damaging frame; after every attack the boss is vulnerable for at least **0.5 s** unless the player is out of reach. Staggers only from the heavy finisher (existing armor rule), to keep light combos meaningful but not endless.

## 4. Phase transition at the threshold
- Threshold: confirm **40%** (brief) or keep **50%** (implemented). `[PROPOSED]`: 40% for a longer first phase; needs approval and a boss_check update.
- Sequence (about 2.5 s, `[IMPLEMENTED]` roar extended): boss kneels and roars, shockwave ring pulses outward harmlessly, armor plates glow crimson, music shifts, banner "THE WARDEN ENRAGED" under the boss bar. He is invulnerable and cannot be staggered, the player is pushed back slightly and gets a free medkit window.
- Summons: two soldiers (existing) arrive during the roar; they are not meant to be the main threat.

## 5. Phase 2 — "Enraged" (threshold to 0%)
| Change | Detail | Status |
|---|---|---|
| Aggression | speed x1.35, cooldowns x0.6 | `[IMPLEMENTED]` |
| Flurry | quick double slash after each slam | `[IMPLEMENTED]` |
| **Ground fire lines** (`[NEW-M4]`) | after the shockwave, three crimson lines sweep outward and burn for 1.5 s; the player must move between them | new tactical problem: space control |
| **Leap slam** (`[NEW-M4]`) | 1.0 s jump telegraph with a shadow marker, lands for 20 damage in a 3.5 m radius | forces movement, punishable on landing (1.0 s) |
| Different movement pattern | strafes around the player at range between attacks instead of walking straight in | `[NEW-M4]` |
| Visual identity | red aura on the cape and cleaver, ember particles (cheap, quality-scaled) | `[NEW-M4]` |
| Soldier summons | two, once | `[IMPLEMENTED]` |

Phase 2 attack order (`[PROPOSED]`): slam → flurry → (shockwave + fire lines) → leap slam → repeat with randomised order so the pattern is learnable but not a metronome.

## 6. Defeat sequence (`[NEW-M4]`)
1. At 0 health he drops to his knees (death clip), the music fades, hit-stop and a brief slow motion (existing hit-stop settings), soldiers still alive are removed.
2. Victory caption: "The Warden falls." (existing text), door seal released (existing), banner "BOSS DEFEATED".
3. Loot drops at his position with a light column; the player collects the Cleaver, Plate and medkits (existing table).
4. Objective Act 5 completes; the objective pointer retargets to the command terminal.

## 7. Balance requirements (all `[PROPOSED]` targets, to be measured)
| Metric | Target | How measured |
|---|---|---|
| Time to kill for a competent player | 90–150 s, never under 45 s | scripted bot with fixed skill + human playtests |
| Damage taken in a clean kill | 40–70% of a 100 health + 60 armor kit | bot telemetry |
| Dodge/jump windows | every damaging attack has a survivable response | frame-data table test |
| Telegraph lead time | at least 0.6 s for every attack; at least 0.8 s for the leap and charge | frame-data table test |
| Punish window | at least 0.5 s after every attack | frame-data table test |
| Retry cost | respawn to the fight start in under 20 s | manual |

Do not solve difficulty by raising health or damage; adjust telegraph length, recovery and positioning first. Any change to the existing numbers in section 1 is a documented balance change that needs approval.

## 8. Tests to add (`[NEW-M4]`)
Frame-data table test (every attack has telegraph and recovery within bounds); phase transition at the chosen threshold exactly once; invulnerable during the roar; new attacks deal their damage once; loot and quest completion on death; Area D encounter respects `boss_warden_defeated`; `boss_check` and `boss_intro_check` keep passing.

## 9. Unverified
- Whether the new attacks fit the current arena and Area D dimensions without clipping the camera.
- Whether 90–150 s is right; the tuning needs human playtests.
- Whether the skinned Warden model (`milestone-002`) has clips for the leap and charge (it has `slam`, `flurry`, `shockwave_cast`, `roar`; leap and charge clips do not exist).
