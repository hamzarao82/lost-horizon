class_name AreaDressing
extends RefCounted
## Primitive-built set dressing for Outpost 17 (Milestone 3 step 2).
## Visual boxes are merged into the Outpost's single greybox mesh (no extra draw calls); only a few
## props get a collider. Every prop is recorded in `props` (name, area, centre, size, collide, yaw),
## which the tests use to check the placement rules and docs/WORLD.md lists.
##
## Keep-clear rules (checked by tests/dressing_check.gd for every solid prop):
##  - the research-wing patrol corridor (x -3.5..1.5, z -58..-36)
##  - both door openings (B-C at x=12, C-D at x=0)
##  - the boss arena zone (x -12..12, z -90..-72)

const PATROL_CORRIDOR: Rect2 = Rect2(-3.5, -58.0, 5.0, 22.0)
const BOSS_ZONE: Rect2 = Rect2(-12.0, -90.0, 24.0, 18.0)
const DOOR_BC_CLEAR: Rect2 = Rect2(8.0, -33.0, 8.0, 6.0)
const DOOR_CD_CLEAR: Rect2 = Rect2(-4.0, -65.0, 8.0, 6.0)

const SCORCH: Color = Color(0.07, 0.07, 0.07)
const JEEP: Color = Color(0.17, 0.15, 0.13)
const TIRE: Color = Color(0.06, 0.06, 0.06)
const WARN_YELLOW: Color = Color(0.88, 0.72, 0.1)
const WARN_BLACK: Color = Color(0.09, 0.09, 0.09)
const MONITOR: Color = Color(0.09, 0.11, 0.12)
const BANNER_RED: Color = Color(0.5, 0.09, 0.09)
const SIGN_GREEN: Color = Color(0.16, 0.22, 0.18)

static var props: Array[Dictionary] = []
static var _used_names: Dictionary = {}

# Interior dressing (Milestone 5): floor variation, trim, power room, generator shed, command building.
const FLOOR_TONES: Array[Color] = [Color(0.2, 0.21, 0.21), Color(0.15, 0.16, 0.17), Color(0.25, 0.25, 0.23)]
const TRIM: Color = Color(0.17, 0.18, 0.17)
const PAPER: Color = Color(0.5, 0.48, 0.4)
const CABLE: Color = Color(0.04, 0.04, 0.05)
const CABINET: Color = Color(0.2, 0.24, 0.23)
const GLOW_TEAL: Color = Color(0.25, 0.95, 0.85)
const GLOW_AMBER: Color = Color(1.0, 0.68, 0.22)

static var floor_tiles: int = 0
static var glow_count: int = 0
static var _glow_teal: ArenaDecor.Builder
static var _glow_amber: ArenaDecor.Builder


static func build(outpost: Node3D, b: ArenaDecor.Builder) -> void:
	props = []
	_used_names = {}
	floor_tiles = 0
	glow_count = 0
	_glow_teal = ArenaDecor.Builder.new()
	_glow_amber = ArenaDecor.Builder.new()
	_area_a(outpost, b)
	_area_b(outpost, b)
	_area_c(outpost, b)
	_area_d(outpost, b)
	_interiors(outpost, b)


## Footprint (world XZ rectangle) of a prop, rotated by its yaw.
static func footprint(p: Dictionary) -> Rect2:
	var c: Vector3 = p["center"]
	var s: Vector3 = p["size"]
	var yaw := deg_to_rad(float(p["yaw"]))
	var ex := absf(cos(yaw)) * s.x * 0.5 + absf(sin(yaw)) * s.z * 0.5
	var ez := absf(sin(yaw)) * s.x * 0.5 + absf(cos(yaw)) * s.z * 0.5
	return Rect2(c.x - ex, c.z - ez, ex * 2.0, ez * 2.0)


