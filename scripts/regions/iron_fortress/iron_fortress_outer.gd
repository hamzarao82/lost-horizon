class_name IronFortressOuter
extends RefCounted
## The first three areas of the Iron Fortress: the approach road and main gate, the outer defensive
## perimeter, and the military barracks. Each function builds one area into its own kit (so Milestone 13 can
## replace one area's art without touching the others) and registers its interactables with `parts`.
## A clear lane (|x| <= 3) runs down the middle of every area: solid props sit to the sides, for cover and
## as landmarks. Placeholder art: boxes and glow strips.

const Z = preload("res://scripts/regions/iron_fortress/iron_fortress_zones.gd")


static func approach(parent: Node3D, parts: IronFortressParts) -> ResearchComplexKit:
	var k := ResearchComplexKit.new(parent, "Approach")
	k.floor_rect(Vector2(0.0, 24.0), Vector2(68.0, 64.0), 0.0, Z.GROUND)
	k.floor_rect(Vector2(0.0, 24.0), Vector2(9.0, 64.0), 0.03, Z.ASPHALT)
	var z := 52.0
	while z > -4.0:
		k.glow(Vector3(0.0, 0.07, z), Vector3(0.25, 0.02, 2.6), Color(0.9, 0.85, 0.5))
		z -= 6.0
	# fence line along both sides and the road gap at the south end (the way back to the Research Complex)
	k.wall_z(-Z.HALF_W, Z.Z_SOUTH, Z.Z_A_B, 3.0, Z.FENCE, [], 0.4)
	k.wall_z(Z.HALF_W, Z.Z_SOUTH, Z.Z_A_B, 3.0, Z.FENCE, [], 0.4)
	k.wall_x(Z.Z_SOUTH, -Z.HALF_W, Z.HALF_W, 3.0, Z.FENCE, [{"x": 0.0, "w": 9.0}], 0.4)
	k.text_sign("IRON FORTRESS  -  MILITARY ZONE  -  NO CIVILIAN TRAFFIC", Vector3(0.0, 4.4, Z.Z_SOUTH + 0.3), Color(1.0, 0.8, 0.2), 0.02)
	# the main gate: a steel curtain wall with the security door (credential: fortress gate)
	k.wall_x(Z.Z_A_B, -Z.HALF_W, Z.HALF_W, 5.6, Z.STEEL, [{"x": 0.0, "w": 4.4}], 1.2)
	k.glow(Vector3(0.0, 0.06, -4.0), Vector3(6.0, 0.02, 0.5), Z.HAZARD)
	k.text_sign("IRON FORTRESS", Vector3(0.0, 4.9, Z.Z_A_B + 0.7), Color(0.9, 0.92, 1.0), 0.02)
	k.light(Vector3(0.0, 4.6, -2.0), Color(0.85, 0.9, 1.0), 1.2, 22.0)
	parts.door("if_gate_door", Vector3(0.0, 0.0, Z.Z_A_B), "fortress_gate")
	# the checkpoint booth beside the road: the log on the back wall and the credential panel
	k.wall_z(-18.0, 18.0, 28.0, 3.2, Z.CONCRETE, [], 0.5)
	k.wall_z(-8.0, 18.0, 28.0, 3.2, Z.CONCRETE, [{"z": 23.0, "w": 2.6}], 0.5)
	k.wall_x(28.0, -18.0, -8.0, 3.2, Z.CONCRETE, [], 0.5)
	k.wall_x(18.0, -18.0, -8.0, 3.2, Z.CONCRETE, [], 0.5)
	k.box(Vector3(-13.0, 3.4, 23.0), Vector3(12.0, 0.3, 11.0), Z.STEEL, false)
	k.text_sign("CHECKPOINT", Vector3(-7.9, 2.6, 23.0), Color(0.95, 0.9, 0.6), 0.012, PI * 0.5)
	parts.terminal("if_checkpoint_log", Vector3(-15.0, 0.0, 27.2), "the gate logbook on the booth's back wall", "iron_fortress_checkpoint_searched")
	parts.panel("if_gate_panel", Vector3(-11.0, 0.0, 27.2), "fortress_gate", "the credential panel, working once the logbook is signed off", "iron_fortress_checkpoint_searched")
	# the raised barrier arm over the road
	k.box(Vector3(-5.6, 1.4, 23.0), Vector3(0.3, 2.8, 0.3), Z.HAZARD, false)
	k.box(Vector3(-1.0, 3.0, 23.0), Vector3(9.4, 0.18, 0.18), Z.HAZARD, false)
	# watchtowers at the four corners of the yard
	for tower in [Vector2(-27.0, 12.0), Vector2(27.0, 12.0), Vector2(-27.0, -2.0), Vector2(27.0, -2.0)]:
		tower_at(k, tower)
	# armored vehicles and barricades with a purpose: cover for the guards, a chicane that slows a rush at the gate
	truck_at(k, Vector3(-21.0, 0.0, 40.0), Z.OLIVE)
	truck_at(k, Vector3(21.0, 0.0, 14.0), Z.SAND)
	for barrier in [Vector3(-9.0, 0.0, 44.0), Vector3(9.0, 0.0, 38.0), Vector3(-10.0, 0.0, 10.0), Vector3(10.0, 0.0, 4.0)]:
		k.box(barrier + Vector3(0.0, 0.45, 0.0), Vector3(4.0, 0.9, 0.7), Z.CONCRETE)
		k.glow(barrier + Vector3(0.0, 0.92, 0.0), Vector3(3.8, 0.04, 0.5), Z.HAZARD)
	# the supply depot (optional cache) behind stacked crates in the east, and the first patrol log on a table
	k.box(Vector3(25.0, 0.6, 34.0), Vector3(2.4, 1.2, 2.4), Z.WOOD)
	k.box(Vector3(25.0, 1.8, 34.0), Vector3(1.6, 1.2, 1.6), Z.WOOD)
	k.box(Vector3(28.0, 0.6, 34.0), Vector3(1.4, 1.2, 1.4), Z.WOOD)
	parts.crate("if_cache_approach", ["bandage", "armor_patch", "credits_small"], Vector3(27.0, 0.0, 29.0), "an optional supply depot cache behind the crates")
	k.blocker(Vector3(27.0, 0.6, 29.0), Vector3(1.2, 1.2, 1.2))
	k.box(Vector3(22.0, 0.45, 8.0), Vector3(1.8, 0.9, 1.2), Z.WOOD)
	parts.doc("if_patrol_log_1", Vector3(22.0, 1.0, 8.0), "the first Team Ash log on a table by the east tower")
	parts.checkpoint("if_checkpoint_approach", Vector3(-5.0, 0.0, 47.0))
	k.finish()
	# enemies: two patrols and a guard at the booth (a patrol may be slipped past; clearing them also counts)
	parts.fspawn("if_app_1", "fortress_infantry", Vector3(-12.0, 0.0, 34.0), 20.0,
			[Vector3(-12.0, 0.0, 34.0), Vector3(10.0, 0.0, 34.0), Vector3(10.0, 0.0, 28.0), Vector3(-12.0, 0.0, 28.0)])
	parts.fspawn("if_app_2", "fortress_infantry", Vector3(14.0, 0.0, 8.0), 18.0,
			[Vector3(14.0, 0.0, 8.0), Vector3(-8.0, 0.0, 8.0), Vector3(-8.0, 0.0, 0.0), Vector3(14.0, 0.0, 0.0)])
	parts.fspawn("if_app_3", "fortress_infantry", Vector3(6.0, 0.0, 18.0), 14.0)
	parts.mission_trigger("if_checkpoint_reach", "if_checkpoint_reach", Vector3(-8.0, 1.5, 23.0), Vector3(4.0, 3.0, 4.0))
	parts.mission_trigger("if_approach_reach", "if_approach_reach", Vector3(0.0, 1.5, 44.0), Vector3(12.0, 3.0, 8.0))
	return k


