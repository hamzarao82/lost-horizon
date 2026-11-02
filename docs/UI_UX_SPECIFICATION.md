# UI / UX Specification

Tags are explained in [MILESTONE_004.md](MILESTONE_004.md). Existing layout rules and measurements are in `UI_LAYOUT.md` and `ui_layout_check`; this document defines the complete set of screens.

## 1. Principles
1. Show only what the player needs now; no screen is permanent clutter.
2. One visual language: the `milestone-002` HUD theme (rounded dark panels, accent colours: health red, armor blue, stamina green, quest gold), the existing fonts and outline style.
3. Every action reachable with mouse and keyboard, a gamepad, and touch; all screens usable at 1280x720 and 800x360 (which the project stretches to 1600x720) and a portrait phone view for menus.
4. Nothing important is only in colour; every state also has text or an icon.

## 2. Screens

| Screen | Status | Notes |
|---|---|---|
| Boot/loading screen | `[IMPLEMENTED]` | progress bar and tips |
| **Main menu** | `[NEW-M4]` | New Game, Continue (disabled without a save), Settings, Credits, Quit (hidden on web and mobile) |
| Story intro | `[IMPLEMENTED]` | skippable; shown on new game only |
| Gameplay HUD | `[IMPLEMENTED]` | see section 3 |
| Pause menu | `[IMPLEMENTED]` | Resume, Save, Load, Restart, Settings, Quit; add Inventory and Quests tabs `[NEW-M4]` |
| Settings | `[IMPLEMENTED]` | master/music volume, mouse and touch sensitivity, quality, FPS toggle; add SFX/ambience/UI volume, control remapping `[PROPOSED]`, language not needed |
| **Inventory / equipment** | `[NEW-M4]` | equipped weapon and armor with stats and comparison, medkits, quest items, documents found |
| **Quest journal** | `[NEW-M4]` (small) | current objective, completed objectives, optional objective, documents list |
| **Mission results** | `[NEW-M4]` | see STORY_AND_MISSION_FLOW.md section 6 |
| **Death / respawn screen** | `[NEW-M4]` (today: "YOU DIED" text and automatic reload) | cause, respawn location, hint, Continue |
| Save/load feedback | partly `[IMPLEMENTED]` ("Progress saved" toast) | add "Checkpoint saved", "Load failed: save is damaged (backup restored)" messages |
| Ending / credits | `[IMPLEMENTED]` (`Ending.tscn`) | reuse after the results screen |

## 3. Gameplay HUD (existing information, all must remain)
Health, armor, stamina, wave and enemy counter (arena), equipped weapon with damage modifier and speed, equipped armor with current/maximum points, medkit count and key, teleport charges with the recharge timer, quest tracker (title, objective, progress), optional objective line, objective pointer (arrow and distance), location banner, mission update banners, subtitles, toasts, boss bar, interaction prompt, controls hint (desktop), touch buttons (mobile), FPS overlay (debug or settings toggle).

Layout contract: the positions come from `Hud.plan_layout`/`layout_story`; any change keeps `ui_layout_check` green (no overlaps at 1280x720, 1600x720, 360x800).

### Wireframe — HUD (landscape)
```
┌────────────────────────────────────────────────────────────────────────┐
│ [heart ████████ 100/100]        Wave 2/5  Enemies 3     Weapon  Katana  │
│ [shield ███ 60/60]                                       Armor   Reinf. │
│ [bolt ██████]                  ⚠ MISSION UPDATE         Medkits x2  [R] │
│ Teleport ◉ ◉  [T]             (banner band, top third)                  │
│ The First Signal                                                       │
│ Restore power (2/3)                         ──►  Panel 18 m  (pointer)  │
│ Optional: find the log                                                  │
│                          (3D view)                                      │
│        subtitle band: "Careful in the compound, they patrol."          │
│        toast band:    Picked up Iron Sword                              │
│ controls hint (desktop)                         [touch buttons on phones]│
└────────────────────────────────────────────────────────────────────────┘
```

### Wireframe — Main menu
```
        LOST HORIZON: BLACK SITE
   ┌──────────────────────────┐
   │        New Game          │
   │        Continue          │   (shows slot info: location, time, date)
   │        Settings          │
   │        Credits           │
   │        Quit              │   (desktop only)
   └──────────────────────────┘
        v0.x   |   FPS option
```

### Wireframe — Equipment screen
```
┌ Equipment ───────────────────────────────────────────────┐
│ WEAPON  Warden's Cleaver  ★★★★★ legendary                │
│   Damage x2.30   Speed 0.95   Power 2.24                 │
│   vs previous: Katana x1.75  1.10  1.84      (+22%)      │
│ ARMOR   Warden Plate  epic   140 / 140                    │
│ Medkits 3     Teleport 1/2 (next in 06:12)                │
│ Quest items: Access card                                  │
│ Documents found 4 / 6        [Back]                       │
└──────────────────────────────────────────────────────────┘
```

### Wireframe — Mission results
```
        MISSION COMPLETE — The First Signal
   Time 24:10    Enemies defeated 17    Secrets 3 / 4
   Reward:  Warden's Cleaver  (legendary)
   Checkpoint saved
        [ Continue ]      [ Main menu ]
```

### Wireframe — Death screen
```
        YOU DIED
   Killed by: The Warden (leap slam)
   Respawn: Command Center checkpoint
   Hint: the shadow shows where he lands.
        [ Respawn ]   [ Main menu ]
```

## 4. Input architecture
- **Keyboard/mouse (Windows, web):** existing bindings (WASD, Shift, Space, Ctrl/C, LMB/RMB, Q, R, T, E, Tab/middle mouse, P). All UI also supports keyboard navigation.
- **Controller-ready:** all gameplay actions use the Input Map; gamepad bindings exist for some (spin, lock-on, pause, teleport, interact) but **movement, jump, attacks and dodge are not bound** (`[IMPLEMENTED]` gap found during release review). `[NEW-M4]`: complete the gamepad map and menu navigation (focus on first button, B to go back).
- **Touch (Android, mobile web):** floating stick, drag to look, buttons Jump, Atk, Heavy, Dodge, Heal, Lock, Tele, Spin, Use (contextual). `[NEW-M4]` menu screens need touch-sized controls (at least 56 px) and the pause button; the FPS toggle is in the settings menu.
- Controls remain remappable: keyboard remapping is `[PROPOSED]`; touch layout scaling is a Settings option `[PROPOSED]`.

## 5. Scaling and platforms
Stretch mode `canvas_items` with `expand` is `[IMPLEMENTED]`: logical height is never below 720. Web: the canvas resizes with the window; the first click captures the pointer (`[IMPLEMENTED]` on `master`). Mobile: landscape only; portrait shows a "rotate your device" notice `[PROPOSED]`.

## 6. Accessibility basics (`[PROPOSED]`, cheap)
Subtitles are always on; adjustable subtitle size; colour-independent rarity labels (text tag "LEGENDARY"); a reduce-screen-shake option; hit-stop off option (`[IMPLEMENTED]` as a setting level).

## 7. UI acceptance criteria
1. Every screen in section 2 exists, opens from a clear entry and can be closed with keyboard, gamepad and touch.
2. No HUD element overlaps another at the three layout sizes (extend `ui_layout_check`).
3. All existing HUD information is present (checklist in QA).
4. Text is readable at 800x360 on a real phone (human check).
5. Save/load/death feedback messages exist and are accurate.

## 8. Unverified
Touch menus on a physical phone; gamepad play (no controller has been tried); portrait handling.
