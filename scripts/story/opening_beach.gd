class_name OpeningBeach
extends CanvasLayer
## The shipwreck, the treasure-retrieval glimpse, and the injured recovery that follows the opening
## cinematic. Same pause/skip pattern as `StoryIntro`. After this finishes, the real player (already
## spawned by Boot/Main) is left in an injured state until `opening_survival`'s three pickups are found,
## at which point `_lift_restrictions` removes them. See docs/OPENING_BEACH.md for what is simplified here
## and why (no blur shader, no NPC AI, no skeletal "lying down" pose — a capsule stand-in and fades).

signal finished

const SKIP_GRACE_SECONDS: float = 0.4
const WAKE_FADE_SECONDS: float = 6.0
const EVENT_HOLD_SECONDS: float = 10.0
const NPC_LEAVE_SECONDS: float = 4.0
const RECOVERY_SECONDS: float = 3.0
const INJURED_HEALTH_FRACTION: float = 0.35
const INJURED_SPEED_MULT: float = 0.55
const FAILSAFE_SECONDS: float = 120.0
const NUDGE_SECONDS: float = 60.0

const SUPPLIES_ID: StringName = &"health_potion"
const JACKET_ID: StringName = &"salvaged_jacket"
const STICK_ID: StringName = &"wooden_stick"
const SURVIVAL_QUEST: StringName = &"opening_survival"

var _age: float = 0.0
var _done: bool = false
var _was_paused: bool = false
var _headless: bool = false
var _skip_requested: bool = false
var _skip_button: Button
var _black: ColorRect
var _caption: Label
var _player: Player
var _world_flags: Node
var _quest_manager: Node
var _viewport: SubViewport
var _bag: Node3D
var _guard: Node3D
var _workers: Array[Node3D] = []
var _event_clock: float = 0.0
var _npc_leaving: bool = false


static func play(tree: SceneTree, player: Player) -> OpeningBeach:
	var node := OpeningBeach.new()
	node._player = player
	tree.root.add_child(node)
	return node


func _init() -> void:
	_headless = DisplayServer.get_name() == "headless"


func _ready() -> void:
	layer = 150
	process_mode = Node.PROCESS_MODE_ALWAYS
	_was_paused = get_tree().paused
	get_tree().paused = true
	_world_flags = get_node_or_null("/root/WorldState")
	_quest_manager = get_node_or_null("/root/QuestManager")
	_build_ui()
	if not _headless:
		_build_scene()
	_run.call_deferred()


func _exit_tree() -> void:
	if get_tree() != null and not _done:
		get_tree().paused = _was_paused


func _process(delta: float) -> void:
	_age += delta
	if not _headless and is_instance_valid(_viewport):
		_step_scene(delta)


func _input(event: InputEvent) -> void:
	if _done or _age < SKIP_GRACE_SECONDS:
		return
	var pressed := false
	if event is InputEventKey:
		pressed = event.pressed and not event.echo
	elif event is InputEventMouseButton or event is InputEventScreenTouch or event is InputEventJoypadButton:
		pressed = event.pressed
	if pressed:
		get_viewport().set_input_as_handled()
		skip()


func skip() -> void:
	_skip_requested = true


# --- sequence ----------------------------------------------------------------

func _run() -> void:
	await _fade(_black, 0.0, WAKE_FADE_SECONDS)
	await _hold(EVENT_HOLD_SECONDS)  # the guard and the workers take the bag (visual only on a real run)
	if not _skip_requested:
		_npc_leaving = true
		await _hold(NPC_LEAVE_SECONDS)
	await _fade(_black, 1.0, 0.6)
	_caption.text = "Get up."
	await _fade(_caption, 1.0, 0.5)
	await _hold(RECOVERY_SECONDS)
	await _fade(_caption, 0.0, 0.5)
	await _fade(_black, 0.0, 0.8)
	_hand_off()
	_finish()


func _hold(seconds: float) -> void:
	if _done:
		return
	var waited := 0.0
	while waited < seconds and not _done:
		if _skip_requested:
			return
		await get_tree().create_timer(0.05, true, false, true).timeout
		waited += 0.05


func _fade(item: CanvasItem, alpha: float, seconds: float) -> void:
	if _done:
		return
	var tween := create_tween()
	tween.tween_property(item, "modulate:a", alpha, seconds)
	await tween.finished


func _finish() -> void:
	if _done:
		return
	_done = true
	get_tree().paused = _was_paused
	finished.emit()
	queue_free()