static func _prop(outpost: Node3D, b: ArenaDecor.Builder, requested_name: String, area: StringName,
		center: Vector3, size: Vector3, color: Color, collide: bool = false, yaw_deg: float = 0.0,
		tilt: Vector3 = Vector3.ZERO) -> void:
	var prop_name := _unique(requested_name)
	var basis := Basis.from_euler(Vector3(deg_to_rad(tilt.x), deg_to_rad(yaw_deg), deg_to_rad(tilt.z)))
	b.box(center, size, color, basis)
	if collide:
		var body: StaticBody3D = outpost.call("_collider", prop_name, center, size)
		body.rotation.y = deg_to_rad(yaw_deg)
	props.append({"name": prop_name, "area": area, "center": center, "size": size,
			"collide": collide, "yaw": yaw_deg})


static func _at(center: Vector3, offset: Vector3, yaw_deg: float) -> Vector3:
	return center + offset.rotated(Vector3.UP, deg_to_rad(yaw_deg))


static func _crate(outpost: Node3D, crate_id: StringName, pos: Vector3, loot: PackedStringArray) -> void:
	var crate := SupplyCrate.new()
	crate.name = String(crate_id).capitalize().replace(" ", "")
	crate.crate_id = crate_id
	crate.loot_paths = loot
	if String(crate_id).begins_with("cache"):
		crate.bonus_table_path = "res://resources/loot/crate_hidden.tres"
	crate.position = pos
	outpost.add_child(crate)
	outpost.call("_collider", String(crate_id) + "Body", pos + Vector3(0.0, 0.4, 0.0), Vector3(1.1, 0.8, 0.85))
	props.append({"name": String(crate_id), "area": &"cache", "center": pos + Vector3(0.0, 0.4, 0.0),
			"size": Vector3(1.1, 0.8, 0.85), "collide": true, "yaw": 0.0})


# --- Area A: beach and perimeter ---------------------------------------------

static func _area_a(o: Node3D, b: ArenaDecor.Builder) -> void:
	var a := &"area_a_perimeter"
	# Abandoned checkpoint: a guard booth, a raised boom and a sign gantry across the gate path.
	_prop(o, b, "BoothA", a, Vector3(-8.5, 1.3, 41.5), Vector3(2.2, 2.6, 2.2), Outpost17.CONCRETE, true)
	_prop(o, b, "BoothRoofA", a, Vector3(-8.5, 2.7, 41.5), Vector3(2.9, 0.2, 2.9), ArenaDecor.RUST)
	_prop(o, b, "BoomA", a, Vector3(-5.4, 2.0, 41.5), Vector3(4.2, 0.18, 0.18), Color(0.7, 0.2, 0.15), false, 0.0, Vector3(0, 0, 32))
	_prop(o, b, "SignBoardA", a, Vector3(0.0, 3.4, 46.0), Vector3(6.4, 1.4, 0.16), SIGN_GREEN)
	_prop(o, b, "SignPostAL", a, Vector3(-3.6, 1.7, 46.0), Vector3(0.3, 3.4, 0.3), ArenaDecor.WOOD_DARK, true)
	_prop(o, b, "SignPostAR", a, Vector3(3.6, 1.7, 46.0), Vector3(0.3, 3.4, 0.3), ArenaDecor.WOOD_DARK, true)
	var label := Label3D.new()
	label.name = "SignLabelA"
	label.text = "OUTPOST 17 - NO ENTRY"
	label.font_size = 54
	label.pixel_size = 0.0095
	label.modulate = Color(0.92, 0.9, 0.78)
	label.outline_size = 6
	label.position = Vector3(0.0, 3.4, 46.12)
	o.add_child(label)
	# Sandbag stacks flanking the path.
	for s: Array in [["SandbagsA1", Vector3(6.8, 0.0, 45.2), 0.0], ["SandbagsA2", Vector3(-9.5, 0.0, 53.0), 20.0],
			["SandbagsA3", Vector3(9.0, 0.0, 57.5), -15.0]]:
		var base: Vector3 = s[1]
		var yaw: float = s[2]
		_prop(o, b, String(s[0]), a, base + Vector3(0, 0.45, 0), Vector3(2.4, 0.9, 0.9), ArenaDecor.KHAKI, true, yaw)
		_prop(o, b, String(s[0]) + "Top", a, base + Vector3(0, 0.95, 0), Vector3(1.8, 0.35, 0.8), ArenaDecor.KHAKI.darkened(0.1), false, yaw)
	# Burnt-out jeep near the gate path.
	var jc := Vector3(11.5, 0.0, 39.0)
	var jyaw := 28.0
	_prop(o, b, "JeepWreckA", a, jc + Vector3(0, 0.7, 0), Vector3(4.2, 1.0, 1.9), JEEP, true, jyaw)
	_prop(o, b, "JeepCabA", a, _at(jc, Vector3(-0.4, 1.5, 0.0), jyaw), Vector3(1.9, 0.8, 1.8), JEEP.lightened(0.05), false, jyaw)
	for w: Vector3 in [Vector3(1.4, 0.35, 1.0), Vector3(1.4, 0.35, -1.0), Vector3(-1.4, 0.35, 1.0), Vector3(-1.4, 0.35, -1.0)]:
		_prop(o, b, "JeepWheelA", a, _at(jc, w, jyaw), Vector3(0.8, 0.7, 0.35), TIRE, false, jyaw)
	# Scattered crates and a warning sign.
	_prop(o, b, "CrateA1", a, Vector3(-12.0, 0.45, 36.5), Vector3(0.9, 0.9, 0.9), ArenaDecor.WOOD, true, 15.0)
	_prop(o, b, "CrateA2", a, Vector3(-11.0, 0.3, 38.0), Vector3(0.6, 0.6, 0.6), ArenaDecor.WOOD_DARK, false, -20.0)
	_prop(o, b, "CrateA3", a, Vector3(14.0, 0.25, 48.0), Vector3(0.5, 0.5, 0.5), ArenaDecor.WOOD, false, 40.0)
	_prop(o, b, "CrateA4", a, Vector3(-14.0, 0.25, 46.0), Vector3(0.5, 0.5, 0.5), ArenaDecor.WOOD_DARK, false, 10.0)
	_prop(o, b, "WarningPostA", a, Vector3(-13.5, 1.0, 33.5), Vector3(0.12, 2.0, 0.12), ArenaDecor.WOOD_DARK)
	_prop(o, b, "WarningSignA", a, Vector3(-13.5, 1.9, 33.4), Vector3(1.1, 0.9, 0.08), WARN_YELLOW)
	_prop(o, b, "WarningBandA", a, Vector3(-13.5, 1.9, 33.34), Vector3(1.1, 0.22, 0.06), BANNER_RED)


