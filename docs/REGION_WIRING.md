# Region wiring (Milestone 7)

Dead Coast and Blackwood are now reached through the real `RegionManager`.

- `DeadCoastRegion` and `BlackwoodRegion` (thin `Region` adapters, scenes `scenes/regions/DeadCoastRegion.tscn` and `BlackwoodRegion.tscn`) own the self-contained builders `DeadCoast` and `Blackwood` as children and delegate `enter`, `capture_state` and `restore_state` to them. Vegetation density is 0.4 on web and mobile.
- `RegionManager` has two small additive hooks: if the loaded region offers `entry_transform(id)` it places the player there, and if it offers `exit_specs()` the exits are spawned from it, so the builder's tables are the single source. Regions without them (Outpost 17, the stub Research Complex) use `RegionData` as before.
- `resources/regions/dead_coast.tres` and `blackwood.tres` point at the real scenes. Their own entry and exit tables stay as fallbacks and for the map; the Research Complex stays on `StubRegion`.
- Entry ids: Dead Coast accepts `beach_arrival`, `from_outpost`, `from_south`, `from_blackwood`; Blackwood accepts `from_dead_coast`, `from_coast`, `from_underground`. Exit locks come from each destination's unlock flag (`CampaignFlow`), so the content's own `locked_flag` markers are not used.

## Verified (`tests/region_wiring_check.gd`, 39 checks, plus `campaign_bot_check` 29, `region_check` 62, `region_save_check` 42)
Real travel both ways, entry placement, exits and their targets, locks and unlocks, a real save and load inside Blackwood, claims surviving, quests started after loading, five round trips with node count and static memory back to baseline. Slowest hop in headless: Dead Coast 395 ms, Blackwood 170 ms, Outpost 17 32 ms (includes first-frame builds).
Windowed, through real travel: draw calls 111 (Dead Coast), 117 (Blackwood), 152 (Outpost 17); about 59 FPS in the two new regions and 49 back in Outpost 17 on integrated graphics.

## Not done
Web and Android untested; the tracker still shows the old arena quest and the wave counter in the new regions; no human has played either region; the Blackwood hatch has no underground.
