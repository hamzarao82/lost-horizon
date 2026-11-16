class_name OpeningBeach
extends CanvasLayer
## The shipwreck, the treasure-retrieval glimpse, and the injured recovery that follows the opening
## cinematic. Same pause/skip pattern as `StoryIntro`. After this finishes, the real player (already
## spawned by Boot/Main) is left in an injured state until `opening_survival`'s three pickups are found,
## at which point `_lift_restrictions` removes them. See docs/OPENING_BEACH.md for what is simplified here
## and why (no blur shader, no NPC AI; the mini-scene uses the real rigged models, with a capsule only if a model
## fails to load).

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
## The mini-scene's rigged models (res://assets/characters/).
const PLAYER_MODEL: String = "res://assets/characters/player.glb"
const SOLDIER_MODEL: String = "res://assets/characters/soldier.glb"
## Protagonist timeline on the mini-scene clock: wake, then sit up (2 s), then stand hunched (1.8 s).
const HERO_WAKE_AT: float = 4.0
const HERO_STAND_AT: float = 9.0
const WORKER_SCALE: float = 0.94

const SUPPLIES_ID: StringName = &"health_potion"
const JACKET_ID: StringName = &"salvaged_jacket"
const STICK_ID: StringName = &"wooden_stick"
const SURVIVAL_QUEST: StringName = &"opening_survival"
const PAYMENT_QUEST: StringName = &"recover_payment"

var _age: float = 0.0
var _done: bool = false
var _was_paused: bool = false
var _headless: bool = false
var _skip_requested: bool = false
var _skip_button: Button
var _black: ColorRect
var _caption: Label
var _blur: ColorRect
var _player: Player
var _world_flags: Node
var _quest_manager: Node
var _viewport: SubViewport
var _bag: Node3D
var _guard: Node3D
var _workers: Array[Node3D] = []
var _hero: Node3D
var _hero_visual: SkinnedVisual
var _hero_stage: int = 0
var _guard_visual: SkinnedVisual
var _worker_visuals: Array[SkinnedVisual] = []
var _workers_walking: bool = false
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
	_clear_blur_over(WAKE_FADE_SECONDS + 3.0)  # the "blurred vision clearing" beat: a pale veil that lifts
	await _fade(_black, 0.0, WAKE_FADE_SECONDS)
	await _hold(EVENT_HOLD_SECONDS * 0.6)
	if not _skip_requested:
		_caption.text = "My bag."
		await _fade(_caption, 1.0, 0.4)
		await _hold(1.4)
		await _fade(_caption, 0.0, 0.4)
	await _hold(EVENT_HOLD_SECONDS * 0.4)  # the guard and the workers take the bag (visual only on a real run)
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


func _clear_blur_over(seconds: float) -> void:
	if _blur == null:
		return
	_blur.modulate.a = 0.65
	var tween := create_tween()
	tween.tween_property(_blur, "modulate:a", 0.0, seconds)


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
	_spawn_survival_pickups()


## The three items the survival quest asks for, as real pickups on the ground near the player, so the quest
## can finish through play (the quest listens for ITEM_COLLECTED from the normal pickup path).
func _spawn_survival_pickups() -> void:
	var parent := _player.get_parent()
	if parent == null or not parent.is_inside_tree():
		return
	var origin := _player.global_position
	var offsets := {SUPPLIES_ID: Vector3(2.5, 0.0, -2.0), JACKET_ID: Vector3(-3.0, 0.0, -3.5), STICK_ID: Vector3(0.5, 0.0, -5.0)}
	for id: StringName in offsets:
		var item := load("res://resources/items/%s.tres" % String(id)) as ItemData
		if item == null:
			continue
		var at: Vector3 = origin + offsets[id] + Vector3(0.0, 0.6, 0.0)
		if parent is Node3D:
			at = (parent as Node3D).to_local(at)
		var pickup := Pickup.spawn(parent, item, at)
		if pickup != null:
			pickup.guaranteed = true


func _start_survival_quest() -> void:
	if _quest_manager == null:
		return
	if _quest_manager.has_method("start_quest"):
		_quest_manager.start_quest(SURVIVAL_QUEST, true)
	_quest_manager.tracker_first = SURVIVAL_QUEST
	if _quest_manager.has_method("start_quest") and not _quest_manager.is_completed(PAYMENT_QUEST):
		_quest_manager.start_quest(PAYMENT_QUEST, true)  # listed under the survival quest; completes on `payment_recovered`
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
	_grant_missing_items()


