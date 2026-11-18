# Review video: the opening story video

`tools/review/record_opening.tscn` (root script `record_opening.gd`) records the game's opening as one MP4 with Godot's Movie Maker, from the real game, windowed.

- Sequence: a 3 s black title card ("LOST HORIZON: BLACK SITE", "The Opening"), then the real opening exactly as a New Game plays it (`OpeningCinematic`, then `OpeningBeach`, which hands control to the Player), then a 2 s "Recover your payment." card, then the engine quits.
- It instances `res://scenes/main/Main.tscn` directly (not Boot), with the WaveManager `autostart` off. `QuestManager` starts the opening itself when the Player appears.
- Safety: `SaveManager.test_mode` is set first, so the real save file is never read or written.
- Failsafe: quits after 240 s of game time, or with an error if the opening never starts within 30 s.

Command (run from the repo root, or use the script):

```
powershell -ExecutionPolicy Bypass -File tools/review/record_opening.ps1
```

This runs `Godot --headless --import`, then `Godot --path <worktree> --write-movie <tmp>.avi --fixed-fps 30 --resolution 1280x720 res://tools/review/record_opening.tscn`, then encodes with ffmpeg (H.264 CRF 20, AAC 160k) and deletes the AVI.

Output: `C:\Users\SCS\OneDrive\Documents\GitHub\lost-horizon-review-hub\videos\lost-horizon-opening-<YYYY-MM-DD>.mp4` (the `-Out` parameter overrides it).

Known limits:
- Recording runs slower than real time on the weak test machine (Intel UHD 620); expect several minutes.
- Movie Maker needs a window, so it cannot run headless or on a machine without a display.
- Caption cards between the cinematic and the beach are not included, so the game timing is untouched.
- The cinematic uses simplified stand-in models (see `docs/OPENING_CINEMATIC.md`), so the video shows them as they are in the game.
