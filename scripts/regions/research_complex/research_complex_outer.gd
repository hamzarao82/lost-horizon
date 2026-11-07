class_name ResearchComplexOuter
extends RefCounted
## The first three areas of the Research Complex: the outdoor perimeter, the administration wing and
## the medical research wing. Each function builds one area into its own kit (so Milestone 13 can replace
## one area's art without touching the others) and registers its interactables with `parts`.

const Z = preload("res://scripts/regions/research_complex/research_complex_zones.gd")


static func perimeter(parent: Node3D, parts: ResearchComplexParts) -> ResearchComplexKit:
	var k := ResearchComplexKit.new(parent, "Perimeter")
	k.floor_rect(Vector2(0.0, 21.0), Vector2(68.0, 68.0), 0.0, Z.GROUND)
	k.floor_rect(Vector2(0.0, 21.0), Vector2(8.0, 68.0), 0.03, Z.ASPHALT)
	var z := 50.0
	while z > -10.0:
		k.glow(Vector3(0.0, 0.07, z), Vector3(0.25, 0.02, 2.6), Color(0.9, 0.85, 0.5))
		z -= 6.0
	# fence line and the road gap at the south end (the exit to Blackwood)
	k.wall_z(-32.0, Z.Z_SOUTH, Z.Z_A_B, 3.0, Z.FENCE, [], 0.4)
	k.wall_z(32.0, Z.Z_SOUTH, Z.Z_A_B, 3.0, Z.FENCE, [], 0.4)
	k.wall_x(Z.Z_SOUTH, -32.0, 32.0, 3.0, Z.FENCE, [{"x": 0.0, "w": 8.0}], 0.4)
	k.text_sign("RESTRICTED ZONE  -  AUTHORISED PERSONNEL ONLY", Vector3(0.0, 4.2, Z.Z_SOUTH + 0.3), Color(1.0, 0.8, 0.2), 0.02)
	# the facility's south facade: windows, a sign and the admin security door
	k.wall_x(Z.Z_A_B, -32.0, 32.0, 5.0, Z.CONCRETE, [{"x": 0.0, "w": 4.4}], 1.0)
	for x in [-24.0, -14.0, 14.0, 24.0]:
		k.glow(Vector3(x, 3.0, Z.Z_A_B + 0.52), Vector3(4.0, 1.0, 0.05), Color(0.12, 0.2, 0.3))
	k.text_sign("RESEARCH ADMINISTRATION", Vector3(0.0, 4.4, Z.Z_A_B + 0.6), Color(0.85, 0.9, 1.0), 0.016)
	k.glow(Vector3(0.0, 0.06, -8.0), Vector3(6.0, 0.02, 0.5), Z.HAZARD)
	parts.door("rc_admin_door", Vector3(0.0, 0.0, Z.Z_A_B), "admin")
	# the checkpoint hut beside the road: records on the back wall, the keycard rack beside them
	k.wall_z(-18.0, 18.0, 28.0, 3.2, Z.CONCRETE, [], 0.5)
	k.wall_z(-7.0, 18.0, 28.0, 3.2, Z.CONCRETE, [{"z": 23.0, "w": 2.6}], 0.5)
	k.wall_x(28.0, -18.0, -7.0, 3.2, Z.CONCRETE, [], 0.5)
	k.wall_x(18.0, -18.0, -7.0, 3.2, Z.CONCRETE, [], 0.5)
	k.box(Vector3(-12.5, 3.4, 23.0), Vector3(12.0, 0.3, 11.0), Z.METAL, false)
	k.glow(Vector3(-12.5, 3.2, 23.0), Vector3(4.0, 0.1, 0.4), Z.LAMP_WARM)
	k.text_sign("CHECKPOINT", Vector3(-6.4, 2.6, 23.0), Color(0.95, 0.9, 0.6), 0.012, PI * 0.5)
	parts.terminal("rc_checkpoint_log", Vector3(-14.0, 0.0, 27.2), "the gate logbook on the hut's back wall", "research_complex_checkpoint_searched")
	parts.panel("rc_checkpoint_panel", Vector3(-9.6, 0.0, 27.2), "admin", "the keycard rack, working once the logbook is read", "research_complex_checkpoint_searched")
	# the raised barrier arm over the road
	k.box(Vector3(-5.6, 1.4, 23.0), Vector3(0.3, 2.8, 0.3), Z.HAZARD, false)
	k.box(Vector3(-1.0, 3.0, 23.0), Vector3(9.4, 0.18, 0.18), Z.HAZARD, false)
	# guard towers
	for tower in [Vector2(-26.0, 14.0), Vector2(26.0, 14.0), Vector2(-26.0, -4.0), Vector2(26.0, -4.0)]:
		_tower(k, tower)
	# vehicles, cover and storage with a purpose (a chicane that slows a rush at the gate, cover for the guards)
	_jeep(k, Vector3(14.0, 0.0, 34.0), false)
	_jeep(k, Vector3(-22.0, 0.0, 6.0), true)
	for barrier in [Vector3(-2.0, 0.0, 46.0), Vector3(2.0, 0.0, 43.0), Vector3(-14.0, 0.0, 12.0), Vector3(12.0, 0.0, 14.0)]:
		k.box(barrier + Vector3(0.0, 0.45, 0.0), Vector3(4.0, 0.9, 0.7), Z.CONCRETE)
		k.glow(barrier + Vector3(0.0, 0.92, 0.0), Vector3(3.8, 0.04, 0.5), Z.HAZARD)
	k.box(Vector3(-24.0, 1.3, 36.0), Vector3(6.0, 2.6, 2.4), Color(0.45, 0.22, 0.18))
	k.box(Vector3(24.0, 0.6, 31.0), Vector3(2.4, 1.2, 2.4), Z.WOOD)
	k.box(Vector3(24.0, 1.8, 31.0), Vector3(1.6, 1.2, 1.6), Z.WOOD)
	k.box(Vector3(27.0, 0.6, 31.0), Vector3(1.4, 1.2, 1.4), Z.WOOD)
	k.box(Vector3(27.0, 0.3, 24.0), Vector3(1.3, 0.6, 1.3), Z.OLIVE, false)
	parts.crate("rc_cache_perimeter", ["bandage", "armor_patch", "credits_small"], Vector3(27.0, 0.0, 24.0), "an optional supply cache off the road, behind the crates")
	k.blocker(Vector3(27.0, 0.6, 24.0), Vector3(1.2, 1.2, 1.2))
	k.finish()
	# enemies: two patrols and a guard at the checkpoint (a patrol may be slipped past; clearing them also counts)
	parts.spawn("rc_guard_1", "security_guard", Vector3(-10.0, 0.0, 37.0), 20.0,
			[Vector3(-10.0, 0.0, 37.0), Vector3(8.0, 0.0, 37.0), Vector3(8.0, 0.0, 31.0), Vector3(-10.0, 0.0, 31.0)])
	parts.spawn("rc_guard_2", "security_guard", Vector3(16.0, 0.0, 10.0), 18.0,
			[Vector3(16.0, 0.0, 10.0), Vector3(-8.0, 0.0, 10.0), Vector3(-8.0, 0.0, 2.0), Vector3(16.0, 0.0, 2.0)])
	parts.spawn("rc_guard_3", "security_guard", Vector3(4.0, 0.0, 19.0), 14.0)
	parts.mission_trigger("rc_checkpoint_reach", "rc_checkpoint_reach", Vector3(-7.0, 1.5, 23.0), Vector3(4.0, 3.0, 4.0))
	parts.mission_trigger("rc_entrance", "rc_entrance", Vector3(0.0, 1.5, -6.0), Vector3(12.0, 3.0, 6.0))
	return k


