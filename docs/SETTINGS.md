# Settings and pause menu

## Controls
| Input | Action |
|---|---|
| P / gamepad Start | Open or close the pause menu (`pause` action) |
| Touch "\|\|" button (left, below the stamina bar) | Open the menu; shown only once a touch is seen or on mobile |
| Esc | Still only releases the mouse (CameraController); it does not pause |

Menu: Resume, Restart, Settings, Quit (hidden on web and mobile). Buttons are 56 px high with 24 pt text; keyboard and gamepad focus work (the first control is focused on every page).
While the menu is open, touches are converted to mouse clicks, because the project sets `emulate_mouse_from_touch=false` (a tap must not trigger the left-click light attack in the game).

## Settings (autoload `Settings`)
Stored in `user://settings.cfg` (IndexedDB on web), saved 0.5 s after the last change and when the menu closes.

| Setting | Range | Default | Effect |
|---|---|---|---|
| Master volume | 0-1 | 1.0 | `AudioManager.set_master_volume` (Master bus) |
| Music volume | 0-1 | 1.0 | Music player volume (base -14 dB) |
| Mouse sensitivity | 0.25-3 | 1.0 | Multiplier on `CameraController.mouse_sensitivity` (authored 0.0025) |
| Touch look sensitivity | 0.25-3 | 1.0 | Multiplier on `TouchControls.look_sensitivity` (authored 0.004) |
| Quality | Low / Medium / High | Low on mobile or a mobile browser, else High | See below |

There is no separate SFX slider: `AudioManager` has one pool and the Master bus only.

### Quality presets
| Preset | Shadows | 3D render scale |
|---|---|---|
| Low | off | 0.7 |
| Medium | on, max 20 m | 0.85 |
| High | as authored in the scene (40 m) | 1.0 |

Applied to every `DirectionalLight3D` (found as nodes enter the tree) and the root viewport's `scaling_3d_scale`. Authored light values are remembered in node metadata, so switching back to High restores them. Render scale may have no visible effect in the Compatibility renderer on some drivers.

## Project settings added
`pause` input action; `[autoload] Settings`; `display/window/handheld/orientation=0` (landscape); `rendering/textures/vram_compression/import_etc2_astc=true` (needed for Android export; the Web preset keeps mobile VRAM compression off).

## Tests
`godot --headless --path . -s tests/menu_check.gd` covers save/load, clamping, pause toggling, sensitivity and quality application.
