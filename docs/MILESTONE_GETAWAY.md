# Milestone 12 (Opening series): The Getaway. The payment, the escape and the beginning of something bigger

Status date: 2026-11-14. This is the brief, the inspection it asks for (done here from the real project), and a plan. **Nothing for this milestone is built.** It follows "The Warden" (`MILESTONE_WARDEN.md`) and is the last of the opening arc. It is not `MILESTONE_012.md` (the complete-game milestone). Legend: **Exists**, **Partial**, **Not built**, **Verified**, **Not tested**.

## 1. The actual location of the payment bag: it does not exist yet
The brief asks to "identify the actual location of the payment bag using the existing story and level design" and not to assume a room. After searching the scripts, resources and docs: **no part of the existing game mentions a payment bag.** There is no item (`resources/items/` has no bag, gold or diamonds), no quest, no document, no placed prop and no flag. The only bag in the project is the procedural prop `TreasureBag` built inside the opening cinematic (`opening_cinematic.gd`, `_build_bag()`) and the bag in the beach mini-scene. Where the bag ends up is therefore a **new story fact that has to be authored**, and it is the single decision on which Milestones 7 to 12 all depend. Candidates that fit the existing map:
| Candidate | Fit |
|---|---|
| Area D's hidden back room (north-west of the command building) | already exists, small, screened by cover, holds the optional "Missing security log"; the Warden fight ends in the same building, so "beyond the Warden" is literal |
| A new short passage behind the command console | needs geometry; risks being a new area |
| The Dead Coast (the region after Outpost 17) | contradicts "recovered only in Milestone 12 after the Warden" if the player has to leave the region |
| The Research Complex | far later in the campaign; not plausible as a "short journey" |
Recommendation: the hidden back room, extended with a sealed store door that opens when the Warden falls.

## 2. Inspection report
| Piece | What exists |
|---|---|
| Warden victory | `BossIntro._on_any_warden_defeated`: flags `boss_warden_defeated` and `warden_d_defeated`, the seal opens, the caption "The Warden falls."; loot from `warden_loot.tres`; the objectives "Take the Warden's signature reward" and "Contact the outside from the command terminal" |
| Progression after the Warden | the command terminal unlocks: "Uplink open. Relaying your position to the outside." and "Signal confirmed. The outside can hear you now." The earlier military terminal said "Signal traced to a relay on the Dead Coast. Coordinates uploaded." The bridge quest `leave_outpost` ("The Road South": "The signal did not end at Outpost 17. It repeats from the south, past the beach gate, on the Dead Coast.") is pinned, and `CampaignFlow` opens the road when the region's bosses are down |
| Escape routes, vehicles, geography | the road south to the Dead Coast; the Dead Coast has a wrecked freighter, a lifeboat, docks, hulls, a cove and a smugglers' shack, but **no working vessel**; the island regions run Outpost 17 → Dead Coast → Blackwood → Research Complex → Iron Fortress |
| Existing ending | `scripts/story/campaign_ending.gd`: the **campaign** ending after the Director, with beats, statistics, a choice (explore or menu) and a replay mode; it sets `campaign_complete` and `ending_seen`. It is the end of the whole game, not of the opening arc |
| Inventory and pickups | `Pickup`, `Inventory.collect/add_item`, `item_collected`, currency (credits), unique-claim; no "payment" currency and no bag item |
| Quest system | `QuestManager` (event objectives, `tracker_first` pin, region tagging); item objectives work off `ITEM_COLLECTED`; "take" and "interact" objective types exist |
| Cinematic and dialogue | `StoryIntro`/`OpeningCinematic`/`OpeningBeach` pattern (pause, skip, `finished` once); captions and a radio line system; no dialogue trees |
| Save and checkpoints | atomic save, per-region state, `PersistentIds`, `Checkpoint` interactables |
| Escape obstacle in the lore | the story already provides one: the signal leads to the Dead Coast and then a chain of facilities; the outside can only be contacted via relays, and the later Iron Fortress holds the Director. The Dead Coast documents describe an abandoned operation and a shipment |

