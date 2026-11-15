class_name OpeningCompound
extends Node3D
## Opening arc, milestones 7 to 10 (docs/OPENING_DECISIONS.md): the search of the compound, the research
## annex, the dispatch hall and the pre-boss gate of Outpost 17, built inside Areas B and C with the
## existing components (documents, terminals, doors, keycards, crates, checkpoints, enemy scenes).
## It leaves Area D, the Warden and the first mission alone. Everything is local to the outpost node.
##
## Flags (WorldState, [a-z0-9_] <= 48): has_lab_pass, doc_op_duty_roster_found, op_lab_entered,
## op_lab_records_read, op_overheard_guards, op_cargo_manifest_read, op_gate_hall_reached,
## op_gate_hall_cleared, op_lab_guards_cleared, op_prep_cache_taken, checkpoint_op_predoor.

const QUESTS: Array[StringName] = [&"opening_search", &"opening_research", &"opening_command_hall", &"opening_restricted"]
const START_QUEST: StringName = &"opening_search"
const GATE_FLAG: StringName = &"opening_event_seen"  # the beach handoff sets it; headless tests never do
const LAB_PASS: StringName = &"has_lab_pass"
const LAB_DOOR_ID: StringName = &"lab"

const GUARD_STATION_CENTER: Vector3 = Vector3(-22.5, 0.0, -27.0)
const LAB_CENTER: Vector3 = Vector3(18.3, 0.0, -45.1)
const GATE_HALL_CENTER: Vector3 = Vector3(-6.0, 0.0, -54.0)

const SOLID_COLOR: Color = Color(0.3, 0.31, 0.3)
const SOLID_DARK: Color = Color(0.2, 0.21, 0.2)
const BEDROLL: Color = Color(0.36, 0.34, 0.26)
const HAZARD_YELLOW: Color = Color(0.86, 0.7, 0.12)
const HAZARD_BLACK: Color = Color(0.1, 0.1, 0.1)

var lab_door: Door
var guard_groups: Dictionary = {}  # group id -> Array[Node3D] while alive

var _opaque: ArenaDecor.Builder = ArenaDecor.Builder.new()
var _glass: ArenaDecor.Builder = ArenaDecor.Builder.new()
var _glow: ArenaDecor.Builder = ArenaDecor.Builder.new()
var _state: Node
var _groups: Dictionary = {}  # group id -> {scenes, positions, area, flag, spawned}


static func build(outpost: Node3D) -> OpeningCompound:
	var node := OpeningCompound.new()
	node.name = "OpeningCompound"
	outpost.add_child(node)
	return node


func _ready() -> void:
	_state = get_node_or_null("/root/WorldState")
	_build_guard_station()
	_build_worker_stores()
	_build_lab()
	_build_gate_hall()
	_build_signage()
	_attach_meshes()
	_build_guard_groups()
	if _state != null:
		_state.area_entered.connect(_on_area_entered)
		_state.flag_changed.connect(_on_flag_changed)


# --- guard station (Area B, north-west corner) ---------------------------------

func _build_guard_station() -> void:
	var c := GUARD_STATION_CENTER
	_opaque.box(Vector3(c.x, 3.2, c.z + 0.1), Vector3(11.4, 0.2, 6.0), SOLID_DARK)  # roof over the lean-to
	for px: float in [-27.8, -17.2]:
		_opaque.box(Vector3(px, 1.6, -24.2), Vector3(0.2, 3.2, 0.2), ArenaDecor.WOOD_DARK)
	_solid("BunkA", Vector3(-27.0, 0.45, -28.6), Vector3(2.4, 0.9, 0.9), ArenaDecor.WOOD_DARK)
	_solid("BunkB", Vector3(-27.0, 0.45, -26.5), Vector3(2.4, 0.9, 0.9), ArenaDecor.WOOD_DARK)
	_opaque.box(Vector3(-27.0, 0.97, -28.6), Vector3(2.2, 0.12, 0.75), BEDROLL)
	_opaque.box(Vector3(-27.0, 0.97, -26.5), Vector3(2.2, 0.12, 0.75), BEDROLL.darkened(0.15))
	_solid("StationDesk", Vector3(-20.5, 0.4, -28.9), Vector3(2.2, 0.8, 0.9), ArenaDecor.WOOD)
	_solid("StationCrates", Vector3(-17.9, 0.5, -28.6), Vector3(1.2, 1.0, 1.2), ArenaDecor.KHAKI)
	var roster := LoreDocument.new()
	roster.title = "Duty roster"
	roster.body_text = "Gate detail: 4 on, 4 off. Lab door: pass from the duty desk only. Section R is not on this roster. Do not ask who is."
	_place(roster, &"op_duty_roster", Vector3(-20.5, 0.7, -27.8))
	if _state == null or not _state.has_flag(LAB_PASS):
		Keycard.spawn(self, Vector3(-18.9, 0.9, -26.6), LAB_PASS, "Lab Pass")


