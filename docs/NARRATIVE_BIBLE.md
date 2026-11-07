# Narrative Bible: Lost Horizon: Black Site

Status date: 2026-11-07. Compiled by reading the in-game text, not the summaries. Every statement is tagged with its source file. **Proposed** marks anything this document adds; it changes no game text. Where the sources disagree, see `CAMPAIGN_AUDIT.md` section 5. The Iron Fortress is **not in `master`** when this was written (no region scene, no quests, no documents); only its boss and enemy configs, captions in `scripts/ai/director.gd` and the plan in `MILESTONE_009.md` exist, so Acts IV and V are partly **proposed**.

## 1. Sources used
`docs/STORY.md` (the original four-quest layer, partly stale), `docs/STORY_AND_MISSION_FLOW.md`, `scripts/story/intro.gd` and `ending.gd`, `scripts/world/world_flow.gd`, `scripts/world/outpost17.gd`, `scripts/world/boss_intro.gd`, `resources/quests/**/*.tres` (captions and objectives), `scripts/regions/dead_coast/dead_coast_content.gd`, `scripts/regions/blackwood/blackwood.gd`, `scripts/regions/research_complex/research_complex_story.gd`, `scripts/regions/campaign_flow.gd`, `scripts/ai/director.gd`. The 39 story documents are listed in `CAMPAIGN_AUDIT.md`.

## 2. Protagonist
- Unnamed; no gender, age or background is stated anywhere. [intro.gd]
- Survives a transport lost in a storm: "A storm hit the transport without warning." "The ship broke apart in the dark." "Everything after that is gone." "You wake on a beach among the wreckage. No weapon. No radio. No memory of how you got here." [intro.gd CAPTIONS]
- Has no weapon worth the name (the starting item is the improvised blade, `inventory.gd` STARTING_WEAPON), is guided by a weak signal from Outpost 17. [intro.gd, first_signal.tres start captions]
- **Gap:** why the protagonist was on that transport, and any connection to the operation, is never stated. `MILESTONE_009.md` asks the Iron Fortress to say "why the protagonist became involved"; nothing in the game says it yet. **Proposed:** the protagonist was aboard because the transport was carrying someone or something the organization wanted moved; decide with the owner before writing it.

## 3. Island and military history
- The island hosts a secret military organization's installations: Outpost 17, a coastal route, a jungle annex, a research facility and a command stronghold behind "the iron gate". [world docs; rc_black_site_data]
- The island has a coast road with a checkpoint ordered to wave through trucks stencilled "BS" without inspection. [dead_coast_log_checkpoint_orders]
- Locals were paid to look away ("The uniformed ones pay double to be forgotten"), and a supply depot was built for a coast that "nobody came back to hold". [dead_coast_log_cove_ledger, dead_coast_log_depot_inventory]
- **Gap:** nothing states when the installations were built, what the island was before, or who the organization answers to above the Director.

## 4. The military organization
- Called "the island's command" and "the command"; a headquarters inland "behind the iron gate". [rc_director_order, rc_black_site_data]
- Chain: the Director "answers to no one on this island"; Project Black Site "answers to the Director". [rc_black_site_data]
- Outposts carry out orders without question: "NO RECORDS. NO QUESTIONS." signed "Commander's office, Outpost 17". [dead_coast_log_checkpoint_orders]
- Standard practice is secrecy and plausible deniability: Blackwood is "a training area. Nobody asks twice." [bw_log_director_note]
- **Gap:** the organization has no name. **Proposed:** keep it unnamed and refer to "the command".

## 5. Project Black Site
- "Live trials on the island, run under the Director." "Outpost 17 exists to keep the trials quiet." [log_project_black_site]
- Abbreviation "BS" on crates and routes, as in "BS 4 / 9": consignments 4 of 9 were shipped, contents "LIVE FEED, RESTRAINTS, SEDATIVES", authorised by the Director. [dead_coast_wreck_hull, _log_black_site_link]
- "Project Black Site cannot lose another batch." [dead_coast_log_black_site_link]
- The programme recruits "volunteers" filed under logistics, not personnel; "Compartment 7 is not discussed outside Compartment 7." [rc_staff_memo]
- The first-generation compound "was a test of what the body can be made to endure"; it is stable "only in the second generation"; "Phase two cannot be run here. Equipment is being moved to the command. We were the proof of concept." [rc_lab_notes]
- The research data sections: A to C logistics and transfers, D medical trials, E containment, F Project Black Site. [rc_archive_terminal]

