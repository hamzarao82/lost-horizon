# LOST HORIZON: BLACK SITE — COMPLETE TEST BRIEF

You are a QA tester (human or AI assistant). Your job is to test the build described below, find real bugs, and report them precisely. Read sections 1 to 4 first, play, then follow the test plan in section 10. Report with the template in section 12.

Rules for you:
- Report what you actually saw. Do not guess. If you could not check something, write "NOT TESTED".
- A bug is: a crash, an error, a soft lock (you cannot progress), something shown wrongly, something that contradicts this brief, or something confusing. Also report anything that is boring, too hard or too easy, and say why.
- Nobody has played this game past its first minutes. Every balance number below comes from formulas and automated bots, not from play. Your opinion on difficulty and feel is the most valuable thing you can give.

---

## 1. What the game is

**Lost Horizon: Black Site** is a single-player, third-person, action-adventure game with RPG progression. You are a lone survivor on an abandoned military island. You uncover "Project Black Site", an illegal human-experimentation program run by a figure called "the Director", fight through five regions, and end with a boss fight and an ending.

It is a solo-developer project built with heavy AI assistance. Art is stylized low-poly (boxy buildings, tinted soldier models for most enemies and bosses, no custom animations for most boss attacks). Sound is all procedurally generated and has never been listened to by the developer.

## 2. How to run it

| Platform | How | Notes |
|---|---|---|
| Windows | `C:\Users\SCS\work\lost-horizon-m1\build\windows\LostHorizon.exe` (desktop shortcut "Lost Horizon - Black Site"). Keep `LostHorizon.pck` in the same folder. | ~109 MB exe + ~17 MB pck. Unsigned: SmartScreen may warn ("More info" then "Run anyway"). Close any running copy before testing a new build. |
| Web | https://hamzarao82.github.io/lost-horizon/play/ | Single-thread WebAssembly. First load ~32 to 42 s on integrated graphics; the menu appears after ~6 s with "Loading world... NN%" and New Game greyed out until ready. Use a hard refresh after updates. |
| Android | NOT TESTED. A debug-signed APK exists from an early version only. | Do not report Android results unless you have run it on a device. |

**Which build am I running?** The main menu shows a dim label in the bottom-left corner: `build <commit>  |  <date time>`. Report it in every bug report. If there is no label, you are running an old build.

Command-line options (Windows exe): `-- --no-menu` skips the menu and starts the game directly. `--boot-report` prints timing markers.

**Save files** (JSON): `%APPDATA%\Godot\app_userdata\Lost Horizon\save_slot_<N>.json` (also `.bak` and `.tmp`). Delete these to reset your progress for a clean test. Saves are versioned (version 4) and written atomically.

## 3. Controls

| Action | Keyboard / mouse |
|---|---|
| Move | W A S D |
| Camera | mouse (third-person; mouse is captured during play) |
| Jump | Space |
| Sprint | Left Shift |
| Dodge | Ctrl or C (short invulnerability window ~0.18 s) |
| Interact | E |
| Light attack | Left mouse button (three-hit combo; chains if pressed in time) |
| Heavy attack | Right mouse button |
| Use medkit | R (refuses at full health, does not waste the kit) |
| Teleport | T (2 charges, ~10 minutes recharge each, random short-range safe landing) |
| Lock on | Tab (cycle with target next/previous) |
| Special | Q |
| Pause | P (Esc also closes screens) |
| Inventory | I |
| Character (attributes and skills) | K |
| Journal | J |
| Map | M |
| Performance overlay | F3 (FPS, draw calls, triangles, memory) |

Gamepad bindings exist (left stick move, right stick camera, face buttons attack/dodge/interact, Start pause, Select equipment) but have never been tried on a real controller. Touch controls exist for mobile but are untested on a device.

The bottom of the screen shows a help line: `WASD move | Shift sprint | Space jump | Ctrl or C dodge | LMB light | RMB heavy | R medkit | F3 stats`.

## 4. The HUD (what you should see)

