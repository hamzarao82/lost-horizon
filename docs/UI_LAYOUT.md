# HUD layout

All HUD placement comes from one pure function, `Hud.plan_layout(viewport_size, touch)` (scripts/ui/hud.gd),
which returns a rectangle per widget. `_process` positions the widgets from it, and
`tests/ui_layout_check.gd` verifies that no two rectangles overlap and that none sits under a touch button.

## Bands (logical pixels; the project stretches to at least 1280x720)

| Band | Widgets |
|---|---|
| Top edge | wave label (centre, y 12), equipment panel (right, y 12-94) |
| Boss | boss name (y 40), boss bar (y 66-86, at most 440 px and 34% of the width, clear of the equipment panel) |
| Banner band (upper third) | `WAVE n`, `QUEST COMPLETE`: one at a time, 1.6 s each, queue of 3, y 98 |
| Left column | health/armor/stamina bars (y 90-134), teleport label (y 146), pause button (touch, y 140), quest tracker (y 205+) |
| Bottom | interaction prompt, then subtitle (two lines), then toast (y H-110), then the controls hint (y H-30, desktop) |
| Touch | button column at the right edge; with touch on, the subtitle, prompt and toast are centred in the free area left of it |

## Rules
- **Banners** never share a band with subtitles; they queue, they do not stack.
- **Subtitles**: at most two lines, wrapped at about 60% of the screen width (720 px max); long text is split at sentence ends
  into pieces of at most 110 characters; reading time is 3-6 s from the text length (a caller that explicitly asks for under 3 s gets exactly that); at most 3 wait in the queue
  (the oldest is dropped). A wave start or the boss appearing drops the queue and fades the line on screen.
- **Enemy labels**: only the locked-on or nearest enemy shows its name/health label, fading out between 10 and 16 m.
  The boss has no floating label (the boss bar names it).
- **Damage numbers**: random origin spread, a sideways drift as they rise (so they clear the enemy label), size follows camera
  distance (0.6-1.5x).
- **Pickup labels**: size follows camera distance (0.5-1.5x), only the 3 nearest show one, and close ones stack vertically.
- **Interaction prompt** sits just above the subtitle band (`Hud.prompt_position`).

## What was wrong before (from the trailer footage)
- `WAVE n` was drawn at 25% of the screen height, in the middle of the fight, over enemy labels.
- The interaction prompt (H-170) sat on top of the three-line subtitle (up to H-184).
- With touch on, the centred subtitle ran under the Spin and Heal buttons.
- Every enemy and pickup label was always visible; a pickup label became huge when the camera was close.
- The controls hint was pinned to y=690 regardless of the window height.

## Checking it
- Headless: `godot --headless --path . -s tests/ui_layout_check.gd` (44 checks: plan overlaps at 1280x720, 1600x720 and
  1280x2844 with touch on and off, touch circles vs widgets, caption and banner rules, label limits on a live scene).
- Windowed screenshots: run the game at `--resolution 1280x720`, `800x360` and `360x800` (stretch turns these into 1280x720,
  1600x720 and 1280x2844 logical sizes) and look at wave start, quest complete with a subtitle, and a boss fight.

## Not covered
- The text widths used in the plan are conservative constants, because headless text measurement is unreliable.
- A real phone has not been tried. The `OUTPOST 17` location title (drawn by the world scripts, not the HUD) stays on screen for
  several seconds at about y 190, below the banner band.

## Milestone 002: HUD theme, icons and bars (FX-HUD agent)

Presentation only; every HUD item and the `Hud.plan_layout` contract are unchanged (bars block 240 x 44 at (16, 90)).

- **`scripts/ui/hud_theme.gd` (`HudTheme`)**: colours (health red, armor blue, stamina green, quest gold, teleport cyan),
  font sizes (15 / 18 / 22 / 30), `panel_style()` (rounded translucent panels), `style_label()` and a cached shared `Theme`
  (outlined labels, rounded dark buttons with gold hover/focus, rounded panels). The HUD root, the pause menu and its
  button use it.
- **`scripts/ui/hud_icons.gd` (`HudIcons`)**: vector icons drawn with `_draw()` calls (heart, shield, bolt, medkit, swirl,
  sword, heavy, armor, chevron, crosshair, spin, dodge, use). No textures, scale to any size.
- **`scripts/ui/hud_bar.gd` (`HudBar`)**: rounded bar with an optional icon and `cur/max` text. Same `max_value` / `value`
  names as `ProgressBar`. The fill eases toward the value, a lighter "ghost" segment shows recent loss before it drains, the
  first value snaps, and it only redraws while something is moving.
- **Bars:** health 18 px (heart + numbers), armor 14 px (shield + numbers, hidden until armor is worn), stamina 8 px.
- **Equipment panel (`HudEquipment`)**: weapon with a rarity chip and damage modifier (and speed if not 1.0), armor with
  points, medkits with the `[R]` hint.
- **Teleport readout (`HudTeleport`)**: swirl icon, two charge pips, `READY [T]` or `mm:ss [T]`. Read-only from the player's
  `TeleportAbility`; the ability's own text label is hidden (its toast still shows). A denied use nudges the readout.
- **Backdrops:** translucent rounded panels behind the wave label, toast, quest tracker and subtitle, fitted to the labels
  every frame (the subtitle is measured so short lines get a snug panel).
- **Touch buttons:** dark translucent discs with a ring and an icon plus a small caption; positions unchanged.

### Screenshots checked (windowed, Intel UHD 620)
1280x720, 800x360 (touch, stretched to 1600x720) and 360x800 (portrait, touch): the bars, equipment panel, teleport readout,
tracker, banner, caption and toast all fit with no overlap; at 360x800 nothing is off-screen (the game is landscape-first, so
text is small there).

### Tests
`tests/ui_layout_check.gd` (56 checks): layout plan overlaps and touch-button clearance at three sizes, captions, banners,
labels, and the new widgets (bar easing/snap/clamp, teleport text, equipment data, backdrops, icon drawing, theme caching, every
touch button has an icon).
