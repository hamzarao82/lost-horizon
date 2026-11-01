class_name WorldFlow
extends Node3D
## Milestone 1 world flow, built in code and added to Main.tscn as the `World` node:
##   beach start -> radio -> three breakers -> south gate opens -> courtyard waves -> Warden
##   -> keycard drops -> command terminal.
## Everything is primitives with shared materials; static scenery is merged into one mesh. State
## (flags) lives in the WorldState autoload, so a death restart keeps the puzzle progress.
## Only gameplay-neutral colliders are added; the arena layout and WaveManager rules are unchanged.

const SPAWN: Vector3 = Vector3(0.0, 0.1, 64.0)
const BEACH_X: float = 42.0          # beach is x in [-42, 42]
const BEACH_NEAR_Z: float = 30.0     # the south arena fence
const BEACH_FAR_Z: float = 80.0      # end of walkable sand
const SWITCH_IDS: Array[StringName] = [&"switch_1", &"switch_2", &"switch_3"]
const SWITCH_SPOTS: Dictionary = {
	&"switch_1": Vector3(-17.5, 0.0, 41.5),  # behind the wrecked boat
	&"switch_2": Vector3(34.5, 0.0, 49.0),   # on the east perimeter fence
	&"switch_3": Vector3(-30.5, 0.0, 57.0),  # at the foot of the watchtower
}
const RADIO_SPOT: Vector3 = Vector3(-7.0, 0.0, 60.4)
const TERMINAL_SPOT: Vector3 = Vector3(0.0, 0.0, -27.6)
const RADIO_LINES: Array[String] = [
	"...static... Anyone out there? This is Outpost 17.",
	"Our power is dead and the courtyard gate is locked down.",
	"Throw the three breakers: behind the wreck, on the east fence, at the watchtower.",
]
const CAPTION_SECONDS: float = 4.5

## Tests and tools that need the player at the arena origin turn this off.
@export var start_on_beach: bool = true

var gate: WorldGate
var radio: Interactable
var terminal: Interactable
var switches: Array[BreakerSwitch] = []
var crates: Array[SupplyCrate] = []
var trigger: Area3D
var courtyard_started: bool = false

var _waves: Node
var _terminal_screen: MeshInstance3D
var _terminal_screen_locked: StandardMaterial3D
var _terminal_screen_open: StandardMaterial3D
var _caption: Label
var _caption_tween: Tween


func _ready() -> void:
	_waves = get_parent().get_node_or_null("WaveManager")
	_build_colliders()
	_build_scenery()
	_build_interactables()
	_build_trigger()
	_build_caption()
	_wire_signals()
	_attach_interactor()
	_refresh_from_state()
	if start_on_beach and DisplayServer.get_name() != "headless":
		place_player()


## Put the player at the beach start, facing the arena.
func place_player() -> void:
	var player := get_tree().get_first_node_in_group("player") as Player
	if player:
		player.global_position = SPAWN
		player.velocity = Vector3.ZERO


# --- colliders ---------------------------------------------------------------

