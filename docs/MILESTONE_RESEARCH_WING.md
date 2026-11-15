# Milestone 8 (Opening series): The Research Wing. Experiments, restricted records and escalating danger

Status date: 2026-11-14. This is the brief, the inspection it asks for (done here from the real project), and a plan. **Nothing for this milestone is built.** It follows "The Search" (`MILESTONE_THE_SEARCH.md`, plan only). Legend: **Exists**, **Partial**, **Not built**, **Verified**, **Not tested**.

## 1. The central finding: "the existing research wing" is two different things
The brief tells the builder to "reuse the existing research wing" of Outpost 17. The project has two candidates, and they are not the same:

| Candidate | Where | Size and content | Where it sits in the campaign |
|---|---|---|---|
| **Area C, Research Access Facility** (inside Outpost 17) | `scripts/world/outpost17.gd`, z -30 to -62 | a checkpoint desk, an open storage room, a control room with the military terminal, a generator shed, a cover barrier, a few crates; about 45 by 32 m, mostly greybox walls | the second half of the first region; reached through `DoorBC` |
| **The Research Complex** (a separate region) | `resources/regions/research_complex.tres`, `scripts/regions/research_complex/` | six areas: Research Perimeter, Administration Wing, **Medical Research Wing**, Containment Sector, Central Research Laboratory, Underground Exit; four missions; sixteen story documents; Subject Zero and the Facility Commander; three puzzles; a floor hazard; persistence tests (79, 75 and 38 checks) | **the fourth region**, behind `research_complex_unlocked`, set by Blackwood's third mission. Its road leads on to the Iron Fortress |

Everything the brief describes (restricted access, laboratory infrastructure, observation areas, secure storage, research personnel, test records, restricted personnel files, observation chambers, medical or biological material, signs of coerced workers, stronger resistance, narrow corridors against open testing rooms, cover) **already exists in the Research Complex**, and the Research Complex's story (section 5 of `RESEARCH_COMPLEX.md`) is exactly the "first disturbing revelation": deliberate, organised experiments on subjects who never consented; the containment failure was an order, not an accident; Project Black Site is bigger than this facility. Outpost 17's own Area C has none of this; it has a log and a terminal about a damaged comms panel.

So there are three honest ways to meet the brief, and the choice is a story and scope decision for you, not a code detail:

| Option | What it means | Cost and risk |
|---|---|---|
| **A. Treat Area C as the wing (small)** | Dress Area C with laboratory props, add a few documents and one stronger encounter, and end on a short revelation using lore the game already has | Smallest; but Area C is a courtyard with three rooms, so it can give a taste of research, not a "wing" |
| **B. Move the Research Complex earlier** | Make the Research Complex region the second area of the campaign and keep the order Outpost 17 → Research Complex → ... by changing the unlock chain in `campaign_flow.gd` and the region data | It already is the content the brief wants, tested and persisted; the cost is campaign reordering: Dead Coast and Blackwood come later, their missions' story (a shipment and an abandoned operation; human experimentation leading toward the Research Complex) assumes the old order, and tests and documents assert the old chain |
| **C. Link them: a door from Outpost 17 into the Research Complex** | Keep the campaign order, but open a visible entrance in Area C that previews a slice (the Medical Research Wing and its records) as the first revelation, then returns the player to Outpost 17 until the later region unlocks | Needs a controlled preview of a region that is not unlocked yet (region travel and saved state rules), and risks showing content twice |

Recommendation: **Option A for gameplay, borrowing the Research Complex's own documents as wording references.** It does not duplicate a facility, does not reorder the campaign, and keeps the Research Complex's revelations fresh for when the player reaches it. If you want the full research experience early, Option B is the real answer and should be planned as its own campaign-reordering milestone.

## 2. Inspection report
### Existing content that can be reused (Option A)
Area C's storage room, control room and generator shed; its checkpoint and the `PatrolGroup` there; the Security log (the ordered breaker puzzle), the "Military record: Warden" and the optional "Missing security log"; the military terminal; the `LoreDocument`, `Terminal`, `Door`, `CardReader` and `SupplyCrate` components; loot tables; and the facility props the Research Complex builder uses (benches, tanks, cells, observation window) which can be reused as scene pieces rather than copied.

### Story material in the project (so nothing contradicts it)
- Outpost 17: a signal and research site; the Warden is an earlier experiment; the first mission names Project Black Site and the Director.
- Blackwood: human experimentation, pointing toward the Research Complex without revealing everything.
- Research Complex: the sixteen documents above; the Director appears by title only; "Project Black Site is bigger than this facility".
Any new text should echo these, not extend them: experiments on unwilling subjects, an order behind a containment failure, a bigger project elsewhere.

### Conflicts found
1. The brief puts the revelation about unconsenting experiments in Outpost 17, but the existing campaign delivers it in Blackwood and the Research Complex. Showing it early does not contradict the lore, but it **pre-empts** those regions' reveals.
2. Outpost 17's Area C document set (a damaged comms panel, a breaker order) is about power, not research.
3. The First Signal already contains the "Project Black Site" file near the end of the same region (see `MILESTONE_THE_SEARCH.md`), so a research revelation in Area C overlaps it.
4. "Existing NPCs": there are **no research personnel NPCs** in the project (no scientists, no dialogue trees); only guards, subjects and documents.