## 6. Research operations and the subjects
- The Blackwood annex ran an earlier site: Subject 14 (transferred from the coast hospital, no next of kin), dose four, "speech lost on day nine, strength gain beyond projection"; the medical officer asked to be reassigned; a subject list of fourteen crossed-out names, "Moved down to Sublevel 1" under 14, "Not yet" under 15. [bw_log_experiment_1, bw_log_subject_list]
- The Research Complex held 31 numbered subjects, 22 of them soldiers reported missing in the field, the rest "found"; "consent, none recorded". [rc_subject_roster, rc_archive_terminal]
- Dr. Hale records that the compound "does not stop"; Subject 11 no longer answers; Subject 14 answered "for four days"; Hale "asked to stop at subject nineteen". [rc_medical_evidence]
- Signs of restraint and an unexplained transfer order in the medical wing. [rc_exam_note, rc_ward_notice]
- A second signal exists: a flat voice counting grid squares of the research site map every night. [bw_log_tech_notes]
- **Gap:** who or what the counting voice is; what the compound is.

## 7. The containment failure
- Incident 0214: "The cell locks were not broken. They were released from the control level at 02:14, in sequence, one block at a time." "It recorded an order." The release was authorised with a command key. [rc_incident_report]
- The official finding is "equipment failure"; "The Director's office has asked that this page not be copied." [rc_incident_report]
- "Lockdown was ordered from below. Not from here." [rc_security_console]
- The Director ordered it reported as an accident, with no inquiry and no survivors' statements, and all data copied to the command. [rc_director_order]
- Staff stopped coming out "three weeks ago". [rc_checkpoint_log]
- **Gap:** who used the command key and why; whether the release was sabotage by staff, by a subject, or by the Director. **Proposed:** keep it open for the Iron Fortress records (the Director, or someone using his key, released the subjects to destroy evidence).

## 8. The Warden and the Director
- **The Warden:** Sgt. Aldous Venn, decorated, declared killed in action, re-enrolled into Project Black Site as a "Warden-class patient", pain response suppressed, loyalty transferred to the Director. "The first subject to keep his mind." [log_military_record, log_project_black_site] He holds the command room at Outpost 17; his line is "This is as far as you go." [boss_intro.gd] Outpost 17's missing security log: "The Warden answers only to the Director." [log_missing_security]
- **The Director:** known by title only. He "authorised" the shipments, approved "the next phase", asked that the incident page not be copied, wanted the Blackwood annex "quiet until the next shipment clears Outpost 17". [dead_coast_log_black_site_link, rc_staff_memo, rc_incident_report, bw_log_director_note] "Signed with a title, not a name." [rc_director_order]
- In the boss captions the Director says "You were never meant to find this place." and "Every record burns. Every witness is a loose end. You are the last one." and the defeat line is "The Director falls." [director.gd LINES, DEFEAT_LINE]
- **Gap:** the Director has no name, face or motive stated beyond secrecy. **Proposed:** a man who authorized the experiments and managed both the military and the research sides (`MILESTONE_009.md`); his reason (why the experiments were conducted) is not yet in any text.

## 9. Characters named anywhere
| Name | Where | What is said |
|---|---|---|
| Sgt. Aldous Venn (the Warden) | log_military_record | decorated, declared killed in action, became a Warden-class patient |
| The Director | many | title only; authorises shipments and orders the cover-up |
| Dr. Hale | rc_medical_evidence | trial doctor who asked to stop at subject nineteen |
| R. Hale | dead_coast_data_device | signed the Blackwood shipping ledger (probably the same person: **unstated**) |
| Private Okoro | bw_log_patrol_2 | says "the animals went quiet before the first shot was fired" |
| "Static" | STORY_AND_MISSION_FLOW (design) | an unseen radio contact; not named in the game strings |
| Subjects 11, 14, 19 and numbers up to 31 | rc / bw docs | numbered subjects |
| CALLOWAY | dead_coast_wreck_hull | freighter name on the wreck |