func _static_box(box_name: String, center: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = box_name
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = center
	add_child(body)
	return body


func _build_colliders() -> void:
	var near := BEACH_NEAR_Z
	var length := BEACH_FAR_Z - near
	# Sand: contiguous with the arena floor, top at y = 0.
	_static_box("BeachFloor", Vector3(0.0, -0.5, near + length * 0.5), Vector3(BEACH_X * 2.0, 1.0, length))
	# Boundary walls (no meshes; the rope fence in ArenaDecor is the visible edge).
	_static_box("BeachWallE", Vector3(BEACH_X + 0.5, 2.0, near + length * 0.5), Vector3(1.0, 4.0, length + 1.0))
	_static_box("BeachWallW", Vector3(-BEACH_X - 0.5, 2.0, near + length * 0.5), Vector3(1.0, 4.0, length + 1.0))
	_static_box("BeachWallS", Vector3(0.0, 2.0, BEACH_FAR_Z + 0.5), Vector3(BEACH_X * 2.0 + 2.0, 4.0, 1.0))
	# Fence stubs that join the arena's south fence to the beach walls.
	var stub_width := BEACH_X - 30.0
	_static_box("FenceStubE", Vector3(30.0 + stub_width * 0.5, 2.0, near), Vector3(stub_width, 4.0, 1.0))
	_static_box("FenceStubW", Vector3(-30.0 - stub_width * 0.5, 2.0, near), Vector3(stub_width, 4.0, 1.0))
	# Set pieces the player cannot walk through.
	_static_box("RadioHutBody", Vector3(-7.0, 1.2, 58.0), Vector3(3.2, 2.4, 2.8))
	_static_box("WatchtowerBody", Vector3(-33.0, 2.5, 55.0), Vector3(3.0, 5.0, 3.0))
	_static_box("EastFenceBody", Vector3(36.0, 0.9, 49.0), Vector3(0.4, 1.8, 14.0))
	for id in SWITCH_IDS:
		var spot: Vector3 = SWITCH_SPOTS[id]
		_static_box("%sHousing" % String(id), spot + Vector3(0.0, 0.55, -0.1), Vector3(0.7, 1.1, 0.4))


# --- scenery (one merged mesh) -----------------------------------------------

func _build_scenery() -> void:
	var b := ArenaDecor.Builder.new()
	var wood := ArenaDecor.WOOD
	var wood_dark := ArenaDecor.WOOD_DARK
	var khaki := ArenaDecor.KHAKI
	var olive := ArenaDecor.OLIVE
	var rust := ArenaDecor.RUST
	var steel := Color(0.28, 0.3, 0.3)

	# Radio hut with antenna.
	var hut := Vector3(-7.0, 0.0, 58.0)
	b.box(hut + Vector3(0.0, 1.2, 0.0), Vector3(3.2, 2.4, 2.8), khaki)
	b.box(hut + Vector3(0.0, 2.5, 0.0), Vector3(3.7, 0.2, 3.3), rust)
	b.box(hut + Vector3(0.0, 1.0, 1.41), Vector3(0.9, 1.9, 0.06), wood_dark)
	b.box(hut + Vector3(-1.0, 1.5, 1.41), Vector3(0.6, 0.5, 0.06), steel)
	b.prism(hut + Vector3(1.1, 2.6, -0.8), 0.07, 0.05, 4.0, 5, steel)
	b.box(hut + Vector3(1.1, 5.9, -0.8), Vector3(1.4, 0.06, 0.06), steel)
	b.box(hut + Vector3(1.1, 5.4, -0.8), Vector3(0.9, 0.06, 0.06), steel)
	# Radio set on a crate in front of the hut.
	b.box(RADIO_SPOT + Vector3(0.0, 0.25, -0.5), Vector3(0.9, 0.5, 0.6), wood)
	b.box(RADIO_SPOT + Vector3(0.0, 0.62, -0.5), Vector3(0.7, 0.25, 0.4), olive)
	b.box(RADIO_SPOT + Vector3(0.2, 0.82, -0.5), Vector3(0.05, 0.3, 0.05), steel)

	# Watchtower.
	var tower := Vector3(-33.0, 0.0, 55.0)
	for sx in [-1.2, 1.2]:
		for sz in [-1.2, 1.2]:
			b.box(tower + Vector3(sx, 2.6, sz), Vector3(0.28, 5.2, 0.28), wood_dark)
	b.box(tower + Vector3(0.0, 2.3, 0.0), Vector3(2.6, 0.12, 0.12), wood_dark, Basis(Vector3.UP, 0.78))
	b.box(tower + Vector3(0.0, 2.3, 0.0), Vector3(2.6, 0.12, 0.12), wood_dark, Basis(Vector3.UP, -0.78))
	b.box(tower + Vector3(0.0, 5.2, 0.0), Vector3(3.2, 0.2, 3.2), wood)
	b.box(tower + Vector3(0.0, 6.15, 1.5), Vector3(3.2, 1.7, 0.12), khaki)
	b.box(tower + Vector3(0.0, 6.15, -1.5), Vector3(3.2, 1.7, 0.12), khaki)
	b.box(tower + Vector3(1.5, 6.15, 0.0), Vector3(0.12, 1.7, 3.2), khaki)
	b.box(tower + Vector3(0.0, 7.1, 0.0), Vector3(3.8, 0.2, 3.8), rust)
	b.box(tower + Vector3(1.9, 2.6, 0.0), Vector3(0.08, 5.2, 0.08), wood_dark, Basis(Vector3.BACK, 0.12))
	for i in 8:
		b.box(tower + Vector3(1.78, 0.5 + i * 0.6, 0.0), Vector3(0.1, 0.06, 0.6), wood_dark)

	# East perimeter fence (posts and wire).
	var z := 42.0
	while z <= 56.0:
		b.box(Vector3(36.0, 0.95, z), Vector3(0.14, 1.9, 0.14), wood_dark)
		if z < 56.0:
			b.box(Vector3(36.0, 1.6, z + 1.0), Vector3(0.04, 0.04, 2.0), steel)
			b.box(Vector3(36.0, 1.1, z + 1.0), Vector3(0.04, 0.04, 2.0), steel)
			b.box(Vector3(36.0, 0.6, z + 1.0), Vector3(0.04, 0.04, 2.0), steel)
		z += 2.0

	# Breaker housings (the lever and lamp belong to each BreakerSwitch).
	for id in SWITCH_IDS:
		var spot: Vector3 = SWITCH_SPOTS[id]
		b.box(spot + Vector3(0.0, 0.55, -0.1), Vector3(0.7, 1.1, 0.4), steel)
		b.box(spot + Vector3(0.0, 1.12, -0.1), Vector3(0.76, 0.08, 0.46), rust)

	# Command shed against the north wall, inside the courtyard (visual only, no collision).
	var shed := Vector3(0.0, 0.0, -27.2)
	for sx in [-3.2, 3.2]:
		b.box(shed + Vector3(sx, 1.6, 1.2), Vector3(0.22, 3.2, 0.22), wood_dark)
		b.box(shed + Vector3(sx, 1.6, -1.8), Vector3(0.22, 3.2, 0.22), wood_dark)
	b.box(shed + Vector3(0.0, 3.3, -0.3), Vector3(7.2, 0.2, 3.6), rust)
	b.box(TERMINAL_SPOT + Vector3(0.0, 0.55, -0.9), Vector3(1.7, 1.1, 0.8), steel)

	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.95
	var node := MeshInstance3D.new()
	node.name = "WorldProps"
	node.mesh = b.finish()
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)