## 3. Mapping the brief to what exists (Option A)
| Brief item | Status |
|---|---|
| Transition from Milestone 7 into the wing | **Partial.** `DoorBC` and the Area C entrance exist; the new transition needs a restricted door tied to the Search's access card |
| A distinct look: restricted, advanced equipment, lab infrastructure, observation areas, secure storage | **Partial.** The dressing kit has generator and pipe pieces; the Research Complex has lab props in code that can be reused; no observation window or specimen prop exists in Area C |
| Research discoveries: documents, test records, restricted files, observation chambers, biological material | **Partial.** Documents and terminals are supported; none of this text is written for Area C. Existing Research Complex entries can guide tone |
| Workers used against their will | **Not built** in Outpost 17; present in the Research Complex's documents |
| Terminals useful at a glance | **Exists** as a component (title and a short body) |
| Stronger resistance than the compound, using narrow corridors and open rooms | **Partial.** Heavy, elite and ranged configs exist; the Research Complex configs already carry the new tactics. Outpost 17's enemies are bare scenes without configs |
| Loot through existing systems | **Exists** |
| Payment clue linked to the layout (a transport record or storage reference) | **Not built**; the destination is still undecided (see The Search) |
| One significant, incomplete revelation grounded in lore | **Not built** as an authored beat; text would be new, wording drawn from the existing documents |
| Objectives via the existing quest system, no duplicates | **Not built**; the existing First Signal chain overlaps |

## 4. Planned work (Option A)
| Phase | Work | Status |
|---|---|---|
| 0 | Prerequisites: the opening plans through The Search; a decision on Option A, B or C; the payment destination | not started |
| 1 | Dress Area C as a research space: observation window, specimen tanks, benches (reuse the Research Complex's builders), signage, tighter lighting | not started |
| 2 | Restricted access: a lab door opened by the card from The Search; test that the route is still walkable | not started |
| 3 | Documents and one terminal: four short entries (transfer record of workers to "Section R", a redacted subject sheet, a medical supply manifest, a duty note), wording consistent with the Research Complex's documents | not started |
| 4 | Encounter: one narrow-corridor fight and one open testing-room fight with existing configs (soldier, heavy, elite), tactics configs optional, no health inflation, plus a supply reward | not started |
| 5 | Revelation and trail: a final document or terminal screen showing that subjects are held against their will and that a "transfer to the lower level" took the cargo, leading to the next restricted place; objective text persisted | not started |
| 6 | Tests: every interaction changes real state; route probes; saves at each step; regression of `first_signal`, the Warden and `research_complex_*` suites | not started |
| 7 | Windows and browser checks, performance, report | not started |

## 5. Risks and honest limits
- The biggest risk is duplicating the Research Complex's story in a smaller, weaker form; the three-option decision above is the way to avoid it.
- Reordering the campaign (Option B) touches unlock flags, quest chains, journal text and many tests.
- No scientist NPCs or dialogue trees exist; "research personnel" can only be guards and documents.
- Outpost 17's enemies do not use the new tactics unless configs are added.
- Nobody has played the opening or the Research Complex with a controller and eyes; difficulty and pacing of 7 to 12 minutes cannot be judged without a person.
- Area C is a greybox; a "wing" feel needs props that exist only in code in the other region.

## 6. Acceptance tracking
All twelve criteria in the brief are **not started** as a unit. Criteria 3 (assets reused) and 10 (no major contradictions) are design intentions of Option A. Criterion 11 (save/load and progression) holds today by the full regression, and the Research Complex's own acceptance results are recorded in `RESEARCH_COMPLEX.md` section 7.

## Status after the compound build (2026-11-15)
Built in one pass for Milestones 7 to 10 (decisions in `OPENING_DECISIONS.md`): `scripts/world/opening_compound.gd` (`OpeningCompound`, hooked by one line in `outpost17.gd`), four quests (`opening_search`, `opening_research`, `opening_command_hall`, `opening_restricted`), and `tests/opening_compound_check.gd` (85 checks, 0 failed). Existing suites rerun on the change: dressing 47, world 61, world_progression 32, boss_intro 20, boss 20, patrol 24, patrol_retry 9, mission 50, quest 125, quest_chain 50, campaign_bot 34, campaign_flow 81, playthrough_bot 63, explosive_barrel 26, elite_strongholds 144, tactics_live 51, ai_scheduler 38, arena 49, run_tests 72, map 165, region 67, story_consistency 31, stage_* 32/53/40, boss_road 33, save 62, journal 85, ui_layout 56, opening_beach 27, boot 32: all 0 failed, 0 script errors.
Windowed screenshots were taken and looked at (guard station, annex window and door, dispatch hall with the hazard-striped command door); one sign hidden by a roof post was fixed. Nobody has played it by hand; frame rate in the capture (11 to 24 FPS) was measured in a software-rendered window under load and is not a budget figure.
Two small edits outside the new files: `tests/dressing_check.gd` skips interactables marked `behind_door` (the lab terminal and sheet are only reachable once the lab door is open; the new test proves reachability both ways), and `barrel_placement.gd` gained the gate-hall barrel (`op17_gate_hall`).
**This milestone (The Research Wing, Option A):** a walled annex in Area C's east yard (7.5 by 7.3 m): a translucent observation window, three specimen tanks with a glow, a bench, a cold floor plate, one or two teal lights (one on low quality and web), a door gated by the lab pass, a lab terminal (transfer log: 6 of 9 routed to Section R, consent blank) and a redacted subject sheet. Wording follows `RESEARCH_COMPLEX.md`; no project name beyond existing text. Two guards stand at the lab door. **Not built:** research personnel NPCs, medical stores as a separate room.