static func perimeter(parent: Node3D, parts: IronFortressParts) -> ResearchComplexKit:
	var k := ResearchComplexKit.new(parent, "Perimeter")
	var h := Z.WALL_H
	k.floor_rect(Vector2(0.0, -26.0), Vector2(66.0, 42.0), 0.0, Z.GROUND)
	k.floor_rect(Vector2(0.0, -26.0), Vector2(8.0, 42.0), 0.03, Z.ASPHALT)
	k.wall_z(-Z.HALF_W, Z.Z_A_B, Z.Z_B_C, 3.6, Z.FENCE, [], 0.5)
	k.wall_z(Z.HALF_W, Z.Z_A_B, Z.Z_B_C, 3.6, Z.FENCE, [], 0.5)
	k.wall_x(Z.Z_B_C, -Z.HALF_W, Z.HALF_W, h, Z.STEEL, [{"x": 0.0, "w": 4.4}], 1.0)
	k.text_sign("BARRACKS  >>", Vector3(0.0, 4.1, Z.Z_B_C + 0.6), Color(0.95, 0.9, 0.6), 0.014)
	k.glow(Vector3(0.0, 0.06, -44.0), Vector3(6.0, 0.02, 0.5), Z.HAZARD)
	parts.door("if_barracks_door", Vector3(0.0, 0.0, Z.Z_B_C), "barracks")
	# the security control room (east): the gate activation terminal and the barracks credential panel
	k.wall_z(12.0, -18.0, -32.0, 3.4, Z.CONCRETE, [{"z": -25.0, "w": 3.0}], 0.5)
	k.wall_z(28.0, -18.0, -32.0, 3.4, Z.CONCRETE, [], 0.5)
	k.wall_x(-18.0, 12.0, 28.0, 3.4, Z.CONCRETE, [], 0.5)
	k.wall_x(-32.0, 12.0, 28.0, 3.4, Z.CONCRETE, [], 0.5)
	k.box(Vector3(20.0, 3.6, -25.0), Vector3(17.0, 0.3, 15.0), Z.STEEL, false)
	for x in [15.0, 20.0, 25.0]:
		k.glow(Vector3(x, 2.0, -31.6), Vector3(3.0, 1.0, 0.1), Z.SCREEN_BLUE)
	k.text_sign("SECURITY CONTROL", Vector3(11.9, 2.6, -25.0), Color(0.7, 0.9, 1.0), 0.011, -PI * 0.5)
	parts.terminal("if_security_control", Vector3(24.0, 0.0, -30.6), "the perimeter control console in the security room", "iron_fortress_gate_activated")
	parts.panel("if_barracks_panel", Vector3(16.0, 0.0, -30.6), "barracks", "the credential panel, working once the gate sequence runs", "iron_fortress_gate_activated")
	# the vehicle maintenance bay (west), open at the front, and the ammunition storage behind it
	truck_at(k, Vector3(-20.0, 0.0, -14.0), Z.OLIVE)
	truck_at(k, Vector3(-20.0, 0.0, -24.0), Z.STEEL)
	k.box(Vector3(-26.0, 1.2, -30.0), Vector3(5.0, 2.4, 3.0), Color(0.45, 0.22, 0.18))
	k.box(Vector3(-20.0, 1.2, -30.0), Vector3(5.0, 2.4, 3.0), Color(0.3, 0.32, 0.2))
	k.text_sign("AMMUNITION", Vector3(-23.0, 3.2, -28.4), Color(1.0, 0.7, 0.3), 0.01)
	# guard posts and towers: where the infantry stand
	for tower in [Vector2(-27.0, -10.0), Vector2(27.0, -10.0), Vector2(-27.0, -40.0), Vector2(27.0, -40.0)]:
		tower_at(k, tower)
	for cover in [Vector3(-9.0, 0.0, -14.0), Vector3(9.0, 0.0, -20.0), Vector3(-9.0, 0.0, -36.0), Vector3(9.0, 0.0, -38.0)]:
		k.box(cover + Vector3(0.0, 0.45, 0.0), Vector3(3.6, 0.9, 0.8), Z.CONCRETE)
		k.glow(cover + Vector3(0.0, 0.92, 0.0), Vector3(3.4, 0.04, 0.5), Z.HAZARD)
		parts.cover(cover + Vector3(0.0, 0.0, 1.2))
	# the missing patrol's camp: tents, a second log and a small cache (Team Ash)
	for tent in [Vector3(-26.0, 0.0, -40.0), Vector3(-22.0, 0.0, -42.5)]:
		k.box(tent + Vector3(0.0, 0.8, 0.0), Vector3(3.0, 1.6, 2.4), Z.OLIVE)
	k.box(Vector3(-17.0, 0.45, -41.0), Vector3(1.6, 0.9, 1.0), Z.WOOD)
	parts.doc("if_patrol_log_2", Vector3(-17.0, 1.0, -41.0), "the last Team Ash log at their camp")
	parts.crate("if_cache_patrol", ["bandage", "antiseptic", "credits_small"], Vector3(-29.0, 0.0, -36.0), "the missing patrol's supply cache behind their tents")
	k.blocker(Vector3(-29.0, 0.6, -36.0), Vector3(1.2, 1.2, 1.2))
	parts.checkpoint("if_checkpoint_perimeter", Vector3(5.0, 0.0, -9.0))
	k.light(Vector3(0.0, 4.0, -26.0), Color(0.9, 0.9, 1.0), 1.1, 26.0)
	k.finish()
	parts.fspawn("if_per_1", "fortress_infantry", Vector3(-14.0, 0.0, -16.0), 18.0,
			[Vector3(-14.0, 0.0, -16.0), Vector3(-14.0, 0.0, -34.0), Vector3(-5.0, 0.0, -34.0), Vector3(-5.0, 0.0, -16.0)])
	parts.fspawn("if_per_2", "fortress_infantry", Vector3(14.0, 0.0, -34.0), 18.0,
			[Vector3(14.0, 0.0, -34.0), Vector3(14.0, 0.0, -14.0), Vector3(6.0, 0.0, -14.0), Vector3(6.0, 0.0, -34.0)])
	parts.fspawn("if_per_elite", "elite_security_soldier", Vector3(8.0, 0.0, -26.0), 11.0)
	parts.mission_trigger("if_perimeter_reach", "if_perimeter_reach", Vector3(0.0, 1.5, -10.0), Vector3(10.0, 3.0, 4.0))
	return k