- **Top left:** health bar (100 at the start), armor bar when armor is equipped, stamina bar, teleport charges with `READY [T]` or a recharge timer.
- **Top left under that:** the mission tracker: mission title, then the current objective. In the later regions the title line also shows a stage line such as `Wreckage  -  Dead Coast: step 4 of 16`. Optional objectives show in a smaller line.
- **Top right:** equipment panel: current weapon with its damage multiplier (for example `Improvised Blade x1.00 dmg`), armor, and medkit count with `[R]`.
- **Top centre:** a counter. In Outpost 17's arena it reads `Wave n/5  Enemies: m`. In the later regions it reads `Enemies left: N` (or `Area clear` when N is 0). While a stage wave fight is running it reads `Wave n/N  Enemies: m`. Boss name and boss health bar appear below it during a boss fight.
- **Yellow arrow with a label:** the objective arrow. It points to the current step of the current stage (labels such as `Perimeter`, `Hold point`, `Boss`, `Patrol`, `Road to Blackwood`, `Explore ahead`). It hides when you are within ~6 m of the target.
- **Centre messages:** wave banners, `ARENA CLEARED` or `WAVES CLEARED` (should disappear after ~5 s), `YOU DIED`.
- **Toasts:** item pickups with rarity colours, level-up banner, document found, credits.
- **Captions:** radio lines and story text at the bottom centre.

## 5. Systems, in detail

### 5.1 Combat
- Player is a CharacterBody3D with five states: free, dodge, attack, hit, dead. Inputs are buffered; attacks start the same physics tick as the press.
- Light chain: three hits. Heavy, sprint, air and spin attacks exist. Weapons differ by damage multiplier and attack speed.
- Hits land only in an attack's active frames, once per swing per target. Hit-stop is short (≤0.07 s) and never stacks. Enemies stagger.
- Damage pipeline (one place, each modifier applied once): weapon multiplier × attributes × skills × gear, then armor reduction. At level 1 with the starting blade the numbers equal the original game's.
- Dodge: invulnerable for a short window; it feeds the Counterattack skill.

### 5.2 Survival
- Health 100 base. Armor is a separate pool that absorbs damage first (percent bar), refilled by Armor Patch consumables and armor items.
- Medkits ("Medkit" item, stack up to 99) are the only healing path. Teleport Cell restores a charge.
- Death: a death screen shows the cause and respawn place; the game reloads from the last checkpoint or the start. Nothing duplicates on reload (enemies cleared stay cleared, rewards are not repeated).
- Teleport: exactly 2 charges, 600 s of real wall-clock time to recharge each, persisted in the save. It chooses a random safe landing spot 8 to 18 m away; if none exists it refuses and keeps the charge.
- A player who falls below y = -40 is returned to the last solid ground (or dies into the normal respawn if none is known).

