class_name IronFortressInner
extends RefCounted
## The last three areas of the Iron Fortress: the command center (communications puzzle, intelligence
## archive, the Director's file), the inner fortress (lockdown puzzle, the Fortress Captain, the optional
## supply depot) and the Project Black Site control facility (final records, the Director's arena).
## A clear lane (|x| <= 3) runs down the middle of every area; solid props sit to the sides.

const Z = preload("res://scripts/regions/iron_fortress/iron_fortress_zones.gd")
const COMMS_DONE: StringName = &"iron_fortress_comms_done"
const LOCKDOWN_DONE: StringName = &"iron_fortress_lockdown_done"
const CONTROL_OPEN: StringName = &"iron_fortress_control_open"
const DIRECTOR_DOWN: StringName = &"iron_fortress_director_defeated"
const REGION: StringName = &"iron_fortress"


static func command_center(parent: Node3D, parts: IronFortressParts) -> ResearchComplexKit:
	var k := ResearchComplexKit.new(parent, "Command")
	var h := Z.WALL_H
	k.floor_rect(Vector2(0.0, -109.0), Vector2(64.0, 42.0), 0.0, Z.COMMAND_FLOOR)
	k.wall_z(-Z.HALF_W, Z.Z_C_D, Z.Z_D_E, h, Z.COMMAND_WALL, [], 1.0)
	k.wall_z(Z.HALF_W, Z.Z_C_D, Z.Z_D_E, h, Z.COMMAND_WALL, [], 1.0)
	k.wall_x(Z.Z_D_E, -Z.HALF_W, Z.HALF_W, h, Z.COMMAND_WALL, [{"x": 0.0, "w": 4.4}], 1.0)
	k.text_sign("INNER FORTRESS  >>", Vector3(0.0, 4.2, Z.Z_D_E + 0.6), Color(1.0, 0.6, 0.5), 0.014)
	k.glow(Vector3(0.0, 0.04, -128.0), Vector3(5.0, 0.02, 0.5), Z.HAZARD)
	parts.door("if_inner_door", Vector3(0.0, 0.0, Z.Z_D_E), "inner_access")
	# the intelligence archive (west): shelves, one terminal, an optional classified order on a desk
	k.wall_z(-9.0, -96.0, -112.0, 3.6, Z.COMMAND_WALL, [{"z": -104.0, "w": 3.0}], 0.6)
	k.wall_x(-96.0, -31.0, -9.0, 3.6, Z.COMMAND_WALL, [], 0.6)
	k.wall_x(-112.0, -31.0, -9.0, 3.6, Z.COMMAND_WALL, [], 0.6)
	for z in [-98.0, -101.0, -107.0, -110.0]:
		k.box(Vector3(-29.8, 1.1, z), Vector3(1.0, 2.2, 1.6), Z.STEEL, false)
	k.text_sign("INTELLIGENCE ARCHIVE", Vector3(-8.9, 2.8, -104.0), Color(0.7, 0.9, 1.0), 0.01, PI * 0.5)
	parts.terminal("if_intel_archive", Vector3(-22.0, 0.0, -110.6), "the archive index terminal", "iron_fortress_archive_found")
	k.box(Vector3(-18.0, 0.45, -100.0), Vector3(3.0, 0.9, 1.2), Z.WOOD)
	parts.doc("if_orders_2", Vector3(-18.0, 1.0, -100.0), "optional classified order 23 on the archive desk")
	parts.mission_trigger("if_archive_reach", "if_archive_reach", Vector3(-15.0, 1.5, -104.0), Vector3(4.0, 3.0, 6.0))
	# the communications center (east): Puzzle B, four relay racks to a pattern and a main switch
	k.wall_z(9.0, -96.0, -124.0, 3.6, Z.COMMAND_WALL, [{"z": -108.0, "w": 3.0}], 0.6)
	k.wall_x(-96.0, 9.0, 31.0, 3.6, Z.COMMAND_WALL, [], 0.6)
	k.wall_x(-124.0, 9.0, 31.0, 3.6, Z.COMMAND_WALL, [], 0.6)
	for x in [12.0, 17.0, 22.0, 27.0]:
		k.glow(Vector3(x, 2.4, -95.4), Vector3(3.0, 1.0, 0.1), Z.SCREEN_GREEN)
	k.text_sign("COMMUNICATIONS", Vector3(8.9, 2.8, -108.0), Color(0.6, 1.0, 0.8), 0.011, -PI * 0.5)
	var puzzle := LabPowerPuzzle.new()
	puzzle.name = "CommsPuzzle"
	puzzle.puzzle_id = &"comms"
	puzzle.region_id = REGION
	var pattern: Array[bool] = [false, true, true, false]
	puzzle.pattern = pattern
	parent.add_child(puzzle)
	parts.puzzles["comms"] = puzzle
	for i in 4:
		parts.switch("if_relay_%d" % i, Vector3(12.0 + 3.0 * i, 0.0, -122.6), puzzle, "breaker_%d" % i, "Set relay rack %d" % (i + 1), "relay rack %d on the comms room wall" % (i + 1))
	parts.switch("if_comms_main", Vector3(26.0, 0.0, -122.6), puzzle, "lever", "Throw the main comms switch", "the main switch at the end of the relay racks")
	var display := k.text_sign(puzzle.display_text().replace("LAB POWER", "COMMS RELAY"), Vector3(19.0, 3.7, -123.2), Color(0.5, 1.0, 0.8), 0.011)
	display.name = "RelayDisplay"
	k.box(Vector3(14.0, 0.45, -100.0), Vector3(3.0, 0.9, 1.2), Z.WOOD)
	parts.doc("if_comms_notes", Vector3(14.0, 1.0, -100.0), "the comms duty notes on the desk", "\n\n" + puzzle.hint_text().replace("lab breakers", "relay racks"))
	# the operations room (north): the files, the Director's file and the inner access panel
	parts.terminal("if_ops_files", Vector3(-6.0, 0.0, -128.4), "the operations terminal, dead until the network is back", "iron_fortress_files_retrieved", "iron_fortress_comms_done")
	parts.terminal("if_director_dossier", Vector3(6.0, 0.0, -128.4), "the Director's dossier terminal, locked behind the files", "iron_fortress_director_known", "iron_fortress_files_retrieved")
	parts.panel("if_inner_panel", Vector3(11.0, 0.0, -128.4), "inner_access", "the credential panel, working once the dossier is read", "iron_fortress_director_known")
	# the tactical table in the centre, off the lane, with cover for the commander
	k.box(Vector3(-7.0, 0.5, -117.0), Vector3(5.0, 1.0, 3.0), Z.COMMAND_WALL * 0.9)
	k.box(Vector3(7.0, 0.5, -117.0), Vector3(5.0, 1.0, 3.0), Z.COMMAND_WALL * 0.9)
	k.glow(Vector3(-7.0, 1.04, -117.0), Vector3(4.6, 0.04, 2.6), Z.SCREEN_BLUE)
	k.glow(Vector3(7.0, 1.04, -117.0), Vector3(4.6, 0.04, 2.6), Z.SCREEN_BLUE)
	for cover in [Vector3(-12.0, 0.0, -114.0), Vector3(12.0, 0.0, -114.0), Vector3(-12.0, 0.0, -121.0), Vector3(12.0, 0.0, -121.0), Vector3(0.0, 0.0, -125.0)]:
		parts.cover(cover)
	parts.checkpoint("if_checkpoint_command", Vector3(5.0, 0.0, -91.0))
	k.light(Vector3(0.0, 4.0, -100.0), Color(0.55, 0.7, 1.0), 1.1, 26.0)
	k.light(Vector3(0.0, 4.0, -120.0), Color(0.5, 0.65, 1.0), 1.1, 26.0)
	k.finish()
	parts.fspawn("if_cmd_elite", "elite_security_soldier", Vector3(-12.0, 0.0, -110.0), 14.0)
	parts.fspawn("if_cmd_commander", "tactical_commander", Vector3(0.0, 0.0, -122.0), 18.0)
	parts.mission_trigger("if_command_reach", "if_command_reach", Vector3(0.0, 1.5, -91.0), Vector3(10.0, 3.0, 4.0))
	return k