## 3. Mapping the brief to what exists
| Brief item | Status |
|---|---|
| Warden victory leads into a final section | **Partial.** The seal opens and the terminal unlocks; there is no door or passage beyond the boss |
| Journey to the deeper area, a final restricted store | **Not built** (see section 1) |
| Environmental evidence connecting the place to the stolen bag | **Not built** |
| Recognizable original bag | **Partial.** A procedural bag exists in the cinematic code and can be reused as a 3D prop so the same shape, colour and coin discs appear |
| Visible recovery: recognize, check contents, react, secure | **Not built.** Needs a small scripted moment: a camera push, a caption (one line in his voice), a prop animation, an inventory addition. **No animations exist** for crouching or opening a bag, so it would be camera, caption and a prop lid, not a rigged action |
| "Not a generic loot container" | **Met by design** if built as a story interaction rather than a `SupplyCrate` |
| Award only after the interaction | **Buildable**: a dedicated interactable that grants through `Inventory` and sets a saved flag; no award path exists today |
| Escape obstacle emerging from the lore | **Partial.** The relay and Dead Coast direction are in the data; an obstacle for "leaving Outpost 17" must be chosen: the road is open after the Warden by design, so the obstacle would have to be an event, for example the facility's alarm or a lockdown closing the beach gate until a breaker is thrown |
| Short final playable section, limited encounter, reach a direction-setting place | **Partial.** The compound already holds all the space; a small lockdown fight at the gate is possible |
| Ending cinematic: closes the arc, payment in hand, island more complicated, next goal is to leave, more beyond Outpost 17 | **Not built.** A new, short `OpeningEnding` in the style of the other opening scenes is the natural form; it is not the campaign ending |
| Objective chain (reach the deeper area, find, recover, find a way out, reach the next destination) | **Partial.** The last step already exists (`leave_outpost`); the others are new quests or objectives |
| Ending title or transition; do not auto-start a region | **Buildable.** The region transition is manual through the road gate; the existing flow does not start Dead Coast automatically |
| Continue and main menu intact; ending only once; no bag duplication; save/load preserves it | **Buildable and testable** with the flag and `PersistentIds` pattern used elsewhere |

## 4. Story conflicts to report (not to invent around)
1. **No payment anywhere in the lore.** The bag has no supply-chain explanation: why did a guard and two workers carry it to a facility that runs secret trials? A believable line (a "salvage and recovery" rule for anything washed ashore, a manifest entry) is new text and should be checked against the Dead Coast documents about an abandoned shipment.
2. **The existing First Signal ends by contacting the outside**; the brief's ending says the protagonist still has not escaped and must find a way off the island. These are compatible only if "contact the outside" is reworded as reaching a relay, not as a rescue.
3. **The campaign ending (after the Director) also uses "the outside" and a witness aboard a transport**, adjusted under M12 for the thief canon; the opening ending must not preempt it.
4. **The two Warden sites** (see `MILESTONE_WARDEN.md`) affect "victory leads into the final section".

## 5. Planned work
| Phase | Work | Status |
|---|---|---|
| 0 | Prerequisites: every earlier opening plan; the decision on the bag's location; the Warden decisions | not started |
| 1 | The payment prop (a shared `PaymentBag` scene reusing the cinematic's shape) and the item(s): a quest item `payment_bag` plus a currency grant, nothing granted before the interaction | not started |
| 2 | The store: a sealed door in Area D's hidden room, opened by `warden_d_defeated`, with a small cache and the bag on a shelf; environmental evidence (a manifest line, a worker's marking) | not started |
| 3 | The recovery moment: interaction with a camera push, a one-line caption, the lid opening, inventory change, a flag `payment_recovered` (<= 48 chars) saved once, an item toast | not started |
| 4 | The obstacle: an alarm and a short lockdown at the beach gate, with a few guards using existing configs, a breaker to throw; no wave; ends at the gate | not started |
| 5 | The ending scene: a short skippable `OpeningEnding` (pause, skip, `finished` once, plays once, not replayed on Continue), title card, no automatic region start | not started |
| 6 | Objectives chain in the quest data; the last step handed to `leave_outpost` | not started |
| 7 | Tests: the bag cannot be granted before the interaction or twice; save and load at each step; the ending fires once; Continue and the main menu work; regression of the campaign suites | not started |
| 8 | Human playtest; Windows and browser checks; report | needs you |

## 6. Risks and honest limits
- The whole arc leans on a destination for the bag that does not exist in the lore; building any of Milestones 7 to 12 before settling it risks rework.
- No animations for the recovery; the moment will be a camera and caption sequence on a prop, not a performance.
- The brief's escape obstacle (alarm and lockdown) has no precedent in the map and would be new code on existing doors.
- Everything before this milestone in the opening series is unplanned in code or unplayed.
- Pacing and satisfaction can only be judged by a person.

## 7. Acceptance tracking
All twelve criteria in the brief are **not started**. Criteria 10 and 11 (save/load preserves the ending; Continue and menu intact) hold today for the existing campaign ending and saves by the regression, and would need new tests for the opening ending. Criterion 4 (visible recovery of gold and diamonds) is blocked until the bag item, the store and the recovery moment exist.