## 10. Timeline (reconstructed; the game never states dates)
1. Project Black Site begins as live trials at a Blackwood annex and a research facility; first generation subjects (Subject 14 among them). [bw docs, rc_lab_notes]
2. Shipments labelled BS go out in numbered consignments (4 of 9 and more) by coast and through Outpost 17; the Director authorises them. [dead_coast docs]
3. The Warden becomes the first subject to keep his mind. [log_project_black_site]
4. Staff and guards stop coming out of the research facility ("three weeks ago"); Incident 0214 releases the cells; the Director orders it filed as equipment failure and the data moved to the command. [rc docs]
5. Outposts lose contact; patrols leave their posts; the Blackwood patrol camp is abandoned. [bw_log_patrol_1/2, outpost checkpoint log]
6. A transport carrying the protagonist is lost in a storm; the protagonist wakes on the Outpost 17 beach. [intro.gd]
7. **Proposed:** the Iron Fortress holds the Director and the remaining Project Black Site records; the protagonist reaches it through the recovered route table. [rc_black_site_data]

## 11. Major revelations by act (as implemented and as proposed)
| Act | Region | Revelations in the game today | Missions |
|---|---|---|---|
| I Discovery | Outpost 17 | the island is not abandoned by accident; Project Black Site, the Warden and the Director are named; the Warden is a former soldier | `first_signal` (15 objectives), arena chain, bridge quest `leave_outpost` |
| II Investigation | Dead Coast, Blackwood | secret shipments (BS 4 of 9), a blind checkpoint, bought silence, Blackwood as the annex, a counting voice, subject lists | `dc_wreckage`, `dc_silent_checkpoint`, `dc_lost_cargo`; `into_the_blackwood`, `ghost_frequency`, `experimental_site` |
| III Experiments | Research Complex | consent was never recorded; 31 subjects, 22 soldiers; the containment failure was an order; the compound; the data route to the command | `rc_restricted_zone`, `rc_silent_records`, `rc_containment_breach`, `rc_project_black_site` |
| IV Confrontation | Iron Fortress | **not in master.** Proposed per `MILESTONE_009.md`: the Director's identity and purpose, the command's records, who used the key | planned five missions |
| V Consequences | Iron Fortress control facility | **not in master.** Proposed: the Director fight, the ending | planned mission 5 |

## 12. The ending as currently designed
- **No campaign ending exists.** The only ending is the original arena ending: finishing the optional arena quest `final_transmission` plays "The transmission is out. The story continues..." with credits and a Play Again button. [ending.gd, quest_manager.gd FINAL_QUEST] This can fire mid-campaign (see the audit, contradiction 1).
- The first mission ends with "Signal confirmed. They know you're alive now. Move." and the command terminal: "Uplink open. Relaying your position to the outside." / "Signal confirmed. Project Black Site is no longer a secret." [first_signal.tres, outpost17.gd]
- The Director's defeat sets the flag `iron_fortress_director_defeated` and shows "The Director falls." [director.gd]; no scene follows it.
- **Proposed ending** (for Milestone 10, owner to approve): after the Director falls, a short radio exchange confirms the transmission reached the outside; a results screen; the compound's trial records are the evidence; the island's command is exposed but not fully destroyed; credits; return to the world with post-campaign exploration. Keep one thread open: the identity of the counting voice from the Blackwood.

## 13. Open questions reserved for optional future content
- Who the counting voice in the Blackwood is. [bw_log_tech_notes]
- What happened below "Sublevel 1" and why "Not yet" is written under Subject 15. [bw_log_subject_list]
- Whether Dr. Hale and "R. Hale" are the same person and why a doctor signed a shipping ledger.
- What the other consignments of the series carried: the manifest is "Consignment 4 of 9", forty sealed containers, weight not matching the declared contents.
- What the Director's superiors, if any, know.
- Whether other Warden-class patients exist.
