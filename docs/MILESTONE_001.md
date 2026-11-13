# Milestone 001 report: first playable combat prototype

Status date: retrospective (written 2026-11-13; the work itself predates this document — see git history on `master` before the `milestone-002` branch point). This fills a gap: Milestones 3 onward each got a status report (`MILESTONE_003_REPORT.md` onward) but the first two never did. Legend: **Implemented**, **Verified** (a test was actually run), **Not tested**.

## What this milestone was
The first playable slice: a combat prototype proving the core loop (movement, melee combat, a five-wave arena, a boss, loot, saves, a web and Android export) before any stylized visuals or world content existed. Characters were box placeholders; there was no Outpost 17 world yet, just the arena.

## What was built
| Area | Built | Evidence |
|---|---|---|
| Player | `CharacterBody3D`, FSM (FREE/DODGE/ATTACK/HIT/DEAD), input queue with buffering, lock-on, light combo (3 hits), heavy, sprint/air/spin attacks, dodge i-frames | `run_tests` (72), `input_check` (51), `lockon_check` (25), `hitstop_check` (13) |
| Enemies | `Enemy` states (IDLE/CHASE/ATTACK/STAGGER/DEAD), the Warden boss (`Warden extends Enemy`) with its original attack set and phases | `boss_check` (20) |
| Health and equipment | `HealthComponent` with an armor pool, `Inventory`/`ItemData`/`LootTable`/`Pickup`, medkits, teleport (2 charges, 10-minute recharge) | `equipment_check` (61), `teleport_check` (51) |
| Combat feedback | Hit-stop, damage numbers, a small effects pool | `fx_check` (28) |
| Arena | `WaveManager`, five waves, the Warden on wave 5 | `run_tests`, `boss_check` |
| Save/boot/settings | A versioned save, boot flow, a settings menu | `save_check` (62), `boot_check` (32), `menu_check` (17) |
| Platforms | Web export (single-thread, GL Compatibility) and a debug-signed Android APK | both exported; see Performance below |

## Acceptance (by the standard this project later adopted: a feature counts as working only when a test proves it)
All of the above rows are **Implemented and Verified** by the automated suites listed, which exist in the repository today and still pass (they are part of every later milestone's full regression run). What was **not** verified at the time: a human playtest, and Android on a physical device (the debug APK was built and exported, never installed and run on hardware).

## Performance (Intel UHD 620 laptop, `tests/benchmark.gd`)
Avg FPS 93 to 99 (one quiet run measured 142), 1% low 47 to 49, peak draw calls 177 to 181, with box-placeholder characters. Web export: wasm 37.7 MB (about 10 MB gzipped), pack 0.57 MB, time to playable about 27 to 30 s after a shading fix (was about 80 s before it). Windows exe about 104 MB plus the 0.57 MB pack. Android debug APK about 27.5 MB. A `v0.1.0` release's assets (`release-assets/LostHorizon-windows.zip`, `LostHorizon-android.apk`) were prepared from this milestone's code; the public GitHub release itself needed the owner's approval and is tracked separately in `RELEASE_READINESS.md`.

## Known limits at the time
- Box-placeholder characters (no stylized art yet — that is Milestone 002).
- No explorable world; the arena was the whole game.
- Android never run on a physical device.
- No human playtest recorded.
- This document was written after the fact, from the test suites and performance numbers that survive in the repository; it does not capture day-to-day decisions made during the milestone itself (those are in the conversation history, not reproduced here).
