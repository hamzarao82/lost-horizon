class_name ObjectivePointer
extends CanvasLayer
## A small compass arrow at the edge of the view pointing to where the CURRENT quest objective is,
## with the distance ("Radio 42 m"). Hidden when the objective has no place, or when the target is
## on screen and closer than 6 m. Placement avoids the HUD bands and the touch buttons.

const LABELS: Dictionary = {
	&"area_a_perimeter": "Perimeter", &"area_b_compound": "Compound", &"area_c_research": "Research wing",
	&"area_d_command": "Command", &"radio": "Radio", &"checkpoint_desk": "Checkpoint",
	&"military_terminal": "Terminal", &"security_panel": "Panel", &"log_missing_security": "Missing log",
	&"power_switch_a": "Switch A", &"power_switch_b": "Switch B", &"power_switch_c": "Switch C",
	&"card_reader_c": "Card reader", &"command_terminal": "Terminal",
	&"log_project_black_site": "Black Site file", &"command_terminal_d": "Command terminal",
}
const HIDE_WITHIN: float = 6.0
const REFRESH_SECONDS: float = 0.25
const SIZE: Vector2 = Vector2(84.0, 52.0)
const MIN_RADIUS: float = 140.0

var target: Variant = null        # Vector3 or null
var label: String = ""

var _control: Control
var _refresh: float = 0.0
var _screen_pos: Vector2 = Vector2.ZERO
var _direction: Vector2 = Vector2.UP
var _distance: float = 0.0
var _visible_now: bool = false


func _ready() -> void:
	layer = 49  # under the HUD (50), above the 3D view
	add_to_group("objective_pointer")
	_control = Control.new()
	_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_control.draw.connect(_draw_pointer)
	add_child(_control)


func _process(delta: float) -> void:
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = REFRESH_SECONDS
		_resolve_target()
	_update_screen()


# --- what the pointer points at ----------------------------------------------

## The first unfinished, non-optional objective of the active quest (same rule as the HUD tracker).
func current_objective() -> ObjectiveData:
	var quests := get_node_or_null("/root/QuestManager")
	if quests == null:
		return null
	# Same order as the HUD tracker (pinned bridge quest, then this region's quests), so the arrow and the
	# tracker text always talk about the same mission.
	var order: Array = quests._tracker_order() if quests.has_method("_tracker_order") else quests.active.keys()
	for quest_id in order:
		var quest: QuestData = quests.get_quest(quest_id)
		if quest == null:
			continue
		var state: Dictionary = quests.active[quest_id]
		for index in quest.objectives.size():
			var objective: ObjectiveData = quest.objectives[index]
			if not state["done"][index] and not objective.optional:
				return objective
	return null


func _resolve_target() -> void:
	_resolve_for(current_objective())


## Aims at one objective. Public so a test can ask whether every objective of a region can be found.
func _resolve_for(objective: ObjectiveData) -> void:
	target = null
	label = ""
	if objective == null:
		return
	match objective.type:
		ObjectiveData.Type.ENTER_AREA:
			for area_id in objective.targets:
				# Aim at the real trigger volume when it exists (that is where "entering" happens),
				# otherwise at the middle of the area.
				var trigger := get_tree().root.find_child("Trigger_" + String(area_id), true, false) as Node3D
				if trigger != null:
					target = Vector3(trigger.global_position.x, 0.0, trigger.global_position.z)
					label = LABELS.get(StringName(area_id), String(_region_landmark(StringName(area_id)).get("name", "Area")))
					return
				var rect := _area_rect(StringName(area_id))
				if rect.size != Vector2.ZERO:
					target = Vector3(rect.get_center().x, 0.0, rect.get_center().y)
					label = LABELS.get(StringName(area_id), "Area")
					return
				# Mission triggers (Research Complex, Iron Fortress): matched by their trigger or event id.
				var mission_trigger := _find_mission_trigger(StringName(area_id))
				if mission_trigger != null:
					target = Vector3(mission_trigger.global_position.x, 0.0, mission_trigger.global_position.z)
					label = "Objective"
					return
				# Later regions: the map knows where each area is (same ids as the quest targets).
				var landmark := _region_landmark(StringName(area_id))
				if not landmark.is_empty():
					var area_rect: Rect2 = landmark.get("rect", Rect2())
					target = Vector3(area_rect.get_center().x, 0.0, area_rect.get_center().y)
					label = String(landmark.get("name", "Area"))
					return
		ObjectiveData.Type.INTERACT, ObjectiveData.Type.DISCOVER:
			for id in objective.targets:
				if _point_at_interactable(StringName(id)):
					return
		ObjectiveData.Type.KILL_COUNT:
			_point_at_nearest_enemy()
		ObjectiveData.Type.FLAG:
			_resolve_flag_target(objective)


