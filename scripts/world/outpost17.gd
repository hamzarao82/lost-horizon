class_name Outpost17
extends Node3D
## Milestone 3 world layout. Area A (beach) and Area B (courtyard) already exist in Main/WorldFlow and
## are left untouched; this node adds AREA C (Research Access Facility, z -30..-62) and AREA D
## (Command Center, z -62..-92) north of the courtyard as bounded greybox, the doors that join them,
## the area triggers, the new interactables, the first encounter and a location banner.
## Everything visual is one merged vertex-coloured mesh; colliders are plain StaticBody3D boxes.

const AREAS: Dictionary = {
	&"area_a_perimeter": {"name": "Outer Perimeter", "rect": Rect2(-42.0, 30.0, 84.0, 50.0)},
	&"area_b_compound": {"name": "Military Compound", "rect": Rect2(-30.0, -30.0, 60.0, 60.0)},
	&"area_c_research": {"name": "Research Access Facility", "rect": Rect2(-22.5, -62.0, 45.0, 32.0)},
	&"area_d_command": {"name": "Command Center", "rect": Rect2(-22.5, -92.0, 45.0, 30.0)},
}
const X_MIN: float = -22.5
const X_MAX: float = 22.5
const WALL_H: float = 4.0
const BANNER_SECONDS: float = 2.6

const CONCRETE: Color = Color(0.34, 0.35, 0.33)  # darker: 0.58 blew out to cream under the warm sun
const CONCRETE_DARK: Color = Color(0.24, 0.25, 0.24)
const STEEL: Color = Color(0.28, 0.3, 0.3)
const TEAL: Color = Color(0.2, 0.55, 0.62)

var triggers: Dictionary = {}  # area id -> AreaTrigger
var doors: Dictionary = {}     # door id -> Door
var encounter: EncounterGroup

var _b: ArenaDecor.Builder
var _banner: Label
var _banner_tween: Tween


## Shows a caption through WorldFlow when it exists (the story captions band). Safe without it.
static func say(from: Node, text: String, seconds: float = 4.5) -> void:
	if from == null or not from.is_inside_tree():
		return
	var flow := from.get_tree().get_first_node_in_group("world_flow")
	if flow != null and flow.has_method("caption"):
		flow.call("caption", text, seconds)


func _ready() -> void:
	_b = ArenaDecor.Builder.new()
	_build_geometry()
	_finish_mesh()
	_build_doors()
	_build_triggers()
	_build_interactables()
	_build_encounter()
	_build_patrols()
	# The HUD shows the area-name banner now (Hud.show_location); a second label here doubled the text.
	# _build_banner() is kept for headless use but not called.
	var state := get_node_or_null("/root/WorldState")
	if state:
		state.area_entered.connect(_on_area_entered)


## Display name of the area containing a world position ("" outside all areas).
func location_at(pos: Vector3) -> String:
	var flat := Vector2(pos.x, pos.z)
	for id: StringName in [&"area_c_research", &"area_d_command", &"area_b_compound", &"area_a_perimeter"]:
		if (AREAS[id]["rect"] as Rect2).has_point(flat):
			return AREAS[id]["name"]
	return ""


# --- geometry ---------------------------------------------------------------

func _solid(solid_name: String, center: Vector3, size: Vector3, color: Color) -> void:
	_b.box(center, size, color)
	_collider(solid_name, center, size)


