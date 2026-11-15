# Opening arc: design decisions (2026-11-15)

The owner asked for the opening milestones (0 to 12) to be completed as far as possible in one session and did not answer the open questions in the plans, so these defaults were chosen to keep risk low and reuse what exists. Each can be reversed later; they are listed so builders and reviewers agree.

1. **The payment bag's location:** Outpost 17, Area D, the hidden back room (north-west of the command building), behind a sealed store door that opens when the Area D Warden falls (`warden_d_defeated`). Recovered only there. Flag `payment_recovered`.
2. **The name "Outpost 17":** the internal ids stay (`outpost_17`). The visible region name is masked as "The Perimeter" in the map status, the save-slot info and travel labels until the flag `outpost_name_known` is set by passing the compound entrance sign (a weathered "OUTPOST 17" plate). New saves made before the flag show the masked name.
3. **The Warden:** left fully intact. No deferral of `BossIntro`. The road to the Dead Coast stays tied to `boss_warden_defeated` (either Warden). Only the new payment store depends on `warden_d_defeated`.
4. **The research wing:** Option A: Area C of Outpost 17 is dressed as a research space and holds the research discoveries. The Research Complex region is untouched and keeps its own revelations for later.
5. **The Trail and the Settlement:** built by dressing Area A (the beach strip, z 30 to 80) rather than adding a new region; the compound is hidden behind a ridge, foliage and rock until the viewpoint at the beach gate.
6. **The First Signal:** kept intact (all flags, objectives, rewards, ids). It no longer auto-starts on New Game; it starts when the player passes the compound entrance sign. Its description is reworded so the name and the project are not the first thing read; objective ids do not change.
7. **Geography of Milestones 7 to 10:** M7 = Area B side rooms and Area C storage; M8 = Area C research dressing; M9 = the DoorCD hall and control room (not Area D's interior); M10 = the guarded gate and pre-boss supplies at DoorCD, plus a new checkpoint just before DoorCD.
8. **Audio:** the 3 MB budget is full. No new sound files unless an equal amount is removed; reuse existing sounds, pitch and bus effects.
9. **Animations:** none exist for waking, sitting, limping or opening a bag. Built as camera, caption, fade and prop motion; real rig animation stays a Milestone 13 item.