func _resolve_flag_target(objective: ObjectiveData) -> void:
	for flag in objective.targets:
		match String(flag):
			"has_access_card":
				if not _point_at_pickup("Keycard", "Access card"):
					_point_at_nearest_enemy()
			"comms_power_on":
				_point_at_power_step()
			"patrol_d_guards_cleared", "boss_warden_defeated":
				_point_at_nearest_enemy()
			"next_location_unlocked":
				_point_at_interactable(&"military_terminal")
			"dead_coast_arrived":
				# The way on is the south road gate; the exit trigger sits just north of the barricade.
				# Two ways out lead there: the south gate and the service road behind the Warden room.
				var player_node := get_tree().get_first_node_in_group("player") as Node3D
				var best := INF
				for exit_name in ["Exit_to_dead_coast", "Exit_to_dead_coast_north"]:
					var exit_node := get_tree().root.find_child(exit_name, true, false) as Node3D
					if exit_node == null:
						continue
					var spot := Vector3(exit_node.global_position.x, 0.0, exit_node.global_position.z)
					var distance := spot.distance_to(player_node.global_position) if player_node != null else 0.0
					if distance < best:
						best = distance
						target = spot
						label = "Service road" if exit_name.ends_with("north") else "Road south"
			_:
				var flag_name := String(flag)
				if flag_name.ends_with("_waves_cleared"):
					_point_at_wave_hold()  # a stage wave fight: head for its hold area
				elif _is_boss_flag(flag_name):
					_point_at_boss()  # a stage boss: the living boss, or the spot where it will stand
				elif flag_name.ends_with("_arrived"):
					_point_at_road_to(StringName(flag_name.trim_suffix("_arrived")))  # the road to the next stage
				elif flag_name.begins_with("patrol_") and flag_name.ends_with("_cleared"):
					_point_at_nearest_enemy()  # a patrol group has to be defeated
				elif not _point_at_interactable(StringName(flag_name)):
					_point_at_next_area()  # no object carries this flag: lead on through the region
				if target == null:
					continue
		return


func _point_at_power_step() -> void:
	var world := get_node_or_null("/root/WorldState")
	if world != null and not world.has_flag(&"panel_inspected"):
		_point_at_interactable(&"security_panel")
		return
	var puzzle := get_tree().get_first_node_in_group("sequence_puzzle")
	if puzzle != null and puzzle.data != null:
		var step: int = puzzle.current_step()
		if step < puzzle.data.order.size():
			_point_at_interactable(StringName(puzzle.data.order[step]))


## Prefers an available match (nearest first). A match that is locked for now is still the right place to
## head for while its objective is open, so it is used when nothing else matches.
func _point_at_interactable(id: StringName) -> bool:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var best: Interactable = null
	var best_available := false
	var best_distance := INF
	for node in get_tree().get_nodes_in_group("interactables"):
		var item := node as Interactable
		if item == null or item.interaction_id != id:
			continue
		var available := item.is_available()
		var distance := player.global_position.distance_to(item.global_position) if player != null else 0.0
		if (available and not best_available) or (available == best_available and distance < best_distance):
			best = item
			best_available = available
			best_distance = distance
	if best == null:
		return false
	target = best.global_position
	label = LABELS.get(id, short_label(id))
	return true


func _point_at_pickup(class_name_to_find: String, text: String) -> bool:
	for node in get_tree().root.find_children("*", class_name_to_find, true, false):
		var spatial := node as Node3D
		if spatial != null:
			target = spatial.global_position
			label = text
			return true
	return false


func _point_at_nearest_enemy() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var best := INF
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Node3D
		if enemy == null or (enemy.has_method("is_dead") and enemy.is_dead()):
			continue
		var d := player.global_position.distance_to(enemy.global_position) if player else 0.0
		if d < best:
			best = d
			target = enemy.global_position
			label = "Enemy"


