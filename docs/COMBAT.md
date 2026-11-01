# Combat

## Attack model
Attacks are `AttackData` resources (`resources/attacks/*.tres`), timed in frames at 60 Hz:
startup (no hit) -> active (hitbox on) -> recovery (vulnerable; chain or dodge-cancel allowed).
Damage is applied only by `Hitbox` while active, once per target per activation, scaled by the attacker's `damage_scale`.

| Attack | Startup | Active | Recovery | Damage | Stamina |
|---|---:|---:|---:|---:|---:|
| light_1 | 6 | 4 | 10 | 10 | 5 |
| light_2 | 6 | 4 | 12 | 12 | 5 |
| heavy_1 | 16 | 6 | 22 | 28 | 15 |

Chain: light -> light -> heavy finisher. Heavy can be started any time (or finishes a light chain).
Input buffer 0.2 s. Dodge (0.38 s, i-frames for the first 0.18 s, 20 stamina) can cancel recovery.

## Enemies
| Type | HP | Speed | Swing (startup/dmg) | Notes |
|---|---:|---:|---|---|
| Soldier | 60 | 3.2 | 30f / 12 | Telegraphs red |
| Heavy | 140 | 2.2 | 42f / 24 | Resists stagger |
| Hunter | 45 | 5.2 | 14f / 9 | 30% chance to sidestep a hit |

Attack token: with 2 or fewer enemies one attacks at a time; with more, two. The others circle at range.

## Equipment
### Weapons
Weapons multiply outgoing damage and change swing speed (`Inventory.attack_speed()`; the player scales its attack timings by it).
**Power** (used by the auto-equip rule) = `damage_multiplier x attack_speed^0.5`: speed counts half as much as damage. A weapon with lower power than the equipped one is not picked up and stays on the ground.

| Weapon | Rarity | Damage | Speed | Power | Model |
|---|---|---:|---:|---:|---|
| Improvised Blade | Common | x1.00 | 1.00 | 1.00 | bent scrap, no guard |
| Combat Knife | Uncommon | x1.25 | 1.15 | 1.34 | short, small guard |
| Iron Sword | Uncommon | x1.35 | 1.00 | 1.35 | plain arming sword |
| Military Machete | Rare | x1.50 | 1.00 | 1.50 | broad, bent tip, olive grip |
| Katana | Rare | x1.75 | 1.10 | 1.84 | long, thin, curved tip, round guard |
| Tactical Sword | Epic | x1.90 | 1.00 | 1.90 | wide guard, blue trim |
| Claymore | Epic | x2.10 | 0.85 | 1.94 | huge two-hander |
| Warden's Cleaver | Legendary | x2.30 | 0.95 | 2.24 | slab blade, red-black, glows |

Models are built in code by `scripts/visual/weapon_model.gd` (about 7 pooled meshes, swapped when `Inventory.changed` fires). Rare and better weapons glow in their rarity colour. The item's `reach` scales the model length only; the hitbox belongs to the player scene.

### Armor is a bar
Armor no longer reduces damage by a percentage. Each armor gives an **armor bar** that sits on the player's `HealthComponent` and works like a second health bar: all incoming damage drains armor first, and only the overflow reaches health.

| Armor | Rarity | Armor points |
|---|---|---:|
| Light Tactical Armor | Common | 30 |
| Reinforced Armor | Uncommon | 60 |
| Heavy Combat Armor | Rare | 100 |
| Warden Plate | Epic | 140 |

Rules:
- Equipping an armor that is better (more points) than the current one **refills the bar completely**; weaker armor is left on the ground.
- Armor does not regenerate. It is refilled only by a better armor or by **Armor Plates**.
- **Armor Plate** (+40 points) is used the moment it is picked up. It stays on the ground when the bar is already full or when no armor is worn, so it is never wasted.
- `damaged(amount)` still reports the full incoming amount (damage numbers), even when armor absorbed all of it.
- HUD: a blue bar under health (hidden until armor is worn), plus `Armor: <name> current/max` in the equipment panel.

Medkits heal 40 health (R key / Heal button). Tests: `tests/equipment_check.gd`.

## Waves
5 waves: 2 Soldiers; 2 Soldiers + Hunter; Heavy + Hunter + Soldier; Heavy + 2 Hunters; the Warden (boss).

## Lock-on
`Targeting` (scripts/combat/targeting.gd) picks the enemy nearest the screen centre within 14 m and a 75-degree cone of the camera, with a line-of-sight ray against the world. It drops the lock when the target dies or is freed, goes beyond 18 m, or is out of sight for more than 1.5 s.

| Input | Action |
|---|---|
| Middle mouse / Tab / right-stick click | `lock_on`: lock, press again to release |
| Mouse wheel / RB / LB | `target_next` / `target_prev`: switch left or right by screen position (wraps) |
| Touch "Lock" button | Lock; tapping again hops to the next enemy, and releases when there is only one |

While locked: attacks and strafing face the target (sprinting turns you to your movement), dodge still follows input, the camera eases toward keeping the target in view (mouse and touch look still nudge it), and a yellow arrow floats above the target.
Camera extras: FOV widens by 8 degrees while sprinting, and a soft lag follows player velocity. Shake is unchanged.
Tests: `tests/lockon_check.gd` (25 checks).

## Input & Moves

### Input queue
Presses are buffered in a FIFO queue (max 3, each lives 0.2 s) and handled independently every tick, so any combination works (move + sprint + attack, dodge during an attack, jump + attack, heal mid-swing).
- Keyboard/mouse/gamepad presses are read from `_input` events, so a press that starts and ends between two physics ticks (low FPS on web/Android) is never lost.
- Touch buttons use `Input.action_press`, which makes no event, so they are picked up by polling. `TouchControls` keeps the action pressed for one extra tick on release.
- A press is never queued twice (events mark the action as seen for that tick; polled repeats within one tick are ignored).
- Attacks begin on the same physics tick that consumes the press. The swing pose and lunge start on that first tick.
- Heal has its own 0.8 s buffer and works in FREE and HIT. Lock-on toggles immediately and is never queued.

### Moves
| Move | Input | Frames (startup/active/recovery) | Damage | Stamina | Notes |
|---|---|---|---:|---:|---|
| Light 1 | Attack | 6 / 4 / 10 | 10 | 5 | |
| Light 2 | Attack in recovery | 6 / 4 / 12 | 12 | 5 | |
| Light 3 | Attack in recovery | 7 / 4 / 14 | 15 | 6 | new; light combo ends here |
| Heavy | Heavy (or after any light) | 10 / 6 / 15 | 28 | 15 | retuned from 16 / 6 / 22 |
| Sprint attack | Attack while sprinting | 8 / 5 / 16 | 16 | 12 | long forward lunge; flows into light 1 |
| Air attack | Attack while airborne (or jump + attack) | 5 / 8 / 10 | 18 | 14 | dives down; landing ring (radius 2.6) hits for 80% |
| Spin | Q / gamepad Y / touch "Spin" | 6 / 10 / 18 | 20 | 30 | ring radius 3.2 around you, 6 s cooldown (`special_cooldown_left`) |

Chains: L-L-L-H and L-L-H both work; heavy finishes any light. No fourth light.
Dodge cancel: during recovery, or from the active window of a swing that has already connected. Not during startup, so a heavy cannot be dodged out of before it lands.
Jump cancels recovery. Weapon speed (`Inventory.attack_speed()`) scales how fast frames advance.
`Player.grant_invulnerability(seconds)` adds i-frames that stack by maximum, never shorten.
Tests: `tests/input_check.gd`.
