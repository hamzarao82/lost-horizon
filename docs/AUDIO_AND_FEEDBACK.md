# Audio and Game Feedback

Tags are explained in [MILESTONE_004.md](MILESTONE_004.md). Existing audio facts come from `assets/audio`, `tools/gen_sfx.gd`, `scripts/audio/audio_manager.gd` and `ASSETS.md`.

## 1. What exists `[IMPLEMENTED]`
All 14 sounds are **procedurally generated** by `tools/gen_sfx.gd` (22 050 Hz mono WAV, about 0.76 MB in total): `swing_light`, `swing_heavy`, `hit_light`, `hit_heavy`, `hurt`, `dodge`, `pickup`, `equip`, `heal`, `enemy_swing_windup`, `enemy_death`, `wave_start`, `teleport`, and a 12-second seamless `music_loop`. `AudioManager` is an autoload with 8 pooled players, a music player, master and music volume in the settings, and wires enemy and wave sounds through signals. No sound has been judged by ear in an actual mix `[UNVERIFIED]`.

## 2. Gap analysis against the brief

| Category | Status | Need |
|---|---|---|
| Player footsteps | missing | surface-aware light steps (sand, concrete, metal), walk/run/sprint rates |
| Weapon swings | `[IMPLEMENTED]` light/heavy | variants per weapon class (knife quick, claymore heavy) `[PROPOSED]` |
| Weapon impacts | `[IMPLEMENTED]` light/heavy | flesh-less "armor" and "boss" impact variants |
| Enemy attacks | windup only | per-type attack sounds |
| Enemy reactions | death only | hit grunts (non-verbal), stagger |
| Boss attacks | missing (uses generic sounds) | slam, shockwave, leap, charge, roar, phase-change sting, death |
| Teleport | `[IMPLEMENTED]` | fine |
| Medkit use | `heal` exists | a short "inject" layer |
| Loot collection | pickup/equip | rarity-based chime (higher rarity, richer) |
| UI feedback | missing | button hover/click, tab switch, objective complete, mission update |
| Mission completion | missing | completion sting and results screen music |
| Environmental ambience | missing | beach waves, wind, insects, distant gulls; courtyard hum; interior room tone |
| Jungle ambience | missing | birds, insects (the slice has a beach and an outpost; jungle only as backdrop) |
| Military radio transmissions | missing | static burst, short beeps, a handset click for each transmission |
| Background music | one loop | exploration loop, combat intensity layer, boss track, mission-complete stinger |

## 3. Sourcing options (no download is assumed, no URL is invented)
| Option | Description | Licence effort | Quality |
|---|---|---|---|
| A. Extend the procedural generator | add footsteps, UI, radio, ambience and boss sounds to `tools/gen_sfx.gd` | none (all original) | functional, synthetic |
| B. CC0 or purchased packs supplied by the owner | the owner downloads packs and places them in `assets/audio/`; every file gets a row in `ASSETS.md` | per-file ledger | better; recordings sound natural |
| C. Self-recorded | the owner records footsteps, impacts, ambience | none if original | depends on equipment |
| D. Hybrid (recommended `[PROPOSED]`) | keep procedural sounds as the always-available fallback, replace the most noticeable ones (footsteps, ambience, music, boss) with licensed recordings | per-file ledger | best value |

Rule: a sound without a recorded licence is not shipped. Non-commercial-only licences are not allowed. AI-generated audio is not used unless its terms clearly allow this use and the owner approves.

## 4. Mix design (`[NEW-M4]`)
Audio buses: **Master → SFX, Ambience, Music, UI, Radio**. Each has its own volume in Settings (today only master and music are exposed).

| Rule | Value |
|---|---|
| Music level | about -14 dB under SFX; ducks 4–6 dB for 1.5 s on a radio transmission and on boss attacks |
| Priority | boss and player damage sounds are never dropped; footsteps and ambience are dropped first when the 8-player pool is busy |
| Concurrency | pool raised to 12–16 on desktop, kept at 8 on mobile and web (`[PROPOSED]`, to be measured) |
| Pitch variation | ±6% on repeated sounds (existing) |
| Panning | non-positional is acceptable for the slice; positional audio for boss and enemy attacks is `[PROPOSED]` if cheap on web |
| Peak limiting | master limiter to prevent clipping when many hits overlap |