# --- handoff: the real player, injured, with the survival quest pinned -------

func _hand_off() -> void:
	if not is_instance_valid(_player):
		_player = Engine.get_main_loop().root.get_tree().get_first_node_in_group("player") as Player
	if not is_instance_valid(_player):
		return
	_player.health.health = _player.health.max_health * INJURED_HEALTH_FRACTION
	_player.injured_speed_mult = INJURED_SPEED_MULT
	_player.attacks_locked = true
	if _world_flags != null and _world_flags.has_method("set_flag"):
		_world_flags.set_flag(&"opening_event_seen", true)
	_start_survival_quest()


func _start_survival_quest() -> void:
	if _quest_manager == null:
		return
	if _quest_manager.has_method("start_quest"):
		_quest_manager.start_quest(SURVIVAL_QUEST, true)
	_quest_manager.tracker_first = SURVIVAL_QUEST
	if _quest_manager.has_signal("quest_completed"):
		_quest_manager.quest_completed.connect(_on_quest_completed)
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		_watch_nudge(tree)
		_watch_failsafe(tree)


func _on_quest_completed(quest_id: StringName) -> void:
	if quest_id != SURVIVAL_QUEST:
		return
	_lift_restrictions()
	if _quest_manager != null and _quest_manager.tracker_first == SURVIVAL_QUEST:
		_quest_manager.tracker_first = &""


func _lift_restrictions() -> void:
	if not is_instance_valid(_player):
		return
	var tween := _player.create_tween()
	tween.tween_method(_apply_speed_lift, 0.0, 1.0, 3.0)
	_player.attacks_locked = false


func _apply_speed_lift(t: float) -> void:
	if is_instance_valid(_player):
		_player.injured_speed_mult = lerp(INJURED_SPEED_MULT, 1.0, t)


## A caption pointing at the still-missing stick after a minute, and an automatic grant after two, so
## nobody can be stuck unarmed if a pickup is missed or unreachable.
func _watch_nudge(tree: SceneTree) -> void:
	await tree.create_timer(NUDGE_SECONDS, true, false, true).timeout
	if _quest_manager == null or not _quest_manager.is_active(SURVIVAL_QUEST):
		return
	if not _has_item(STICK_ID):
		var huds := tree.root.find_children("*", "Hud", true, false)
		if not huds.is_empty() and huds[0].has_method("show_caption"):
			huds[0].show_caption("There has to be something on this beach you can defend yourself with.", 4.0)


func _watch_failsafe(tree: SceneTree) -> void:
	await tree.create_timer(FAILSAFE_SECONDS, true, false, true).timeout
	if _quest_manager == null or not is_instance_valid(_player):
		return
	if not _has_item(STICK_ID):
		var stick := load("res://resources/items/wooden_stick.tres") as ItemData
		_player.inventory.collect(stick)
		_player.inventory.equip(stick)


func _has_item(item_id: StringName) -> bool:
	if not is_instance_valid(_player) or _player.inventory == null:
		return false
	return _player.inventory.count_of(String(item_id)) > 0 or _player.inventory.weapon == load("res://resources/items/%s.tres" % String(item_id))


# --- UI ------------------------------------------------------------------

func _build_ui() -> void:
	_black = ColorRect.new()
	_black.color = Color.BLACK
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_black)

	_caption = Label.new()
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_caption.set_anchors_preset(Control.PRESET_FULL_RECT)
	_caption.add_theme_font_size_override("font_size", 30)
	_caption.add_theme_color_override("font_outline_color", Color.BLACK)
	_caption.add_theme_constant_override("outline_size", 6)
	_caption.modulate.a = 0.0
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_caption)

	_skip_button = Button.new()
	_skip_button.text = "Skip"
	_skip_button.custom_minimum_size = Vector2(120.0, 48.0)
	_skip_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 16)
	_skip_button.pressed.connect(skip)
	add_child(_skip_button)


# --- the wake/treasure mini-scene (skipped entirely on headless) ------------