func _find_mission_trigger(id: StringName) -> Node3D:
	for node in get_tree().root.find_children("*", "MissionTrigger", true, false):
		var trigger := node as MissionTrigger
		if trigger != null and (trigger.trigger_id == id or trigger.event_id == id):
			return trigger
	return null


static func _is_boss_flag(flag_name: String) -> bool:
	return flag_name == "research_complex_elite_down" or ("_boss_" in flag_name and flag_name.ends_with("_defeated"))


## The nearest living boss; before it exists (or after a reload) the spot a stage boss will stand.
func _point_at_boss() -> bool:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var best := INF
	for node in get_tree().get_nodes_in_group("boss"):
		var boss := node as Node3D
		if boss == null or (boss.has_method("is_dead") and boss.is_dead()):
			continue
		var distance := player.global_position.distance_to(boss.global_position) if player != null else 0.0
		if distance < best:
			best = distance
			target = Vector3(boss.global_position.x, 0.0, boss.global_position.z)
			label = "Boss"
	if target != null:
		return true
	for node in get_tree().get_nodes_in_group("stage_boss_spawns"):
		var spawn := node as StageBoss
		if spawn != null and not spawn.is_defeated():
			target = Vector3(spawn.global_position.x, 0.0, spawn.global_position.z)
			label = "Boss"
			return true
	return false


## The nearest exit trigger whose destination is `region`.
func _point_at_road_to(region: StringName) -> bool:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var best := INF
	for node in get_tree().root.find_children("*", "RegionExit", true, false):
		var road := node as RegionExit
		if road == null or road.target_region != region:
			continue
		var distance := player.global_position.distance_to(road.global_position) if player != null else 0.0
		if distance < best:
			best = distance
			target = Vector3(road.global_position.x, 0.0, road.global_position.z)
			label = "Road to %s" % String(region).replace("_", " ").capitalize()
	return target != null


## The hold area of this stage's wave encounter (a StageWaves node joins the group "stage_waves").
func _point_at_wave_hold() -> bool:
	for node in get_tree().get_nodes_in_group("stage_waves"):
		var stage := node as Node3D
		if stage != null:
			target = Vector3(stage.global_position.x, 0.0, stage.global_position.z)
			label = "Hold point"
			return true
	return false


## The current region's map landmark with this id (an area), or an empty dictionary.
func _region_landmark(area_id: StringName) -> Dictionary:
	var data := MapData.load_for(MapData.current_region())
	if data == null:
		return {}
	for raw in data.landmarks:
		if raw is Dictionary and String((raw as Dictionary).get("id", "")) == String(area_id):
			return raw
	return {}


## No specific object to aim at: lead the player on to the first area of this region not yet discovered.
func _point_at_next_area() -> bool:
	var data := MapData.load_for(MapData.current_region())
	if data == null:
		return false
	for raw in data.landmarks:
		if not (raw is Dictionary):
			continue
		var item: Dictionary = raw
		if String(item.get("kind", "area")) != "area" or MapData.is_flag_set(String(item.get("flag", ""))):
			continue
		var rect: Rect2 = item.get("rect", Rect2())
		target = Vector3(rect.get_center().x, 0.0, rect.get_center().y)
		label = "Explore ahead"
		return true
	return false


func _area_rect(area_id: StringName) -> Rect2:
	var areas: Dictionary = Outpost17.AREAS
	if areas.has(area_id):
		return areas[area_id]["rect"]
	return Rect2()


# --- where it is drawn ---------------------------------------------------------

func _update_screen() -> void:
	var camera := get_viewport().get_camera_3d()
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if target == null or camera == null or player == null:
		_set_visible(false)
		return
	var world_target: Vector3 = target
	var flat := Vector2(world_target.x - player.global_position.x, world_target.z - player.global_position.z)
	_distance = flat.length()
	var viewport := get_viewport().get_visible_rect().size
	var on_screen := not camera.is_position_behind(world_target) \
			and Rect2(Vector2(80.0, 80.0), viewport - Vector2(160.0, 160.0)).has_point(camera.unproject_position(world_target))
	if on_screen and _distance < HIDE_WITHIN:
		_set_visible(false)
		return
	_direction = screen_direction(camera.global_transform.basis, flat)
	_screen_pos = place(_direction, viewport, TouchControls.touch_active)
	_set_visible(true)


func _set_visible(value: bool) -> void:
	_visible_now = value
	if _control != null:
		_control.visible = value
		_control.queue_redraw()


