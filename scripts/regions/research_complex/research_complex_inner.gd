class_name ResearchComplexInner
extends RefCounted
## The inner areas of the Research Complex: the containment sector (cells, floor hazards, the
## containment override puzzle and the elite's chamber), the central laboratory (the power puzzle, cover
## for the Commander, the data archive and the final chamber) and the underground exit.

const Z = preload("res://scripts/regions/research_complex/research_complex_zones.gd")
const OVERRIDE_DONE: String = "research_complex_containment_done"
const LAB_POWER_DONE: String = "research_complex_lab_power_done"
const ELITE_DOWN: String = "research_complex_elite_down"
const NEXT_LEAD: String = "research_complex_next_lead"


static func containment(parent: Node3D, parts: ResearchComplexParts) -> ResearchComplexKit:
	var k := ResearchComplexKit.new(parent, "Containment")
	var h := Z.WALL_H
	k.floor_rect(Vector2(0.0, -106.0), Vector2(62.0, 44.0), 0.0, Z.CELL_FLOOR)
	k.wall_z(-30.0, Z.Z_C_D, Z.Z_D_E, h, Z.CELL_WALL, [], 1.0)
	k.wall_z(30.0, Z.Z_C_D, Z.Z_D_E, h, Z.CELL_WALL, [], 1.0)
	k.wall_x(Z.Z_D_E, -30.0, 30.0, h, Z.CELL_WALL, [{"x": 0.0, "w": 4.4}], 1.0)
	# the cell blocks: damaged partitions with doorways, glass strips, cell dividers
	var doorways: Array = [{"z": -88.0, "w": 3.0}, {"z": -96.0, "w": 3.0}, {"z": -104.0, "w": 3.0}, {"z": -112.0, "w": 3.0}]
	k.wall_z(-12.0, Z.Z_C_D, -116.0, 3.6, Z.CELL_WALL, doorways, 0.6)
	k.wall_z(12.0, Z.Z_C_D, -116.0, 3.6, Z.CELL_WALL, doorways, 0.6)
	for z in [-92.0, -100.0, -108.0]:
		k.wall_x(z, -30.0, -12.0, 3.4, Z.CELL_WALL, [], 0.5)
		k.wall_x(z, 12.0, 30.0, 3.4, Z.CELL_WALL, [], 0.5)
	for door_z in [-88.0, -96.0, -104.0, -112.0]:
		for off in [-2.9, 2.9]:
			k.glow(Vector3(-11.65, 2.4, door_z + off), Vector3(0.05, 0.9, 1.4), Color(0.3, 0.55, 0.65))
			k.glow(Vector3(11.65, 2.4, door_z + off), Vector3(0.05, 0.9, 1.4), Color(0.3, 0.55, 0.65))
	k.wall_x(-116.0, -30.0, -12.0, 3.6, Z.CELL_WALL, [], 0.6)
	k.wall_x(-116.0, 12.0, 30.0, 3.6, Z.CELL_WALL, [], 0.6)
	k.box(Vector3(-21.0, 2.2, -122.0), Vector3(18.0, 4.4, 12.0), Z.CELL_WALL)
	k.box(Vector3(21.0, 2.2, -122.0), Vector3(18.0, 4.4, 12.0), Z.CELL_WALL)
	# emergency floor strips, a damaged cell door and rubble, so the story reads
	var sz := -86.0
	while sz > -114.0:
		k.glow(Vector3(0.0, 0.03, sz), Vector3(0.25, 0.02, 3.0), Color(0.9, 0.2, 0.1))
		sz -= 6.0
	k.box(Vector3(-11.0, 0.5, -99.0), Vector3(1.8, 1.0, 1.4), Color(0.35, 0.3, 0.28))
	k.box(Vector3(11.5, 0.35, -91.0), Vector3(1.4, 0.7, 1.2), Color(0.35, 0.3, 0.28))
	k.text_sign("LOCKDOWN ACTIVE", Vector3(0.0, 3.0, -115.3), Color(1.0, 0.25, 0.15), 0.010)
	k.light(Vector3(0.0, 3.6, -94.0), Color(1.0, 0.45, 0.25), 1.2, 26.0)
	k.light(Vector3(0.0, 3.6, -108.0), Color(1.0, 0.4, 0.25), 1.2, 26.0)
	k.light(Vector3(0.0, 4.0, -122.0), Color(1.0, 0.3, 0.2), 1.5, 20.0)
	# the elite's chamber behind a door that opens when the containment override completes
	k.wall_x(-116.0, -12.0, 12.0, h, Z.CELL_WALL, [{"x": 0.0, "w": 6.0}], 1.0)
	k.floor_rect(Vector2(0.0, -122.0), Vector2(24.0, 12.0), 0.03, Color(0.27, 0.16, 0.15))
	k.box(Vector3(6.0, 0.45, -125.0), Vector3(2.6, 0.9, 1.2), Z.METAL)
	k.text_sign("HOLDING CELL 0", Vector3(0.0, 3.8, -115.3), Color(1.0, 0.3, 0.2), 0.012)
	# the override: three pedestal consoles in the corridor, then the lever next to the sealed door
	var puzzle := ContainmentOverride.new()
	puzzle.name = "ContainmentOverride"
	parent.add_child(puzzle)
	parts.puzzles["containment"] = puzzle
	parts.switch("rc_override_a", Vector3(-8.0, 0.0, -90.5), puzzle, "terminal_a", "Activate override A", "override terminal A, west of the corridor")
	parts.switch("rc_override_b", Vector3(8.0, 0.0, -102.0), puzzle, "terminal_b", "Activate override B", "override terminal B, east of the corridor")
	parts.switch("rc_override_c", Vector3(-8.0, 0.0, -112.5), puzzle, "terminal_c", "Activate override C", "override terminal C, near the elite chamber")
	parts.switch("rc_override_lever", Vector3(3.0, 0.0, -113.4), puzzle, "lever", "Pull the release lever", "the release lever beside the sealed chamber door")
	var control := ContainmentControl.new()
	control.name = "OverrideLamp"
	control.position = Vector3(-3.0, 0.0, -113.4)
	parent.add_child(control)
	control.bind(puzzle)
	parts.placed.append({"kind": "interactable", "name": "rc_override_lamp", "pos": control.position, "radius": 1.5, "why": "the override status lamp", "solid": false})
	parts.doc("rc_override_notes", Vector3(-9.0, 0.9, -86.0), "the technician notes on a pedestal at the start of the corridor", "", 0.0)
	k.glow(Vector3(-9.0, 0.93, -86.0), Vector3(0.5, 0.04, 0.35), Color(0.95, 0.95, 0.85))
	k.box(Vector3(-9.0, 0.45, -86.0), Vector3(0.9, 0.9, 0.9), Z.METAL)
	parts.flag_door("rc_elite_door", Vector3(0.0, 0.0, -116.0), OVERRIDE_DONE, "Sealed: the containment override has to be completed", 6.0)
	parts.doc("rc_incident_report", Vector3(6.0, 0.9, -125.0), "the incident report on a table in the elite's chamber", "", 0.0)
	k.glow(Vector3(6.0, 0.93, -125.0), Vector3(0.5, 0.04, 0.35), Color(0.95, 0.95, 0.85))
	parts.panel("rc_lab_panel", Vector3(-4.5, 0.0, -127.2), "lab", "the laboratory access panel in the chamber, live once the elite is down", ELITE_DOWN)
	parts.door("rc_lab_door", Vector3(0.0, 0.0, Z.Z_D_E), "lab")
	parts.checkpoint("rc_checkpoint_containment", Vector3(6.0, 0.0, -87.0))
	parts.area_trigger("rc_elite_chamber", Vector3(0.0, 2.0, -122.0), Vector3(22.0, 6.0, 11.0))
	k.finish()
	# floor hazards: two timed strips across the corridor (never active without the amber warning first)
	for spec in [{"z": -96.0, "offset": 0.0}, {"z": -108.0, "offset": 0.75}]:
		var hazard := ResearchComplexHazard.new()
		hazard.name = "Hazard_%d" % int(-float(spec["z"]))
		hazard.size = Vector3(24.0, 1.5, 1.6)
		hazard.offset = float(spec["offset"])
		hazard.position = Vector3(0.0, 0.0, float(spec["z"]))
		parent.add_child(hazard)
	# subjects in the cells wake when the player comes near; the elite is released by the chamber trigger
	parts.spawn("rc_subject_cell_1", "experimental_subject", Vector3(-21.0, 0.0, -96.0), 11.0)
	parts.spawn("rc_subject_cell_2", "experimental_subject", Vector3(21.0, 0.0, -104.0), 11.0)
	parts.spawn("rc_subject_cell_3", "experimental_subject", Vector3(-21.0, 0.0, -111.0), 11.0)
	parts.spawn("rc_elite_subject", "elite_subject", Vector3(0.0, 0.0, -122.0))
	return k