# --- worker stores (Area C storage room) ---------------------------------------

func _build_worker_stores() -> void:
	for z: float in [-35.5, -37.3, -39.1]:
		_opaque.box(Vector3(-19.6, 0.1, z), Vector3(1.8, 0.2, 0.8), BEDROLL.darkened(0.1 * absf(fmod(z, 3.0))))
	_opaque.box(Vector3(-19.6, 0.5, -33.6), Vector3(2.4, 0.06, 1.0), SOLID_DARK)  # a hung tarp edge, no collider
	_solid("StoresCrates", Vector3(-10.4, 0.6, -43.6), Vector3(1.4, 1.2, 1.4), ArenaDecor.WOOD)
	var manifest := LoreDocument.new()
	manifest.title = "Supply manifest"
	manifest.body_text = "Bedding 14, ration tins 14, gloves 14. Transfers up from the harbor this week: 9. Counted back to quarters: 6. Do not log the difference."
	_place(manifest, &"op_supply_manifest", Vector3(-12.0, 0.7, -36.0))
	_label("WORKER STORES", Vector3(-15.0, 3.0, -44.6))


# --- research annex (Area C east yard) -----------------------------------------

func _build_lab() -> void:
	var x_w := 14.5
	_solid("LabWallN", Vector3(18.25, 2.0, -41.5), Vector3(7.5, 4.0, 0.4), SOLID_COLOR)
	_solid("LabWallS", Vector3(18.25, 2.0, -48.8), Vector3(7.5, 4.0, 0.4), SOLID_COLOR)
	_solid("LabWallWN", Vector3(x_w, 2.0, -42.6), Vector3(0.4, 4.0, 2.2), SOLID_COLOR)
	_opaque.box(Vector3(x_w, 0.45, -47.75), Vector3(0.4, 0.9, 2.1), SOLID_DARK)  # window sill
	_glass.box(Vector3(x_w, 2.05, -47.75), Vector3(0.12, 2.3, 2.0), Color(0.6, 0.9, 0.95))
	_collider("LabWindow", Vector3(x_w, 2.0, -47.75), Vector3(0.4, 4.0, 2.1))
	_opaque.box(Vector3(18.25, 0.05, -45.15), Vector3(7.2, 0.02, 7.0), Color(0.46, 0.56, 0.58))  # cold floor plate
	for tz: float in [-43.0, -45.2, -47.4]:
		_collider("LabTank", Vector3(20.9, 1.1, tz), Vector3(0.9, 2.2, 0.9))
		_opaque.box(Vector3(20.9, 0.15, tz), Vector3(1.0, 0.3, 1.0), SOLID_DARK)
		_glass.box(Vector3(20.9, 1.3, tz), Vector3(0.8, 1.8, 0.8), Color(0.6, 0.95, 0.85))
		_glow.box(Vector3(20.9, 1.25, tz), Vector3(0.45, 1.3, 0.45), Color(0.3, 1.0, 0.7))
	_solid("LabBench", Vector3(17.4, 0.45, -47.9), Vector3(3.2, 0.9, 0.9), SOLID_COLOR)
	_glow.box(Vector3(17.4, 1.02, -48.1), Vector3(1.0, 0.04, 0.5), Color(0.3, 0.9, 1.0))

	lab_door = Door.new()
	lab_door.name = "DoorLab"
	lab_door.door_id = LAB_DOOR_ID
	lab_door.width = 3.0
	lab_door.locked_by_flag = LAB_PASS
	lab_door.lock_reason = "Restricted: lab pass required"
	lab_door.position = Vector3(x_w, 0.0, -45.2)
	lab_door.rotation.y = PI * 0.5
	add_child(lab_door)

	var terminal := Terminal.new()
	terminal.terminal_title = "Lab terminal"
	terminal.finish_flag = &"op_lab_records_read"
	terminal.pages = PackedStringArray([
		"TRANSFER LOG: 6 of 9 from the harbor routed to Section R. Consent field: blank.",
		"Medical stores moved to Section R separately. Do not mix them with compound stores."])
	_place(terminal, &"op_lab_terminal", Vector3(16.8, 0.2, -42.3))
	terminal.set_meta("behind_door", true)
	var sheet := LoreDocument.new()
	sheet.title = "Subject sheet"
	sheet.body_text = "Subject: worker. Volunteer: no. Response to stimulus: [REDACTED]. Return to quarters: not scheduled."
	_place(sheet, &"op_subject_sheet", Vector3(19.7, 0.7, -42.3))
	sheet.set_meta("behind_door", true)
	_trigger("LabEntered", Vector3(18.25, 1.5, -45.1), Vector3(6.4, 3.0, 6.4), &"op_lab_entered")
	_trigger("OverheardGuards", Vector3(10.0, 1.5, -44.0), Vector3(3.0, 3.0, 3.0), &"op_overheard_guards", _play_overheard)
	var count := 1 if _low_quality() else 2
	for i in count:
		var lamp := OmniLight3D.new()
		lamp.name = "LabLight%d" % i
		lamp.light_color = Color(0.55, 0.95, 1.0)
		lamp.light_energy = 0.9
		lamp.omni_range = 8.0
		lamp.shadow_enabled = false
		lamp.position = Vector3(17.0 + 2.6 * float(i), 3.0, -45.1)
		add_child(lamp)
	_label("RESEARCH ANNEX  -  SECTION R", Vector3(x_w - 0.3, 3.4, -45.2), -PI * 0.5)


