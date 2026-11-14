# Milestone 2 (Opening series): Stranded. Beach awakening and the stolen payment

Status date: 2026-11-14. This is the brief, an audit of the shipped beach sequence (`OPENING_BEACH.md`) against each section and acceptance criterion, and the list of gaps. It is **not** `MILESTONE_002.md` (the stylized visual upgrade). Legend: **Implemented**, **Partial**, **Not built**, **Verified** (a test or screenshot), **Not tested**.

**Headline finding from this audit: the shipped opening has a defect that can leave the player unable to attack for the whole game.** The survival quest needs three items, and the restrictions (attacks locked, 0.55 speed) are lifted only when all three are collected. The medkit exists in Outpost 17 supply crates, but **no pickup for the salvaged jacket or the wooden stick is placed anywhere in the world** (a search of every script, scene and resource finds them only in the item files, the quest file, the balance table and `opening_beach.gd`). The 120 s failsafe grants the stick but not the jacket, so the quest cannot complete through play, and the restrictions never lift. The automated test (`opening_beach_check`) did not catch it because it hands the items to the inventory directly instead of finding them in the world. The earlier "Done, tested" label on the opening was too generous for this part. See section 7 for the fix.

## 1. Scope
The first minutes on the island: waking on the beach, seeing the bag taken, getting control, finding supplies and a weapon, a first objective. No outpost, no name, no larger mystery, no antagonist, no hero framing. Out of scope: hunger, thirst, crafting.

## 2. Story canon
The protagonist is a thief, paid in gold and diamonds, wrecked by a hurricane, with no knowledge of the island. His aims are to survive, recover his payment, and escape. He does not care about the workers.

## 3. What was built (see `OPENING_BEACH.md` for the mechanics)
`scripts/story/opening_beach.gd` runs after the cinematic: a black fade, a short scripted mini-scene in its own `SubViewport` (sand, three wreckage pieces, a palm with the bag, the protagonist lying down, a guard and two workers who take the bag and walk off), a single caption ("Get up."), then a handoff to the real player at 35% health, speed ×0.55, attacks locked, with the quest `opening_survival` pinned.

## 4. Sections of the brief against the build
| Brief section | Status |
|---|---|
| 3. Waking up: lying, eyes opening, struggling, sitting up, holding his side, looking around; close cinematic camera | **Partial.** A fade-in and a flat capsule stand-in lying down. **No waking, sitting, side-holding or looking animations**; the real rigged player is not used. Whether the project even has lying or injured clips was not found; the earlier audit (`OPENING_EXPERIENCE.md` section 4) listed them as missing |
| 3. Wreckage, wet sand, waves, vegetation, hurricane damage | **Partial.** Three wreckage boxes, sand, a palm, shore in a procedural mini-scene; no wet-sand look, no vegetation beyond one tree, no wave motion beyond what the scene draws |
| 4. Bag glimpse: bag caught in a tree, recognizable as the same bag | **Implemented** (a bag in a palm); recognizable by shape and the coin discs, judged by screenshot only |
| 4. Guard orders two exhausted workers; they take the bag and leave through the vegetation, destination hidden | **Partial.** A guard and two workers walk in, take the bag and walk off along the shore. **No ordering gesture, no exhausted or frightened body language** beyond a linear walk; stand-in capsules |
| 4. No outpost, name, layout, leadership or backstory | **Met and verified**: the mini-scene is a separate world with no outpost geometry |
| 5. Player takes control after a transition from the injured pose | **Partial.** Control is handed to the real player after the fade, with reduced speed and locked attacks. There is **no injured-to-standing animation transition** and no limp |
| 5. Nearby interactables: medical supply, clothing, stick | **Not met in the world.** See the headline finding. The items and the quest objectives exist; placing them on the beach was never built |
| 5. Pickup animation and UI notification, real inventory | **Partial.** The pickup path (`Pickup` to `Inventory` to `item_collected` to the quest) is real and the existing item toast is used; **no pickup animation** |
| 5. Weapon usable when equipped | **Implemented, verified** by test (auto-equip on collect; attacks unlock on quest completion), subject to the defect above |
| 6. Objective "Recover your payment." | **Not built.** The pinned quest is "find medical supplies / find something to wear / find something to defend yourself". **No objective mentions the payment**, and nothing points inland |
| 6. Directional hint only if needed | **Not built** |
| 7. Fast action feel, no survival simulation | **Met.** No hunger, thirst or crafting were added |
| 8. Audio: waves, wind, fading thunder, creaking, breathing, tension | **Partial.** The beach ambience crossfade from the cinematic plays; **no creaking, breathing, pain or tension sounds** |
| 9. Camera returns to gameplay, controls restored | **Implemented** for the pause and layer handling, tested for flags and values; the camera was never separately a cinematic camera in the real world |
| 9. Persistence of health and inventory | **Verified for inventory and health through the existing save path**; not run through a real quit and continue by a person |
| 9. Cannot play twice on load or continue | **Implemented, verified** (`should_play_intro()` gating unchanged and its truth table is tested) |
| 9. Skip and reload do not break it | **Partly verified.** Skip is implemented and its input handling is tested; skipping mid-walk is not covered by a test |
| 9. Windows and browser | Windows export smoke test only; **browser not tested** |

## 5. Acceptance criteria
| # | Criterion | Status |
|---|---|---|
| 1 | Player wakes on the beach | **Partial** (a fade-in, not a wake) |
| 2 | Injury and recovery communicated by animation | **Not met** (a caption and a speed/lock penalty, no animation) |
| 3 | Destroyed speedboat visible | **Partial** (wreckage boxes; no recognisable boat remains) |
| 4 | Payment bag recognizable | **Implemented** |
| 5 | Guard and two workers retrieve the bag | **Implemented** (scripted stand-ins) |
| 6 | Group disappears without revealing the outpost | **Implemented, verified** |
| 7 | Player regains control | **Implemented**, with restrictions that may never lift (defect) |
| 8 | Player can explore the wreckage | **Not met** for the items; no explorable wreckage pickups exist |
| 9 | Medical supplies and a weapon collected via real inventory systems | **Not met in play**; met only in the test that injects the items |
| 10 | Objective "Recover your payment" displayed | **Not met** |
| 11 | Player can continue exploring inland | **Met** in the sense that the world is open; no hint |
| 12 | Existing gameplay systems remain functional | **Verified** (full regression, 97 suites) |

By the brief's rule this milestone is **not complete**.

## 6. Known limitations
- Stand-in capsules for the protagonist, guard and workers; no rigged animation of any kind in the sequence.
- Not placed in the world: jacket, stick (and a dedicated medkit).
- The payment objective, the hint, creaking and breathing sounds, a pickup animation.
- Not run in a browser; never played by a person end to end.

## 7. Fix plan (and status)
1. Place three pickups with `Pickup.spawn` near the player's start position when the handoff runs (medkit, jacket, stick), on solid ground, not blocking any route, with ids that survive saving.
2. Make the 120 s failsafe grant every missing item, not only the stick, so the quest can always complete.
3. Add a first tracked objective "Recover your payment" that stays pinned above the survival quest, with a clear note that it completes later, and make sure the old campaign flow does not conflict with it. A decision is needed on where it ends: the brief says only that the bag must not be tied to a destination.
4. Extend `opening_beach_check` so the items must exist in the live world after the handoff, not be injected into the inventory.
5. Later, with the real rig: waking, sitting, limp and pickup animations, and breathing and creaking sounds.

Status of this plan is recorded in `OPENING_BEACH.md` when it is done. Nothing in this list is built at the time of writing.
