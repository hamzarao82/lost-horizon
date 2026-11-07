# Campaign Audit

Status date: 2026-11-07. Generated from the project, not from documents: `tools/campaign_audit.gd` (read-only) prints section 2 below; `tests/story_continuity_check.gd` (460 checks) re-runs the structural checks. Nothing here edits a game file. The Iron Fortress is **not in `master`**; this audit covers Outpost 17, Dead Coast, Blackwood and the Research Complex.

## 1. Result in one paragraph
Structure is sound: 15 quests, 99 objectives, 4 region data files (three load their own scene; Outpost 17 lives inside Main), 39 story documents, no duplicate quest or document ids, every reward item exists, every prerequisite and next-quest link resolves, every flag obeys `[a-z0-9_]` and 48 characters, and every flag the quests, regions and the unlock chain depend on has a producer in code. Producer checks are **text heuristics** (a literal in a script, or a confirmed dynamic pattern such as `patrol_<id>_cleared`), not proof that the code path runs; the campaign bots prove behaviour. The real problems are narrative, not structural: see section 5. The most serious is that the old arena ending can still fire in the middle of the campaign.

## 2. Missions, regions, flags and documents (tool output)
### Quests (15 files)
| region | quest id | title | category | required | optional | rewards | prerequisites | next | flag objectives |
|---|---|---|---|---:|---:|---|---|---|---|
| blackwood | experimental_site | The Experimental Site | MAIN | 7 | 2 | credits_medium, credits_medium, upgrade_kit_weapon, blackwood_ghost_charm |  |  | blackwood_site_defenders_cleared, blackwood_research_complex_access, doc_bw_log_subject_list_found |
| blackwood | ghost_frequency | Ghost Frequency | MAIN | 6 | 1 | credits_medium, armor_plate, electronics |  | experimental_site | blackwood_comms_power, blackwood_transmissions_read, blackwood_black_site_link, doc_bw_log_tech_notes_found |
| blackwood | into_the_blackwood | Into the Blackwood | MAIN | 5 | 1 | credits_medium, bandage, bandage |  | ghost_frequency | blackwood_ambush_cleared, doc_bw_log_patrol_1_found, doc_bw_log_patrol_2_found |
| outpost_17 | broken_perimeter | Broken Perimeter | MAIN | 2 | 0 | health_potion, health_potion | restore_power | final_transmission |  |
| outpost_17 | leave_outpost | The Road South | MAIN | 1 | 0 |  | first_signal |  | dead_coast_arrived |
| dead_coast | dc_lost_cargo | Lost Cargo | MAIN | 5 | 3 | coastal_weapon_part, credits_medium | dc_silent_checkpoint |  | patrol_dead_coast_camp_cleared |
| dead_coast | dc_silent_checkpoint | The Silent Checkpoint | MAIN | 5 | 1 | armor_patch, credits_medium | dc_wreckage | dc_lost_cargo | dead_coast_route_pass, patrol_dead_coast_checkpoint_cleared |
| dead_coast | dc_wreckage | Wreckage | MAIN | 6 | 1 | upgrade_kit_weapon, credits_medium |  | dc_silent_checkpoint | patrol_dead_coast_beach_cleared |
| outpost_17 | final_transmission | The Final Transmission | MAIN | 2 | 0 | health_potion | broken_perimeter |  | has_keycard |
| outpost_17 | first_signal | The First Signal | MAIN | 15 | 1 | combat_knife |  | restore_power | has_access_card, comms_power_on, next_location_unlocked, patrol_d_guards_cleared, boss_warden_defeated |
| research_complex | rc_containment_breach | Containment Breach | MAIN | 6 | 2 | credits_medium, credits_medium, upgrade_kit_armor |  | rc_project_black_site | research_complex_containment_done, research_complex_subjects_cleared, research_complex_elite_down, doc_rc_override_notes_found, rc_cache_medical_taken |
| research_complex | rc_project_black_site | Project Black Site | MAIN | 8 | 1 | credits_medium, credits_medium, upgrade_kit_weapon, electronics |  |  | research_complex_lab_power_done, research_complex_lab_security_cleared, research_complex_next_lead, door_rc_service_hatch_open, doc_rc_lab_notes_found, doc_rc_director_order_found |
| research_complex | rc_restricted_zone | The Restricted Zone | MAIN | 5 | 1 | credits_medium, bandage, armor_patch |  | rc_silent_records | research_complex_perimeter_pass, credential_admin, door_rc_admin_door_open, rc_cache_perimeter_taken |
| research_complex | rc_silent_records | Silent Records | MAIN | 7 | 3 | credits_medium, antiseptic, electronics |  | rc_containment_breach | research_complex_security_online, research_complex_archive_power, research_complex_records_retrieved, credential_medical, research_complex_ambush_cleared, rc_cache_admin_taken, doc_rc_staff_memo_found, doc_rc_exam_note_found, doc_rc_ward_notice_found |
| outpost_17 | restore_power | Restore Power | MAIN | 2 | 0 | light_tactical_armor | first_signal | broken_perimeter | power_on |

