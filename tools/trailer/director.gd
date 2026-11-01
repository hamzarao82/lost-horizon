extends SceneTree
## Trailer director. Plays the real game with a bot that only uses public input actions
## (like the touch controls do) and records it with Godot's movie writer:
##
##   godot --path . --write-movie raw.avi --fixed-fps 30 --resolution 1280x720 \
##         -s tools/trailer/director.gd -- --shots=<absolute dir for screenshots>
##
## It never touches the player's real save or teleport state: SaveManager runs in test mode and the
## teleport ability writes to a throw-away file that is deleted at the end.
## See tools/trailer/README.md and docs/TRAILER.md.

const MAIN_SCENE: String = "res://scenes/main/Main.tscn"
const ITEM_DIR: String = "res://resources/items/"
const TICK: float = 1.0 / 60.0
const TELEPORT_TEMP: String = "user://trailer_teleport.cfg"
const COMBO: Array[String] = ["attack_light", "attack_light", "attack_light", "attack_heavy"]
const COMBO_GAP: Array[float] = [0.30, 0.30, 0.42, 1.0]

var main: Node3D
var player: Player
var cam: CameraController
var cam_node: Camera3D
var waves: WaveManager
var world: Node

var _shots_dir: String = ""
var _taken: Dictionary = {}
var _releases: Dictionary = {}  # action -> physics ticks left
var _atk_cd: float = 0.0
var _combo: int = 0
var _dodge_cd: float = 0.0
var _spin_cd: float = 0.0
var _heal_cd: float = 0.0
var _hit_shot_armed: bool = false
var _hit_shot_due: float = -1.0
var _loot_shot_due: float = -1.0
var _clock: float = 0.0

var _ui: CanvasLayer
var _fade: ColorRect
var _caption: Label
var _title: Label
var _subtitle: Label
var _caption_tween: Tween


func _initialize() -> void:
	_run.call_deferred()


# --- setup -----------------------------------------------------------------

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			_shots_dir = arg.substr(8)
	if _shots_dir == "":
		_shots_dir = ProjectSettings.globalize_path("user://trailer_shots")
	DirAccess.make_dir_recursive_absolute(_shots_dir)

	Player.require_mouse_capture = false
	var save_manager := root.get_node_or_null("SaveManager")
	if save_manager:
		save_manager.set("test_mode", true)  # never write the real save slot
	var quests := root.get_node_or_null("QuestManager")
	if quests:
		quests.set("intro_done", true)  # skip the opening: the trailer cuts it itself
	_build_overlay()
	node_added.connect(_on_node_added)

	main = (load(MAIN_SCENE) as PackedScene).instantiate() as Node3D
	root.add_child(main)
	await _frames(8)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player = main.get_node("Player") as Player
	cam = player.get_node("CameraPivot") as CameraController
	cam_node = player.get_node("CameraPivot/SpringArm3D/Camera3D") as Camera3D
	waves = main.get_node("WaveManager") as WaveManager
	world = main.get_node_or_null("World")
	var perf := main.get_node_or_null("PerfOverlay") as CanvasLayer
	if perf:
		perf.visible = false
	var ability := player.get_node_or_null("TeleportAbility")
	if ability:
		ability.set("save_path", TELEPORT_TEMP)  # keep the user's real teleport charges untouched
		ability.set("charges", 2)
		ability.set("ready_at", 0.0)
		ability.call("_refresh_ui")

	# Starting kit so the HUD shows armor, a weapon multiplier and medkits.
	player.inventory.add_item(_item("military_machete"))
	player.inventory.add_item(_item("reinforced_armor"))
	player.inventory.add_item(_item("health_potion"))
	player.inventory.add_item(_item("health_potion"))
	await _frames(2)

	await _act_beach()
	await _act_switches()
	await _act_gate()
	await _act_fight()
	await _act_boss()
	await _act_title()
	_cleanup()
	quit()


func _item(id: String) -> ItemData:
	return load(ITEM_DIR + id + ".tres") as ItemData


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _build_overlay() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 95
	root.add_child(_ui)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_fade)
	_caption = _label(46, 8)
	_caption.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_caption.position = Vector2(0, 70)
	_caption.size = Vector2(1280, 60)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.modulate.a = 0.0
	_title = _label(84, 14)
	_title.text = "LOST HORIZON: BLACK SITE"
	_title.size = Vector2(1280, 120)
	_title.position = Vector2(0, 250)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_color_override("font_color", Color(0.98, 0.84, 0.35))
	_title.modulate.a = 0.0
	_subtitle = _label(30, 6)
	_subtitle.text = "Wake up.  Survive.  Escape."
	_subtitle.size = Vector2(1280, 50)
	_subtitle.position = Vector2(0, 380)
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.modulate.a = 0.0