func _build_scene() -> void:
	var container := SubViewportContainer.new()
	container.stretch = true
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)
	container.move_to_front()
	_black.move_to_front()
	_caption.move_to_front()
	_skip_button.move_to_front()

	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.size = get_viewport().get_visible_rect().size if get_viewport() else Vector2i(1280, 720)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.62, 0.68)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.68, 0.6)
	env.ambient_light_energy = 0.9
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_viewport.add_child(world_env)
	container.add_child(_viewport)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -20.0, 0.0)
	sun.light_energy = 1.0
	_viewport.add_child(sun)

	var sand := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30.0, 30.0)
	sand.mesh = plane
	var sand_mat := StandardMaterial3D.new()
	sand_mat.albedo_color = Color(0.78, 0.68, 0.5)
	sand.material_override = sand_mat
	_viewport.add_child(sand)

	for i in 3:
		var wreck := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(1.2 - i * 0.2, 0.3, 0.4)
		wreck.mesh = box
		var wreck_mat := StandardMaterial3D.new()
		wreck_mat.albedo_color = Color(0.6, 0.55, 0.45)
		wreck.material_override = wreck_mat
		wreck.position = Vector3(-2.0 + i * 1.3, 0.15, -3.0 + i * 0.4)
		wreck.rotation_degrees.y = i * 35.0
		_viewport.add_child(wreck)

	var palm := Node3D.new()
	var trunk := MeshInstance3D.new()
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.1
	trunk_mesh.bottom_radius = 0.14
	trunk_mesh.height = 3.0
	trunk.mesh = trunk_mesh
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.4, 0.3, 0.2)
	trunk.material_override = trunk_mat
	trunk.position.y = 1.5
	palm.add_child(trunk)
	var fronds := MeshInstance3D.new()
	var frond_mesh := SphereMesh.new()
	frond_mesh.radius = 0.8
	frond_mesh.height = 0.6
	fronds.mesh = frond_mesh
	var frond_mat := StandardMaterial3D.new()
	frond_mat.albedo_color = Color(0.25, 0.55, 0.25)
	fronds.material_override = frond_mat
	fronds.position.y = 3.1
	palm.add_child(fronds)
	palm.position = Vector3(3.0, 0.0, -4.0)
	_viewport.add_child(palm)

	_bag = _build_bag()
	_bag.position = Vector3(3.0, 2.6, -4.0)
	_viewport.add_child(_bag)

	var lying := _build_capsule(Color(0.25, 0.27, 0.3))
	lying.rotation_degrees.x = -90.0
	lying.position = Vector3(0.0, 0.25, 1.5)
	_viewport.add_child(lying)

	_guard = _build_capsule(Color(0.2, 0.18, 0.15))
	_guard.position = Vector3(-8.0, 0.55, -4.0)
	_viewport.add_child(_guard)
	for i in 2:
		var worker := _build_capsule(Color(0.45, 0.4, 0.35))
		worker.position = Vector3(-9.0, 0.55, -4.0 + (i - 0.5) * 1.2)
		_viewport.add_child(worker)
		_workers.append(worker)

	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 0.8, 4.5)
	_viewport.add_child(cam)  # look_at() needs the node in the tree first (it reads global_transform)
	cam.look_at(Vector3(1.5, 1.0, -3.0), Vector3.UP)
	cam.current = true


func _build_capsule(tint: Color) -> Node3D:
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.22
	capsule.height = 1.1
	body.mesh = capsule
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	body.material_override = mat
	body.position.y = 0.55
	root.add_child(body)
	return root


func _build_bag() -> Node3D:
	var root := Node3D.new()
	var sack := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.2
	sphere.height = 0.32
	sack.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.3, 0.18)
	sack.material_override = mat
	root.add_child(sack)
	return root


func _step_scene(delta: float) -> void:
	_event_clock += delta
	var approach: float = clampf(_event_clock / EVENT_HOLD_SECONDS, 0.0, 1.0)
	if is_instance_valid(_guard):
		_guard.position.x = lerp(-8.0, -1.5, approach)
	for i in _workers.size():
		var worker := _workers[i]
		if is_instance_valid(worker):
			worker.position.x = lerp(-9.0, -0.5, approach)
	if approach >= 0.95 and is_instance_valid(_bag):
		_bag.position.y = 0.6  # lowered into a worker's hands once they arrive
	if _npc_leaving and is_instance_valid(_guard):
		var leave_t: float = clampf((_event_clock - EVENT_HOLD_SECONDS) / NPC_LEAVE_SECONDS, 0.0, 1.0)
		_guard.position.z = lerp(-4.0, -14.0, leave_t)  # off along the treeline, never toward the camera
		for worker in _workers:
			if is_instance_valid(worker):
				worker.position.z = lerp(-4.0, -14.0, leave_t)