static func laboratory(parent: Node3D, parts: ResearchComplexParts) -> ResearchComplexKit:
	var k := ResearchComplexKit.new(parent, "Laboratory")
	var h := Z.WALL_H
	k.floor_rect(Vector2(0.0, -150.0), Vector2(62.0, 44.0), 0.0, Z.LAB_FLOOR)
	k.wall_z(-30.0, Z.Z_D_E, Z.Z_END, h, Z.LAB_WALL, [], 1.0)
	k.wall_z(30.0, Z.Z_D_E, Z.Z_END, h, Z.LAB_WALL, [], 1.0)
	k.wall_x(Z.Z_END, -30.0, 30.0, h, Z.LAB_WALL, [{"x": Z.HATCH_X, "w": 3.4}], 1.0)
	k.wall_z(-12.0, Z.Z_D_E, Z.Z_END, 3.8, Z.LAB_WALL, [{"z": -148.0, "w": 3.2}], 0.6)
	k.wall_z(12.0, Z.Z_D_E, Z.Z_END, 3.8, Z.LAB_WALL, [{"z": -152.0, "w": 3.2}], 0.6)
	k.wall_x(-158.0, -12.0, 12.0, h, Z.LAB_WALL, [{"x": 0.0, "w": 4.4}], 0.8)
	k.floor_rect(Vector2(0.0, -165.0), Vector2(24.0, 14.0), 0.03, Color(0.14, 0.17, 0.28))
	# the main hall: benches that double as cover, glowing tanks, floor guide lines
	for pos in [Vector3(-8.0, 0.5, -137.0), Vector3(8.0, 0.5, -137.0), Vector3(-8.0, 0.5, -147.0), Vector3(8.0, 0.5, -147.0)]:
		k.box(pos, Vector3(4.0, 1.0, 1.4), Color(0.4, 0.45, 0.55))
		k.glow(pos + Vector3(0.0, 0.55, 0.0), Vector3(3.4, 0.04, 0.9), Z.SCREEN_BLUE)
	for x in [-4.0, 4.0]:
		k.box(Vector3(x, 1.6, -153.0), Vector3(1.4, 3.2, 1.4), Color(0.2, 0.3, 0.4))
		k.glow(Vector3(x, 1.6, -152.28), Vector3(0.8, 2.4, 0.05), Color(0.35, 0.9, 1.0))
	k.glow(Vector3(0.0, 0.05, -140.0), Vector3(0.3, 0.02, 24.0), Color(0.4, 0.6, 1.0))
	k.text_sign("CENTRAL RESEARCH LABORATORY", Vector3(0.0, 4.0, Z.Z_D_E + 0.6), Color(0.7, 0.85, 1.0), 0.012)
	k.text_sign("PROJECT BLACK SITE  -  AUTHORISED ONLY", Vector3(0.0, 3.4, -157.4), Color(0.7, 0.85, 1.0), 0.009)
	# west wing: the data archive
	for z in [-134.0, -138.0, -156.0, -160.0, -164.0]:
		k.box(Vector3(-28.8, 1.2, z), Vector3(1.0, 2.4, 2.4), Z.METAL, false)
	k.box(Vector3(-22.0, 0.45, -140.0), Vector3(3.0, 0.9, 1.2), Z.WOOD)
	k.box(Vector3(-24.0, 0.45, -160.0), Vector3(3.0, 0.9, 1.2), Z.WOOD)
	# east wing: the power control room with the breaker wall
	k.box(Vector3(21.0, 2.4, -171.4), Vector3(14.0, 4.0, 0.4), Color(0.16, 0.2, 0.3), false)
	for x in [16.0, 19.0, 22.0, 25.0]:
		k.glow(Vector3(x, 3.0, -171.15), Vector3(1.4, 0.4, 0.04), Color(0.35, 0.8, 1.0))
	k.light(Vector3(0.0, 3.8, -140.0), Color(0.55, 0.7, 1.0), 1.3, 28.0)
	k.light(Vector3(-21.0, 3.4, -150.0), Color(0.5, 0.65, 1.0), 1.0, 20.0)
	k.light(Vector3(21.0, 3.4, -150.0), Color(0.5, 0.65, 1.0), 1.0, 20.0)
	k.light(Vector3(0.0, 3.4, -165.0), Color(0.45, 0.6, 1.0), 1.2, 18.0)
	# the laboratory power puzzle (Puzzle B): breakers must match the wall display, then the lever
	var puzzle := LabPowerPuzzle.new()
	puzzle.name = "LabPowerPuzzle"
	parent.add_child(puzzle)
	parts.puzzles["lab_power"] = puzzle
	var base_x := 16.0
	for i in 4:
		parts.switch("rc_breaker_%d" % i, Vector3(base_x + 3.0 * i, 0.0, -170.6), puzzle, "breaker_%d" % i, "Flip breaker %d" % (i + 1), "breaker %d on the power room wall" % (i + 1))
	parts.switch("rc_lab_lever", Vector3(28.0, 0.0, -170.6), puzzle, "lever", "Pull the main power lever", "the main power lever at the end of the breaker wall")
	var display := k.text_sign(puzzle.display_text(), Vector3(21.0, 3.9, -170.9), Color(0.5, 0.9, 1.0), 0.011)
	display.name = "BreakerDisplay"
	parts.doc("rc_lab_notes", Vector3(-22.0, 0.9, -140.0), "the laboratory notes on a desk in the data archive", "\n\n" + puzzle.hint_text(), 0.0)
	parts.doc("rc_director_order", Vector3(-24.0, 0.9, -160.0), "an optional order from the Director's office", "", 0.0)
	for p in [Vector3(-22.0, 0.93, -140.0), Vector3(-24.0, 0.93, -160.0)]:
		k.glow(p, Vector3(0.5, 0.04, 0.35), Color(0.95, 0.95, 0.85))
	parts.flag_door("rc_final_door", Vector3(0.0, 0.0, -158.0), LAB_POWER_DONE, "Sealed: restore the laboratory power first")
	parts.terminal("rc_black_site_data", Vector3(-3.0, 0.0, -170.8), "the Project Black Site terminal in the final chamber", NEXT_LEAD, LAB_POWER_DONE)
	parts.flag_door("rc_service_hatch", Vector3(Z.HATCH_X, 0.0, Z.Z_END), NEXT_LEAD, "The service hatch is sealed: retrieve the data first", 3.4)
	parts.checkpoint("rc_checkpoint_lab", Vector3(-6.0, 0.0, -132.0))
	parts.area_trigger("rc_final_chamber", Vector3(0.0, 2.0, -165.0), Vector3(22.0, 6.0, 12.0))
	k.finish()
	# cover for the Commander: points behind the benches (the ranged brain picks one that sees the player)
	for cover in [Vector3(-10.0, 0.0, -139.0), Vector3(10.0, 0.0, -139.0), Vector3(-10.0, 0.0, -149.0), Vector3(10.0, 0.0, -149.0), Vector3(0.0, 0.0, -155.0)]:
		parts.cover(cover)
	parts.spawn("rc_lab_heavy_1", "heavy_guard", Vector3(-6.0, 0.0, -142.0), 14.0)
	parts.spawn("rc_lab_heavy_2", "heavy_guard", Vector3(8.0, 0.0, -143.0), 14.0)
	return k