static func barracks(parent: Node3D, parts: IronFortressParts) -> ResearchComplexKit:
	var k := ResearchComplexKit.new(parent, "Barracks")
	var h := Z.WALL_H
	k.floor_rect(Vector2(0.0, -67.0), Vector2(64.0, 42.0), 0.0, Z.BARRACKS_FLOOR)
	k.wall_z(-Z.HALF_W, Z.Z_B_C, Z.Z_C_D, h, Z.BARRACKS_WALL, [], 1.0)
	k.wall_z(Z.HALF_W, Z.Z_B_C, Z.Z_C_D, h, Z.BARRACKS_WALL, [], 1.0)
	k.wall_x(Z.Z_C_D, -Z.HALF_W, Z.HALF_W, h, Z.BARRACKS_WALL, [{"x": 0.0, "w": 4.4}], 1.0)
	k.text_sign("COMMAND CENTER  >>", Vector3(0.0, 4.2, Z.Z_C_D + 0.6), Color(0.7, 0.85, 1.0), 0.014)
	k.glow(Vector3(0.0, 0.04, -86.0), Vector3(5.0, 0.02, 0.5), Z.HAZARD)
	parts.door("if_command_door", Vector3(0.0, 0.0, Z.Z_C_D), "command_key")
	# the bunk block (west): beds in rows, the duty roster pinned on the end wall
	k.wall_z(-9.0, Z.Z_B_C - 6.0, -66.0, 3.4, Z.BARRACKS_WALL, [{"z": -57.0, "w": 3.0}], 0.6)
	k.wall_x(-66.0, -31.0, -9.0, 3.4, Z.BARRACKS_WALL, [], 0.6)
	k.wall_x(-52.0, -31.0, -9.0, 3.4, Z.BARRACKS_WALL, [], 0.6)
	for row in [-56.0, -60.0, -64.0]:
		for x in [-27.0, -21.0, -15.0]:
			k.box(Vector3(x, 0.35, row), Vector3(2.0, 0.7, 1.0), Z.OLIVE, false)
	parts.doc("if_barracks_roster", Vector3(-12.0, 1.0, -64.5), "the duty roster on the bunk block's end wall")
	# the armory (east): a manifest terminal and the optional recovery cache behind a cage
	k.wall_z(9.0, Z.Z_B_C - 6.0, -66.0, 3.4, Z.BARRACKS_WALL, [{"z": -57.0, "w": 3.0}], 0.6)
	k.wall_x(-66.0, 9.0, 31.0, 3.4, Z.BARRACKS_WALL, [], 0.6)
	k.wall_x(-52.0, 9.0, 31.0, 3.4, Z.BARRACKS_WALL, [], 0.6)
	for x in [14.0, 18.0, 22.0]:
		k.box(Vector3(x, 1.0, -64.5), Vector3(3.0, 2.0, 0.8), Z.STEEL, false)
	k.text_sign("ARMORY", Vector3(9.1, 2.8, -57.0), Color(1.0, 0.7, 0.3), 0.012, PI * 0.5)
	parts.terminal("if_armory_terminal", Vector3(14.0, 0.0, -53.2), "the armory issue terminal by the door", "iron_fortress_armory_checked")
	parts.crate("if_cache_armory", ["armor_plate", "bandage", "credits_medium"], Vector3(27.0, 0.0, -62.0), "the armory recovery cache in the back of the cage")
	k.blocker(Vector3(27.0, 0.6, -62.0), Vector3(1.4, 1.2, 1.4))
	# training yard in the open centre: dummies and a hazard-marked firing line, off the lane
	for dummy in [Vector3(-5.5, 0.0, -50.0), Vector3(5.5, 0.0, -51.0), Vector3(-5.5, 0.0, -58.0), Vector3(5.5, 0.0, -60.0)]:
		k.box(dummy + Vector3(0.0, 0.8, 0.0), Vector3(0.5, 1.6, 0.5), Z.WOOD)
		parts.cover(dummy + Vector3(0.0, 0.0, 1.0))
	k.glow(Vector3(0.0, 0.04, -55.0), Vector3(14.0, 0.02, 0.3), Z.HAZARD)
	# the lockdown relay (stage one) in the south-east and the command office (north-west) with its key panel
	parts.terminal("if_lockdown_relay", Vector3(20.0, 0.0, -80.6), "the lockdown relay at the east wall", "iron_fortress_lockdown_step_a")
	k.wall_z(-9.0, -72.0, Z.Z_C_D, 3.4, Z.BARRACKS_WALL, [{"z": -76.0, "w": 3.0}], 0.6)
	k.wall_x(-72.0, -31.0, -9.0, 3.4, Z.BARRACKS_WALL, [], 0.6)
	k.box(Vector3(-24.0, 0.45, -78.0), Vector3(3.0, 0.9, 1.2), Z.WOOD)
	parts.panel("if_command_panel", Vector3(-20.0, 0.0, -86.6), "command_key", "the key cabinet in the command office, unlocked once the defenders are down", "iron_fortress_barracks_cleared")
	parts.doc("if_orders_1", Vector3(-24.0, 1.0, -78.0), "optional classified order 11 on the office desk")
	parts.checkpoint("if_checkpoint_barracks", Vector3(5.0, 0.0, -49.0))
	k.light(Vector3(0.0, 4.0, -67.0), Color(1.0, 0.95, 0.8), 1.1, 28.0)
	k.finish()
	parts.fspawn("if_bar_elite_1", "elite_security_soldier", Vector3(-12.0, 0.0, -58.0), 15.0)
	parts.fspawn("if_bar_elite_2", "elite_security_soldier", Vector3(12.0, 0.0, -72.0), 15.0)
	parts.fspawn("if_bar_heavy_1", "heavy_assault_unit", Vector3(0.0, 0.0, -68.0), 14.0)
	parts.mission_trigger("if_barracks_reach", "if_barracks_reach", Vector3(0.0, 1.5, -49.0), Vector3(10.0, 3.0, 4.0))
	return k