# --- Area B: courtyard, along the walls only ---------------------------------

static func _area_b(o: Node3D, b: ArenaDecor.Builder) -> void:
	var a := &"area_b_compound"
	# Watch post on the east wall.
	_prop(o, b, "WatchPostBaseB", a, Vector3(26.3, 1.2, 10.0), Vector3(3.6, 2.4, 3.6), ArenaDecor.WOOD_DARK, true)
	_prop(o, b, "WatchPostDeckB", a, Vector3(26.3, 2.55, 10.0), Vector3(4.4, 0.2, 4.4), ArenaDecor.WOOD)
	for corner: Vector2 in [Vector2(-2.0, -2.0), Vector2(2.0, -2.0), Vector2(-2.0, 2.0), Vector2(2.0, 2.0)]:
		_prop(o, b, "WatchPostPostB", a, Vector3(26.3 + corner.x, 3.575, 10.0 + corner.y), Vector3(0.18, 1.85, 0.18), ArenaDecor.WOOD_DARK)
	_prop(o, b, "WatchPostRoofB", a, Vector3(26.3, 4.6, 10.0), Vector3(4.8, 0.15, 4.8), ArenaDecor.RUST)
	# Stacked barrels on the west wall.
	_prop(o, b, "BarrelStackB", a, Vector3(-27.0, 0.7, 6.0), Vector3(1.9, 1.4, 1.4), Color(0.28, 0.3, 0.22), true)
	_prop(o, b, "BarrelRedB", a, Vector3(-26.4, 1.55, 6.3), Vector3(0.6, 0.9, 0.6), Color(0.55, 0.15, 0.1))
	_prop(o, b, "BarrelTanB", a, Vector3(-27.5, 1.55, 5.7), Vector3(0.6, 0.9, 0.6), ArenaDecor.KHAKI)
	# A wrecked radio-mast piece lying by the east wall.
	_prop(o, b, "MastBaseB", a, Vector3(22.8, 0.25, -23.0), Vector3(1.2, 0.5, 1.2), ArenaDecor.STONE)
	_prop(o, b, "MastWreckB", a, Vector3(26.2, 0.3, -23.0), Vector3(7.0, 0.18, 0.18), Color(0.4, 0.4, 0.38), false, 0.0, Vector3(0, 0, 3))