## 5. Platform constraints
- **Web:** audio starts after the first user gesture; keep total audio under about 1.5 MB (the current set is 0.76 MB); prefer OGG for music and ambience, WAV for short effects.
- **Android:** many simultaneous voices cost CPU; keep the pool small; test audio focus loss when the app is backgrounded `[UNVERIFIED]`.
- **Memory:** stream music and ambience, preload only the short effects.

## 6. Combat feedback matrix (existing and proposed)
| Event | Sound | Visual | Haptic/camera | Status |
|---|---|---|---|---|
| Light hit | `hit_light` | sparks, damage number, hit-stop (≤0.03 s) | small shake | `[IMPLEMENTED]` |
| Heavy hit | `hit_heavy` | big sparks, ring, hit-stop (≤0.07 s) | larger shake | `[IMPLEMENTED]` |
| Taking damage | `hurt` | red number, flash | shake | `[IMPLEMENTED]` |
| Armor absorbing | armor clank variant | blue flash on the armor bar | none | `[NEW-M4]` |
| Block-less dodge | `dodge` | dust | none | `[IMPLEMENTED]` |
| Enemy windup | `enemy_swing_windup` | red tint and ground ring | none | `[IMPLEMENTED]` |
| Boss attack | boss-specific | floor wedge fills to the strike frame | strong shake on impact | partly `[IMPLEMENTED]`, sounds `[NEW-M4]` |
| Pickup | rarity chime | light column, label | none | partly |
| Mission update | chime | banner | none | `[NEW-M4]` |
| Death | `enemy_death` | burst and ring | none | `[IMPLEMENTED]` |

**Touch devices:** haptic feedback (vibration on heavy hits and damage) is `[PROPOSED]`, off by default, with a setting.

## 7. Acceptance criteria for audio
1. Every item in section 2 has at least one sound (procedural or licensed) and an entry in `ASSETS.md`.
2. No clipping in a scripted heavy fight (measured by peak level of the mix).
3. Music ducks under radio lines; dialogue subtitles always stay readable.
4. The mix is reviewed by ear on desktop speakers, headphones and a phone speaker; findings are recorded.
5. Total audio size under 3 MB for web, and web load time does not regress (the web build decoded audio at boot before the loading fix; keep it lazy).

## 8. Unverified
Quality of the procedural sounds in a real mix; Android audio latency and focus handling; the effect of 16 voices on web performance.

## Implementation status (Milestone 4, procedural sounds)
All sounds are synthesized by `tools/gen_sfx.gd`; no external audio. Total audio is about 1.3 MB. **Nothing here has been listened to by a person**; the tests prove that files load and hooks fire, not how they sound.

| Sound | Status |
|---|---|
| `footstep` | `[IMPLEMENTED]` played by `AudioManager` from a physics tick while the player is on the floor, in the FREE state, moving faster than 2 m/s (every 0.44 s walking, 0.30 s at 6.5 m/s or more); no steps in the air, while dodging, attacking, dead or paused |
| `ambience_loop` | `[IMPLEMENTED]` 5 s wind/surf bed at -24 dB on the master bus (mute and master volume apply); loaded lazily on web |
| `radio_static`, `radio_beep` | `[IMPLEMENTED]` played with every `QuestManager.caption_requested` subtitle, so story, radio and boss captions all get the blip |
| `boss_slam`, `boss_charge`, `boss_leap`, `boss_roar`, `boss_fire`, `mission_complete`, `ui_click` | `[IMPLEMENTED]` earlier in Milestone 4 |
| Per-surface footsteps, positional audio, music layers, real mix and ducking | `[NOT DONE]` |

Covered by `tests/audio_check.gd`.
