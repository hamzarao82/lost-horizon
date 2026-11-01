# Release process

Everything runs from the repo root on Windows. Godot is `C:\Tools\Godot\4.7.2\Godot_v4.7.2-stable_win64_console.exe` (alias it as `$G` below). Export templates for 4.7.2 must be installed (Editor > Manage Export Templates).

## 0. Before you start

```powershell
# Tests: every line must end with "0 failed"
foreach ($t in 'run_tests','boss_check','menu_check','lockon_check','save_check','fx_check','equipment_check','teleport_check','input_check','boot_check') {
  Write-Host "== $t"; & $G --headless --path . -s "tests/$t.gd" 2>&1 | Select-String 'checks|FAIL'
}
& $G --headless --path . --import
```

Frame rate (needs a real window, vsync off):

```powershell
& $G --path . -s tests/benchmark.gd 2>&1 | Select-String BENCH
```

Add the result to the table in [PERFORMANCE.md](PERFORMANCE.md).

## 1. Export

```powershell
New-Item -ItemType Directory -Force build\web, build\windows, build\android | Out-Null
& $G --headless --path . --export-release "Web"             build/web/index.html
& $G --headless --path . --export-release "Windows Desktop" build/windows/LostHorizon.exe
& $G --headless --path . --export-debug   "Android"         build/android/LostHorizon.apk
```

Notes:
- **Web** must stay single-threaded (`variant/thread_support=false`, already set). GitHub Pages cannot send the COOP/COEP headers a threaded build needs. If the export fails with an empty "configuration errors" message, check that the mobile texture-compression option matches the project setting `rendering/textures/vram_compression/import_etc2_astc`.
- **Android** uses the JDK and SDK paths in Godot's editor settings and the debug keystore Godot created (`%APPDATA%\Godot\keystores\debug.keystore`). That keystore is for local debug signing only and must never be committed. A Play Store build would need your own release keystore.
- Check the Android package after export: `apksigner verify --verbose build\android\LostHorizon.apk`.

## 2. Package the downloads

```powershell
Compress-Archive -Path build\windows\LostHorizon.exe, build\windows\LostHorizon.pck -DestinationPath LostHorizon-windows.zip -Force
Copy-Item build\android\LostHorizon.apk LostHorizon-android.apk -Force
```

The site's Download buttons link to `releases/latest/download/LostHorizon-windows.zip` and `.../LostHorizon-android.apk`, so keep exactly these names.

## 3. Publish the downloads (GitHub Release)

Upload from your machine so large binaries never enter git history:

```powershell
gh release create v0.2.0 LostHorizon-windows.zip LostHorizon-android.apk --title "Lost Horizon v0.2.0" --generate-notes
# later, to replace a file:
gh release upload v0.2.0 LostHorizon-windows.zip --clobber
```

`.github/workflows/release.yml` does the same from CI if you commit the two files into `release-assets/` (each file must be under 100 MB; prefer the command above).

## 4. Publish the playable web build (GitHub Pages)

The Pages workflow does not run Godot. It copies a prebuilt export from `site-assets/play/` into the site, so commit that folder:

```powershell
Remove-Item site-assets\play -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force site-assets\play | Out-Null
Copy-Item build\web\* site-assets\play\ -Recurse
git add site-assets portfolio
git commit -m "Update web build"
git push
```

Then in the repository settings enable **Pages > Build and deployment > Source: GitHub Actions** (once). The `Deploy site` workflow publishes:

| URL | Content |
|---|---|
| `https://hamzarao82.github.io/lost-horizon/` | portfolio page |
| `https://hamzarao82.github.io/lost-horizon/play/` | the Godot web build |

The wasm file is about 39 MB. Pages serves it as `application/wasm` and normally compresses it in transit (about 10 MB). Each web update adds roughly 40 MB to the repository history, so refresh `site-assets/play` sparingly, or publish the web build from a separate `gh-pages` branch if the repo grows.

## 5. Screenshots and trailer

- Screenshots: save PNG files (1280x720 or 1920x1080) in `portfolio/public/screens/`. As soon as one PNG, JPG or WebP exists the placeholder SVGs stop showing. File names become captions: `boss-fight.png` shows "boss fight".
- Trailer: save an H.264 MP4 as `portfolio/public/trailer.mp4`. The page shows a Trailer section only when the file exists. Keep it under ~25 MB.
- Rebuild and check locally:

```powershell
cd portfolio
$env:NEXT_PUBLIC_BASE_PATH = "/lost-horizon"
npm ci
npm run build          # output in portfolio/out
```

## 6. Pre-publish check

```powershell
powershell -ExecutionPolicy Bypass -File tools\publish_check.ps1
```

It reads only. It fails on keystores or private keys, token patterns, files over 90 MB, a missing `.gitignore` entry for `build/` or `.godot/`, and missing LICENSE, README or `docs/ASSETS.md`. Fix every ERROR before pushing.

## Versioning

Bump `version/code` and `version/name` in the Android preset in `export_presets.cfg` for each release, tag the commit `vX.Y.Z`, and note the changes in the GitHub release.
