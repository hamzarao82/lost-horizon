# Enemy patrols (Milestone 3)

Patrol behaviour is **additive**: `Enemy` gained four states (`PATROL`, `SUSPICIOUS`, `SEARCH`, `RETURN`, appended to the enum so existing values are unchanged). They are used only by enemies given a `PatrolRoute`. Wave enemies, the courtyard encounter and the Warden never have one, so their behaviour and the `run_tests` / `boss_check` expectations are untouched.

## Pieces
- `PatrolRoute` (Node3D): local waypoints, `loop` (A,B,C,A...) or ping-pong (A,B,C,B,A...), `wait_seconds` at each point.
- `PatrolGroup` (Node3D): wakes on `WorldState.area_entered(area_id)`, spawns its squad once (cap: **4 active patrollers** overall), positions each enemy on its route before adding it to the tree, and sets the flag `patrol_<id>_cleared` when every member is dead. A group whose flag is already set never spawns, so a wiped squad stays dead after a reload (the flag is saved with the world flags).
- `DetectionComponent.can_see`: flat range, field-of-view cone (130 degrees), and a ray against the world layer (walls and doors block sight, characters do not).

## Behaviour
```
PATROL -> (player seen long enough, or very close) -> CHASE (alert)
PATROL -> (saw something, lost it) / (heard combat nearby) -> SUSPICIOUS: walk to the last known position
SUSPICIOUS -> arrive / timeout 8 s / stuck -> SEARCH (5 s, looks around)
SEARCH -> RETURN: walk to the nearest waypoint -> PATROL
CHASE -> player lost (> 24 m) -> SUSPICIOUS at the last known position -> ... -> back on the route
```
- Suspicion builds at 1.6 per second while a player farther than 6 m stays visible (instant inside 6 m).
- Combat noise: a landed hit makes patrollers within 12 m of the victim suspicious.
- Being hit staggers the enemy and then it chases like any other enemy.
- Never stuck: movement with no progress for 2 s skips the waypoint (patrol), gives up and searches (suspicious) or resumes patrolling (return). If a route node disappears the enemy becomes an ordinary idle enemy.

## Placement
`Outpost17` creates one squad, `c_guards` (a soldier and a hunter), walking the research wing's central corridor (x = -1, z from -36 to -58). It wakes when the player enters the courtyard (`area_b_compound`), so the guards are already on their beat when the player reaches the door.

## Not done / limits
- Movement is direct steering plus stuck recovery. There are no baked navigation meshes; the routes avoid all walls and props. Complex interiors would need `NavigationAgent3D`.
- Only one squad exists; Area D has none yet.

Tests: `tests/patrol_check.gd` (24 checks: route walking, noticing, behind-the-back, wall blocking sight, noise -> search -> return, stuck recovery, being hit, neighbour noise, groups, the 4-patroller cap, cleared flag, ordinary enemies and the Warden unchanged).
