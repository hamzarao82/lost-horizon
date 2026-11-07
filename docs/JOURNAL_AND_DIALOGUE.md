# Journal, document index and dialogue (Milestone 10, first part)

Status date: 2026-11-07. Legend: **Implemented and tested**, **Implemented, not tested**, **Not implemented**.

## What exists
| Piece | Files | Status |
|---|---|---|
| Dialogue lines and sequences | `scripts/story/dialogue_line.gd`, `dialogue_sequence.gd`, `resources/story/dialogue/*.tres` (3 examples) | implemented and tested (`dialogue_check`, 25 checks) |
| Dialogue player | `scripts/story/dialogue_player.gd` | implemented and tested |
| Document data and index | `scripts/story/document_data.gd`, `document_index.gd`, `resources/story/documents/*.tres` (48), `tools/gen_document_index.gd` | implemented and tested (`journal_check`, 85 checks) |
| Collection hooks | one call each in `lore_document.gd` and `terminal.gd`; `notify_document` in `rpg_notifications.gd` | implemented and tested |
| Journal screen | `scripts/ui/journal_screen.gd`; Journal button and key `J` in `pause_menu.gd` | implemented and tested; screenshots of the Main and Documents tabs |

## Dialogue
A `DialogueSequence` is an ordered list of `DialogueLine` (speaker, text, seconds, optional sound cue). `DialoguePlayer.play(&"id")` loads `resources/story/dialogue/<id>.tres` and sends each line, prefixed with the speaker name, through the existing caption path (`QuestManager.say`). It never clears other captions: lines queue behind whatever the HUD already shows. Pressing the interact action stops the rest of a sequence (the line on screen finishes by itself). A once-only sequence stores the flag `dlg_<id>` in `WorldState`, so it survives a save and load and never plays twice. Sound cues use existing `AudioManager` names only and are skipped if the sound or the manager is missing.

Three example sequences ship (`radio_dead_coast_handoff`, `terminal_command_post`, `optional_supply_chatter`). They are written by `tools/gen_dialogue.gd` and are **not yet wired to any trigger**: calling `DialoguePlayer.play` from the region hand-off, a terminal and an optional pickup is the next step for Milestone 10.

## Document index
`tools/gen_document_index.gd` instantiates each region scene, collects every `LoreDocument` and `Terminal`, and writes one `DocumentData` resource per object. The title and body are copied from the world object, not rewritten. Categories are a keyword heuristic (military intelligence, research record, personnel file, incident report, communication, classified, personal note) and are a reading aid, not canon. Re-run the tool after adding documents or a region. The Iron Fortress scene is not in `master` yet, so no Iron Fortress documents are indexed.

Indexed documents: Outpost 17 7, Dead Coast 13, Blackwood 12, Research Complex 16, total 48. The tool reported no empty bodies and no duplicate keys. Keys are `[a-z0-9_]`, at most 30 characters, so `journal_collected_<key>` stays within the 48 character limit of `WorldState`.

Reading a document or terminal calls `DocumentIndex.mark_collected(interaction_id)`, which sets `journal_collected_<key>` and shows a "Document found" toast once. Known limits: documents whose text is built at runtime (rather than stored on the node) are indexed with the text they had when the tool ran; a terminal and a document that share an interaction id would both be marked.

## Journal screen
Tabs: **Main** (missions by region in campaign order with the current objective, locked regions show only `???`), **Side** (optional objectives and the older arena quests), **Documents** (by category; collected ones open on the page, uncollected ones show only `???` and the region), **Story** (revelations that appear after their flag; short and no more than the documents already say), **Regions** (status, missions done, documents collected). It reads existing data only; there is no second quest or map system. The mission list per region is a constant in `journal_screen.gd`; quests that do not exist (the Iron Fortress) are skipped, so adding that region means adding its quest ids to `MISSIONS`.

The page rebuilds when it opens, when a tab changes, and when a flag changes while open, never per frame. Buttons are at least 56 px tall and the layout is tested at 1280x720, 1600x720 and 800x360.

## Tests (all run, 0 failed, zero script errors)
`dialogue_check` 25, `journal_check` 85. `journal_check` covers the index (unique valid keys, no empty bodies, per-region counts), both collection hooks, the discovery toast, tab content for seeded progress, hidden undiscovered entries, collected flags through a real `WorldState` round trip and a real `SaveManager` save and load, the pause-menu hook, and layout at three sizes.

## Screenshots (windowed, real game)
Journal Main tab, Documents tab with a document open, and a dialogue line on screen. The F3 stats overlay (switched on for the shots) partly covers the "Journal" title; this is the overlay, not the layout.

## Not done
- Dialogue triggers in the game (the sequences exist but nothing calls them yet).
- Iron Fortress documents and missions in the journal (the region is not in `master`).
- Per-document "read" versus "unread" state (only collected or not).
- A text search or sort in the journal; gamepad and touch use were not tested on real devices (focus and layout only).
- The Story tab text is a short original summary and has not been reviewed against the final narrative bible.