# --- interactables -----------------------------------------------------------

func _build_interactables() -> void:
	radio = Interactable.new()
	radio.name = "Radio"
	radio.interaction_id = &"radio"
	radio.prompt_text = "Use radio"
	radio.interact_radius = 2.4
	radio.position = RADIO_SPOT + Vector3(0.0, 0.5, 0.0)
	add_child(radio)

	for id in SWITCH_IDS:
		var item := BreakerSwitch.new()
		item.name = String(id).capitalize().replace(" ", "")
		item.interaction_id = id
		item.position = SWITCH_SPOTS[id] + Vector3(0.0, 0.0, 0.2)
		add_child(item)
		switches.append(item)

	var crate_items := {
		&"crate_1": [Vector3(11.0, 0.0, 58.0), PackedStringArray([
				"res://resources/items/health_potion.tres", "res://resources/items/combat_knife.tres"])],
		&"crate_2": [Vector3(-26.0, 0.0, 46.0), PackedStringArray([
				"res://resources/items/health_potion.tres", "res://resources/items/light_tactical_armor.tres"])],
	}
	for id in crate_items:
		var crate := SupplyCrate.new()
		crate.name = String(id).capitalize().replace(" ", "")
		crate.crate_id = id
		crate.loot_paths = crate_items[id][1]
		crate.position = crate_items[id][0]
		add_child(crate)
		crates.append(crate)
		_static_box(String(id) + "Body", crate.position + Vector3(0.0, 0.4, 0.0), Vector3(1.1, 0.8, 0.85))

	gate = WorldGate.new()
	gate.name = "Gate"
	gate.position = Vector3(0.0, 0.0, BEACH_NEAR_Z)
	add_child(gate)

	terminal = Interactable.new()
	terminal.name = "CommandTerminal"
	terminal.interaction_id = &"command_terminal"
	terminal.prompt_text = "Use command terminal"
	terminal.locked_text = "Terminal locked: keycard required"
	terminal.locked = true
	terminal.one_shot = true
	terminal.interact_radius = 2.6
	terminal.position = TERMINAL_SPOT + Vector3(0.0, 0.8, 0.2)
	add_child(terminal)
	_terminal_screen_locked = StandardMaterial3D.new()
	_terminal_screen_locked.albedo_color = Color(0.9, 0.55, 0.1)
	_terminal_screen_locked.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_terminal_screen_open = StandardMaterial3D.new()
	_terminal_screen_open.albedo_color = Color(0.3, 1.0, 0.5)
	_terminal_screen_open.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_terminal_screen = MeshInstance3D.new()
	var screen_mesh := BoxMesh.new()
	screen_mesh.size = Vector3(1.1, 0.6, 0.05)
	_terminal_screen.mesh = screen_mesh
	_terminal_screen.position = TERMINAL_SPOT + Vector3(0.0, 1.4, -0.55)
	_terminal_screen.material_override = _terminal_screen_locked
	_terminal_screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_terminal_screen)


func _build_trigger() -> void:
	trigger = Area3D.new()
	trigger.name = "ArenaTrigger"
	trigger.collision_layer = 0
	trigger.collision_mask = 2  # the player
	trigger.position = Vector3(0.0, 2.0, 22.0)  # the courtyard just inside the gate
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(26.0, 6.0, 12.0)
	shape.shape = box
	trigger.add_child(shape)
	add_child(trigger)
	trigger.body_entered.connect(_on_trigger_entered)


func _build_caption() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 48
	add_child(layer)
	_caption = Label.new()
	_caption.add_theme_font_size_override("font_size", 22)
	_caption.add_theme_color_override("font_outline_color", Color.BLACK)
	_caption.add_theme_constant_override("outline_size", 6)
	_caption.add_theme_color_override("font_color", Color(0.85, 1.0, 0.85))
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.custom_minimum_size = Vector2(720.0, 0.0)
	_caption.visible = false
	layer.add_child(_caption)