# --- Area C: research wing ---------------------------------------------------

static func _area_c(o: Node3D, b: ArenaDecor.Builder) -> void:
	var a := &"area_c_research"
	# Signs of a hurried evacuation.
	_prop(o, b, "OverturnedChairC1", a, Vector3(-6.5, 0.25, -35.0), Vector3(0.5, 0.45, 0.5), Outpost17.STEEL, false, 20.0, Vector3(0, 0, 70))
	_prop(o, b, "OverturnedChairC2", a, Vector3(-7.0, 0.25, -52.0), Vector3(0.5, 0.45, 0.5), Outpost17.STEEL, false, -35.0, Vector3(0, 0, 75))
	_prop(o, b, "OverturnedChairC3", a, Vector3(9.0, 0.25, -44.0), Vector3(0.5, 0.45, 0.5), Outpost17.STEEL, false, 60.0, Vector3(0, 0, 65))
	_prop(o, b, "TippedBoxC1", a, Vector3(-6.2, 0.35, -41.0), Vector3(0.7, 0.7, 0.7), ArenaDecor.WOOD, false, 12.0, Vector3(18, 0, 0))
	for sc: Array in [["ScorchC1", Vector3(5.0, 0.035, -41.0), Vector3(2.6, 0.03, 2.0), 0.0],
			["ScorchC2", Vector3(-6.0, 0.035, -56.0), Vector3(3.2, 0.03, 2.2), 25.0],
			["ScorchC3", Vector3(14.0, 0.035, -46.0), Vector3(2.0, 0.03, 1.6), -10.0]]:
		_prop(o, b, String(sc[0]), a, sc[1], sc[2], SCORCH, false, sc[3])
	# Shattered monitor wall on the east wall.
	for i in 5:
		var tint := Outpost17.TEAL.darkened(0.4) if i == 2 else MONITOR
		_prop(o, b, "MonitorC%d" % (i + 1), a, Vector3(21.9, 1.8 + 0.12 * float(i % 2), -38.0 - 1.4 * float(i)),
				Vector3(0.12, 1.0, 1.2), tint, false, 0.0, Vector3(6.0 * float(i - 2), 0.0, 9.0 * float((i % 3) - 1)))
	# Warning stripes at both doors (flat decals).
	for side: Array in [["StripeBCn", 12.0, -28.4], ["StripeBCs", 12.0, -31.6], ["StripeCDn", 0.0, -60.6], ["StripeCDs", 0.0, -63.4]]:
		for i in 8:
			var stripe_color := WARN_YELLOW if i % 2 == 0 else WARN_BLACK
			_prop(o, b, "%s%d" % [String(side[0]), i], a, Vector3(float(side[1]) - 1.75 + 0.5 * float(i), 0.035, float(side[2])),
					Vector3(0.5, 0.03, 0.9), stripe_color)
	# Security cameras high on the walls.
	for cam: Array in [["CameraC1", Vector3(-21.7, 3.7, -32.5)], ["CameraC2", Vector3(21.7, 3.7, -32.5)], ["CameraC3", Vector3(-12.0, 3.7, -61.3)]]:
		_prop(o, b, String(cam[0]), a, cam[1], Vector3(0.4, 0.3, 0.5), Outpost17.STEEL, false, 0.0, Vector3(0, 0, 8))
		_prop(o, b, String(cam[0]) + "Lens", a, cam[1] + Vector3(0, -0.05, 0.3), Vector3(0.12, 0.12, 0.2), Color(0.05, 0.05, 0.08))
	# Hidden cache behind the storage room's back wall corner.
	_crate(o, &"cache_c_hidden", Vector3(-19.5, 0.0, -47.2),
			PackedStringArray(["res://resources/items/health_potion.tres", "res://resources/items/katana.tres"]))
	_prop(o, b, "TarpC", a, Vector3(-19.5, 0.9, -48.2), Vector3(1.6, 0.06, 1.0), Outpost17.CONCRETE_DARK, false, 0.0, Vector3(30, 0, 0))