Total objectives: 99

### Regions (4)
| region | name | scene | scene loads | unlock flag | flag producer |
|---|---|---|---|---|---|
| blackwood | Blackwood | res://scenes/regions/BlackwoodRegion.tscn | true | blackwood_unlocked | dynamic: CampaignFlow derives <region>_unlocked |
| dead_coast | Dead Coast | res://scenes/regions/DeadCoastRegion.tscn | true | dead_coast_unlocked | dynamic: CampaignFlow derives <region>_unlocked |
| outpost_17 | Outpost 17 |  | false |  | none needed |
| research_complex | Research Complex | res://scenes/regions/ResearchComplexRegion.tscn | true | research_complex_unlocked | dynamic: CampaignFlow derives <region>_unlocked |

### Campaign chain (CampaignFlow.CHAIN)
- dead_coast unlocks after `mission_first_signal_complete` (aliases: [])
- blackwood unlocks after `dead_coast_mission_3_complete` (aliases: [&"dead_coast_region_complete", &"dead_coast_cargo_complete"])
- research_complex unlocks after `blackwood_mission_3_complete` (aliases: [&"blackwood_region_complete", &"blackwood_research_complex_access"])

### Flags referenced by quests, regions and the chain (55)
| flag | referenced by | rule ok | producer |
|---|---|---|---|
| blackwood_ambush_cleared | quest into_the_blackwood objective survive_ambush | true | dynamic: BlackwoodEncounter sets blackwood_<id>_cleared (blackwood_encounter.gd:36) |
| blackwood_black_site_link | quest ghost_frequency objective black_site_link | true | literal in blackwood.gd |
| blackwood_comms_power | quest ghost_frequency objective restore_station | true | literal in frequency_puzzle.gd |
| blackwood_mission_3_complete | CHAIN research_complex after | true | literal in campaign_flow.gd |
| blackwood_region_complete | CHAIN research_complex alias | true | literal in campaign_flow.gd |
| blackwood_research_complex_access | CHAIN research_complex alias | true | literal in blackwood.gd, campaign_flow.gd |
| blackwood_site_defenders_cleared | quest experimental_site objective defeat_defenders | true | literal in blackwood.gd |
| blackwood_transmissions_read | quest ghost_frequency objective read_transmissions | true | literal in blackwood.gd |
| blackwood_unlocked | region blackwood unlock_flag | true | dynamic: CampaignFlow derives <region>_unlocked |
| boss_warden_defeated | quest first_signal objective defeat_warden | true | literal in objective_pointer.gd, boss_intro.gd, outpost17.gd |
| comms_power_on | quest first_signal objective restore_comms_power | true | literal in objective_pointer.gd, power_switch.gd, outpost17.gd |
| credential_admin | quest rc_restricted_zone objective get_credential | true | dynamic: AccessPanel sets credential_<level> (facility_ids.gd:10) |
| credential_medical | quest rc_silent_records objective medical_access | true | dynamic: AccessPanel sets credential_<level> (facility_ids.gd:10) |
| dead_coast_arrived | quest leave_outpost objective arrive_dead_coast | true | literal in campaign_flow.gd |
| dead_coast_cargo_complete | CHAIN blackwood alias | true | literal in campaign_flow.gd, dead_coast.gd |
| dead_coast_mission_3_complete | CHAIN blackwood after | true | literal in campaign_flow.gd |
| dead_coast_region_complete | CHAIN blackwood alias | true | literal in campaign_flow.gd |
| dead_coast_route_pass | quest dc_silent_checkpoint objective obtain_route_access | true | literal in dead_coast.gd, dead_coast_content.gd |
| dead_coast_unlocked | region dead_coast unlock_flag | true | dynamic: CampaignFlow derives <region>_unlocked |
| doc_bw_log_patrol_1_found | quest into_the_blackwood objective camp_logs | true | dynamic: LoreDocument sets doc_<id>_found |
| doc_bw_log_patrol_2_found | quest into_the_blackwood objective camp_logs | true | dynamic: LoreDocument sets doc_<id>_found |
| doc_bw_log_subject_list_found | quest experimental_site objective subject_list | true | dynamic: LoreDocument sets doc_<id>_found |
| doc_bw_log_tech_notes_found | quest ghost_frequency objective tech_notes | true | dynamic: LoreDocument sets doc_<id>_found |
| doc_rc_director_order_found | quest rc_project_black_site objective lab_papers | true | dynamic: LoreDocument sets doc_<id>_found |
| doc_rc_exam_note_found | quest rc_silent_records objective optional_docs | true | dynamic: LoreDocument sets doc_<id>_found |
| doc_rc_lab_notes_found | quest rc_project_black_site objective lab_papers | true | dynamic: LoreDocument sets doc_<id>_found |
| doc_rc_override_notes_found | quest rc_containment_breach objective override_notes | true | dynamic: LoreDocument sets doc_<id>_found |
| doc_rc_staff_memo_found | quest rc_silent_records objective optional_docs | true | dynamic: LoreDocument sets doc_<id>_found |
| doc_rc_ward_notice_found | quest rc_silent_records objective optional_docs | true | dynamic: LoreDocument sets doc_<id>_found |
| door_rc_admin_door_open | quest rc_restricted_zone objective unlock_admin | true | dynamic: Door sets door_<id>_open (door.gd:41) |
| door_rc_service_hatch_open | quest rc_project_black_site objective open_hatch | true | dynamic: Door sets door_<id>_open (door.gd:41) |
| has_access_card | quest first_signal objective find_access_card | true | literal in quest_manager.gd, objective_pointer.gd, encounter_group.gd, card_reader.gd, outpost17.gd |
| has_keycard | quest final_transmission objective take_keycard | true | literal in quest_manager.gd, keycard.gd, world_flow.gd |
| mission_first_signal_complete | CHAIN dead_coast after | true | literal in quest_manager.gd, campaign_flow.gd |
| next_location_unlocked | quest first_signal objective unlock_next_location | true | literal in quest_manager.gd, objective_pointer.gd, outpost17.gd |
| patrol_d_guards_cleared | quest first_signal objective defeat_command_guards | true | literal in objective_pointer.gd |
| patrol_dead_coast_beach_cleared | quest dc_wreckage objective defeat_beach_patrols | true | dynamic: PatrolGroup sets patrol_<id>_cleared (patrol_group.gd:23) |
| patrol_dead_coast_camp_cleared | quest dc_lost_cargo objective clear_raider_camp | true | dynamic: PatrolGroup sets patrol_<id>_cleared (patrol_group.gd:23) |
| patrol_dead_coast_checkpoint_cleared | quest dc_silent_checkpoint objective defeat_defenders | true | dynamic: PatrolGroup sets patrol_<id>_cleared (patrol_group.gd:23) |
| power_on | quest restore_power objective power_on | true | literal in teleport.gd, world_gate.gd, world_flow.gd |
| rc_cache_admin_taken | quest rc_silent_records objective admin_cache | true | dynamic: SupplyCrate sets <crate_id>_taken (supply_crate.gd:32) |
| rc_cache_medical_taken | quest rc_containment_breach objective medical_cache | true | dynamic: SupplyCrate sets <crate_id>_taken (supply_crate.gd:32) |
| rc_cache_perimeter_taken | quest rc_restricted_zone objective perimeter_cache | true | dynamic: SupplyCrate sets <crate_id>_taken (supply_crate.gd:32) |
| research_complex_ambush_cleared | quest rc_silent_records objective survive_ambush | true | literal in research_complex.gd |
| research_complex_archive_power | quest rc_silent_records objective restore_archive_power | true | literal in research_complex_outer.gd |
| research_complex_containment_done | quest rc_containment_breach objective restore_emergency | true | literal in research_complex_inner.gd |
| research_complex_elite_down | quest rc_containment_breach objective defeat_elite | true | literal in research_complex.gd, research_complex_inner.gd |
| research_complex_lab_power_done | quest rc_project_black_site objective restore_lab_power | true | literal in research_complex_inner.gd |
| research_complex_lab_security_cleared | quest rc_project_black_site objective lab_security | true | literal in research_complex.gd |
| research_complex_next_lead | quest rc_project_black_site objective learn_lead | true | literal in research_complex_inner.gd |
| research_complex_perimeter_pass | quest rc_restricted_zone objective perimeter_guards | true | literal in research_complex.gd |
| research_complex_records_retrieved | quest rc_silent_records objective retrieve_records | true | literal in research_complex_outer.gd |
| research_complex_security_online | quest rc_silent_records objective restore_security | true | literal in research_complex_outer.gd |
| research_complex_subjects_cleared | quest rc_containment_breach objective survive_subjects | true | literal in research_complex.gd |
| research_complex_unlocked | region research_complex unlock_flag | true | dynamic: CampaignFlow derives <region>_unlocked |