### 5.3 Items, equipment, crafting, economy
- Bag capacity 40 stacks. Categories: weapons, armor, consumables, materials, quest items, collectibles, upgrade components. Quest and unique items cannot be dropped or sold.
- Weapons (damage multiplier): Improvised Blade 1.0 (start), Combat Knife 1.25, Iron Sword 1.35, Military Machete 1.5, Katana 1.75, Tactical Sword 1.9, Claymore 2.1, Warden's Cleaver 2.3 (unique boss reward).
- Armor: Light Tactical, Reinforced, Heavy Combat, Warden Plate (unique). Gear slots: helmet, gloves, boots (shown on the character model), accessory (no model).
- Rarity: common, uncommon, rare, epic, legendary (colour-coded).
- Crafting (6 recipes): Bandage, Armor Patch, Medkit Supply, Sharpening Oil, Armor Upgrade Kit, Weapon Upgrade Kit.
- Upgrading: up to level 5, costs materials and credits; the Warden's Cleaver has its own curve (less raw damage per level, gains speed and a little damage reduction).
- Merchant: one quartermaster in Outpost 17 (compound gate area): buy and sell, limited stock, no profit from buy-and-resell.
- Currency: "credits", one balance owned by the inventory.
- 46 item resource files in total, including region boss rewards (for example Harbor Commander's Cap, Cove Boss's Gloves, Patrol Chief's Boots, Site Overseer's Badge, Facility Commander's Visor, Fortress Captain's Badge, The Director's Signet).

### 5.4 Progression
- XP and levels (12 levels). Level-ups give attribute points and skill points. Kill XP shrinks for over-levelled targets and repeat kills; quest and discovery XP is larger.
- Five attributes: Vitality, Strength, Endurance, Agility, Technique.
- Fourteen skills: Sharpened Edge, Heavy Hitter, Whirlwind, Toughness, Tempered Nerves, Field Medic, Fleet Foot, Light Step, Deep Lungs, Quick Recharge, Focus, Scavenger, Combo Extension, Counterattack. They have prerequisites and ranks.
- Enemies scale gently with player level (level 1 equals authored numbers; bosses use a gentler curve).

### 5.5 Quests and world flags
- Quests are data (`.tres` resources), event-driven (enter area, interact, discover, kill count, collect item, flag). About 29 quest resources exist.
- **Outpost 17 missions** keep an order-independent design: events that happen early are remembered.
- **The four later regions are strict, step by step:** only the current step is active, in list order. If you do something early (read a log, kill a patrol), it is remembered and counted the moment its step comes up, so nothing can soft-lock. Optional objectives never block.
- Tracker and arrow show only the current region's quests (pinned "road" step first once the way on is open).
- World flags are saved. A flag name may contain only `a-z`, `0-9` and underscore and at most 48 characters, or the save drops it. (A past bug: dotted flag names silently vanished on save.)

### 5.5b The rule for moving to the next stage (changed last)
**The way on opens when a stage's bosses are down. You do not have to finish every mission step or clear every enemy.**

| From | Opens when | To |
|---|---|---|
| Outpost 17 | the Warden is defeated | Dead Coast |
| Dead Coast | Harbor Commander AND Cove Boss defeated | Blackwood |
| Blackwood | Patrol Chief AND Site Overseer defeated | Research Complex |
| Research Complex | Subject Zero AND Facility Commander defeated | Iron Fortress |

When open: a lit "ROAD TO ..." door or the exit unlocks; a "take the road" step appears pinned at the top of the tracker and the arrow leads to the gate; the exit shows a refusal caption until then. Finishing the missions (the older rule) also opens the road, whichever comes first. One boss alone is not enough. Skipping mission steps means missing their XP, credits and loot unless you return.

### 5.6 Regions and content
The game is five regions, played in order. Each later region is built from code plus data and is loaded one at a time (only one region exists in memory; Outpost 17 is kept detached while you are away).

**Region 1: Outpost 17** (Main scene)
- Areas A Perimeter, B Compound, C Research Wing, D Command Center, plus a beach. A five-wave combat arena in the courtyard ends with the Warden (a boss with two phases at ~40% health: slam, shockwave, flurry, charge, leap, fire lines; health 420).
- Mission "The First Signal": about 15 required objectives (reach the perimeter, search the checkpoint, use the radio, defeat soldiers, find an access card, restore power with three switches in the order B, A, C after inspecting the panel first, upload at the military terminal, enter the research wing, read the Project Black Site file, defeat the Warden, take his reward, contact the outside from the command terminal), plus one optional log.
- Patrols with sight cone, suspicion and search states; max 4 active patrollers at once.
- Exits to Dead Coast: a barricade gate at the far south end of the beach ("ROAD CLOSED" until open) and a "SERVICE ROAD" door in the north wall of Area D behind the Warden's room.
- NPC: the quartermaster (merchant).

**Region 2: Dead Coast** (7 areas: Wreckage Beach, Coastal Trail, Abandoned Checkpoint, Smuggler's Cove, Cliffside Watchpoint, Hidden Supply Depot, Exit toward Blackwood)
- 6 patrol squads (12 soldiers), 2 bosses, 3 stage waves at a hold point, 12 caches, about 13 documents, 3 missions (Wreckage, The Silent Checkpoint, Lost Cargo) and a "road" step. Enemies left on arrival: 14.
- Bosses: Harbor Commander (checkpoint area) and Cove Boss (near the cove). Unique rewards each.

**Region 3: Blackwood** (7 areas: Jungle Entrance, Overgrown Military Trail, Abandoned Patrol Camp, Research Perimeter, Hidden Communications Station, Experimental Testing Site, Research Facility Entrance)
- Dense instanced vegetation, a stream, dark teal look with a readable trail (lanterns), a fair ambush (cue, then attack after ~1.5 s), a "frequency" puzzle (three dials to 4-1-7 read from a log; wrong input resets only that step), guard coordination (one guard noticing alerts neighbours within 10 m).
- Bosses: Patrol Chief and Site Overseer. 3 stage waves. 3 missions (Into the Blackwood, Ghost Frequency, The Experimental Site). A hatch at the testing site only shows a caption (there is no underground level: known).

**Region 4: Research Complex** (6 areas: Research Perimeter, Administration Wing, Medical Research Wing, Containment Sector, Central Research Laboratory, Underground Exit)
- Zone-coloured interiors (cool grey admin, clinical green medical, red-orange containment, blue lab), security doors that need credentials, terminals, an archive power breaker, a lab power puzzle (breaker pattern) and a containment override (three terminals then a release lever), a floor hazard that always shows an amber warning for 0.5 s before it can damage.
- Enemies: Research Security Guard, Heavy Facility Guard, Experimental Subject (fast lunge), Elite Experimental Subject "Subject Zero" (mini-boss), Facility Commander (ranged, now a second boss). 3 stage waves. 4 missions. 16 story entries.
- The underground exit leads to the Iron Fortress.

**Region 5: Iron Fortress** (6 areas: Fortress Approach, Outer Defensive Perimeter, Military Barracks, Command Center, Inner Fortress, Project Black Site Control Facility)
- Gate credentials, communications relays (a wrong pull trips the racks only), inner lockdown with three control points (completed points are never lost). 17 story entries. 4 stage waves (the hold point is inside the barracks, so the garrison may join the fight: unjudged).
- Enemies: Fortress Infantry, Elite Security Soldier, Heavy Assault Unit, Tactical Commander (ranged, cover repositioning), Fortress Captain (mini-boss, 360 health), **The Director** (final boss, 600 health, three phases at 60% and 25%, invulnerable 2.0 s transitions with in-character captions, ranged volleys, line barrage, dash strike, expanding rings, clear vulnerability windows).
- Defeating the Director with the final transmission sent sets `campaign_complete` and starts the ending.

**Ending:** a fade, seven closing captions, a statistics screen (campaign and optional completion shown separately), credits, then a choice: Continue Exploring or Main Menu. It plays once automatically; replay from the menu's Credits entry is NOT wired yet (known).

Enemies-left totals on arrival (patrol members plus boss spawns): Dead Coast 14, Blackwood 14, Research Complex 14, Iron Fortress 19.

### 5.7 Other screens
- Main menu: New Game, Continue (shows place and time; disabled with no save), Settings, Credits, Quit (hidden on web and mobile).
- Pause menu: Resume, Inventory, Character, Crafting, Map, Gear overview, Journal, Save, Load, Restart, Settings, Main menu, Quit.
- Inventory (I), Character (K), Crafting, Merchant, Journal (J: Main, Side, Documents, Story, Regions tabs; 65 documents indexed), Map (M: region overview with locked/available/current/completed states, region detail with discovered areas, your marker and objective marker).
- Settings: audio, quality preset (Low, Medium, High), sensitivity, FPS toggle. There is no key rebinding screen and no "Load Game" list (Continue loads the single save): known.

## 6. How it was made (technical)

- **Engine and language:** Godot 4.7.2 (editor/export), GDScript, GL Compatibility renderer, base viewport 1280x720.
- **Size:** 188 GDScript files (~32,700 lines), 24 scenes, 260 `.tres` data resources, 50 GLB models, 30 generated WAV files, 46 generated icons, 94 automated test suites.
- **Code layout (`scripts/`):** `ai` (enemies, bosses, patrol, detection, ranged), `combat` (hitbox, health), `player` (player, teleport), `core` (boot, settings, save, world state, run stats, build info), `inventory`, `items`, `loot`, `progression`, `quests`, `regions` (framework, adapters, builders per region, gates, bosses), `story` (dialogue, ending), `ui` (HUD, menus, screens), `visual` (skinned character adapter, gear), `world` (Outpost 17, arena, waves, interactables), `audio`, `fx`, `camera`.
- **Autoloads:** AudioManager, Settings, Fx, SaveManager, Teleport (watcher), WorldState, QuestManager, RunStats, Progression, RegionManager.
- **Data-driven:** items, loot tables, enemy configs, attack frame data, quests, objectives, recipes, merchant stock, wave tables, skills, attributes, region data and map data are `.tres` resources, many generated by `tools/gen_*.gd` scripts so they can be regenerated.
- **Regions:** `RegionData` resources plus a `Region` base and per-region adapters. `RegionManager.travel()` loads one region at a time with a fade, places the player at an entry transform, applies a per-region sky/fog/sun preset and ambience, and saves per-region state (cleared encounters, claimed ids) through `RegionStore` and `PersistentIds`.
- **Characters and art:** characters and weapons are Blender-scripted low-poly GLBs on a skinned rig; environments are procedural boxes plus a small CC0 prop kit and CC0 PBR textures (ambientCG, Poly Haven); vegetation is instanced with view ranges. Web builds use simpler vertex-colour materials.
- **Audio:** every sound is generated by `tools/gen_sfx.gd` (combat, UI, footsteps, ambience loops for coast, jungle and facility, radio, boss sounds, mission-complete). None has been listened to by the developer.
- **Save system:** version 4 JSON with sections for player, inventory, progression, world flags, region state and checkpoints; atomic writes with `.bak`; migration from versions 2 and 3; hostile-data validation.
- **Web build:** single-thread export, hashed asset names (`tools/package_web.ps1`), custom HTML loading shell with a real progress bar, menu shown early while the world builds, deployed by GitHub Pages from `master`.
- **Build stamp:** `tools/stamp_build.ps1` writes the commit and time into `scripts/core/build_info.gd` before each export.
- **Process:** built over 12 milestones: first playable, stylized visuals, explorable world, vertical slice, first signal, progression systems, Dead Coast and Blackwood, Research Complex, Iron Fortress, campaign integration, advanced combat plus arena, completion. Each change ships with automated tests (`tests/*_check.gd`, run headless). A bot test (`playthrough_bot`) plays the first mission through real events; others test saves, regions, quests, bosses, waves, the arrow and the HUD. The last full run passed all 90 suites; later changes were checked with targeted suites. Tests prove logic and numbers, not feel.

## 7. Known issues and limits (do not report these as new unless they behave worse than described)

1. **Nobody has played beyond the first region by hand.** Every fight, wave size, boss number and reward is unjudged.
2. **Bosses have no new models or animations.** They are tinted/scaled soldier models. Attacks are shown by floor markers, aim lines and an existing wind-up pose. Dead Coast and Blackwood bosses are melee only. No boss sounds beyond generated ones.
3. **Art is low-poly and boxy**; interiors can look washed out (the administration wing is very pale blue); far from commercial quality.
4. **Web load** takes ~32 to 42 s (menu visible at ~6 s). Desktop frame rate on integrated graphics at High quality measured ~57 FPS average, below the 60 FPS target; Medium/Low are faster.
5. **Android and phone browsers are untested.**
6. **Sound has never been listened to.**
7. **Story:** five contradictions are documented and unresolved (for example the first mission's terminal points at the Research Complex while the next destination is Dead Coast; the radio voice has two identities; one test subject appears in two facilities; "R. Hale" and "Dr. Hale" are not linked). The ending's backstory beat (the protagonist as a witness aboard a transport) is a proposal.
8. **Iron Fortress hold point** sits inside the barracks, so its garrison may join the wave fight.
9. **No key rebinding, no Load Game list, no ending replay from the menu, no Blackwood underground.**
10. Optional objectives get no arrow. The "Explore ahead" arrow is only a hint when nothing specific carries the objective.
11. Stage waves, strict step order, enemies-left counter, bosses and gates were added at the end and have been tested by bots and unit tests only.

## 8. Recent fixes worth re-testing (these were reported by a tester)

- The arrow now follows the camera heading only, and shows only the current stage's targets.
- `ARENA CLEARED` used to stay on screen forever. It should now disappear after ~5 s.
- A patrol squad held back by the four-patroller cap used to be lost for good (a hidden "last enemy" that blocked a stage). It now retries while you are within ~90 m.
- The enemies-left counter used to be empty outside wave fights.
- Walking back across Outpost 17 after the Warden: the service road door now offers a shortcut.

## 9. Setup before you test

1. Close any running copy. Note the build stamp on the menu.
2. For a clean run delete the save files (section 2). For a continuation test keep them.
3. Windowed 1280x720 is the reference size; also try a larger and a smaller window (800x360 is the smallest layout test) and the web page.
4. Turn on F3 (performance overlay) when you check performance.

## 10. Test plan (follow in order; mark each PASS, FAIL or NOT TESTED)

**A. Launch and menu**
- A1. The game starts; the menu shows the title, New Game, Continue (greyed with no save), Settings, Credits; the build stamp is visible bottom-left.
- A2. Settings opens and closes; Credits opens and closes. Esc/Space/Enter skips the opening fade.
- A3. (Web) New Game stays disabled showing `Loading world... NN%` (the number should never go backwards) until ready.

**B. First minutes (Outpost 17)**
- B1. New Game: the intro plays and can be skipped; control returns; the tracker shows "The First Signal" and an objective.
- B2. Movement, camera, jump, sprint, stamina drain and recovery feel right. Collision with walls and props; no sticking.
- B3. Light combo (three hits), heavy attack, dodge i-frames, lock-on (Tab). Attacks hit once per swing; enemies stagger.
- B4. HUD elements match section 4. The arrow points at the current objective and hides when you are close.
- B5. Pickups: walk over items; toasts show rarity colours; equip a better weapon in the inventory (I) and see the damage multiplier change.
- B6. Medkit (R) heals; at full health it refuses and keeps the kit. Teleport (T) moves you a short random distance, uses a charge, shows a recharge timer.
- B7. Pause (P), Save, Load, Restart, Main menu all work; the Inventory, Character, Crafting, Map and Journal screens open and close with keyboard and mouse, with no overlapping text.

**C. The first mission** (follow the tracker; note any step you could not do)
- C1. Each objective updates the tracker and completes once. The radio, checkpoint desk and military terminal work.
- C2. The power puzzle: inspect the panel first, then switches in the order B, A, C; a wrong order resets it only.
- C3. The access card opens the reader; doors open and stay open.
- C4. The arena (five waves) starts when intended, each wave is harder, no wave sticks after all enemies die, `ARENA CLEARED` disappears after ~5 s, the reward is paid once.
- C5. The Warden: two phases (transition roar and caption at ~40%), readable telegraphs, you can dodge and punish, he drops a unique reward once; the boss bar shows and disappears.
- C6. After the Warden: the caption "The road south is open" (or similar), the tracker shows "The Road South", the arrow leads to an exit. Test both exits: the SERVICE ROAD door behind the Warden's room and the south beach gate.

**D. Save and reload (do this in every region)**
- D1. Save mid-mission, quit, relaunch, Continue: the same place, objective, inventory, equipment, level, medkits and teleport timer.
- D2. Die and respawn: no duplicated enemies or rewards.
- D3. Kill some enemies, save, reload: cleared enemies stay dead and "Enemies left" is consistent.

**E. Dead Coast**
- E1. Arrival: the radio caption, the tracker `Wreckage - Dead Coast: step 1 of N`, the arrow points at the first area. "Enemies left: 14" is shown.
- E2. Strict order: do a later objective early (read a log, kill a patrol). The tracker keeps showing the current step; the early action is counted when its turn comes.
- E3. The arrow: for each step check that it points at the right thing (area, object, enemy, `Hold point`, `Boss`, `Patrol`). Report any step where it is wrong or missing, with where you stood.
- E4. Patrols: approach each area; squads appear within a second of you getting near (the cap of four must never leave an enemy missing). "Enemies left" goes down by one per kill and ends at "Area clear" (excluding the bosses and wave enemies until they are dead).
- E5. The stage wave fight: enter the hold point; `Wave n/3 Enemies: m` shows; waves run; reward once; a reload after clearing does not repeat it; die mid-wave: the fight resets cleanly.
- E6. Both bosses (Harbor Commander, Cove Boss): readable telegraphs, fair damage, boss bar, unique reward, defeat caption. Defeating them in either order is allowed.
- E7. The gate: before both are down it is closed ("ROAD CLOSED" or a refusal caption). After both are down the door lights up, the tracker pins "take the road", the arrow leads to it, walking in reaches Blackwood. Test with mission steps still unfinished.
- E8. Dead Coast is not a dead end: from Blackwood you can walk back.

**F. Blackwood** — repeat E1 to E8 with its own names. Also: the ambush gives a warning cue before it attacks; the frequency puzzle (4-1-7) accepts the right input and resets only its own step on a wrong one; the trail is readable (not too dark); the stream and vegetation render; the hatch only shows a caption.

**G. Research Complex** — repeat E1 to E8. Also: credentials open the doors, the archive and lab puzzles complete, the containment override works in any order within its window, the floor hazard always shows its warning first, Subject Zero and the Facility Commander (boss bar and unique reward), the underground exit opens to the Iron Fortress when both are down.

**H. Iron Fortress** — repeat E1 to E7 (no exit forward). Also: gate credentials, communications relays, the three lockdown points, the Fortress Captain, and the final fight with the Director: all three phases (60% and 25% thresholds), 2 s invulnerable transitions with captions, no unavoidable damage, no trap loops, vulnerability windows after big attacks.

**I. The ending**
- I1. Defeating the Director sets campaign complete: fade, seven captions, statistics screen, credits, then the choice. Esc/Space/Enter skips beats safely.
- I2. Continue Exploring: all regions stay open, nothing re-locks, the Director does not respawn, the tracker shows a post-campaign line.
- I3. Main Menu returns to the title; Continue loads the post-campaign save; New Game resets everything.

**J. Economy and progression**
- J1. XP, level-ups, attribute and skill spending (prerequisites and ranks). Check that every skill actually changes something.
- J2. The merchant buys and sells; money never appears from nowhere. Crafting consumes exactly its inputs. Upgrades preview matches the result. Quest and unique items cannot be dropped or sold.

**K. Journal, map and documents**
- K1. Reading a document shows a "Document found" toast and adds it to the Journal; unread documents show as unknown. The Journal tabs show correct progress.
- K2. The Map (M) shows the five regions with the right states, discovered areas only, your marker and the objective.

**L. Performance and platforms**
- L1. Use F3: record FPS, draw calls and memory in Outpost 17, Dead Coast, Blackwood, and during a wave fight. Report any frame spike or stutter.
- L2. (Web) record time to menu and time to playable; reload and check the save persisted.
- L3. Resize the window; check no UI overlaps at 800x360, 1280x720 and 1600x720.

**M. Try to break it (soft locks and exploits)**
- M1. Quit during a wave, a boss fight, a puzzle step, and the ending; reload.
- M2. Do objectives in reverse order; skip optional ones; leave a region and come back mid-mission.
- M3. Alt-tab, pause during fights, open screens during fights.
- M4. Fall off edges, jump on props, teleport near walls; look for places you can get stuck or fall out of the world.
- M5. Spam interact, attack, dodge, medkit; check nothing triggers twice (rewards, objectives, damage).

## 11. Quick reference: expected numbers

Player health 100; bag 40 stacks; medkits stack 99; teleport charges 2 (600 s recharge each); weapons' multipliers in 5.3; Warden health 420; Director health 600 (phases at 60% and 25%); Fortress Captain 360; stage bosses 340 to 450; stage waves hold 3 to 4 enemies (cap 6): Dead Coast 3 waves, Blackwood 3, Research Complex 3, Iron Fortress 4; stage wave rewards 140/160, 160/180, 180/200 and 220/240 XP/credits; arena completion reward 100 XP and 120 credits (once); boss telegraphs at least 0.6 s with at least 0.5 s punish windows; Outpost 17 max 4 active patrollers; a 12-projectile cap for ranged enemies.

## 12. Bug report template (one per bug)

```
Title: <short>
Build stamp: <text from the menu corner>
Platform: Windows / Web (browser + version)
Where: <region, area, nearest landmark, coordinates if F3 shows them>
Step/objective shown in the tracker: <text>
What I did: <numbered steps>
What I expected: <...>
What happened: <...>
How often: always / sometimes / once
Severity: crash / cannot progress / wrong behaviour / cosmetic / balance
Evidence: <screenshot or video name, any error text>
```

## 13. Final report (after testing)

1. A table of every test case in section 10 with PASS / FAIL / NOT TESTED.
2. Your list of bugs, most serious first, with the template.
3. Can the game be completed from New Game to the ending without a blocker? If not, where does it stop?
4. Difficulty: the three hardest and three easiest moments, and why.
5. Pacing: the most boring stretch and the most confusing step.
6. Whether the arrow, tracker, enemies-left counter and gates are clear enough to follow without help.
7. Total play time, and the build stamp you tested.