# --- Area D: command wing ----------------------------------------------------

static func _area_d(o: Node3D, b: ArenaDecor.Builder) -> void:
	var a := &"area_d_command"
	# Map table by the front wall (the boss arena zone behind it stays empty).
	_prop(o, b, "MapTableD", a, Vector3(-5.0, 0.5, -68.6), Vector3(3.0, 1.0, 1.6), ArenaDecor.WOOD, true)
	_prop(o, b, "MapTopD", a, Vector3(-5.0, 1.03, -68.6), Vector3(2.6, 0.04, 1.3), ArenaDecor.CANVAS)
	# Wall screens and a banner on the side walls.
	for z in [-67.6, -70.2]:
		for x: float in [13.62, -13.62]:
			_prop(o, b, "ScreenFrameD", a, Vector3(x * 1.003, 2.6, z), Vector3(0.08, 1.4, 2.0), MONITOR)
			_prop(o, b, "ScreenD", a, Vector3(x * 0.995, 2.6, z), Vector3(0.1, 1.2, 1.8), Outpost17.TEAL)
	_prop(o, b, "BannerD", a, Vector3(13.62, 2.8, -76.0), Vector3(0.08, 2.4, 1.4), BANNER_RED)
	_prop(o, b, "BannerEmblemD", a, Vector3(13.56, 3.2, -76.0), Vector3(0.1, 0.6, 0.6), WARN_BLACK)
	# East strip behind the command building: a hidden cache and stacked crates.
	_crate(o, &"cache_d_hidden", Vector3(19.5, 0.0, -90.0),
			PackedStringArray(["res://resources/items/health_potion.tres", "res://resources/items/heavy_combat_armor.tres"]))
	_prop(o, b, "CrateD1", a, Vector3(21.0, 0.4, -87.8), Vector3(0.8, 0.8, 0.8), ArenaDecor.WOOD, false, 8.0)
	_prop(o, b, "CrateD2", a, Vector3(21.0, 1.1, -87.8), Vector3(0.6, 0.6, 0.6), ArenaDecor.WOOD_DARK, false, 30.0)
	_prop(o, b, "TarpD", a, Vector3(18.0, 0.2, -84.0), Vector3(2.4, 0.06, 1.6), Outpost17.CONCRETE_DARK, false, -12.0, Vector3(0, 0, 6))


## Stable unique names: the first use keeps its name, repeats become Name_2, Name_3 ...
static func _unique(requested: String) -> String:
	var count: int = int(_used_names.get(requested, 0)) + 1
	_used_names[requested] = count
	return requested if count == 1 else "%s_%d" % [requested, count]


# --- Interiors (Milestone 5): floors, trim, power room, generator shed, command building -------------

## A flat, non-solid decal lying on the floor (top about 0.05 m, above the floor plate and the tile layer).
static func _flat(o: Node3D, b: ArenaDecor.Builder, prop_name: String, area: StringName, x: float, z: float,
		sx: float, sz: float, color: Color, yaw_deg: float = 0.0, y: float = 0.04) -> void:
	_prop(o, b, prop_name, area, Vector3(x, y, z), Vector3(sx, 0.02, sz), color, false, yaw_deg)


## Emissive accent (screens, lamps). Goes into one of two small meshes added by _attach_glow.
static func _lit(prop_name: String, area: StringName, center: Vector3, size: Vector3, amber: bool = false,
		record: bool = true) -> void:
	var gb := _glow_amber if amber else _glow_teal
	gb.box(center, size, GLOW_AMBER if amber else GLOW_TEAL)
	glow_count += 1
	if record:
		props.append({"name": _unique(prop_name), "area": area, "center": center, "size": size, "collide": false, "yaw": 0.0})