static func inner_fortress(parent: Node3D, parts: IronFortressParts) -> ResearchComplexKit:
	var k := ResearchComplexKit.new(parent, "Inner")
	var h := Z.WALL_H
	k.floor_rect(Vector2(0.0, -151.0), Vector2(64.0, 42.0), 0.0, Z.INNER_FLOOR)
	k.wall_z(-Z.HALF_W, Z.Z_D_E, Z.Z_E_F, h, Z.INNER_WALL, [], 1.0)
	k.wall_z(Z.HALF_W, Z.Z_D_E, Z.Z_E_F, h, Z.INNER_WALL, [], 1.0)
	k.wall_x(Z.Z_E_F, -Z.HALF_W, Z.HALF_W, h, Z.INNER_WALL, [{"x": 0.0, "w": 4.4}], 1.0)
	k.text_sign("CONTROL  >>  AUTHORIZED PERSONNEL ONLY", Vector3(0.0, 4.2, Z.Z_E_F + 0.6), Color(1.0, 0.4, 0.3), 0.012)
	k.glow(Vector3(0.0, 0.04, -170.0), Vector3(5.0, 0.02, 0.5), Z.LAMP_RED)
	parts.flag_door("if_control_door", Vector3(0.0, 0.0, Z.Z_E_F), "iron_fortress_control_open", "Sealed: the inner lockdown is still on, and the Captain holds the hall")
	# defensive corridors: two wall lines with a wide opening, so the hall is a kill zone and the sides are routes
	k.wall_z(-12.0, -134.0, -168.0, 3.6, Z.INNER_WALL, [{"z": -142.0, "w": 5.0}, {"z": -158.0, "w": 5.0}], 0.8)
	k.wall_z(12.0, -134.0, -168.0, 3.6, Z.INNER_WALL, [{"z": -146.0, "w": 5.0}, {"z": -160.0, "w": 5.0}], 0.8)
	for pillar in [Vector3(-6.0, 0.0, -138.0), Vector3(6.0, 0.0, -138.0), Vector3(-6.0, 0.0, -154.0), Vector3(6.0, 0.0, -154.0)]:
		k.box(pillar + Vector3(0.0, 2.0, 0.0), Vector3(1.2, 4.0, 1.2), Z.INNER_WALL * 1.2)
		k.glow(pillar + Vector3(0.0, 0.05, 0.0), Vector3(1.8, 0.04, 1.8), Z.LAMP_RED)
		parts.cover(pillar + Vector3(0.0, 0.0, 1.4))
	# Puzzle C: three override terminals in the hall, any order inside a forgiving window, then the release lever
	var puzzle := ContainmentOverride.new()
	puzzle.name = "LockdownOverride"
	puzzle.puzzle_id = &"lockdown"
	puzzle.region_id = REGION
	parent.add_child(puzzle)
	parts.puzzles["lockdown"] = puzzle
	parts.switch("if_lock_a", Vector3(-9.0, 0.0, -141.0), puzzle, "terminal_a", "Disable lockdown point A", "lockdown point A in the west hall")
	parts.switch("if_lock_b", Vector3(9.0, 0.0, -151.0), puzzle, "terminal_b", "Disable lockdown point B", "lockdown point B in the east hall")
	parts.switch("if_lock_c", Vector3(-9.0, 0.0, -162.0), puzzle, "terminal_c", "Disable lockdown point C", "lockdown point C near the control door")
	parts.switch("if_lock_lever", Vector3(6.0, 0.0, -169.2), puzzle, "lever", "Pull the lockdown release", "the release lever beside the control door")
	# the optional supply depot (west), reached through an opening in the west wall line, guarded by two elites
	k.wall_z(-24.0, -134.0, -150.0, 3.4, Z.INNER_WALL, [{"z": -142.0, "w": 4.0}], 0.6)
	k.wall_x(-134.0, -31.0, -24.0, 3.4, Z.INNER_WALL, [], 0.6)
	k.wall_x(-150.0, -31.0, -24.0, 3.4, Z.INNER_WALL, [], 0.6)
	k.box(Vector3(-29.0, 0.6, -137.0), Vector3(2.4, 1.2, 2.4), Z.WOOD)
	k.box(Vector3(-29.0, 1.8, -137.0), Vector3(1.6, 1.2, 1.6), Z.WOOD)
	parts.crate("if_cache_depot", ["armor_plate", "antiseptic", "electronics", "credits_medium"], Vector3(-29.0, 0.0, -146.0), "the hidden supply depot cache, guarded by two elites")
	k.blocker(Vector3(-29.0, 0.6, -146.0), Vector3(1.4, 1.2, 1.4))
	k.text_sign("DEPOT", Vector3(-23.9, 2.8, -142.0), Color(1.0, 0.7, 0.3), 0.012, PI * 0.5)
	# an optional classified order near the south end, and a rest point
	k.box(Vector3(22.0, 0.45, -136.0), Vector3(3.0, 0.9, 1.2), Z.WOOD)
	parts.doc("if_orders_3", Vector3(22.0, 1.0, -136.0), "optional classified order 31 on a table behind the east wall")
	parts.checkpoint("if_checkpoint_inner", Vector3(5.0, 0.0, -133.0))
	parts.area_trigger("if_captain_hall", Vector3(0.0, 2.0, -161.0), Vector3(26.0, 6.0, 20.0))
	k.light(Vector3(0.0, 4.0, -140.0), Color(1.0, 0.45, 0.35), 1.2, 26.0)
	k.light(Vector3(0.0, 4.0, -160.0), Color(1.0, 0.4, 0.3), 1.2, 26.0)
	k.finish()
	parts.fspawn("if_inn_heavy_1", "heavy_assault_unit", Vector3(-9.0, 0.0, -136.0), 12.0)
	parts.fspawn("if_inn_heavy_2", "heavy_assault_unit", Vector3(9.0, 0.0, -144.0), 12.0)
	parts.fspawn("if_inn_elite_1", "elite_security_soldier", Vector3(-8.0, 0.0, -148.0), 12.0)
	parts.fspawn("if_inn_elite_2", "elite_security_soldier", Vector3(8.0, 0.0, -156.0), 12.0)
	parts.fspawn("if_depot_elite_1", "elite_security_soldier", Vector3(-27.0, 0.0, -140.0), 9.0)
	parts.fspawn("if_depot_elite_2", "elite_security_soldier", Vector3(-27.0, 0.0, -144.0), 9.0)
	parts.fspawn("if_captain", "fortress_captain", Vector3(0.0, 0.0, -164.0))
	parts.mission_trigger("if_inner_reach", "if_inner_reach", Vector3(0.0, 1.5, -133.0), Vector3(10.0, 3.0, 4.0))
	return k


