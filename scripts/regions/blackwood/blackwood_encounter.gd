class_name BlackwoodEncounter
extends Node3D
## A purposeful encounter: existing enemy scenes that spawn when the player enters a trigger area.
## `warning_seconds` > 0 makes it an ambush: a warning cue fires first (caption plus a sound hook and the
## `warning` signal), and the enemies only appear that long afterwards, so the player always gets
## a beat to react. Completed encounters set `blackwood_<id>_cleared` and never spawn again; an
## unfinished one restarts on the next entry (it has not been "done" yet).

signal warning
signal spawned_enemies(count: int)
signal cleared

@export var encounter_id: StringName
@export var trigger_area: StringName
@export var scene_paths: PackedStringArray
## Spawn offsets from this node; the enemies appear at these positions.
@export var offsets: PackedVector3Array
@export var warning_seconds: float = 0.0
@export var warning_text: String = ""
## Sound requested through AudioManager at the warning (a missing stream is simply ignored).
@export var warning_sound: StringName = &"bird_flush"
@export var coordinate: bool = true
## Ambush enemies start hostile; guard groups start idle and notice the player on their own.
@export var aggro_on_spawn: bool = true

var triggered: bool = false
var spawned: bool = false
var is_cleared: bool = false
var enemies: Array[Enemy] = []

var _alive: int = 0
var _timer: Timer


func cleared_flag() -> StringName:
	return RegionFlags.key(&"blackwood", StringName("%s_cleared" % String(encounter_id)))


## Also recorded as a one-time id in the region state (saved with it), so a cleared encounter stays cleared.
func claim_id() -> StringName:
	return StringName("encounter_%s" % String(encounter_id))



func _ready() -> void:
	var state := get_node_or_null("/root/WorldState")
	if state == null:
		return
	if state.has_flag(cleared_flag()) or PersistentIds.is_claimed(&"blackwood", claim_id()):
		is_cleared = true
		triggered = true
		spawned = true
		return
	state.area_entered.connect(_on_area_entered)


func _on_area_entered(id: StringName) -> void:
	if id == trigger_area:
		trigger()


## Public so tests can fire it without physics. Returns false when it already ran.
func trigger() -> bool:
	if triggered or is_cleared:
		return false
	triggered = true
	if warning_seconds <= 0.0:
		_spawn()
		return true
	warning.emit()
	if warning_text != "":
		Outpost17.say(self, warning_text, warning_seconds + 1.5)
	var audio := get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("play"):
		audio.play(warning_sound)
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.wait_time = warning_seconds
	add_child(_timer)
	_timer.timeout.connect(_spawn)
	_timer.start()
	return true


func _spawn() -> void:
	if spawned:
		return
	spawned = true
	var parent := get_parent()
	for i in scene_paths.size():
		var scene := load(scene_paths[i]) as PackedScene
		if scene == null:
			continue
		var enemy := scene.instantiate() as Enemy
		if enemy == null:
			continue
		enemy.coordinate_alarm = coordinate
		# Position before entering the tree so the enemy never overlaps the player for a frame.
		enemy.position = position + (offsets[i] if i < offsets.size() else Vector3.ZERO)
		parent.add_child(enemy)
		if aggro_on_spawn:
			enemy.aggro()
		enemy.defeated.connect(_on_defeated)
		enemies.append(enemy)
		_alive += 1
	spawned_enemies.emit(enemies.size())


func _on_defeated() -> void:
	_alive -= 1
	if _alive > 0 or is_cleared:
		return
	is_cleared = true
	var state := get_node_or_null("/root/WorldState")
	if state:
		state.set_flag(cleared_flag(), true)
	PersistentIds.claim(&"blackwood", claim_id())
	cleared.emit()