func _play_overheard() -> void:
	Outpost17.say(self, "Guard: The new cargo went down to the command level, not the stores.", 3.6)
	if not is_inside_tree():
		return
	get_tree().create_timer(4.2).timeout.connect(func() -> void:
		Outpost17.say(self, "Guard: Then it is not ours to count. Keep your mouth shut.", 3.6))


# --- dispatch hall (Area C, west of the patrol lane, before DoorCD) -------------

func _build_gate_hall() -> void:
	var dispatch := Terminal.new()
	dispatch.terminal_title = "Dispatch terminal"
	dispatch.finish_flag = &"op_cargo_manifest_read"
	dispatch.pages = PackedStringArray([
		"INBOUND: salvage from the east beach. One bag, sealed, unclaimed. Routed to the restricted store, command level.",
		"Seal on the command wing stays down. The Warden holds the command room. Nobody passes unannounced."])
	_place(dispatch, &"op_dispatch_terminal", Vector3(-7.5, 0.2, -49.0))
	var cp := Checkpoint.new()
	_place(cp, &"op_predoor", Vector3(-7.0, 0.8, -54.5))
	_collider("PreDoorCheckpointBody", Vector3(-7.0, 0.8, -54.9), Vector3(0.6, 1.6, 0.6))
	var crate := SupplyCrate.new()
	crate.name = "OpPrepCache"
	crate.crate_id = &"op_prep_cache"
	crate.loot_paths = PackedStringArray(["res://resources/items/health_potion.tres", "res://resources/items/armor_plate.tres"])
	crate.position = Vector3(-8.5, 0.0, -57.5)
	add_child(crate)
	_collider("OpPrepCacheBody", crate.position + Vector3(0.0, 0.4, 0.0), Vector3(1.1, 0.8, 0.85))
	# A torn cell wall and a note: the only foreshadowing of the room beyond, in the game's own words.
	_opaque.box(Vector3(-10.4, 0.9, -50.9), Vector3(0.18, 1.8, 1.6), SOLID_DARK, Basis(Vector3.UP, 0.5).rotated(Vector3.RIGHT, 0.25))
	_opaque.box(Vector3(-10.9, 0.15, -49.8), Vector3(1.4, 0.3, 0.6), SOLID_COLOR, Basis(Vector3.UP, -0.4))
	var note := LoreDocument.new()
	note.title = "Cell note"
	note.body_text = "Cell wall torn outward, steel. Scratched inside: THE WARDEN ANSWERS ONLY TO THE DIRECTOR. Hold detail doubled."
	_place(note, &"op_cell_note", Vector3(-10.0, 0.7, -52.2))
	_trigger("GateHallReached", Vector3(-5.5, 1.5, -54.0), Vector3(8.0, 3.0, 9.0), &"op_gate_hall_reached")
	_wake_volume("GuardWake", Vector3(0.0, 1.5, -37.0), Vector3(40.0, 3.0, 8.0))