func _grant_missing_items() -> void:
	if _quest_manager == null or not is_instance_valid(_player):
		return
	for id: StringName in [SUPPLIES_ID, JACKET_ID, STICK_ID]:
		if _has_item(id):
			continue
		var item := load("res://resources/items/%s.tres" % String(id)) as ItemData
		if item == null:
			continue
		_player.inventory.collect(item)
		if id != SUPPLIES_ID:
			_player.inventory.equip(item)


func _has_item(item_id: StringName) -> bool:
	if not is_instance_valid(_player) or _player.inventory == null:
		return false
	var item := load("res://resources/items/%s.tres" % String(item_id)) as ItemData
	return _player.inventory.count_of(String(item_id)) > 0 or _player.inventory.weapon == item or _player.inventory.armor == item


# --- UI ------------------------------------------------------------------

func _build_ui() -> void:
	_black = ColorRect.new()
	_black.color = Color.BLACK
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_black)

	_blur = ColorRect.new()
	_blur.color = Color(0.82, 0.84, 0.86)
	_blur.modulate.a = 0.0
	_blur.set_anchors_preset(Control.PRESET_FULL_RECT)
	_blur.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_blur)

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
	_skip_button.anchor_left = 1.0
	_skip_button.anchor_right = 1.0
	_skip_button.anchor_top = 1.0
	_skip_button.anchor_bottom = 1.0
	_skip_button.offset_left = -136.0
	_skip_button.offset_right = -16.0
	_skip_button.offset_top = -64.0
	_skip_button.offset_bottom = -16.0
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
	_blur.move_to_front()
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

	# The real rigged characters. The protagonist is the player model (lying, waking, sitting, standing hunched).
	# The guard is the soldier model. The two workers are soldier models, dulled and a little smaller, limping on the
	# player's limp_walk clip (the soldier file has no limp clip of its own).
	var hero := _spawn_visual(PLAYER_MODEL, true, Color.WHITE, Vector3(0.0, 0.0, 0.6), 0.0)
	_hero = hero[0]
	_hero_visual = hero[1]
	if _hero_visual != null:
		_hero_visual.driver.play_story_clip("lying_idle", 1.0, true)

	var guard := _spawn_visual(SOLDIER_MODEL, false, Color.WHITE, Vector3(-8.0, 0.0, -4.0), -90.0)  # faces +X
	_guard = guard[0]
	_guard_visual = guard[1]
	if _guard_visual != null:
		_guard_visual.driver.set_speed(2.0)
		_guard_visual.driver.play_state(&"loco")

	var limp := _limp_clip()
	for i in 2:
		var worker := _spawn_visual(SOLDIER_MODEL, false, Color(0.62, 0.58, 0.5),
				Vector3(-9.0, 0.0, -4.0 + (i - 0.5) * 1.2), -90.0)
		var worker_node: Node3D = worker[0]
		worker_node.scale = Vector3.ONE * WORKER_SCALE  # a little smaller and worn down next to the guard
		_workers.append(worker_node)
		var visual := worker[1] as SkinnedVisual
		if visual != null:
			_worker_visuals.append(visual)
			if visual.hand_socket != null:
				visual.hand_socket.hold(null)  # workers carry no weapon
			if limp != null:
				visual.driver.add_clip("limp_walk", limp.duplicate())
	_set_workers_walking(true)

	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 0.8, 4.5)
	_viewport.add_child(cam)  # look_at() needs the node in the tree first (it reads global_transform)
	cam.look_at(Vector3(1.5, 1.0, -3.0), Vector3.UP)
	cam.current = true


## Places a SkinnedVisual of a rigged GLB in the mini-scene, under its own holder node. Returns [holder, visual]; the
## visual is null (and the holder carries a capsule) when the model is missing or broken, so the scene still plays.
func _spawn_visual(path: String, player_look: bool, tint: Color, pos: Vector3, yaw_deg: float) -> Array:
	var holder := Node3D.new()
	holder.position = pos
	holder.rotation_degrees.y = yaw_deg
	_viewport.add_child(holder)
	var visual := SkinnedVisual.new()
	visual.model_path = path
	holder.add_child(visual)
	if not visual.load_standalone(player_look):
		holder.remove_child(visual)
		visual.free()
		holder.add_child(_build_capsule(tint if tint != Color.WHITE else Color(0.3, 0.3, 0.32)))
		return [holder, null]
	if tint != Color.WHITE:
		# A private copy per surface: the imported material is shared with the in-game characters and stays as it is.
		for mi in visual.meshes:
			if mi == null or mi.mesh == null:
				continue
			for surface in mi.mesh.get_surface_count():
				var base := mi.get_active_material(surface) as BaseMaterial3D
				if base == null:
					continue
				var copy := base.duplicate() as BaseMaterial3D
				copy.albedo_color = tint
				mi.set_surface_override_material(surface, copy)
	return [holder, visual]