static func control_facility(parent: Node3D, parts: IronFortressParts) -> ResearchComplexKit:
	var k := ResearchComplexKit.new(parent, "Control")
	var h := Z.WALL_H
	k.floor_rect(Vector2(0.0, -193.0), Vector2(64.0, 42.0), 0.0, Z.CONTROL_FLOOR)
	k.wall_z(-Z.HALF_W, Z.Z_E_F, Z.Z_END, h, Z.CONTROL_WALL, [], 1.0)
	k.wall_z(Z.HALF_W, Z.Z_E_F, Z.Z_END, h, Z.CONTROL_WALL, [], 1.0)
	k.wall_x(Z.Z_END, -Z.HALF_W, Z.HALF_W, h, Z.CONTROL_WALL, [], 1.0)
	k.text_sign("PROJECT BLACK SITE  -  CONTROL", Vector3(0.0, 4.2, Z.Z_E_F - 0.7), Color(0.6, 1.0, 0.8), 0.016, PI)
	# the control room (south part): records and the project archive against the partition, the restricted lab to the west
	k.wall_x(-186.0, -Z.HALF_W, Z.HALF_W, 3.8, Z.CONTROL_WALL, [{"x": 0.0, "w": 16.0}], 0.8)
	parts.terminal("if_control_records", Vector3(-11.0, 0.0, -184.6), "the control room's final records terminal", "iron_fortress_records_read")
	parts.terminal("if_project_archive", Vector3(11.0, 0.0, -184.6), "the sealed project archive terminal", "iron_fortress_archive_read")
	for x in [-24.0, -20.0, -16.0]:
		k.box(Vector3(x, 0.5, -178.0), Vector3(2.4, 1.0, 1.2), Z.CONTROL_WALL * 0.8)
		k.glow(Vector3(x, 1.04, -178.0), Vector3(2.0, 0.04, 0.9), Z.SCREEN_GREEN)
	k.text_sign("RESTRICTED LABORATORY", Vector3(-20.0, 3.2, -175.2), Color(1.0, 0.6, 0.4), 0.01)
	for x in [-26.0, -22.0, 22.0, 26.0]:
		k.glow(Vector3(x, 2.2, -171.4), Vector3(2.2, 1.0, 0.1), Z.SCREEN_BLUE)
	# the final arena: open floor, four pillars to dodge around, cover points, no pits, no hazards
	for pillar in [Vector3(-12.0, 0.0, -196.0), Vector3(12.0, 0.0, -196.0), Vector3(-12.0, 0.0, -206.0), Vector3(12.0, 0.0, -206.0)]:
		k.box(pillar + Vector3(0.0, 2.0, 0.0), Vector3(1.6, 4.0, 1.6), Z.CONTROL_WALL * 0.85)
		k.glow(pillar + Vector3(0.0, 0.05, 0.0), Vector3(2.2, 0.04, 2.2), Z.LAMP_RED)
		parts.cover(pillar + Vector3(0.0, 0.0, 1.6))
	k.glow(Vector3(0.0, 0.04, -200.0), Vector3(22.0, 0.02, 0.3), Z.HAZARD)
	k.glow(Vector3(0.0, 0.04, -200.0), Vector3(0.3, 0.02, 22.0), Z.HAZARD)
	parts.terminal("if_end_console", Vector3(0.0, 0.0, -212.4), "the transmission console behind the arena", "iron_fortress_ending_read", "iron_fortress_director_defeated")
	parts.checkpoint("if_checkpoint_control", Vector3(5.0, 0.0, -175.0))
	parts.area_trigger("if_arena", Vector3(0.0, 2.0, -200.0), Vector3(60.0, 6.0, 26.0))
	k.light(Vector3(0.0, 4.0, -178.0), Color(0.8, 1.0, 0.9), 0.8, 26.0)
	k.light(Vector3(0.0, 4.0, -196.0), Color(0.9, 1.0, 0.95), 0.9, 30.0)
	k.light(Vector3(0.0, 4.0, -208.0), Color(0.9, 1.0, 0.95), 0.8, 26.0)
	k.finish()
	parts.fspawn("if_director", "director", Vector3(0.0, 0.0, -205.0))
	parts.mission_trigger("if_control_reach", "if_control_reach", Vector3(0.0, 1.5, -175.0), Vector3(10.0, 3.0, 4.0))
	return k