func _build_signage() -> void:
	for i in 8:
		_opaque.box(Vector3(-1.75 + 0.5 * float(i), 4.45, -61.45), Vector3(0.5, 0.35, 0.1), HAZARD_YELLOW if i % 2 == 0 else HAZARD_BLACK)
	_label("RESTRICTED  -  COMMAND LEVEL", Vector3(0.0, 3.85, -61.4))
	_label("GUARD STATION", Vector3(GUARD_STATION_CENTER.x, 2.75, -24.25))


func _build_guard_groups() -> void:
	_add_group(&"op_lab_guards", ["res://scenes/enemies/PatrolSoldier.tscn", "res://scenes/enemies/PatrolSoldier.tscn"],
			[Vector3(12.0, 0.1, -44.0), Vector3(12.4, 0.1, -47.4)], &"area_c_research", &"op_lab_guards_cleared")
	_add_group(&"op_gate_hall", ["res://scenes/enemies/PatrolSoldier.tscn", "res://scenes/enemies/HunterElite.tscn", "res://scenes/enemies/PatrolSoldier.tscn"],
			[Vector3(-5.5, 0.1, -51.0), Vector3(-6.5, 0.1, -58.6), Vector3(4.0, 0.1, -57.5)], &"area_c_research", &"op_gate_hall_cleared")


# --- enemy groups: spawn once on entering the area, remembered when cleared ----------

func _add_group(id: StringName, scenes: Array, positions: Array, area: StringName, flag: StringName) -> void:
	_groups[id] = {"scenes": scenes, "positions": positions, "area": area, "flag": flag, "spawned": false, "alive": 0}
	if _state != null and _state.has_flag(flag):
		_groups[id]["spawned"] = true


func spawn_group(id: StringName) -> int:
	var g: Dictionary = _groups.get(id, {})
	if g.is_empty() or g["spawned"]:
		return 0
	g["spawned"] = true
	var host := get_parent()
	var made := 0
	for i in (g["scenes"] as Array).size():
		var scene := load(g["scenes"][i]) as PackedScene
		if scene == null:
			continue
		var enemy := scene.instantiate() as Node3D
		enemy.position = g["positions"][i]
		host.add_child(enemy)
		if enemy.has_signal("defeated"):
			enemy.connect("defeated", _on_guard_defeated.bind(enemy, id))
			g["alive"] = int(g["alive"]) + 1
			made += 1
	guard_groups[id] = made
	return made


func _on_guard_defeated(_last: Node3D, id: StringName) -> void:
	var g: Dictionary = _groups.get(id, {})
	if g.is_empty():
		return
	g["alive"] = int(g["alive"]) - 1
	if int(g["alive"]) <= 0 and _state != null:
		_state.set_flag(g["flag"], true)