### Story documents (39)
| region | id | title | words |
|---|---|---|---:|
| outpost_17 | checkpoint_desk | Checkpoint log | 22 |
| outpost_17 | log_sequence | Security log | 18 |
| outpost_17 | log_military_record | Military record: Warden | 27 |
| outpost_17 | log_missing_security | Missing security log | 21 |
| outpost_17 | log_project_black_site | Project Black Site | 30 |
| dead_coast | dead_coast_wreck_hull | Freighter hull | 31 |
| dead_coast | dead_coast_log_wreck_manifest | Cargo manifest | 25 |
| dead_coast | dead_coast_data_device | Data device | 23 |
| dead_coast | dead_coast_log_checkpoint_orders | Posted orders | 21 |
| dead_coast | dead_coast_trail_markers | Drag marks | 21 |
| dead_coast | dead_coast_cargo_gear | Sealed equipment case | 24 |
| dead_coast | dead_coast_log_cove_ledger | Smugglers' ledger | 18 |
| dead_coast | dead_coast_log_black_site_link | Consignment sheet | 28 |
| dead_coast | dead_coast_log_watch_journal | Watch sergeant's journal | 34 |
| dead_coast | dead_coast_log_depot_inventory | Depot inventory | 29 |
| blackwood | bw_log_patrol_1 | Sergeant's log | 33 |
| blackwood | bw_log_patrol_2 | Torn page | 44 |
| blackwood | bw_log_frequency | Technician's frequency log | 47 |
| blackwood | bw_log_tech_notes | Technician's notes | 43 |
| blackwood | bw_log_director_note | Unsigned note | 29 |
| blackwood | bw_log_experiment_1 | Experiment record, Subject 14 | 41 |
| blackwood | bw_log_subject_list | Subject list | 20 |
| blackwood | bw_log_hatch | Maintenance note | 27 |
| research_complex | rc_checkpoint_log | Checkpoint logbook | 58 |
| research_complex | rc_visitor_log | Reception visitor log | 40 |
| research_complex | rc_staff_memo | Staff memo | 38 |
| research_complex | rc_security_console | Security network | 44 |
| research_complex | rc_archive_breaker | Archive power panel | 13 |
| research_complex | rc_archive_terminal | Research archive | 56 |
| research_complex | rc_medical_evidence | Trial notes, Dr. Hale | 52 |
| research_complex | rc_subject_roster | Subject roster | 20 |
| research_complex | rc_ward_notice | Ward notice | 30 |
| research_complex | rc_exam_note | Examination note | 29 |
| research_complex | rc_incident_report | Containment incident report | 61 |
| research_complex | rc_override_notes | Technician notes | 34 |
| research_complex | rc_lab_notes | Laboratory notes | 42 |
| research_complex | rc_director_order | Order, Director's office | 41 |
| research_complex | rc_black_site_data | PROJECT BLACK SITE: recovered data | 66 |
| research_complex | rc_exit_notice | Underground exit | 28 |

