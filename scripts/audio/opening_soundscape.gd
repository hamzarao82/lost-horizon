class_name OpeningSoundscape
extends Node
## Quiet sound for the opening approach in Area A: leaves and breeze on the trail, a machinery hum and the
## odd distant murmur near the work yard, and a rattle when the perimeter gate's crank is turned. Built from
## sounds in assets/audio only; none of it has been listened to (see docs/AUDIO_SANITY.md). Does nothing on a
## headless run except keep its numbers testable through `update_for()`.

const TRAIL_MAX_Z: float = 44.5   ## south of the fence is the trail; north of it the compound side
const YARD_CENTER: Vector2 = Vector2(34.0, 35.0)
const YARD_HEARING: float = 45.0
const MURMUR_HEARING: float = 32.0
const TRAIL_DB: float = -20.0
const HUM_DB_FAR: float = -48.0
const HUM_DB_NEAR: float = -22.0
const MURMUR_DB: float = -24.0
const MURMUR_MIN_GAP: float = 6.0
const MURMUR_MAX_GAP: float = 9.5
const RATTLE_FLAG: StringName = &"perimeter_crank_turned"
const TICK_SECONDS: float = 0.25

var trail_target_db: float = -60.0
var hum_target_db: float = -60.0
var murmurs_played: int = 0
var rattles_played: int = 0

var _trail: AudioStreamPlayer
var _hum: AudioStreamPlayer
var _tick: float = 0.0
var _next_murmur: float = 4.0
var _clock: float = 0.0
var _rattled: bool = false
var _headless: bool = DisplayServer.get_name() == "headless"


static func attach(parent: Node) -> OpeningSoundscape:
	var node := OpeningSoundscape.new()
	node.name = "OpeningSoundscape"
	parent.add_child(node)
	return node


func _ready() -> void:
	if _headless:
		return
	_trail = _make_loop("res://assets/audio/ambience_trail.wav")
	_hum = _make_loop("res://assets/audio/machinery_hum.wav")


func _make_loop(path: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.bus = "Master"
	player.volume_db = -60.0
	add_child(player)
	var stream := load(path) as AudioStream
	if stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
		(stream as AudioStreamWAV).loop_end = (stream as AudioStreamWAV).data.size() / 2
	player.stream = stream
	return player


func _process(delta: float) -> void:
	_clock += delta
	_tick += delta
	if _tick < TICK_SECONDS:
		return
	_tick = 0.0
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player != null:
		update_for(player.global_position, TICK_SECONDS)
	_smooth_players(TICK_SECONDS)


## Pure decision step: where the player stands decides the targets and whether a one-shot is due.
func update_for(position: Vector3, step: float) -> void:
	var on_trail: bool = position.z > TRAIL_MAX_Z and position.z < 80.0
	trail_target_db = TRAIL_DB if on_trail else -60.0
	var to_yard := Vector2(position.x, position.z).distance_to(YARD_CENTER)
	if to_yard < YARD_HEARING:
		hum_target_db = lerpf(HUM_DB_NEAR, HUM_DB_FAR, clampf(to_yard / YARD_HEARING, 0.0, 1.0))
	else:
		hum_target_db = -60.0
	if to_yard < MURMUR_HEARING:
		_next_murmur -= step
		if _next_murmur <= 0.0:
			_next_murmur = randf_range(MURMUR_MIN_GAP, MURMUR_MAX_GAP)
			murmurs_played += 1
			_play(&"guard_murmur", MURMUR_DB)
	var world := get_node_or_null("/root/WorldState")
	if not _rattled and world != null and world.has_method("has_flag") and world.has_flag(RATTLE_FLAG):
		_rattled = true
		rattles_played += 1
		_play(&"fence_rattle", -8.0)


func _smooth_players(step: float) -> void:
	_ease(_trail, trail_target_db, step)
	_ease(_hum, hum_target_db, step)


func _ease(player: AudioStreamPlayer, target: float, step: float) -> void:
	if player == null:
		return
	player.volume_db = move_toward(player.volume_db, target, 60.0 * step)
	if player.volume_db <= -59.0 and player.playing and target <= -59.0:
		player.stop()
	elif player.volume_db > -59.0 and not player.playing:
		player.play()


func _play(sfx_name: StringName, volume_db: float) -> void:
	if _headless:
		return
	var audio := get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("play"):
		audio.call("play", sfx_name, volume_db)