static func _attach_glow(o: Node3D) -> void:
	for pair: Array in [[_glow_teal, GLOW_TEAL, "OutpostGlowTeal"], [_glow_amber, GLOW_AMBER, "OutpostGlowAmber"]]:
		var gb: ArenaDecor.Builder = pair[0]
		if gb.tris == 0:
			continue
		var material := StandardMaterial3D.new()
		material.vertex_color_use_as_albedo = true
		material.emission_enabled = true
		material.emission = pair[1]
		material.emission_energy_multiplier = 1.5
		material.roughness = 1.0
		var node := MeshInstance3D.new()
		node.name = pair[2]
		node.mesh = gb.finish()
		node.material_override = material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		o.add_child(node)


static func _interiors(o: Node3D, b: ArenaDecor.Builder) -> void:
	_floors_and_trim(b)
	_power_room(o, b)
	_generator_shed(o, b)
	_command_building(o, b)
	_attach_glow(o)


## Tiles of three concrete tones with seams (the plate below shows through) instead of one flat grey,
## and a dark baseboard along the outer walls. Visual only: no colliders, no manifest entries.
static func _floors_and_trim(b: ArenaDecor.Builder) -> void:
	for area: Array in [[-46.0, 32.0], [-77.0, 30.0]]:
		var z_mid: float = area[0]
		var depth: float = area[1]
		var cols := 8
		var rows := 5
		var cw := 45.0 / float(cols)
		var rh := depth / float(rows)
		for i in cols:
			for j in rows:
				var tone: Color = FLOOR_TONES[(i * 7 + j * 3 + int(absf(z_mid))) % FLOOR_TONES.size()]
				b.box(Vector3(-22.5 + cw * (float(i) + 0.5), 0.026, z_mid - depth * 0.5 + rh * (float(j) + 0.5)),
						Vector3(cw - 0.14, 0.012, rh - 0.14), tone)
				floor_tiles += 1
	for t: Array in [[-21.9, -46.0, 32.0], [21.9, -46.0, 32.0], [-21.9, -77.0, 30.0], [21.9, -77.0, 30.0],
			[-13.6, -73.0, 14.6], [13.6, -73.0, 14.6]]:
		b.box(Vector3(t[0], 0.6, t[1]), Vector3(0.2, 1.2, t[2]), TRIM)  