## The player's limp_walk clip, copied for the soldier-model workers (same rig, same bone paths). Null if missing.
func _limp_clip() -> Animation:
	var scene := load(PLAYER_MODEL) as PackedScene
	var inst := scene.instantiate() as Node3D if scene != null else null
	if inst == null:
		return null
	var clip: Animation = null
	var found := inst.find_children("*", "AnimationPlayer", true, false)
	if not found.is_empty():
		var source := found[0] as AnimationPlayer
		if source.has_animation(&"limp_walk"):
			clip = source.get_animation(&"limp_walk").duplicate() as Animation
			clip.loop_mode = Animation.LOOP_LINEAR
	inst.free()
	return clip


## The protagonist's wake, driven by the mini-scene clock: lying -> wake -> sit up -> stand, hunched, a hand to his side.
## Each pose is held (the last frame stays) until the next one starts.
func _step_hero() -> void:
	if _hero_visual == null:
		return
	var clip := ""
	if _hero_stage == 0 and _event_clock >= HERO_WAKE_AT:
		clip = "wake"
	elif _hero_stage == 1 and _event_clock >= HERO_WAKE_AT + 3.0:
		clip = "sit_up"
	elif _hero_stage == 2 and _event_clock >= HERO_STAND_AT:
		clip = "stand_up"
	elif _hero_stage == 3 and _event_clock >= HERO_STAND_AT + 1.8:
		clip = "hold_side"
	if clip == "":
		return
	_hero_stage += 1
	_hero_visual.driver.play_story_clip(clip, 1.0, true)


## Workers limp while they are dragged in and while they leave; they stand still once the guard has arrived.
func _set_workers_walking(walking: bool) -> void:
	if walking == _workers_walking:
		return
	_workers_walking = walking
	for visual in _worker_visuals:
		if not is_instance_valid(visual):
			continue
		if walking:
			visual.driver.play_story_clip("limp_walk", 1.0, true)
		else:
			visual.driver.release_story()
			visual.driver.set_speed(0.0)
			visual.driver.play_state(&"loco")


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
	_step_hero()
	var approach: float = clampf(_event_clock / EVENT_HOLD_SECONDS, 0.0, 1.0)
	var arrived: bool = approach >= 0.95 and not _npc_leaving
	var moving: bool = not arrived
	_set_workers_walking(moving)
	if _guard_visual != null:
		_guard_visual.driver.set_speed(2.0 if moving else 0.0)
		_guard_visual.driver.play_state(&"loco")
	var leave_t: float = clampf((_event_clock - EVENT_HOLD_SECONDS) / NPC_LEAVE_SECONDS, 0.0, 1.0) if _npc_leaving else 0.0
	var turn: float = lerp_angle(deg_to_rad(-90.0), 0.0, clampf(leave_t * 4.0, 0.0, 1.0))  # to face the treeline
	if is_instance_valid(_guard):
		_guard.position.x = lerp(-8.0, -1.5, approach)
		_guard.rotation.y = turn
		if arrived and approach > 0.5:
			_guard.rotation.y = turn + sin(_event_clock * 4.0) * 0.12  # an ordering jab at the workers
	for worker in _workers:
		if is_instance_valid(worker):
			worker.position.x = lerp(-9.0, -0.5, pow(approach, 1.2))  # they drag behind the guard
			worker.rotation.y = turn
	if approach >= 0.95 and is_instance_valid(_bag):
		_bag.position.y = 0.6  # lowered into a worker's hands once they arrive
	if _npc_leaving and is_instance_valid(_guard):
		_guard.position.z = lerp(-4.0, -14.0, leave_t)  # off along the treeline, never toward the camera
		for worker in _workers:
			if is_instance_valid(worker):
				worker.position.z = lerp(-4.0, -14.0, leave_t)
