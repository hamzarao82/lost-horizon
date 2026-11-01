# Performance log

Budgets: Windows 60 FPS; web and Android 30 FPS; web under 50 MB build and ~1 GB RAM; textures 512 (1024 hero only); 4 active enemies.
Dev machine: i7-8650U, Intel UHD 620, 15.9 GB. Android test device: Redmi K80.
Overlay: F3 toggles (on by default in debug builds).

| Date | Build | Platform | Scene | Avg FPS | Draw calls | Mem MB | Size MB | Notes |
|---|---|---|---|---|---|---|---|---|
| 2026-11-01 | Godot 4.7.2 | Web export (no threads) | Test arena | not measured | n/a | n/a | 39 MB wasm (~10 MB gzip) + 71 KB pck | Export works; not yet run in a browser |
| 2026-11-01 | Godot 4.7.2 | Windows export | Test arena | not measured | n/a | n/a | 105 MB | Export works |
