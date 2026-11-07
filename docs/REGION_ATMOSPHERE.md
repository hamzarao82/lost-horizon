# Region atmosphere: environment presets and ambience

Status date: 2026-11-06. Legend: **Verified** = a test or a screenshot that was actually run; **Not verified** = not run or not possible here.

## What exists
| Piece | File | Status |
|---|---|---|
| `EnvironmentPreset` resource (sky, sun, ambient, fog, tonemap exposure, glow, shadow distance) | `scripts/regions/environment_preset.gd` | Verified by `env_audio_check` |
| Four presets: `outpost_17`, `dead_coast`, `blackwood`, `research_complex` | `resources/regions/env/*.tres` | Verified (values); looks reviewed in screenshots |
| `EnvironmentPresets.apply(id, tween_seconds)` | `scripts/regions/environment_presets.gd` | Verified |
| Hook: `RegionManager._apply_presets` calls it on every region change (one added line) | `scripts/regions/region_manager.gd` | Verified through the hook in `env_audio_check` |
| `AudioManager.set_region_ambience(name, fade)` equal-power crossfade, two loop slots | `scripts/audio/audio_manager.gd` | State machine Verified; **nobody has heard it** |
| New sounds `ambience_coast`, `ambience_jungle`, `ambience_facility`, `bird_flush`, `metal_creak` | `tools/gen_sfx.gd`, `assets/audio/*.wav` | Files, lengths, seams and levels Verified; **sound quality not judged by a listener** |

## How applying works
- The persistent `WorldEnvironment` and `DirectionalLight3D` live in `Main` and are never detached on region travel, so presets keep working in every region.
- `apply` reads the current values, then tweens all of them with one `Tween` (default 1.5 s) and writes the exact target at the end. A new `apply` kills the running tween and starts from the current values (no jump). After the tween ends nothing runs per frame (checked by test).
- `outpost_17` equals the look authored in `Main.tscn`: a test compares every value, and a rendered neutral scene gave **0 differing sampled pixels** between the original scene and the applied preset. Returning from any region restores the exact original values (tested).
- `RegionData.environment_preset` may be empty (the region id is used) and the legacy name `outpost` is an alias of `outpost_17` (the Outpost 17 region data names it `outpost`; without the alias, returning to Outpost 17 would have applied nothing: found by the test).
- The sun's authored shadow distance is stored in the light's `lh_base_shadow_distance` meta, so `Settings` quality scaling still works on top of the preset.

## Platform scaling
Web and mobile (`OS.has_feature("web")` or `"mobile"`): glow forced off and shadow distance capped (30 m web, 25 m mobile, from the performance budget). Fog density stays as authored so readability does not change between platforms. Fog in the Compatibility renderer is already cheap, so no further "cheaper fog" step exists. Verified by value tests only; not run on web or a phone.

## The four looks (screenshots of a neutral test scene: same ground, boxes and camera for every preset)
Files: `scratchpad/m21shots/` (outside the repository).
- **outpost_17:** identical to the original scene.
- **dead_coast:** warm, bright, long sightlines, light haze. After the first screenshot the exposure was lowered (0.9 to 0.8) and the sun to 1.12 because the ground and near props were close to blown out. The horizon band is still quite bright and the scene is plain because the test scene has no real art.
- **blackwood:** dark green, low sun, dense fog. Props are clearly readable, but the whole frame is a fairly uniform teal and sky and ground have little contrast. It reads as moody, not as a dense canopy: that needs real vegetation and shadow from tree meshes, which this pass does not provide.
- **research_complex:** cool and flat (shot taken, mean pixel luminance 0.50); not looked at in detail.

## Readability check (Blackwood)
`EnvironmentPresets.readability_estimate`: brightness of a mid-grey (0.5 albedo) surface seen through 15 m of fog, `exposure * (0.5*(ambient + sun*sin(elevation)) * exp(-density*15) + 0.5*lum(fog)*(1-exp(...)))`. It is a comparison number, not a render. Current values: outpost_17 0.318, dead_coast 0.45, blackwood 0.181, research_complex 0.406. The test requires Blackwood >= 0.12 and >= 45% of Outpost 17 (it is 57%) and still darker than Outpost 17. In the rendered neutral scene the mean pixel luminance (sky included) was 0.80 for dead_coast (before the exposure change), 0.35 for blackwood and 0.50 for research_complex. This does not prove navigation is comfortable in the real region: that needs the real Blackwood scene.

## Ambience
- Region ambience name to stream: `outpost` to `ambience_loop` (unchanged), `dead_coast` to `ambience_coast`, `blackwood` to `ambience_jungle`, `research_complex` to `ambience_facility`.
- Crossfade: equal-power curve over 2 s by default; the two loops are never both loud (the quieter one peaks at about 0.71 of full level, tested), no loop exceeds the normal ambience level, interrupted fades continue from the current volumes (no pop), unknown or empty names are ignored, asking for the current region changes nothing.
- Mute and master volume are on the audio bus and are not touched by the crossfade (tested).
- Web: the new loops load on demand when first needed (one small file), not at boot. A late lazy install of the Outpost loop cannot start it again after the player has left (guard tested).
- Headless: loops are never played (the dummy driver leaks looping playback at exit); state is tested instead.
- `bird_flush` (0.9 s) is the planned Blackwood ambush warning cue and `metal_creak` (1.4 s) a facility one-shot. Both are loaded as normal SFX (`AudioManager.play(&"bird_flush")`); nothing calls them yet.
- Audio total: 2.2 MB (budget 3 MB), tested.

## Fixed along the way: loop points were too short
The project imports WAV files as QOA-compressed data. `AudioManager` set the loop end to `data.size() / 2`, which is only right for raw 16-bit audio: for compressed data it is the byte count over two. That gave a loop end of about 1.0 s for the 5 s Outpost ambience and 2.4 s for the 12 s music, so both would have restarted early (on a click, by reading the numbers; **not heard**). All loops now use `get_length() * mix_rate`. A test compares the loop end with the real frame count for all five loops. This changes how the existing Outpost ambience and music loop (they now play their full length as authored).

## Not done or not verified
- Nobody has listened to any new sound or to the crossfade. Level balance between regions is unknown.
- The look of the real regions (no real Dead Coast or Blackwood scenes existed to light); the presets were judged on a neutral box scene only.
- No sky variation beyond colours (no clouds, stars, volumetric fog, canopy light shafts).
- Web and Android: values and loading logic only, not run on either.
- `research_complex` has only a first-pass look.