## Pure placement: where the pointer sits for a direction (screen y grows downward) so that it keeps off
## the HUD bands and the touch buttons. Public so a test can check it.
## Screen direction (x right, y down, so up is negative) of a flat world offset (x, z) as the player sees it.
## Uses the camera's heading only: the downward tilt of a third-person camera and the height of the target must
## not bend the arrow, which they did when the offset was taken in the camera's own tilted frame.
static func screen_direction(camera_basis: Basis, flat_offset: Vector2) -> Vector2:
	var forward := -camera_basis.z
	forward.y = 0.0
	var right := camera_basis.x
	right.y = 0.0
	if forward.length() < 0.001:
		forward = Vector3.FORWARD  # looking straight down: fall back to the world heading
	if right.length() < 0.001:
		right = Vector3.RIGHT
	forward = forward.normalized()
	right = right.normalized()
	var offset := Vector3(flat_offset.x, 0.0, flat_offset.y)
	return Vector2(offset.dot(right), -offset.dot(forward))


static func place(direction: Vector2, viewport: Vector2, touch: bool) -> Vector2:
	var center := viewport * 0.5
	var dir := direction.normalized() if direction.length() > 0.001 else Vector2.UP
	var pos := center + Vector2(dir.x * viewport.x * 0.34, dir.y * viewport.y * 0.30)
	var rects := avoid_rects(viewport, touch)
	for step in 40:
		var box := Rect2(pos - SIZE * 0.5, SIZE)
		var clear := true
		for rect in rects:
			if box.intersects(rect):
				clear = false
				break
		if clear or (pos - center).length() <= MIN_RADIUS:
			break
		pos = center + (pos - center) * 0.95  # slide toward the middle until clear
	return pos


## The screen areas the HUD uses, for a viewport size (matches the layout in hud.gd).
static func avoid_rects(viewport: Vector2, touch: bool) -> Array[Rect2]:
	var rects: Array[Rect2] = [
		Rect2(0.0, 80.0, 300.0, 110.0),                              # bars, teleport label
		Rect2(0.0, 190.0, 440.0, 100.0),                             # quest tracker
		Rect2(viewport.x - 400.0, 0.0, 400.0, 125.0),                # equipment panel
		Rect2(viewport.x * 0.5 - 300.0, 0.0, 600.0, 175.0),          # wave label, boss bar, banners
		Rect2(viewport.x * 0.5 - 380.0, viewport.y - 200.0, 760.0, 200.0),  # subtitles, toast, prompt
	]
	if touch:
		rects.append(Rect2(viewport.x - 440.0, viewport.y - 330.0, 440.0, 330.0))  # touch buttons
	return rects


func _draw_pointer() -> void:
	if not _visible_now:
		return
	var dir := _direction.normalized() if _direction.length() > 0.001 else Vector2.UP
	var side := Vector2(-dir.y, dir.x)
	var tip := _screen_pos + dir * 18.0
	var points := PackedVector2Array([tip, _screen_pos - dir * 10.0 + side * 13.0, _screen_pos - dir * 10.0 - side * 13.0])
	_control.draw_colored_polygon(points, Color(0.95, 0.8, 0.25, 0.92))
	_control.draw_polyline(PackedVector2Array([points[0], points[1], points[2], points[0]]), Color(0.1, 0.08, 0.02, 0.95), 2.0)
	var font := ThemeDB.fallback_font
	var text := "%s %d m" % [label, roundi(_distance)]
	var text_pos := _screen_pos + Vector2(-70.0, 34.0 if dir.y < 0.5 else -26.0)
	_control.draw_string_outline(font, text_pos, text, HORIZONTAL_ALIGNMENT_CENTER, 140.0, 16, 4, Color.BLACK)
	_control.draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_CENTER, 140.0, 16, Color(1.0, 0.95, 0.75))


const REGION_PREFIXES: Array[String] = ["dead_coast_", "blackwood_", "research_complex_", "iron_fortress_", "dc_", "bw_", "rc_", "if_"]


## "dead_coast_wreck_hull" -> "Wreck Hull": the region prefix and a leading "log" are noise to the player.
static func short_label(id: StringName) -> String:
	var text := String(id)
	for prefix in REGION_PREFIXES:
		if text.begins_with(prefix):
			text = text.substr(prefix.length())
			break
	if text.begins_with("log_"):
		text = text.substr(4)
	return text.capitalize() if text != "" else String(id).capitalize()