func _label(font_size: int, outline: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", outline)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(label)
	return label


func _say(text: String, seconds: float = 2.2) -> void:
	_caption.text = text
	if _caption_tween:
		_caption_tween.kill()
	_caption.modulate.a = 0.0
	_caption_tween = create_tween()
	_caption_tween.tween_property(_caption, "modulate:a", 1.0, 0.25)
	_caption_tween.tween_interval(maxf(seconds - 0.65, 0.1))
	_caption_tween.tween_property(_caption, "modulate:a", 0.0, 0.4)


func _fade_to(alpha: float, seconds: float) -> void:
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", alpha, seconds)
	await tween.finished


# --- screenshots -----------------------------------------------------------

func _shot(shot_name: String) -> void:
	if _taken.has(shot_name):
		return
	_taken[shot_name] = true
	await RenderingServer.frame_post_draw
	var image := root.get_viewport().get_texture().get_image()
	var path := _shots_dir.path_join(shot_name + ".png")
	image.save_png(path)
	print("TRAILER shot ", path)


func _on_node_added(node: Node) -> void:
	if node is Enemy:
		(node as Enemy).damaged.connect(_on_enemy_damaged)


func _on_enemy_damaged(_amount: float, _position: Vector3, _was_kill: bool) -> void:
	if _hit_shot_armed and _hit_shot_due < 0.0 and not _taken.has("combo_sparks"):
		_hit_shot_due = _clock + 0.12  # let the sparks and the damage number appear


func _on_item_collected(_item_data: ItemData, kept: bool) -> void:
	if kept and not _taken.has("loot_sword"):
		_loot_shot_due = _clock + 0.5


# --- bot -------------------------------------------------------------------

func _axis(action: String, value: float) -> void:
	if value > 0.01:
		Input.action_press(action, value)
	else:
		Input.action_release(action)


func _set_move(world_dir: Vector3, sprint: bool) -> void:
	var local := Basis(Vector3.UP, cam.global_rotation.y).inverse() * world_dir
	_axis("move_right", maxf(local.x, 0.0))
	_axis("move_left", maxf(-local.x, 0.0))
	_axis("move_backward", maxf(local.z, 0.0))
	_axis("move_forward", maxf(-local.z, 0.0))
	_axis("sprint", 1.0 if sprint else 0.0)


func _stop() -> void:
	_set_move(Vector3.ZERO, false)


func _pulse(action: String, ticks: int = 4) -> void:
	Input.action_press(action)
	_releases[action] = ticks


func _tick_releases() -> void:
	for action in _releases.keys():
		_releases[action] -= 1
		if _releases[action] <= 0:
			Input.action_release(action)
			_releases.erase(action)


func _look_at_yaw(point: Vector3, rate: float = 1.0) -> void:
	var to := point - player.global_position
	to.y = 0.0
	if to.length_squared() < 0.01:
		return
	cam.rotation.y = lerp_angle(cam.rotation.y, atan2(-to.x, -to.z), rate)


func _steer_to(point: Vector3, stop_dist: float, sprint: bool) -> float:
	var to := point - player.global_position
	to.y = 0.0
	var dist := to.length()
	if dist <= stop_dist:
		_stop()
		return dist
	_set_move(to.normalized(), sprint)
	_look_at_yaw(point, 0.07)
	return dist


func _nearest_enemy() -> Enemy:
	var best: Enemy = null
	var best_dist := INF
	for node in get_nodes_in_group("enemies"):
		var enemy := node as Enemy
		if enemy == null or enemy.is_dead():
			continue
		var dist := player.global_position.distance_to(enemy.global_position)
		if dist < best_dist:
			best_dist = dist
			best = enemy
	return best


func _enemies_within(radius: float) -> int:
	var count := 0
	for node in get_nodes_in_group("enemies"):
		var enemy := node as Enemy
		if enemy and not enemy.is_dead() and player.global_position.distance_to(enemy.global_position) <= radius:
			count += 1
	return count


func _nearest_pickup() -> Pickup:
	var best: Pickup = null
	var best_dist := 14.0
	for child in main.get_children():
		var pickup := child as Pickup
		if pickup == null or pickup.is_queued_for_deletion():
			continue
		var dist := player.global_position.distance_to(pickup.global_position)
		if dist < best_dist:
			best_dist = dist
			best = pickup
	return best


func _keep_alive() -> void:
	var health := player.health
	if health.health < 52.0 and player.inventory.potions > 0 and _heal_cd <= 0.0:
		_pulse("use_item")
		_heal_cd = 3.0
	elif health.health < 24.0:
		health.heal(40.0)  # trailer safety net: the bot must never die


func _bot_step(use_spin: bool) -> void:
	_tick_releases()
	_clock += TICK
	_atk_cd -= TICK
	_dodge_cd -= TICK
	_spin_cd -= TICK
	_heal_cd -= TICK
	_keep_alive()
	if _hit_shot_due > 0.0 and _clock >= _hit_shot_due:
		_hit_shot_due = -1.0
		_shot("combo_sparks")
	if _loot_shot_due > 0.0 and _clock >= _loot_shot_due:
		_loot_shot_due = -1.0
		_shot("loot_sword")

	var target := _nearest_enemy()
	var pickup := _nearest_pickup()
	if target == null:
		if pickup:
			_steer_to(pickup.global_position, 0.3, true)
		else:
			_stop()
		return
	var to := target.global_position - player.global_position
	to.y = 0.0
	var dist := to.length()
	if not cam.has_lock_target():
		_look_at_yaw(target.global_position, 0.06)
	var swing_frames := float(target.get("_attack_frames"))
	if _dodge_cd <= 0.0 and dist < 3.4 and target.state == Enemy.State.ATTACK and swing_frames > 12.0 \
			and player.state != Player.State.DODGE:
		_set_move(-to.normalized(), false)
		_pulse("dodge")
		_dodge_cd = 2.2
	elif pickup != null and dist > 4.5:
		_steer_to(pickup.global_position, 0.3, true)
	elif dist > 1.9:
		_steer_to(target.global_position, 1.9, dist > 6.0)
	else:
		_stop()
	if dist <= 2.4 and _atk_cd <= 0.0 and (player.state == Player.State.FREE or player.state == Player.State.ATTACK):
		_pulse(COMBO[_combo % COMBO.size()])
		_atk_cd = COMBO_GAP[_combo % COMBO.size()]
		_combo += 1
	if use_spin and _spin_cd <= 0.0 and player.special_cooldown_left <= 0.0 and _enemies_within(3.6) >= 2:
		_pulse("special")
		_spin_cd = 7.0


func _fight_for(seconds: float, use_spin: bool = true) -> void:
	var elapsed := 0.0
	while elapsed < seconds:
		await physics_frame
		elapsed += TICK
		_bot_step(use_spin)
	_stop()


# --- acts ------------------------------------------------------------------

func _teleport_player(pos: Vector3, face: Vector3) -> void:
	player.global_position = pos
	player.velocity = Vector3.ZERO
	_look_at_yaw(face, 1.0)


func _act_beach() -> void:
	_teleport_player(Vector3(0, 0.1, 64), Vector3(-7, 0, 60))
	await _frames(4)
	_fade_to(0.0, 1.0)
	_say("WAKE UP. SURVIVE.", 2.6)
	await _wait(0.8)
	var radio_pos := Vector3(-7, 0, 60.4)
	if world and world.get("radio") != null:
		radio_pos = (world.get("radio") as Node3D).global_position
	var guard := 0.0
	while guard < 4.0 and _steer_to(radio_pos, 1.7, false) > 1.7:
		await physics_frame
		guard += TICK
	_stop()
	_look_at_yaw(radio_pos, 1.0)
	await _wait(0.3)
	_pulse("interact", 6)
	await _wait(1.2)
	await _shot("beach_radio")
	await _wait(1.0)


func _act_switches() -> void:
	_say("RESTORE THE POWER", 2.4)
	var spots := {
		"switch_1": Vector3(-17.5, 0.0, 41.5),
		"switch_2": Vector3(34.5, 0.0, 49.0),
		"switch_3": Vector3(-30.5, 0.0, 57.0),
	}
	for id in spots:
		var spot: Vector3 = spots[id]
		await _fade_to(1.0, 0.18)
		_teleport_player(spot + Vector3(1.1, 0.1, 1.3), spot)
		await _frames(3)
		_fade_to(0.0, 0.18)
		await _wait(0.35)
		_pulse("interact", 6)
		await _wait(0.9)


func _act_gate() -> void:
	_say("THE GATE OPENS", 2.4)
	await _fade_to(1.0, 0.18)
	_teleport_player(Vector3(0, 0.1, 44), Vector3(0, 0, 30))
	cam.rotation.y = 0.0
	await _frames(3)
	_fade_to(0.0, 0.18)
	var guard := 0.0
	while guard < 3.0 and not (world and world.get("gate") != null and (world.get("gate") as Node).get("is_open") == true):
		await physics_frame
		guard += TICK
	await _wait(0.6)
	await _shot("gate_open")
	# Walk through the gate into the courtyard; the courtyard trigger starts the waves.
	guard = 0.0
	while guard < 5.0 and _steer_to(Vector3(0, 0, 14), 1.0, true) > 1.0:
		await physics_frame
		guard += TICK
	_stop()


func _act_fight() -> void:
	_say("FIGHT", 1.8)
	player.inventory.item_collected.connect(_on_item_collected)
	_hit_shot_armed = true
	var elapsed := 0.0
	var claymore_spawned := false
	var lock_pressed := false
	var lock_shot := false
	var teleport_pressed := false
	var hud_shot := false
	while elapsed < 17.0:
		await physics_frame
		elapsed += TICK
		_bot_step(true)
		if elapsed > 3.5 and not claymore_spawned:
			claymore_spawned = true
			_say("LOOT", 1.8)
			Pickup.spawn(main, _item("claymore"), player.global_position + Vector3(2.5, 0.0, -2.5))
		if elapsed > 6.0 and not lock_pressed and _nearest_enemy() != null:
			lock_pressed = true
			_say("LOCK ON", 1.8)
			_pulse("lock_on")
		if lock_pressed and not lock_shot and cam.has_lock_target() and elapsed > 7.2:
			lock_shot = true
			_shot("lock_on")
		if elapsed > 10.0 and not teleport_pressed:
			teleport_pressed = true
			_say("TELEPORT", 1.8)
			_pulse("teleport")
		if teleport_pressed and not hud_shot and elapsed > 11.8:
			hud_shot = true
			_shot("hud_armor_teleport")
		if elapsed > 13.0 and cam.has_lock_target():
			_pulse("lock_on")
	_stop()


func _act_boss() -> void:
	_say("THE WARDEN", 2.4)
	_pulse("lock_on", 1)
	_hit_shot_armed = false
	for node in get_nodes_in_group("enemies"):
		node.queue_free()
	waves.start_delay = 0.3
	waves.start_wave_at(5)
	var boss: Enemy = null
	var guard := 0.0
	while boss == null and guard < 5.0:
		await physics_frame
		guard += TICK
		var found := get_first_node_in_group("boss")
		if found is Enemy:
			boss = found as Enemy
	if boss == null:
		return
	boss.set("_attack_count", 2)  # the first slam brings the shockwave, so it is on camera
	# Cinematic orbit around the boss; the player is already in the arena.
	var cine := Camera3D.new()
	cine.fov = 55.0
	root.add_child(cine)
	cine.current = true
	var center := boss.global_position + Vector3(0, 1.5, 0)
	var t := 0.0
	while t < 2.6:
		await physics_frame
		t += TICK
		if not is_instance_valid(boss):
			break
		center = boss.global_position + Vector3(0, 1.6, 0)
		var angle := 0.5 + t * 0.7
		cine.global_position = center + Vector3(sin(angle) * 6.5, 0.4 + t * 0.35, cos(angle) * 6.5)
		cine.look_at(center, Vector3.UP)
		_keep_alive()
		if t > 1.2:
			await _shot("boss_intro")
	cam_node.current = true
	cine.queue_free()
	var elapsed := 0.0
	var shot_done := false
	while elapsed < 8.5:
		await physics_frame
		elapsed += TICK
		_bot_step(true)
		if elapsed > 4.0 and not shot_done:
			shot_done = true
			_shot("boss_fight")
	_stop()


func _act_title() -> void:
	await _fade_to(1.0, 0.8)
	var tween := create_tween()
	tween.tween_property(_title, "modulate:a", 1.0, 0.7)
	tween.parallel().tween_property(_subtitle, "modulate:a", 1.0, 1.0)
	await tween.finished
	await _shot("title")
	await _wait(2.4)


func _cleanup() -> void:
	for action in ["move_forward", "move_backward", "move_left", "move_right", "sprint", "attack_light", "attack_heavy", "dodge", "special", "lock_on", "teleport", "use_item", "interact"]:
		Input.action_release(action)
	var save_manager := root.get_node_or_null("SaveManager")
	if save_manager and save_manager.has_method("delete_save"):
		save_manager.call("delete_save")
	if FileAccess.file_exists(TELEPORT_TEMP):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TELEPORT_TEMP))