static func underground(parent: Node3D, parts: ResearchComplexParts) -> ResearchComplexKit:
	var k := ResearchComplexKit.new(parent, "Underground")
	var x := Z.HATCH_X
	k.floor_rect(Vector2(x, -188.0), Vector2(10.0, 32.0), Z.UNDER_Y, Z.UNDER_FLOOR)
	# a staircase of eight 0.5 m steps from the hatch down to the corridor
	for i in 8:
		var top := -0.5 * float(i + 1)
		var z := -173.0 - float(i)
		k.box(Vector3(x, (top + Z.UNDER_Y) * 0.5, z), Vector3(3.2, top - Z.UNDER_Y, 1.0), Color(0.34, 0.34, 0.37))
	k.wall_z(x - 1.8, -172.5, -182.0, 4.4, Z.UNDER_WALL, [], 0.5, Z.UNDER_Y)
	k.wall_z(x + 1.8, -172.5, -182.0, 4.4, Z.UNDER_WALL, [], 0.5, Z.UNDER_Y)
	k.wall_z(x - 5.0, -172.5, Z.UNDER_END_Z, 3.6, Z.UNDER_WALL, [], 0.6, Z.UNDER_Y)
	k.wall_z(x + 5.0, -172.5, Z.UNDER_END_Z, 3.6, Z.UNDER_WALL, [], 0.6, Z.UNDER_Y)
	k.wall_x(Z.UNDER_END_Z, x - 5.0, x + 5.0, 3.6, Z.UNDER_WALL, [], 0.6, Z.UNDER_Y)
	k.box(Vector3(x, Z.UNDER_Y + 3.7, -192.0), Vector3(10.0, 0.3, 24.0), Z.UNDER_WALL, false)
	for zz in [-186.0, -194.0, -200.0]:
		k.glow(Vector3(x, Z.UNDER_Y + 3.5, zz), Vector3(2.0, 0.08, 0.3), Z.LAMP_WARM)
	k.glow(Vector3(x, Z.UNDER_Y + 0.03, -198.0), Vector3(8.0, 0.02, 0.4), Z.HAZARD)
	k.text_sign("SUPPLY ROAD  -  IRON FORTRESS", Vector3(x, Z.UNDER_Y + 2.6, Z.UNDER_END_Z + 0.5), Color(1.0, 0.4, 0.3), 0.016)
	k.light(Vector3(x, Z.UNDER_Y + 3.0, -190.0), Color(1.0, 0.85, 0.6), 1.2, 22.0)
	parts.doc("rc_exit_notice", Vector3(x + 3.0, Z.UNDER_Y + 1.0, -194.0), "the exit notice taped to the tunnel wall", "", 0.0)
	parts.area_trigger("rc_sealed_exit", Vector3(x, Z.UNDER_Y + 1.5, -201.0), Vector3(9.0, 3.0, 3.0))
	k.finish()
	return k