## The guards wake when the player's body walks into the first strip of the research wing (a physical
## volume, so global area signals fired by other systems cannot spawn them early).
func _wake_volume(volume_name: String, center: Vector3, size: Vector3) -> void:
	var area := Area3D.new()
	area.name = volume_name
	area.collision_layer = 0
	area.collision_mask = 2
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	area.add_child(shape)
	area.position = center
	add_child(area)
	area.body_entered.connect(func(body: Node3D) -> void:
		if body is Player:
			for gid: StringName in _groups:
				spawn_group(gid))


func _on_area_entered(id: StringName) -> void:
	if id == &"area_b_compound":
		start_quests_if_ready()


func _on_flag_changed(flag: StringName, value: bool) -> void:
	if value and flag == GATE_FLAG:
		start_quests_if_ready()


## The opening's search quests only start in a real New Game (the beach handoff sets the gate flag).
func start_quests_if_ready() -> bool:
	var qm := get_node_or_null("/root/QuestManager")
	if _state == null or qm == null or not _state.has_flag(GATE_FLAG):
		return false
	for id in QUESTS:
		if qm.is_active(id) or qm.is_completed(id):
			return false
	return qm.start_quest(START_QUEST, true)


# --- building blocks -------------------------------------------------------------

func _solid(solid_name: String, center: Vector3, size: Vector3, color: Color) -> void:
	_opaque.box(center, size, color)
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


func _place(item: Interactable, id: StringName, pos: Vector3) -> void:
	item.name = String(id).capitalize().replace(" ", "")
	item.interaction_id = id
	item.position = pos
	add_child(item)


func _label(text: String, pos: Vector3, yaw: float = 0.0) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 48
	label.pixel_size = 0.008
	label.modulate = Color(0.95, 0.9, 0.7)
	label.outline_size = 8
	label.position = pos
	label.rotation.y = yaw
	add_child(label)


## A one-shot volume that sets a flag when the player walks in (and optionally runs a callback).
func _trigger(trigger_name: String, center: Vector3, size: Vector3, flag: StringName, on_enter: Callable = Callable()) -> void:
	var area := Area3D.new()
	area.name = trigger_name
	area.collision_layer = 0
	area.collision_mask = 2
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	area.add_child(shape)
	area.position = center
	add_child(area)
	area.body_entered.connect(func(body: Node3D) -> void:
		if not (body is Player) or _state == null or _state.has_flag(flag):
			return
		_state.set_flag(flag, true)
		if on_enter.is_valid():
			on_enter.call())


func _low_quality() -> bool:
	var settings := get_node_or_null("/root/Settings")
	return OS.has_feature("web") or (settings != null and int(settings.get("quality")) == 0)


func _attach_meshes() -> void:
	var opaque_material := StandardMaterial3D.new()
	opaque_material.vertex_color_use_as_albedo = true
	opaque_material.roughness = 0.9
	_add_mesh("OpeningCompoundMesh", _opaque, opaque_material)
	var glass_material := StandardMaterial3D.new()
	glass_material.vertex_color_use_as_albedo = true
	glass_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_material.albedo_color = Color(1.0, 1.0, 1.0, 0.28)
	glass_material.roughness = 0.2
	_add_mesh("OpeningCompoundGlass", _glass, glass_material)
	var glow_material := StandardMaterial3D.new()
	glow_material.vertex_color_use_as_albedo = true
	glow_material.emission_enabled = true
	glow_material.emission = Color(0.3, 0.95, 0.8)
	glow_material.emission_energy_multiplier = 1.3
	_add_mesh("OpeningCompoundGlow", _glow, glow_material)


func _add_mesh(mesh_name: String, builder: ArenaDecor.Builder, material: Material) -> void:
	if builder.tris == 0:
		return
	var node := MeshInstance3D.new()
	node.name = mesh_name
	node.mesh = builder.finish()
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