## A watchtower: four legs, a platform and a roof; the legs block, the roof does not.
static func tower_at(k: ResearchComplexKit, p: Vector2) -> void:
	for dx in [-1.0, 1.0]:
		for dz in [-1.0, 1.0]:
			k.box(Vector3(p.x + dx * 1.1, 2.0, p.y + dz * 1.1), Vector3(0.3, 4.0, 0.3), Z.STEEL)
	k.box(Vector3(p.x, 4.1, p.y), Vector3(3.2, 0.2, 3.2), Z.STEEL, false)
	k.box(Vector3(p.x, 5.4, p.y), Vector3(3.8, 0.2, 3.8), Z.OLIVE, false)
	k.glow(Vector3(p.x, 4.4, p.y + 1.7), Vector3(1.2, 0.2, 0.05), Z.LAMP_WARM)


## An armored truck: hull, cab and a turret block. Solid, so it works as cover and as a landmark.
static func truck_at(k: ResearchComplexKit, p: Vector3, color: Color) -> void:
	k.box(p + Vector3(0.0, 1.0, 0.0), Vector3(2.8, 1.6, 6.0), color)
	k.box(p + Vector3(0.0, 1.9, -2.0), Vector3(2.4, 0.8, 1.8), color * 0.8)
	k.box(p + Vector3(0.0, 2.2, 0.8), Vector3(1.4, 0.6, 1.4), Z.STEEL, false)
	k.glow(p + Vector3(0.0, 1.2, -3.02), Vector3(2.0, 0.3, 0.05), Z.LAMP_WARM)