static func _power_room(o: Node3D, b: ArenaDecor.Builder) -> void:
	var a := &"area_c_research"
	# Cable runs from the damaged panel to switch A and to the terminal, and one out toward the door.
	_flat(o, b, "CableToSwitchA", a, 9.2, -59.2, 5.4, 0.09, CABLE, 3.0, 0.047)
	_flat(o, b, "CableToTerminal", a, 14.8, -59.2, 5.4, 0.09, CABLE, -3.0, 0.047)
	_flat(o, b, "CableToDoor", a, 12.0, -55.0, 0.09, 8.0, CABLE, 0.0, 0.047)
	# Hazard-striped panel on the back wall above the console.
	for i in 8:
		_prop(o, b, "HazardPanelC", a, Vector3(7.6 + 0.45 * float(i), 2.55, -60.12), Vector3(0.45, 0.7, 0.07),
				WARN_YELLOW if i % 2 == 0 else WARN_BLACK)
	# Side cabinets and a work desk with a lit monitor (east wall).
	_prop(o, b, "CabinetC1", a, Vector3(19.55, 1.0, -54.4), Vector3(0.8, 2.0, 1.4), CABINET, true)
	_prop(o, b, "CabinetC2", a, Vector3(19.55, 1.0, -52.4), Vector3(0.8, 2.0, 1.4), CABINET.darkened(0.15), true)
	_prop(o, b, "DeskC", a, Vector3(17.0, 0.4, -51.8), Vector3(2.2, 0.8, 0.9), ArenaDecor.WOOD_DARK, true)
	_prop(o, b, "MonitorStandC", a, Vector3(17.0, 0.88, -51.6), Vector3(0.2, 0.16, 0.2), MONITOR)
	_lit("MonitorScreenC", a, Vector3(17.0, 1.2, -51.85), Vector3(0.9, 0.5, 0.05))
	# Shelving with crates against the west wall, barrels by the entrance.
	_prop(o, b, "ShelfC", a, Vector3(4.4, 1.1, -54.5), Vector3(0.5, 2.2, 2.2), Outpost17.STEEL, true)
	for k in 3:
		_prop(o, b, "ShelfBoxC", a, Vector3(4.55, 0.55 + 0.7 * float(k), -54.5 + 0.55 * float(k - 1)), Vector3(0.35, 0.35, 0.5),
				ArenaDecor.WOOD if k % 2 == 0 else ArenaDecor.KHAKI)
	_prop(o, b, "BarrelC1", a, Vector3(4.9, 0.45, -51.2), Vector3(0.6, 0.9, 0.6), Color(0.28, 0.3, 0.22), true)
	_prop(o, b, "BarrelC2", a, Vector3(5.6, 0.45, -51.0), Vector3(0.6, 0.9, 0.6), Color(0.5, 0.14, 0.1))
	# Loose papers, a tipped stool, wall lamps and a status strip over the console.
	for pp: Array in [[8.4, -56.0, 20.0], [9.1, -55.6, -35.0], [15.5, -57.0, 70.0], [13.2, -53.0, 5.0], [16.2, -55.0, -50.0]]:
		_flat(o, b, "PaperC", a, pp[0], pp[1], 0.42, 0.3, PAPER, pp[2], 0.047)
	_prop(o, b, "StoolC", a, Vector3(14.6, 0.2, -56.4), Vector3(0.4, 0.4, 0.4), Outpost17.STEEL, false, 15.0, Vector3(0, 0, 80))
	_lit("StatusStripC", a, Vector3(12.0, 2.15, -60.13), Vector3(2.4, 0.08, 0.05))
	_lit("WallLampC1", a, Vector3(4.05, 3.3, -57.0), Vector3(0.08, 0.3, 0.3), true)
	_lit("WallLampC2", a, Vector3(19.95, 3.3, -57.0), Vector3(0.08, 0.3, 0.3), true)
	_lit("WallLampC3", a, Vector3(12.0, 3.5, -60.13), Vector3(0.3, 0.3, 0.08), true)


static func _generator_shed(o: Node3D, b: ArenaDecor.Builder) -> void:
	var a := &"area_c_research"
	# Pipes along the back wall and down to the generator, cables to switch B.
	_prop(o, b, "ShedPipeH", a, Vector3(-16.5, 3.0, -60.1), Vector3(9.0, 0.25, 0.25), Outpost17.STEEL)
	_prop(o, b, "ShedPipeV", a, Vector3(-13.0, 1.8, -60.1), Vector3(0.25, 3.6, 0.25), Outpost17.STEEL)
	_flat(o, b, "CableGenToSwitchB", a, -15.5, -58.7, 2.4, 0.09, CABLE, 18.0, 0.047)
	# Hazard stripes in front of the generator.
	for i in 8:
		_flat(o, b, "ShedStripe", a, -16.0 + 0.45 * float(i), -56.1, 0.45, 0.8,
				WARN_YELLOW if i % 2 == 0 else WARN_BLACK, 0.0, 0.047)
	# Fuel drums and a battery rack on the west wall.
	_prop(o, b, "FuelDrumS1", a, Vector3(-20.4, 0.45, -54.0), Vector3(0.62, 0.9, 0.62), Color(0.3, 0.32, 0.2), true)
	_prop(o, b, "FuelDrumS2", a, Vector3(-20.5, 0.45, -52.9), Vector3(0.62, 0.9, 0.62), Color(0.5, 0.14, 0.1))
	_prop(o, b, "FuelDrumS3", a, Vector3(-19.6, 0.45, -53.6), Vector3(0.62, 0.9, 0.62), ArenaDecor.KHAKI.darkened(0.1))
	_prop(o, b, "BatteryRackS", a, Vector3(-20.6, 0.6, -57.8), Vector3(0.7, 1.2, 1.8), CABINET)
	_lit("GeneratorLampS", a, Vector3(-13.0, 2.1, -56.72), Vector3(0.18, 0.18, 0.06), true)
	_lit("ShedLampS", a, Vector3(-18.0, 3.5, -60.13), Vector3(0.3, 0.3, 0.08), true)