func _collider(solid_name: String, center: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = solid_name
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = center
	add_child(body)
	return body


func _build_geometry() -> void:
	# Floors: a collider slab plus a thin visual plate (top at y = 0.02, above the terrain mesh).
	_collider("FloorC", Vector3(0.0, -0.5, -46.0), Vector3(45.0, 1.0, 32.0))
	_collider("FloorD", Vector3(0.0, -0.5, -77.0), Vector3(45.0, 1.0, 30.0))
	_b.box(Vector3(0.0, -0.04, -46.0), Vector3(45.0, 0.12, 32.0), CONCRETE_DARK)
	_b.box(Vector3(0.0, -0.04, -77.0), Vector3(45.0, 0.12, 30.0), CONCRETE_DARK)
	# Perimeter walls. The courtyard's north wall (z = -30) is split in Main.tscn for the B-C door.
	_solid("WallCW", Vector3(X_MIN, 2.0, -46.0), Vector3(1.0, WALL_H, 32.0), CONCRETE)
	_solid("WallCE", Vector3(X_MAX, 2.0, -46.0), Vector3(1.0, WALL_H, 32.0), CONCRETE)
	_solid("WallDW", Vector3(X_MIN, 2.0, -77.0), Vector3(1.0, WALL_H, 30.0), CONCRETE)
	_solid("WallDE", Vector3(X_MAX, 2.0, -77.0), Vector3(1.0, WALL_H, 30.0), CONCRETE)
	_solid("WallDN", Vector3(0.0, 2.0, -92.5), Vector3(46.0, WALL_H, 1.0), CONCRETE)
	# C-D partition with a 4 m gap at x = 0 for the second door.
	_solid("WallCDL", Vector3(-12.25, 2.0, -62.0), Vector3(20.5, WALL_H, 1.0), CONCRETE)
	_solid("WallCDR", Vector3(12.25, 2.0, -62.0), Vector3(20.5, WALL_H, 1.0), CONCRETE)

	# --- Area C ---
	# Security checkpoint desk by the entrance (the clue document sits here).
	_solid("CheckpointDesk", Vector3(8.0, 0.5, -35.0), Vector3(3.0, 1.0, 1.2), STEEL)
	_b.box(Vector3(8.0, 3.2, -35.0), Vector3(4.0, 0.2, 2.4), ArenaDecor.RUST)
	for sx in [-1.8, 1.8]:
		_b.box(Vector3(8.0 + float(sx), 1.6, -35.0), Vector3(0.18, 3.2, 0.18), ArenaDecor.WOOD_DARK)
	# Storage room (west, open to the south): optional exploration reward.
	_solid("StorageBack", Vector3(-15.0, 2.5, -45.0), Vector3(12.6, 5.0, 0.6), CONCRETE)
	_solid("StorageW", Vector3(-21.0, 2.5, -39.0), Vector3(0.6, 5.0, 12.6), CONCRETE)
	_solid("StorageE", Vector3(-9.0, 2.5, -39.0), Vector3(0.6, 5.0, 12.6), CONCRETE)
	# Control room (north-east): three walls plus a front wall with a 4 m entrance at x = 12.
	_solid("ControlBack", Vector3(12.0, 2.5, -60.5), Vector3(16.6, 5.0, 0.6), CONCRETE)
	_solid("ControlW", Vector3(3.7, 2.5, -55.5), Vector3(0.6, 5.0, 10.6), CONCRETE)
	_solid("ControlE", Vector3(20.3, 2.5, -55.5), Vector3(0.6, 5.0, 10.6), CONCRETE)
	_solid("ControlFrontL", Vector3(6.85, 2.5, -50.0), Vector3(6.3, 5.0, 0.6), CONCRETE)
	_solid("ControlFrontR", Vector3(17.15, 2.5, -50.0), Vector3(6.3, 5.0, 0.6), CONCRETE)
	_solid("PanelConsole", Vector3(12.0, 0.7, -60.0), Vector3(3.0, 1.4, 0.6), STEEL)
	_b.box(Vector3(12.0, 1.5, -60.0), Vector3(2.6, 0.5, 0.2), Color(0.55, 0.15, 0.1))  # the damaged panel
	_solid("TerminalConsole", Vector3(17.5, 0.6, -60.0), Vector3(1.8, 1.2, 0.6), STEEL)
	_b.box(Vector3(17.5, 1.45, -60.0), Vector3(1.4, 0.7, 0.08), TEAL)
	# Generator shed (west): switch B lives here.
	_solid("ShedBack", Vector3(-16.5, 2.0, -60.5), Vector3(9.6, 4.0, 0.6), ArenaDecor.OLIVE)
	_solid("ShedW", Vector3(-21.2, 2.0, -56.0), Vector3(0.6, 4.0, 9.0), ArenaDecor.OLIVE)
	_solid("Generator", Vector3(-14.5, 1.0, -57.5), Vector3(3.0, 2.0, 1.5), STEEL)
	_b.box(Vector3(-14.5, 2.2, -57.5), Vector3(0.5, 0.8, 0.5), ArenaDecor.RUST)
	# Cover with switch C behind it (east side).
	_solid("CoverBarrier", Vector3(18.5, 1.0, -37.2), Vector3(4.0, 2.0, 0.8), CONCRETE)
	# A few crates of cover in the open yard.
	_solid("CoverCrateA", Vector3(-4.0, 0.6, -44.0), Vector3(1.6, 1.2, 1.6), ArenaDecor.WOOD)
	_solid("CoverCrateB", Vector3(2.0, 0.6, -52.0), Vector3(1.6, 1.2, 1.6), ArenaDecor.WOOD)

	# --- Area D ---
	# Command building: front wall with a 4 m gap at x = 0.
	_solid("CommandBack", Vector3(0.0, 2.5, -80.0), Vector3(28.6, 5.0, 0.6), CONCRETE)
	_solid("CommandW", Vector3(-14.0, 2.5, -73.0), Vector3(0.6, 5.0, 14.6), CONCRETE)
	_solid("CommandE", Vector3(14.0, 2.5, -73.0), Vector3(0.6, 5.0, 14.6), CONCRETE)
	_solid("CommandFrontL", Vector3(-8.15, 2.5, -66.0), Vector3(12.3, 5.0, 0.6), CONCRETE)
	_solid("CommandFrontR", Vector3(8.15, 2.5, -66.0), Vector3(12.3, 5.0, 0.6), CONCRETE)
	_solid("CommandConsole", Vector3(0.0, 0.6, -79.4), Vector3(4.0, 1.2, 1.0), STEEL)
	_b.box(Vector3(0.0, 1.5, -79.4), Vector3(3.4, 0.7, 0.08), TEAL)
	_solid("DeskL", Vector3(-8.0, 0.5, -74.0), Vector3(4.0, 1.0, 1.5), ArenaDecor.WOOD)
	_solid("DeskR", Vector3(8.0, 0.5, -74.0), Vector3(4.0, 1.0, 1.5), ArenaDecor.WOOD)
	# Hidden back room (north-west): entrance gap on its east wall, screened by cover.
	_solid("HiddenS", Vector3(-18.5, 2.5, -83.0), Vector3(7.4, 5.0, 0.6), CONCRETE)
	_solid("HiddenN", Vector3(-18.5, 2.5, -91.7), Vector3(7.4, 5.0, 0.6), CONCRETE)
	_solid("HiddenE1", Vector3(-15.0, 2.5, -84.5), Vector3(0.6, 5.0, 3.0), CONCRETE)
	_solid("HiddenE2", Vector3(-15.0, 2.5, -89.8), Vector3(0.6, 5.0, 3.6), CONCRETE)
	_solid("HiddenCover", Vector3(-12.6, 1.0, -87.0), Vector3(1.4, 2.0, 3.2), ArenaDecor.WOOD)


func _finish_mesh() -> void:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.95
	var node := MeshInstance3D.new()
	node.name = "OutpostGreybox"
	node.mesh = _b.finish()
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	_b = null


# --- doors, triggers ----------------------------------------------------------

func _build_doors() -> void:
	var bc := Door.new()
	bc.name = "DoorBC"
	bc.door_id = &"bc"
	bc.locked_by_flag = &"has_access_card"
	bc.lock_reason = "Door locked: access card required"
	bc.position = Vector3(12.0, 0.0, -30.0)
	add_child(bc)
	doors[&"bc"] = bc
	var cd := Door.new()
	cd.name = "DoorCD"
	cd.door_id = &"cd"
	cd.locked_by_flag = &"comms_power_on"
	cd.lock_reason = "No power to the command wing"
	cd.position = Vector3(0.0, 0.0, -62.0)
	add_child(cd)
	doors[&"cd"] = cd


func _build_triggers() -> void:
	var specs: Dictionary = {
		&"area_a_perimeter": [Vector3(0.0, 2.0, 38.0), Vector3(26.0, 6.0, 16.0)],  # the checkpoint by the beach gate
		&"area_c_research": [Vector3(0.0, 2.0, -46.0), Vector3(40.0, 6.0, 28.0)],
		&"area_d_command": [Vector3(0.0, 2.0, -77.0), Vector3(40.0, 6.0, 26.0)],
	}
	for id: StringName in specs:
		var trigger := AreaTrigger.new()
		trigger.name = "Trigger_" + String(id)
		trigger.area_id = id
		trigger.size = specs[id][1]
		trigger.position = specs[id][0]
		add_child(trigger)
		triggers[id] = trigger


# --- interactables ------------------------------------------------------------

func _place(item: Interactable, id: StringName, pos: Vector3) -> void:
	item.name = String(id).capitalize().replace(" ", "")
	item.interaction_id = id
	item.position = pos
	add_child(item)


func _build_interactables() -> void:
	# Area A: the abandoned checkpoint's log.
	var desk := LoreDocument.new()
	desk.title = "Checkpoint log"
	desk.body_text = "Gate watch abandoned. Patrol 3 pulled north without orders. Do not trust the radio room. Someone is still broadcasting from the compound."
	_place(desk, &"checkpoint_desk", Vector3(6.5, 0.7, 36.0))
	_collider("CheckpointDeskBody", Vector3(6.5, 0.5, 36.4), Vector3(2.2, 1.0, 0.9))

	# Area B: checkpoint, crates, access card reader.
	var cp_b := Checkpoint.new()
	_place(cp_b, &"checkpoint_b", Vector3(-22.0, 0.8, 24.0))
	_collider("CheckpointBBody", Vector3(-22.0, 0.8, 24.4), Vector3(0.6, 1.6, 0.6))
	var crates := {
		&"supply_crate_b1": [Vector3(-24.0, 0.0, -20.0), PackedStringArray(["res://resources/items/health_potion.tres", "res://resources/items/iron_sword.tres"])],
		&"supply_crate_b2": [Vector3(24.0, 0.0, -18.0), PackedStringArray(["res://resources/items/health_potion.tres", "res://resources/items/reinforced_armor.tres"])],
		&"supply_crate_c1": [Vector3(-15.0, 0.0, -41.0), PackedStringArray(["res://resources/items/health_potion.tres", "res://resources/items/armor_plate.tres"])],
	}
	for id: StringName in crates:
		var crate := SupplyCrate.new()
		crate.name = String(id).capitalize().replace(" ", "")
		crate.crate_id = id
		crate.loot_paths = crates[id][1]
		crate.position = crates[id][0]
		add_child(crate)
		_collider(String(id) + "Body", crate.position + Vector3(0.0, 0.4, 0.0), Vector3(1.1, 0.8, 0.85))
	var reader := CardReader.new()
	reader.door_id = &"bc"
	_place(reader, &"card_reader_c", Vector3(9.0, 1.0, -28.9))

	# Area C: clue log, control room objects.
	var seq := LoreDocument.new()
	seq.title = "Security log"
	seq.body_text = "Power was rerouted by hand: breaker B first, then A, then C. Any other order trips the panel."
	_place(seq, &"log_sequence", Vector3(8.0, 0.7, -36.4))
	var panel := SecurityPanel.new()
	_place(panel, &"security_panel", Vector3(12.0, 0.2, -58.6))
	var spots := {
		&"power_switch_a": Vector3(6.5, 0.0, -59.5),
		&"power_switch_b": Vector3(-16.5, 0.0, -59.5),
		&"power_switch_c": Vector3(18.5, 0.0, -39.0),
	}
	for id: StringName in spots:
		var switch := PowerSwitch.new()
		_place(switch, id, spots[id])
	var comms := Terminal.new()
	comms.terminal_title = "Military terminal"
	comms.requires_flag = &"comms_power_on"
	comms.locked_text = "Terminal offline: restore power"
	comms.finish_flag = &"next_location_unlocked"
	comms.pages = PackedStringArray(["Outpost 17 comms online.", "Coordinates uploaded: Research Complex."])
	_place(comms, &"military_terminal", Vector3(17.5, 0.2, -58.7))

	# Area D: the optional missing log, flavour terminal.
	var missing := LoreDocument.new()
	missing.title = "Missing security log"
	missing.body_text = "They are not guarding the island. They are guarding what they put on it. The Warden answers only to the Director."
	_place(missing, &"log_missing_security", Vector3(-19.0, 0.7, -89.0))
	var cmd := Terminal.new()
	cmd.terminal_title = "Command terminal"
	cmd.pages = PackedStringArray(["Command net: all patrols recalled to the lower levels.", "The Warden is holding the courtyard."])
	_place(cmd, &"command_terminal_d", Vector3(0.0, 0.2, -78.4))


# --- patrols -----------------------------------------------------------------

## Two guards walk the central corridor of the research wing (x = -1, between the storage room walls,
## the crates and the control room, so nothing blocks the route). They start walking when the player
## enters the courtyard, so they are already on their beat when the player reaches the door.
func _build_patrols() -> void:
	var guards := PatrolGroup.new()
	guards.name = "PatrolC"
	guards.group_id = &"c_guards"
	guards.area_id = &"area_b_compound"
	guards.scene_paths = PackedStringArray([
		"res://scenes/enemies/PatrolSoldier.tscn", "res://scenes/enemies/HunterElite.tscn"])
	guards.route_points = PackedVector3Array([
		Vector3(-1.0, 0.1, -36.0), Vector3(-1.0, 0.1, -47.0), Vector3(-1.0, 0.1, -58.0)])
	guards.loop = false  # ping-pong along the corridor
	add_child(guards)


# --- encounter ---------------------------------------------------------------

func _build_encounter() -> void:
	encounter = EncounterGroup.new()
	encounter.name = "EncounterB"
	encounter.group_id = &"b"
	encounter.position = Vector3(0.0, 0.1, -20.0)
	encounter.scene_paths = PackedStringArray(["res://scenes/enemies/PatrolSoldier.tscn", "res://scenes/enemies/PatrolSoldier.tscn"])
	encounter.offsets = PackedVector3Array([Vector3(8.0, 0.0, 0.0), Vector3(14.0, 0.0, -2.0)])
	encounter.card_position = Vector3(0.0, 0.9, 20.0)  # fallback only: the card drops where the last soldier falls
	add_child(encounter)


# --- location banner ------------------------------------------------------------

func _build_banner() -> void:
	var layer := CanvasLayer.new()
	layer.name = "LocationBanner"
	layer.layer = 55
	add_child(layer)
	_banner = Label.new()
	_banner.add_theme_font_size_override("font_size", 26)
	_banner.add_theme_color_override("font_color", Color(0.95, 0.95, 0.9))
	_banner.add_theme_color_override("font_outline_color", Color.BLACK)
	_banner.add_theme_constant_override("outline_size", 6)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_banner.offset_top = 140.0
	_banner.offset_left = -300.0
	_banner.offset_right = 300.0
	_banner.modulate.a = 0.0
	layer.add_child(_banner)


func _on_area_entered(id: StringName) -> void:
	if not AREAS.has(id) or _banner == null:
		return
	_banner.text = AREAS[id]["name"]
	_banner.modulate.a = 1.0
	if _banner_tween:
		_banner_tween.kill()
	_banner_tween = create_tween()
	_banner_tween.tween_interval(BANNER_SECONDS)
	_banner_tween.tween_property(_banner, "modulate:a", 0.0, 0.6)