static func admin_wing(parent: Node3D, parts: ResearchComplexParts) -> ResearchComplexKit:
	var k := ResearchComplexKit.new(parent, "AdminWing")
	var h := Z.WALL_H
	k.floor_rect(Vector2(0.0, -28.0), Vector2(62.0, 38.0), 0.0, Z.ADMIN_FLOOR)
	k.wall_z(-30.0, Z.Z_A_B, Z.Z_B_C, h, Z.ADMIN_WALL, [], 1.0)
	k.wall_z(30.0, Z.Z_A_B, Z.Z_B_C, h, Z.ADMIN_WALL, [], 1.0)
	k.wall_x(Z.Z_B_C, -30.0, 30.0, h, Z.ADMIN_WALL, [{"x": 0.0, "w": 4.4}], 1.0)
	# rooms off the central hall; archways are the only openings
	k.wall_z(-8.0, Z.Z_A_B, Z.Z_B_C, 3.6, Z.ADMIN_WALL, [{"z": -17.0, "w": 3.0}, {"z": -30.0, "w": 3.0}, {"z": -41.0, "w": 3.0}], 0.6)
	k.wall_z(8.0, Z.Z_A_B, Z.Z_B_C, 3.6, Z.ADMIN_WALL, [{"z": -20.0, "w": 3.0}, {"z": -38.0, "w": 3.0}], 0.6)
	k.wall_x(-24.0, -30.0, -8.0, 3.6, Z.ADMIN_WALL, [], 0.6)
	k.wall_x(-36.0, -30.0, -8.0, 3.6, Z.ADMIN_WALL, [], 0.6)
	k.wall_x(-30.0, 8.0, 30.0, 3.6, Z.ADMIN_WALL, [], 0.6)
	# lobby: reception desk, floor guide strips, hazard-striped medical door frame
	k.box(Vector3(0.0, 0.55, -18.0), Vector3(6.0, 1.1, 1.2), Z.WOOD)
	k.glow(Vector3(0.0, 1.12, -18.0), Vector3(5.6, 0.03, 0.9), Color(0.55, 0.6, 0.7))
	k.glow(Vector3(-4.0, 0.03, -28.0), Vector3(0.3, 0.02, 34.0), Color(0.5, 0.6, 0.8))
	k.glow(Vector3(4.0, 0.03, -28.0), Vector3(0.3, 0.02, 34.0), Color(0.5, 0.6, 0.8))
	k.glow(Vector3(0.0, 0.04, -44.0), Vector3(5.0, 0.02, 0.5), Z.HAZARD)
	k.text_sign("MEDICAL RESEARCH  >>", Vector3(0.0, 4.0, Z.Z_B_C + 0.6), Color(0.7, 1.0, 0.85), 0.014)
	k.text_sign("RECEPTION", Vector3(0.0, 3.0, -17.2), Color(0.85, 0.9, 1.0), 0.007)
	# offices (west) and the archive (north-west)
	for desk in [Vector3(-22.0, 0.45, -14.0), Vector3(-22.0, 0.45, -29.0), Vector3(-26.0, 0.45, -41.0)]:
		k.box(desk, Vector3(3.0, 0.9, 1.2), Z.WOOD)
	for z in [-38.0, -42.0, -44.0]:
		k.box(Vector3(-28.8, 1.1, z), Vector3(1.0, 2.2, 1.4), Z.METAL, false)
	k.glow(Vector3(-22.0, 0.95, -14.0), Vector3(1.0, 0.04, 0.7), Color(0.9, 0.9, 0.85))
	# security control (east) and the conference room (north-east)
	for z in [-14.0, -20.0, -26.0]:
		k.glow(Vector3(29.4, 2.0, z), Vector3(0.1, 1.0, 2.4), Z.SCREEN_BLUE)
	k.box(Vector3(20.0, 0.45, -18.0), Vector3(5.0, 0.9, 1.4), Z.METAL)
	k.box(Vector3(19.0, 0.45, -40.0), Vector3(8.0, 0.9, 2.4), Z.WOOD)
	for x in [15.0, 23.0]:
		k.box(Vector3(x, 0.3, -42.2), Vector3(1.2, 0.6, 0.9), Z.METAL, false)
	k.light(Vector3(0.0, 3.6, -18.0), Color(0.75, 0.85, 1.0), 1.1, 24.0)
	k.light(Vector3(-19.0, 3.3, -30.0), Color(0.8, 0.88, 1.0), 0.9, 18.0)
	k.light(Vector3(19.0, 3.3, -24.0), Color(0.7, 0.85, 1.0), 0.9, 18.0)
	# interactables
	parts.doc("rc_visitor_log", Vector3(0.0, 1.1, -18.0), "the visitor log on the reception desk", "", 0.0)
	parts.doc("rc_staff_memo", Vector3(19.0, 0.9, -40.0), "an optional staff memo on the conference table", "", 0.0)
	k.glow(Vector3(19.0, 0.93, -40.0), Vector3(0.5, 0.04, 0.35), Color(0.95, 0.95, 0.85))
	k.glow(Vector3(0.0, 1.14, -18.0), Vector3(0.5, 0.04, 0.35), Color(0.95, 0.95, 0.85))
	parts.terminal("rc_security_console", Vector3(22.0, 0.0, -29.2), "the security console against the control room's north wall", "research_complex_security_online")
	parts.terminal("rc_archive_breaker", Vector3(-24.0, 0.0, -45.2), "the archive breaker bank, live once security is online", "research_complex_archive_power", "research_complex_security_online")
	parts.terminal("rc_archive_terminal", Vector3(-14.0, 0.0, -45.2), "the archive terminal, powered by its breaker", "research_complex_records_retrieved", "research_complex_archive_power")
	parts.panel("rc_medical_panel", Vector3(3.6, 0.0, -45.2), "medical", "the access panel beside the medical door, live once security is online", "research_complex_security_online")
	parts.door("rc_medical_door", Vector3(0.0, 0.0, Z.Z_B_C), "medical")
	parts.crate("rc_cache_admin", ["antiseptic", "credits_medium", "electronics"], Vector3(27.0, 0.0, -44.0), "an optional cache in the conference room corner")
	k.blocker(Vector3(27.0, 0.6, -44.0), Vector3(1.2, 1.2, 1.2))
	parts.checkpoint("rc_checkpoint_admin", Vector3(-4.0, 0.0, -12.0))
	parts.area_trigger("rc_archive", Vector3(-19.0, 2.0, -41.0), Vector3(20.0, 6.0, 10.0))
	k.finish()
	parts.spawn("rc_admin_guard_1", "security_guard", Vector3(16.0, 0.0, -22.0), 12.0)
	parts.spawn("rc_admin_guard_2", "security_guard", Vector3(0.0, 0.0, -32.0), 12.0,
			[Vector3(-4.0, 0.0, -32.0), Vector3(4.0, 0.0, -32.0), Vector3(4.0, 0.0, -26.0), Vector3(-4.0, 0.0, -26.0)])
	return k