### Near-duplicate documents (word overlap >= 0.45)


### Broken dependencies reported by the tool: 0
Before the dynamic flag patterns were added the tool listed 13 candidates (patrol clears, door-open flags, credentials, cache `_taken` flags, the Blackwood ambush flag and two Blackwood test-equipment interaction ids). Each was traced to the code that builds the name at runtime (`patrol_group.gd:23`, `door.gd:41`, `facility_ids.gd:10`, `supply_crate.gd:32`, `blackwood_encounter.gd:36`, `blackwood.gd:632`) and the patterns were added to `CampaignAudit.DYNAMIC_FLAGS`. The tool cannot see a typo inside a dynamic name; the bot tests cover that.

## 3. Quest chains as they run
- **Arena chain (Outpost 17):** `first_signal` -> `restore_power` -> `broken_perimeter` -> `final_transmission` (each `next_quest`). It starts automatically when `first_signal` completes, and it ends with the original ending screen (`quest_manager.gd` FINAL_QUEST).
- **Campaign chain:** `first_signal` -> bridge `leave_outpost` -> Dead Coast (`dc_wreckage` -> `dc_silent_checkpoint` -> `dc_lost_cargo`) -> Blackwood (`into_the_blackwood` -> `ghost_frequency` -> `experimental_site`) -> Research Complex (`rc_restricted_zone` -> `rc_silent_records` -> `rc_containment_breach` -> `rc_project_black_site`). Region unlocks come from `CampaignFlow.CHAIN`.
- The tracker now lists the current region's quests first, so the arena chain no longer outranks a regional mission.

