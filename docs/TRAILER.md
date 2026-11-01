# Trailer and screenshots

The trailer (`portfolio/public/trailer.mp4`, 44.9 s, 10.97 MB, H.264 + AAC, 1280x720, 30 fps) and the nine screenshots in `portfolio/public/screens/` are recorded from the real game by `tools/trailer/director.gd`. Nothing is faked: the bot uses the same input actions as the touch controls, and the only direct state changes are the ones listed under "Shortcuts".

## Re-record

Needs a real display (the window opens for about 70 s). Godot's movie writer is supported and fast on this machine: the whole run takes about 70 s and produces about 140 MB of raw MJPEG AVI, so there was no need for the frame-by-frame fallback.

```powershell
$g  = "C:\Tools\Godot\4.7.2\Godot_v4.7.2-stable_win64_console.exe"
$sp = "$env:LOCALAPPDATA\Temp\claude\...\scratchpad\trailer"     # any folder with ~200 MB free
& $g --path . --write-movie "$sp\raw.avi" --fixed-fps 30 --resolution 1280x720 `
     -s tools/trailer/director.gd -- --shots="$sp\shots"

# encode (ffmpeg from winget: Gyan.FFmpeg.Essentials); 44.87 s long, fade out starts at 43.87 s
ffmpeg -y -i "$sp\raw.avi" `
  -vf "fade=t=in:st=0:d=1,fade=t=out:st=43.87:d=1,format=yuv420p" `
  -af "afade=t=in:st=0:d=1,afade=t=out:st=43.87:d=1" `
  -c:v libx264 -crf 26 -preset slow -r 30 -c:a aac -b:a 96k -movflags +faststart portfolio\public\trailer.mp4
ffmpeg -y -ss 17 -i portfolio\public\trailer.mp4 -frames:v 1 -q:v 3 portfolio\public\trailer-poster.jpg

# screenshots: re-encode each shot for size and copy to portfolio\public\screens\<n>-<name>.png
ffmpeg -y -i "$sp\shots\beach_radio.png" -vf scale=1280:-2 -compression_level 100 portfolio\public\screens\1-beach_radio.png

# rebuild the site (in Git Bash set MSYS_NO_PATHCONV=1 so /lost-horizon is not rewritten to a Windows path)
cd portfolio; $env:NEXT_PUBLIC_BASE_PATH="/lost-horizon"; npm run build
```
Delete `raw.avi` and the `shots` folder afterwards (about 140 MB).
The fade-out time must be changed if the length changes: read it with `ffmpeg -i raw.avi`.

## What the bot does (about 45 s)

| Time | Scene | How |
|---|---|---|
| 0-6 s | Beach arrival, radio | Walks to the radio hut with the move actions; presses `interact`; the radio captions and the quest banner come from the game |
| 6-12 s | Restore the power | Cuts to each of the three breakers (fade, place the player beside it on the open side, press `interact`); the game itself flips them and unlocks the gate |
| 12-16 s | Gate opens | Cuts to the gate, then sprints into the courtyard; the courtyard trigger starts the waves |
| 16-32 s | Waves 1-2 | Bot walks to the nearest enemy, light-light-light-heavy chain, dodges committed swings, spins when two enemies are close, picks up a Claymore dropped for the shot (equips: x2.10 damage), uses a medkit below 52 HP, locks on, teleports |
| 32-42 s | The Warden | Cinematic orbit around the boss, then the bot fights him (the first slam brings the shockwave; phase 2 and the summoned soldiers appear) |
| 42-45 s | Title card | Fade to black, "LOST HORIZON: BLACK SITE", fade out |

Captions (FIGHT, LOOT, LOCK ON, TELEPORT, RESTORE THE POWER, THE GATE OPENS, WAKE UP. SURVIVE.) are a code-built label.

## Shortcuts the director takes (so the footage is honest about them)
- It skips the story opening (`QuestManager.intro_done = true`), because the trailer cuts its own intro.
- The three switches and the gate are really operated, but the player is moved next to each switch instead of walking there.
- To reach the boss in time it frees the remaining wave enemies and starts wave 5 (`WaveManager.start_wave_at(5)`); waves 3 and 4 are not shown.
- It sets the Warden's private `_attack_count` to 2 so his first attack is the shockwave.
- The player gets a Military Machete, Reinforced Armor and two medkits at the start, and a Claymore drops during the fight.
- If health falls below 24 it heals 40 so the bot cannot die.
- Lock-on is toggled through `Player.toggle_lock()`; it is event-driven and cannot be pressed through `Input.action_press`.
- The player's real save slot and teleport charges are untouched: `SaveManager.test_mode = true` and the teleport ability writes to a temporary file that the director deletes at the end.

## What the footage shows, and what it does not
- Real gameplay: movement, combos with damage numbers and sparks, the lock-on arrow, the Claymore pickup and its toast, the teleport effect, the armor/health/stamina bars, the wave counter, the Warden's health bar and his summoned soldiers.
- The characters are still the placeholder box people (the Milestone 002 art upgrade has not started), and the environment is the current primitive island.

## Known problems seen in the footage (game, not director)
- The quest banner "QUEST COMPLETE" is drawn at the same height as the radio subtitle lines, so they overlap for a few seconds right after the radio and after the switches.
- Caption queue lag: when story steps fire very quickly (as in the cut-heavy trailer) the subtitle line shows older text while the fight is already running.
- The enemy name labels, damage numbers and pickup labels can overlap (3D labels).
- A pickup label is very large when the camera is almost on top of it.

## Known limits of the recorder
- Needs a display; it cannot run `--headless`.
- The mouse is hidden by the game's camera on startup; the director sets it visible again.
- Movie mode renders at a fixed 30 fps regardless of speed, so hit-stop (which uses real time) is shortened in the footage.
- The raw capture is large (about 140 MB for 45 s); keep 200 MB free.