static func medical_wing(parent: Node3D, parts: ResearchComplexParts) -> ResearchComplexKit:
	var k := ResearchComplexKit.new(parent, "MedicalWing")
	var h := Z.WALL_H
	k.floor_rect(Vector2(0.0, -65.0), Vector2(62.0, 38.0), 0.0, Z.MEDICAL_FLOOR)
	k.wall_z(-30.0, Z.Z_B_C, Z.Z_C_D, h, Z.MEDICAL_WALL, [], 1.0)
	k.wall_z(30.0, Z.Z_B_C, Z.Z_C_D, h, Z.MEDICAL_WALL, [], 1.0)
	k.wall_x(Z.Z_C_D, -30.0, 30.0, h, Z.MEDICAL_WALL, [{"x": 0.0, "w": 4.4}], 1.0)
	k.wall_z(-8.0, Z.Z_B_C, Z.Z_C_D, 3.6, Z.MEDICAL_WALL, [{"z": -52.0, "w": 3.0}, {"z": -64.0, "w": 3.0}, {"z": -77.0, "w": 3.0}], 0.6)
	k.wall_z(8.0, Z.Z_B_C, Z.Z_C_D, 3.6, Z.MEDICAL_WALL, [{"z": -55.0, "w": 3.0}, {"z": -74.0, "w": 5.0}], 0.6)
	k.wall_x(-58.0, -30.0, -8.0, 3.6, Z.MEDICAL_WALL, [], 0.6)
	k.wall_x(-70.0, -30.0, -8.0, 3.6, Z.MEDICAL_WALL, [], 0.6)
	k.wall_x(-64.0, 8.0, 30.0, 3.6, Z.MEDICAL_WALL, [], 0.6)
	# exam rooms: beds, cabinets, a green cross over each archway; blood-red marks on one floor
	for z in [-52.0, -64.0, -77.0]:
		k.box(Vector3(-23.0, 0.45, z), Vector3(1.1, 0.7, 2.3), Color(0.85, 0.88, 0.9))
		k.box(Vector3(-28.8, 1.0, z - 2.0), Vector3(1.0, 2.0, 1.6), Z.METAL, false)
		k.glow(Vector3(-8.35, 3.2, z), Vector3(0.1, 0.5, 1.6), Z.SCREEN_GREEN)
	k.glow(Vector3(-20.0, 0.03, -76.0), Vector3(2.4, 0.02, 1.6), Color(0.45, 0.08, 0.08))
	# records room (north-east) and the observation ward (south-east) with its long window
	for z in [-50.0, -56.0, -60.0]:
		k.box(Vector3(28.8, 1.1, z), Vector3(1.0, 2.2, 3.0), Z.METAL, false)
	k.box(Vector3(20.0, 0.5, -52.0), Vector3(4.0, 1.0, 1.4), Z.WOOD)
	k.glow(Vector3(8.4, 2.0, -68.0), Vector3(0.08, 1.4, 4.0), Color(0.4, 0.8, 0.9))
	k.glow(Vector3(8.4, 2.0, -80.0), Vector3(0.08, 1.4, 4.0), Color(0.4, 0.8, 0.9))
	k.box(Vector3(26.0, 0.4, -80.0), Vector3(2.0, 0.8, 4.0), Color(0.85, 0.88, 0.9))
	k.text_sign("CONTAINMENT  >>", Vector3(0.0, 4.0, Z.Z_C_D + 0.6), Color(1.0, 0.55, 0.3), 0.014)
	k.text_sign("OBSERVATION WARD - DO NOT ENTER ALONE", Vector3(19.0, 3.2, -63.4), Color(1.0, 0.5, 0.3), 0.007)
	k.light(Vector3(0.0, 3.6, -60.0), Color(0.85, 1.0, 0.92), 1.1, 24.0)
	k.light(Vector3(-19.0, 3.3, -64.0), Color(0.85, 1.0, 0.92), 0.9, 18.0)
	k.light(Vector3(19.0, 3.3, -74.0), Color(0.8, 1.0, 0.9), 0.8, 18.0)
	parts.doc("rc_medical_evidence", Vector3(-24.0, 0.9, -64.0), "Dr. Hale's trial notes on the exam room desk", "", 0.0)
	parts.doc("rc_subject_roster", Vector3(20.0, 1.0, -52.0), "the subject roster in the records room", "", 0.0)
	parts.doc("rc_exam_note", Vector3(-24.0, 0.9, -75.0), "an optional examination note on a bed table", "", 0.0)
	parts.doc("rc_ward_notice", Vector3(24.0, 0.9, -69.0), "an optional notice on the ward window", "", 0.0)
	for p in [Vector3(-24.0, 0.93, -64.0), Vector3(20.0, 1.03, -52.0), Vector3(-24.0, 0.93, -75.0), Vector3(24.0, 0.93, -69.0)]:
		k.glow(p, Vector3(0.5, 0.04, 0.35), Color(0.95, 0.95, 0.85))
	parts.crate("rc_cache_medical", ["antiseptic", "bandage", "health_potion"], Vector3(27.0, 0.0, -82.0), "an optional cache in the restricted medical storage corner")
	k.blocker(Vector3(27.0, 0.6, -82.0), Vector3(1.2, 1.2, 1.2))
	parts.door("rc_containment_door", Vector3(0.0, 0.0, Z.Z_C_D), "medical")
	parts.checkpoint("rc_checkpoint_medical", Vector3(4.0, 0.0, -50.0))
	k.finish()
	# the ambush: two subjects wait in the dark ward. A trigger gives a 1.5 s warning before they are released.
	parts.spawn("rc_subject_med_1", "experimental_subject", Vector3(22.0, 0.0, -78.0))
	parts.spawn("rc_subject_med_2", "experimental_subject", Vector3(26.0, 0.0, -72.0))
	parts.mission_trigger("rc_medical_ambush", "rc_medical_ambush", Vector3(0.0, 1.5, -72.0), Vector3(10.0, 3.0, 4.0))
	return k


