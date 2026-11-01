# Trailer director

`director.gd` plays the real game with a bot and records it with Godot's movie writer. Full instructions: [docs/TRAILER.md](../../docs/TRAILER.md).

```powershell
$g = "C:\Tools\Godot\4.7.2\Godot_v4.7.2-stable_win64_console.exe"
& $g --path . --write-movie "$env:TEMP\raw.avi" --fixed-fps 30 --resolution 1280x720 `
     -s tools/trailer/director.gd -- --shots="$env:TEMP\shots"
```

It needs a real display (not `--headless`). It does not touch your real save or teleport charges.