static func _command_building(o: Node3D, b: ArenaDecor.Builder) -> void:
	var a := &"area_d_command"
	# Wall shelving flush with the side walls (x +-13.1, outside the boss zone), file cabinets in the back corners.
	for sx: float in [13.1, -13.1]:
		_prop(o, b, "ShelfD", a, Vector3(sx, 1.0, -78.2), Vector3(0.6, 2.0, 1.6), Outpost17.STEEL, true)
		_prop(o, b, "ShelfBoxD", a, Vector3(sx * 0.994, 1.25, -78.2), Vector3(0.4, 0.4, 1.2), ArenaDecor.WOOD)
	_prop(o, b, "FileCabinetD1", a, Vector3(-13.2, 0.7, -75.6), Vector3(0.7, 1.4, 0.8), CABINET, true)
	_prop(o, b, "FileCabinetD2", a, Vector3(13.2, 0.7, -75.4), Vector3(0.7, 1.4, 0.8), CABINET.darkened(0.12), true)
	# Wall map with pins (west wall) and a cool accent strip along the back wall.
	_prop(o, b, "WallMapD", a, Vector3(-13.62, 2.1, -73.4), Vector3(0.06, 1.5, 2.4), ArenaDecor.CANVAS)
	for pin: Array in [[-13.57, 2.4, -73.9], [-13.57, 1.9, -72.9], [-13.57, 2.2, -73.2]]:
		_prop(o, b, "MapPinD", a, Vector3(pin[0], pin[1], pin[2]), Vector3(0.05, 0.14, 0.14), BANNER_RED)
	_lit("AccentStripD", a, Vector3(0.0, 3.6, -79.65), Vector3(6.0, 0.12, 0.05))
	_lit("WallLampD1", a, Vector3(-13.65, 3.4, -79.0), Vector3(0.08, 0.3, 0.3), true)
	_lit("WallLampD2", a, Vector3(13.65, 3.4, -79.0), Vector3(0.08, 0.3, 0.3), true)
	# Flat decals only inside the arena zone: a hazard line marking where the fight starts, a command rug, papers.
	for i in 20:
		_flat(o, b, "ZoneStripeD", a, -9.5 + 1.0 * float(i), -71.7, 1.0, 0.45, WARN_YELLOW if i % 2 == 0 else WARN_BLACK, 0.0, 0.047)
	_flat(o, b, "CommandRugD", a, 0.0, -75.5, 7.0, 3.2, Color(0.1, 0.13, 0.14), 0.0, 0.04)
	for pp: Array in [[-4.0, -76.4, 25.0], [3.6, -74.2, -40.0], [-2.2, -73.0, 80.0], [5.5, -77.5, 10.0], [-6.5, -78.0, -15.0]]:
		_flat(o, b, "PaperD", a, pp[0], pp[1], 0.42, 0.3, PAPER, pp[2], 0.055)
	# Items on the existing desks (Outpost17's DeskL / DeskR): not manifest props, they add no new obstruction.
	for dx: float in [-8.0, 8.0]:
		b.box(Vector3(dx - 0.8, 1.35, -74.3), Vector3(0.7, 0.45, 0.05), MONITOR)
		b.box(Vector3(dx + 0.9, 1.04, -73.8), Vector3(0.5, 0.06, 0.38), PAPER)
	_lit("DeskScreenDL", a, Vector3(-8.8, 1.35, -74.26), Vector3(0.6, 0.36, 0.04), false, false)
	_lit("DeskScreenDR", a, Vector3(7.2, 1.35, -74.26), Vector3(0.6, 0.36, 0.04), false, false)
