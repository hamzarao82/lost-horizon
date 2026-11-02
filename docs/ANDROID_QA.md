# Android QA (2026-11-02)

**Result: the APK was NOT run.** No phone was attached and the emulator cannot run on this PC. Everything below is static analysis of the APK and export settings, plus instructions for testing on a real phone. No frame-rate or memory numbers for Android exist yet.

## What was attempted and why it failed
| Step | Result |
|---|---|
| `adb devices` | Empty. No phone attached (the owner's Redmi K80 was not connected). |
| Hardware acceleration | WHPX is installed and usable. |
| System images | All installed images are **x86_64**: android-34 default (AOSP, no ARM translation), android-35 and 36 Google APIs / Google Play. The APK contains **arm64-v8a only**, so only a Google Play image with ARM translation could run it. |
| AVD creation | Created `lhqa` on `android-35;google_apis_playstore;x86_64` (then deleted it with `avdmanager delete avd`). |
| Boot | **Refused**: "Not enough space to create userdata partition. Available 3141 MB, need 7372.8 MB." The emulator forces a 6 GB data partition (plus 20% margin) for API 35 Play images and rewrites `config.ini` back to 6 GB on every launch, ignoring `-partition-size` and a smaller `disk.dataPartition.size`. C: has about 3.1 GB free and D: 0.5 GB. |
| Cleanup | AVD deleted, no emulator processes left, nothing else on disk changed. I did not delete any user files to make room. |

To run an emulator here, C: needs about 8 GB free (or an AVD folder on a drive with that space). Ranking by effort: connect the real phone (below), or free about 5 GB on C:.

## Static results (`tools/androidqa/static_check.ps1`, run)
| Check | Result |
|---|---|
| Package / version | `com.hamzarao.losthorizon`, versionCode 1, versionName **0.2.0** (the GitHub release is planned as v0.1.0: names differ) |
| SDK levels | minSdk **24** (Android 7.0), targetSdk 36 |
| ABI | arm64-v8a only. 32-bit-only phones and x86 devices are unsupported (almost all phones since about 2019 are fine) |
| Graphics | `uses-gl-es 0x30000` (OpenGL ES 3.0): matches the Compatibility renderer |
| Permissions | none requested (no network, no storage) |
| Orientation | landscape (`screenOrientation=0`), immersive mode on, resizeable activity |
| Signing | verifies with v2 and v3 schemes (debug keystore). Not v1: irrelevant for minSdk 24+ sideloading. Not suitable for the Play Store |
| Debuggable | **yes** (it is a debug export). Fine for testing. A store build needs a release export and a real keystore |
| `allowBackup` | false |
| zipalign | 4-byte aligned OK. Native libs are stored compressed, so Android extracts them at install. ELF 16 KB alignment of `libgodot_android.so` was **not** verified (no `readelf`) |
| Size | 29.4 MiB APK; `libgodot_android.so` 72 MiB uncompressed, classes.dex 5.5 MiB |
| aapt2 warning | `mipmap/themed_icon` for `anydpi-v26` references a missing file: cosmetic (themed icon missing), no crash |

## Bugs found (ranked)
1. **The export packs website and test files into the APK (and into the web and Windows `.pck`).** The APK contains `assets/portfolio/node_modules/...` (315 JSON files, about 9 MB uncompressed) plus 36 test scripts and `assets/docs`/`tools` entries (328 non-game files in total). The web/Windows pck grew from 0.4 MB to 9.9 MB. Cause: the export preset uses `export_filter="all_resources"` and the project folder now contains `portfolio/` (with `node_modules`), `site-assets/`, `tests/`, `tools/`, `docs/`. Fix (not done, outside my allowed files): add an empty `.gdignore` file in `portfolio/`, `site-assets/`, `docs/`, `tools/` (and in `tests/` if tests are not wanted in builds), or set `exclude_filter="portfolio/*, site-assets/*, tests/*, docs/*, tools/*"` in every export preset. Expected gain: about 9 MB less in each build, faster boot. Also a minor information-leak concern: the shipped game exposes its test and tool scripts.
2. **The FPS overlay can't be toggled on a touch phone.** It only listens for the F3 key. It is visible by default in a debug build (`visible = OS.is_debug_build()`), so the debug APK shows it automatically. A release build would hide it with no way to show it on touch. Suggest a hidden toggle (for example a long press on the wave label, or an option in the pause menu's Settings page).
3. **Version mismatch:** the APK says 0.2.0 while the first release is planned as v0.1.0. Set `version/name` to match, so testers can tell builds apart.
4. **No device or emulator evidence of any kind yet** for: touch layout on a 20:9 phone, touch look and joystick feel, audio on Android, thermal behaviour, cold start time, memory, back-button and app-pause behaviour (the touch controls handle pause and focus loss, tested only headless).

## Test instructions for the Redmi K80
**Option A: copy the file (no PC tools needed)**
1. Copy `release-assets/LostHorizon-android.apk` (29.4 MiB) to the phone (USB cable, cloud drive, or a messaging app that doesn't recompress files).
2. On the phone open it from Files. Allow "Install unknown apps" for that app when asked.
3. A debug-signed app may trigger a Play Protect warning: choose "Install anyway" / "More details > Install anyway".
4. Launch "Lost Horizon". The first start takes a while (the loading screen shows a progress bar).

**Option B: USB debugging (lets me collect evidence)**
1. Settings > About phone > tap "OS version / MIUI-HyperOS version" 7 times to enable Developer options.
2. Settings > Additional settings > Developer options: enable **USB debugging** and **Install via USB** (Xiaomi needs this and a signed-in Mi account).
3. Connect the cable, accept the "Allow USB debugging" prompt, then on the PC: `adb devices` (must show `device`).
4. Run `powershell -NoProfile -ExecutionPolicy Bypass -File tools\androidqa\device_test.ps1 -Seconds 60` and play while it waits. It installs, launches, and writes `androidqa-out/` with a screenshot, `gfxinfo.txt` (frame stats), `meminfo.txt`, and the godot logcat. (This script has not been run yet: report any error it prints.)

**What to look at and send back**
- The **FPS/draw-call/memory overlay appears top-left automatically** (debug build). Send a screenshot during wave 3 or 4 and during the Warden fight. Target 30+ FPS.
- Touch layout: stick (left half), look drag (right), buttons Jump, Atk, Heavy, Dodge, Heal, Lock, Tele, Spin, Use. Are any too small, overlapping, or out of reach? Does the "||" pause button work?
- Does the loading screen finish and how long did it take (rough seconds)?
- Sound: music loop, swings, hits, pickups.
- Does it get hot, drop frames, or close when you switch apps and come back?
- Any crash: send `androidqa-out/logcat_godot.txt` (Option B) or describe what you did right before.

## Limits
Static analysis cannot show runtime behaviour. The only numbers measured for this project are Windows (111-142 FPS on an Intel UHD 620). Android and web performance remain unmeasured.
