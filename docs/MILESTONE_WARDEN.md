# Milestone 11 (Opening series): The Warden. The guardian of Outpost 17

Status date: 2026-11-14. This is the brief, the inspection it asks for (done here from the real code), and a plan. **The Warden fight already exists and is tested; this milestone is mostly a polish and verification pass, not a build.** It follows "The Restricted Sector" (`MILESTONE_RESTRICTED_SECTOR.md`, plan only). Not to be confused with `MILESTONE_011.md` (advanced combat and AI), which already retuned some Warden data. Legend: **Exists**, **Partial**, **Not built**, **Verified**, **Not tested**.

## 1. Inspection report
| Piece | What exists |
|---|---|
| Boss scene and script | `scenes/enemies/Warden.tscn`, `scripts/ai/warden.gd` (`Warden extends Enemy`) |
| Mechanics | two phases; slam, charge (ending in a long wall stun), leap, fire lines, a flurry (chained after the slam in phase 2), a shockwave spawned by the slam; at 40% health a roar (invulnerable 2.5 s) and enrage; a defeat sequence; loot table `resources/loot/warden_loot.tres` |
| Introduction | `scripts/world/boss_intro.gd` (`BossIntro`). On first entry into Area D it seals the doorway at z = -62.6, shows the caption "The Warden: This is as far as you go." for 3 s while the camera locks onto the boss (the boss stands still), then enables him. A returning player gets a 1.2 s "quick" intro |
| Arena | two sites: **Area D, the command building** (the story fight, with the seal) and **wave 5 of the courtyard arena** (the same Warden, also used by Arena Mode) |
| Boss UI | the HUD boss bar and name (`hud.gd`, `boss` group), and since the M11 pass a telegraph strip under it (it fills only for the base melee swing and the Director; other attacks show it full) and a camera-facing health bar for bosses |
| Fairness | `boss_fairness_check` (94): the three violations found earlier are fixed (flurry telegraph 36 frames, shockwave reclassified as an effect of the slam) |
| Existing tests | `boss_check` (20), `boss_intro_check` (20), `warden_design_check` (42), `boss_fairness_check` (94), `balance_sim_check` (30), arena suites (49) |
| Player abilities | combo, dodge with i-frames, two teleport charges (600 s recharge), medkits, armor pool, weapon identity table (M11); all unchanged by the boss |
| Flags | `warden_intro_done`, `boss_warden_defeated` (set when **any** Warden dies), `warden_d_defeated` (set only when the Area D one dies) |
| Defeat handling | `_on_any_warden_defeated`: sets the flags, releases the seal, shows "The Warden falls." Rewards: `warden_loot`; the quest step "Take the Warden's signature reward"; the command terminal unlocks (`requires_flag = boss_warden_defeated`) and the `CampaignFlow` road to the Dead Coast opens when the region's bosses are down |

## 2. Findings that matter for this brief
1. **The intro cannot be skipped and is not a cinematic.** It is a 3 s camera lock plus one caption; the brief's "keep it short, allow skipping if the existing system supports it" is satisfied by it being short, and no skip is available or needed. A richer intro (lighting change, roar, name card) is new work using existing pieces (the camera lock, `Hud.show_caption`, the roar sound).
2. **"Victory triggers progression exactly once" is not guaranteed.** `boss_warden_defeated` is set by **either** Warden: defeating the wave-5 Warden in the courtyard arena (also reachable from Arena Mode) sets it, which unlocks the command terminal and opens the Dead Coast road without ever fighting the Area D encounter. The flags are idempotent (setting twice is harmless), but the story fight and the arena fight are not distinguished by the progression, and no test asserts that the road requires `warden_d_defeated`.
3. **Retry is partly tested.** `boss_intro_check` (20) already asserts: entering again does not spawn a second Warden; after a reload the doorway seals again with a quick intro; the seal releases on victory. **Not asserted:** that boss health is back at full when the player dies mid-fight and returns (the code returns early when the old Warden is still alive, "already fighting him", so a returning player may meet the same Warden at partial health). The brief wants health reset on retry; this needs a test first, then a decision on whether partial health is acceptable.
4. **Seal safety is already covered.** The same test asserts "if the Warden disappears the seal releases by itself", so a removed boss does not trap the player. (An earlier draft of this document claimed otherwise; that was wrong.)
5. **The sound set for the fight is thin.** Slam, charge, leap, roar and fire sounds exist; there is no boss music except the pitch-shifted explore loop (`boss` music mode, unheard), no entrance sting, no distinct defeat sound beyond the shared one.
6. **The payment must not be recovered here**: nothing in the Warden's loot or rewards touches a bag today (no such item exists), which already complies.
7. **The brief says not to invent dialogue**: the existing line ("This is as far as you go.") is the only spoken line and fits.