## 4. Gaps in mission handling
- No mission has failure handling beyond player death and checkpoint reload; there are no timed or escort objectives.
- The Iron Fortress has no quest files in `master` (five planned in `MILESTONE_009.md`); the campaign has no final mission, no ending and no completion flag in `master` (`iron_fortress_director_defeated` and `campaign_complete` exist only in the unmerged Milestone 9 work).
- The Research Complex's last objective flag `research_complex_next_lead` is produced, but nothing consumes it to open a next region; the exit is a sealed placeholder caption.
- Optional objectives exist (17 across the quests) but there is no journal showing them, and documents once read are not collected anywhere the player can reopen.

## 5. Contradictions and tensions (nothing edited; proposals only)
| # | Severity | What | Quotes and sources | Proposed resolution |
|---|---|---|---|---|
| 1 | **High** | The original ending can fire mid-campaign | `quest_manager.gd`: `if quest_id == FINAL_QUEST: _begin_ending(quest)`; `first_signal.next_quest = restore_power`, `restore_power -> broken_perimeter -> final_transmission`; `ending.gd`: "The transmission is out. The story continues..." plus Play Again, which resets the run | Stop `final_transmission` from starting the ending (or remove the auto chain from `first_signal`) and attach the campaign ending to the Director's defeat in Milestone 9 to 10 |
| 2 | High | The first mission's terminal sends the player to the wrong region | `outpost17.gd` comms terminal: "Coordinates uploaded: Research Complex." but the campaign's next destination is the coast (`leave_outpost`: "Follow the signal to the Dead Coast") | Change the terminal page to a coastal signal; keep the Research Complex name for Act III |
| 3 | Medium | Pacing: Project Black Site is "no longer a secret" in the first mission | `outpost17.gd`: "Signal confirmed. Project Black Site is no longer a secret."; `log_project_black_site` already explains the programme and the Director; Act III is supposed to reveal the nature of Project Black Site | Keep the name and the Warden link in Act I, change the "no longer a secret" line (the signal reaches "the outside" only) so Act III keeps its reveal |
| 4 | Medium | The radio voice has two identities | `world_flow.gd` RADIO_LINES: "Anyone out there? This is Outpost 17." and "Our power is dead and the courtyard gate is locked down."; `STORY_AND_MISSION_FLOW.md`: an unseen contact ("Static"), R1 "the old relay at Outpost 17 is still alive"; checkpoint log: "Do not trust the radio room. Someone is still broadcasting from the compound."; ship radio: "Relay Seventeen acknowledges. Proceed on schedule." | Decide that the early voice is a decoy broadcast from the compound and the later radio lines come from an outside contact; mark the early lines as the compound's own signal |
| 5 | Medium | Subject 14 and the subject numbering belong to two facilities | `bw_log_experiment_1`: "Subject 14 (transferred from the coast hospital...) speech lost on day nine"; `bw_log_subject_list`: "Moved down to Sublevel 1"; `rc_medical_evidence`: "Subject 11 no longer answers to name or order. Subject 14 did, for four days."; `rc_subject_roster`: 31 numbers, 22 soldiers, the rest "found" | State once that Blackwood is the first-generation annex and the Research Complex the second, with subjects moved between them; reconcile "four days" and "day nine" (orders answered versus speech lost) |
| 6 | Medium | Who signed the shipping ledger | `dead_coast_data_device`: "SHIPPING LEDGER, BLACKWOOD ROUTE, SIGNED R. HALE"; `rc_medical_evidence`: "Trial notes, Dr. Hale" | Make Hale one person, the doctor who smuggled the ledger out after asking to stop at subject nineteen, or rename one |
| 7 | Medium | Containment failure: lockdown versus release | `rc_security_console`: "lockdown was ordered from below. Not from here."; `rc_incident_report`: "released from the control level at 02:14... authorised with a command key"; `rc_director_order`: "to be reported as an accident" | Treat it as one sequence (release, then lockdown) and state who held the command key in the Iron Fortress documents |
| 8 | Medium | The Warden's rank and role | `STORY_AND_MISSION_FLOW.md` premise: "the outpost commander, the Warden"; `log_military_record`: "Sgt. Aldous Venn... Warden-class patient"; `dead_coast_log_checkpoint_orders`: "Commander's office, Outpost 17" | Make the Warden the Director's enforcer at Outpost 17 and the "Commander's office" a separate administrative office, or rewrite the premise text |
| 9 | Low | Which wreck is the protagonist's | `intro.gd`: "The ship broke apart in the dark."; Dead Coast wreck "CALLOWAY... SEALED - NOT FOR INSPECTION - BS" | State that CALLOWAY is the earlier shipment (a different ship) |
| 10 | Low | `docs/STORY.md` is stale | describes four quests (radio, Restore Power, Broken Perimeter, Final Transmission) and "Thanks for playing"; the first mission now has 15 objectives and a results screen | Rewrite STORY.md around the five-act campaign or mark it historical |

## 6. Document inventory
39 documents: Outpost 17 five, Dead Coast ten, Blackwood eight, Research Complex sixteen (listed in section 2). No duplicate ids. **No near-duplicates at 0.45 word overlap**; several documents repeat the same ideas deliberately (secrecy, "do not ask") in different words. None is in a collection screen yet.

## 7. How to re-run
`godot --headless --path . -s tools/campaign_audit.gd` (prints the tables) and `godot --headless --path . -s tests/story_continuity_check.gd` (460 checks, zero failures when written). When the Iron Fortress lands, add its folder name to `CampaignAudit.region_of_quest_path` and run both again.