# --- wiring ------------------------------------------------------------------

func _state() -> Node:
	return get_node_or_null("/root/WorldState")


func _wire_signals() -> void:
	var state := _state()
	if state:
		state.flag_changed.connect(_on_flag_changed)
		state.interacted.connect(_on_interacted)
	if _waves and _waves.has_signal("all_cleared"):
		_waves.connect("all_cleared", _on_arena_cleared)


func _attach_interactor() -> void:
	var player := get_tree().get_first_node_in_group("player") as Player
	if player and player.get_node_or_null("Interactor") == null:
		var interactor := Interactor.new()
		interactor.name = "Interactor"
		player.add_child(interactor)


## Re-apply every visual from the saved flags (scene reload, loaded game).
func _refresh_from_state() -> void:
	var state := _state()
	if state == null:
		return
	for item in switches:
		item.sync_from_state()
	_update_power()
	_update_terminal()
	if state.has_flag(&"arena_cleared") and not state.has_flag(&"has_keycard"):
		_drop_keycard()


func _on_flag_changed(id: StringName, _value: bool) -> void:
	if id in SWITCH_IDS or id == &"*":
		_update_power()
	if id == &"has_keycard" or id == &"*":
		_update_terminal()


func _update_power() -> void:
	var state := _state()
	if state == null:
		return
	var thrown := 0
	for id in SWITCH_IDS:
		if state.has_flag(id):
			thrown += 1
	if thrown == SWITCH_IDS.size() and not state.has_flag(&"power_on"):
		state.set_flag(&"power_on", true)  # the gate listens for this and opens


func _update_terminal() -> void:
	var state := _state()
	var unlocked: bool = state != null and state.has_flag(&"has_keycard")
	terminal.locked = not unlocked
	_terminal_screen.material_override = _terminal_screen_open if unlocked else _terminal_screen_locked
	if state and state.has_flag(&"command_terminal_used"):
		terminal.mark_used(true)


func _on_interacted(id: StringName) -> void:
	var state := _state()
	match id:
		&"radio":
			if state:
				state.set_flag(&"radio_heard", true)
			_play_radio()
		&"gate_locked":
			caption("The gate is locked down. Restore the power first.")
		&"command_terminal":
			if state:
				state.set_flag(&"command_terminal_used", true)
		&"switch_1", &"switch_2", &"switch_3":
			if state:
				var thrown := 0
				for sid in SWITCH_IDS:
					if state.has_flag(sid):
						thrown += 1
				if thrown < SWITCH_IDS.size():
					caption("Breaker %d of %d thrown." % [thrown, SWITCH_IDS.size()], 2.5)
				else:
					caption("Power restored. The courtyard gate is unlocking.", 4.0)
		&"gate":
			pass


func _play_radio() -> void:
	var state := _state()
	if state and state.has_flag(&"story_captions"):
		return  # the story layer shows its own captions for the radio
	var text := ""
	for line in RADIO_LINES:
		text += line + "\n"
	caption(text.strip_edges(), CAPTION_SECONDS + 3.0)


## Small self-contained caption (bottom-center area). Skipped when the story layer owns captions.
func caption(text: String, seconds: float = CAPTION_SECONDS) -> void:
	var state := _state()
	if state and state.has_flag(&"story_captions") and text != "":
		return
	_caption.text = text
	_caption.visible = true
	_caption.reset_size()
	var size := get_viewport().get_visible_rect().size
	_caption.position = Vector2((size.x - _caption.size.x) * 0.5, size.y * 0.18)
	_caption.modulate.a = 1.0
	if _caption_tween:
		_caption_tween.kill()
	_caption_tween = create_tween()
	_caption_tween.tween_interval(seconds)
	_caption_tween.tween_property(_caption, "modulate:a", 0.0, 0.6)
	_caption_tween.tween_callback(func() -> void: _caption.visible = false)


func _on_trigger_entered(body: Node3D) -> void:
	if not (body is Player):
		return
	var state := _state()
	if state:
		state.emit_area_entered(&"courtyard")
	if courtyard_started:
		return
	courtyard_started = true
	if state and state.has_flag(&"arena_cleared"):
		return  # the arena was already won; do not run the waves again
	if _waves and _waves.has_method("has_started") and not _waves.has_started():
		_waves.call("start")


func _on_arena_cleared() -> void:
	var state := _state()
	if state:
		state.set_flag(&"arena_cleared", true)
	_drop_keycard()


func _drop_keycard() -> void:
	if get_tree().get_nodes_in_group("keycard").size() > 0:
		return
	var card := Keycard.spawn(self, Vector3(0.0, 0.5, 0.0))
	if card:
		card.add_to_group("keycard")
	caption("The Warden is down. Take his keycard to the command terminal.", 5.0)