## 3. Mapping the brief to what exists
| Brief item | Status |
|---|---|
| Cinematic introduction using existing assets, skippable if supported | **Partial.** A short lock-on with a caption; no skip; no lighting or sound establishing "this is not an ordinary guard" |
| Clear telegraphs, timing, recovery windows, dodge opportunities | **Exists and tested** (`boss_fairness_check`, `warden_design_check`) |
| Balanced damage and health | **Exists by formula** (`balance_sim_check`); **never fought by a person** |
| Responsive hit reactions | **Exists** (hit-stop, stagger, wall stun) |
| Close attacks, area attacks, counter windows, reposition pressure, learnable patterns | **Exists** by design and data |
| Respect player abilities, no disabling | **Exists** |
| Arena presentation: lighting, camera, entrance, effects, audio, health display | **Partial.** Boss bar, telegraph strip, elite bar exist; the arena lighting is the shared interior; entrance and audio are minimal |
| Defeat animation, stop hostile behaviour, trigger progression once | **Partial** (finding 2) |
| Open the next access point and give a clear objective | **Exists** (the road quest `leave_outpost`, "Follow the signal to the Dead Coast"); the brief's "evidence the payment is beyond" is **not built** |
| Retry, reset, no duplicates, no invalid save state, no double victory | **Partial and unverified** (findings 3 and 4) |
| Do not recover the payment | **Met** |

## 4. Decisions needed
1. **Which Warden is the story Warden?** Make the road and terminal depend on `warden_d_defeated` (the Area D fight) and keep the wave-5 Warden as arena content only; or keep either, and accept that the arena fight can substitute for the story fight. This changes `CampaignFlow`'s boss list for Outpost 17 and the tests that assert it (`boss_road_check`, `campaign_flow_check`).
2. **How much intro.** Keep it as is, or add a short lighting dip and a roar sound before the caption (small, uses existing pieces).
3. **Where the payment lead appears.** The brief wants the defeat to give evidence that the payment is beyond; the natural place is the Warden's reward or the command terminal's pages (new text only).

## 5. Planned work
| Phase | Work | Status |
|---|---|---|
| 0 | Prerequisites: the opening plans through The Restricted Sector, decisions above | not started |
| 1 | **Tests first** (the missing ones only): boss health on retry after the player's death; save and load mid-fight leaves a valid state; victory fires once; the wave-5 Warden does or does not open the road, per decision 1. (No-duplicate, reseal and seal release are already covered by `boss_intro_check`.) | not started |
| 2 | Fix whatever phase 1 shows (health on retry, the road dependency), no changes to attack data | not started |
| 3 | Intro polish: a one-second light change, the roar sound, a name card via the existing boss bar; keep the 3 s length; nothing skippable is needed | not started |
| 4 | Presentation: entrance and defeat sounds from existing files only (audio budget is full), a hit-spark or ring effect from the existing effects pool on heavy impacts | not started |
| 5 | Progression: the objective after defeat and a clue on the command terminal that something valuable was moved to a restricted store; the payment untouched | not started |
| 6 | Human playtest of the fight (the only way to judge feel and fairness) | needs you |
| 7 | Windows and browser checks, performance (the boss, effects and telegraph strip at web quality), report | not started |

## 6. Risks and honest limits
- The Warden has never been fought by a person; every balance statement here is formula or bot based.
- The two-site structure is the main source of progression bugs.
- Retuning attacks beyond what `boss_fairness_check` requires risks undoing the earlier fairness pass.
- Audio is generated and unheard, and the budget is full, so the fight will sound thin.
- The brief's "evidence that the payment is beyond" depends on the unresolved payment destination.

## 7. Acceptance tracking
Criteria 3, 4, 6 and 7 hold today by tests (boss and fairness suites). Criteria 8 and 9 (defeat and retry; victory once) are **partly verified** (no duplicate, reseal, seal release) and need the health-reset and single-victory tests first. Criterion 11 (payment unrecovered) holds. Criteria 2, 5, 10 and 12 need the work above or a person.

## 8. Status of the polish pass (2026-11-15)
- **Retry, found and fixed:** a player death rebuilds `Main`, so a fresh, full-health Warden always follows a death. The one real way to meet a *wounded* living Warden was to leave Area D mid-fight (a teleport can carry the player past the seal) and re-enter; `BossIntro` used to ignore that and resume against the wounded boss. It now replaces a hurt Warden with a fresh full-health one on re-entry and keeps an untouched one (no churn). `warden_retry_check`, 16 checks.
- **Save and load mid-fight:** the saved world remembers the intro and claims no victory; after a load there is no Warden until Area D is entered, then exactly one at full health with the doorway sealed (same test).
- **Victory once:** `warden_progression_check`, 12 checks: both defeat flags, "The Warden falls." once, the new lead caption once, kill XP once, loot dropped and not repeated on re-entry, no new Warden afterwards, `payment_recovered` unset.
- **Which Warden sets which flag (decision 3):** the courtyard (wave 5) Warden sets `boss_warden_defeated` only (the Dead Coast road and the command terminal use it); only the Area D fight also sets `warden_d_defeated` (the payment store will use it). Asserted.
- **Entrance:** the full (first) introduction now plays the existing `boss_roar` sound and a short screen dip (a self-freeing overlay at canvas layer 90, 45% at most). Lengths (3 s, quick 1.2 s) and the caption text are unchanged. The boss name already shows through the existing boss bar, so nothing was added to the HUD.
- **After the fall:** a second caption "Whatever they moved is behind the command room." follows "The Warden falls." (Area D fight only). No payment is recovered and no objective was changed.
- **Not changed:** attack data and mechanics (`boss_fairness_check` still 94/0). **Still unverified:** the fight has not been played by a person; the new roar and dip have not been seen or heard.