# --- small shared props --------------------------------------------------------------

static func _tower(k: ResearchComplexKit, at: Vector2) -> void:
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			k.box(Vector3(at.x + sx * 1.2, 1.5, at.y + sz * 1.2), Vector3(0.3, 3.0, 0.3), Z.METAL, false)
	k.box(Vector3(at.x, 3.1, at.y), Vector3(3.4, 0.25, 3.4), Z.METAL, false)
	k.box(Vector3(at.x, 4.0, at.y), Vector3(2.6, 1.6, 2.6), Z.OLIVE, false)
	k.glow(Vector3(at.x, 4.2, at.y + 1.32), Vector3(2.0, 0.5, 0.04), Color(0.9, 0.8, 0.45))
	k.blocker(Vector3(at.x, 1.5, at.y), Vector3(2.6, 3.0, 2.6))


static func _jeep(k: ResearchComplexKit, at: Vector3, along_z: bool) -> void:
	var body := Vector3(1.9, 0.9, 3.8) if along_z else Vector3(3.8, 0.9, 1.9)
	var cab := Vector3(1.7, 0.8, 1.8) if along_z else Vector3(1.8, 0.8, 1.7)
	k.box(at + Vector3(0.0, 0.85, 0.0), body, Z.OLIVE, false)
	k.box(at + Vector3(0.0, 1.6, 0.0), cab, Color(0.25, 0.3, 0.22), false)
	k.blocker(at + Vector3(0.0, 0.9, 0.0), Vector3(body.x, 1.8, body.z))
	for wx in [-1.0, 1.0]:
		for wz in [-1.0, 1.0]:
			var off := Vector3(wx * body.x * 0.5, 0.35, wz * body.z * 0.32)
			k.box(at + off, Vector3(0.4, 0.7, 0.7) if along_z else Vector3(0.7, 0.7, 0.4), Color(0.1, 0.1, 0.1), false)
