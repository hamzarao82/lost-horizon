extends Node
## Autoload "AudioManager": pooled non-positional SFX, a looping music track, master volume/mute,
## and self-wiring of enemy / wave sounds so gameplay scenes need no audio code.

const AUDIO_DIR: String = "res://assets/audio/"
const SFX_NAMES: Array[StringName] = [
	&"swing_light", &"swing_heavy", &"hit_light", &"hit_heavy", &"hurt", &"dodge",
	&"pickup", &"equip", &"heal", &"enemy_swing_windup", &"enemy_death", &"wave_start",
	&"teleport", &"boss_slam", &"boss_charge", &"boss_leap", &"boss_roar", &"boss_fire", &"mission_complete", &"ui_click",
	&"footstep", &"radio_static", &"radio_beep", &"bird_flush", &"metal_creak",
]
const POOL_SIZE: int = 8
const MUSIC_DB: float = -14.0
const MUSIC_NAME: StringName = &"music_loop"
const LAZY_START_FRAMES: int = 90
const AMBIENCE_NAME: StringName = &"ambience_loop"
const AMBIENCE_DB: float = -24.0
## RegionData.ambience -> stream name. Outpost 17 keeps its original loop.
const REGION_AMBIENCE: Dictionary = {
	&"outpost": &"ambience_loop", &"dead_coast": &"ambience_coast",
	&"blackwood": &"ambience_jungle", &"research_complex": &"ambience_facility",
}
const STEP_MIN_SPEED: float = 2.0
const STEP_SPRINT_SPEED: float = 6.5  ## walk is 5 and sprint 8.5 (player.gd)
const STEP_INTERVAL_WALK: float = 0.44
const STEP_INTERVAL_SPRINT: float = 0.30

var _streams: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _next: int = 0
var _music: AudioStreamPlayer
var _ambience: AudioStreamPlayer
var _ambience_b: AudioStreamPlayer  ## second slot: the incoming loop of a region crossfade
var _slot_streams: Array[StringName] = [AMBIENCE_NAME, &""]
var _slot_gain: Array[float] = [1.0, 0.0]  ## linear, 1.0 = AMBIENCE_DB
var _active_slot: int = 0
var _region_ambience: StringName = &"outpost"
var _amb_tween: Tween
var _step_timer: float = 0.0
var _lazy_queue: Array[StringName] = []
var _lazy_wait_frames: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_pool.append(player)
	_music = AudioStreamPlayer.new()
	_music.volume_db = MUSIC_DB
	add_child(_music)
	_ambience = AudioStreamPlayer.new()
	_ambience.volume_db = AMBIENCE_DB
	add_child(_ambience)
	_ambience_b = AudioStreamPlayer.new()
	_ambience_b.volume_db = -80.0
	add_child(_ambience_b)
	get_tree().node_added.connect(_on_node_added)

	if OS.has_feature("web"):
		# Single-threaded wasm: loading 13 streams and the music loop here would delay the first frame of
		# the boot screen. Load one per frame once the game is up (Boot has usually cached them already).
		_lazy_queue.assign(SFX_NAMES)
		_lazy_queue.append(MUSIC_NAME)
		_lazy_queue.append(AMBIENCE_NAME)
		_lazy_wait_frames = LAZY_START_FRAMES
		set_process(true)
	else:
		set_process(false)
		for sfx_name in SFX_NAMES:
			_load_sfx(sfx_name)
		_install_music()
		_install_ambience()

	_connect_mission.call_deferred()
	_connect_captions.call_deferred()
	get_tree().node_added.connect(_wire_button)

func _process(_delta: float) -> void:
	if _lazy_wait_frames > 0:
		_lazy_wait_frames -= 1
		return
	if _lazy_queue.is_empty():
		set_process(false)
		return
	var next: StringName = _lazy_queue.pop_front()
	if next == AMBIENCE_NAME:
		_install_ambience()
	elif next == MUSIC_NAME:
		_install_music()
	else:
		_load_sfx(next)


func _load_sfx(sfx_name: StringName) -> void:
	var stream := _load_stream(sfx_name)
	if stream:
		_streams[sfx_name] = stream


func _install_music() -> void:
	var music_stream := _load_stream(MUSIC_NAME)
	if music_stream is AudioStreamWAV:
		var wav := music_stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = _loop_end_frames(wav)
	if music_stream:
		_music.stream = music_stream
		# The headless dummy audio driver leaks the looping playback at exit; nothing to hear there.
		if DisplayServer.get_name() != "headless":
			_music.play()


func play(sfx_name: StringName, volume_db: float = 0.0, pitch_jitter: float = 0.06) -> void:
	var stream: AudioStream = _streams.get(sfx_name)
	if stream == null or _pool.is_empty():
		return
	var player := _pool[_next]
	for candidate in _pool:  # prefer an idle player, otherwise steal round-robin
		if not candidate.playing:
			player = candidate
			break
	_next = (_next + 1) % _pool.size()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	player.play()


## Plays one sound silently so the mixer/stream setup cost is paid before the first real hit.
func warm_up(sfx_name: StringName) -> void:
	play(sfx_name, -80.0, 0.0)


func warm_up_names() -> Array[StringName]:
	return SFX_NAMES


func set_master_volume(linear: float) -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(clampf(linear, 0.0, 1.0)))


func set_muted(muted: bool) -> void:
	AudioServer.set_bus_mute(0, muted)


func _load_stream(stream_name: StringName) -> AudioStream:
	var path := "%s%s.wav" % [AUDIO_DIR, stream_name]
	if not ResourceLoader.exists(path):
		return null
	return load(path) as AudioStream


func _on_node_added(node: Node) -> void:
	# A node can re-enter the tree (a region returning from being detached): connect each signal only once.
	if node is Enemy:
		if node.has_signal(&"swing_started") and not node.is_connected(&"swing_started", _on_enemy_swing):
			node.connect(&"swing_started", _on_enemy_swing)
		if node.has_signal(&"was_hit") and not node.is_connected(&"was_hit", _on_enemy_hit):
			node.connect(&"was_hit", _on_enemy_hit)
		if node.has_signal(&"defeated") and not node.is_connected(&"defeated", _on_enemy_defeated):
			node.connect(&"defeated", _on_enemy_defeated)
	elif node is WaveManager:
		if not node.wave_started.is_connected(_on_wave_started):
			node.wave_started.connect(_on_wave_started)


func _on_enemy_swing() -> void:
	play(&"enemy_swing_windup", -6.0)


# Landed hits are played by the player (it knows light vs heavy); only a dodge needs a sound here.
func _on_enemy_hit(dodged: bool) -> void:
	if dodged:
		play(&"dodge", -4.0)


func _on_enemy_defeated() -> void:
	play(&"enemy_death")


func _on_wave_started(_index: int, _total: int) -> void:
	play(&"wave_start", -2.0, 0.0)


func _exit_tree() -> void:
	# Drop stream references so the engine exits without leaked-resource warnings.
	for player in _pool:
		player.stop()
		player.stream = null
	if _ambience:
		_ambience.stop()
		_ambience.stream = null
	if _music:
		_music.stop()
		_music.stream = null
	_streams.clear()


## Mission-complete jingle; QuestManager is an autoload that may not exist in minimal test scenes.
func _connect_mission() -> void:
	var quests := get_node_or_null("/root/QuestManager")
	if quests and quests.has_signal("mission_completed"):
		quests.mission_completed.connect(_on_mission_completed)


func _on_mission_completed(_quest_id: StringName) -> void:
	play(&"mission_complete")


## Every button gets a click without each screen wiring its own sound.
func _wire_button(node: Node) -> void:
	if node is BaseButton:
		(node as BaseButton).pressed.connect(play.bind(&"ui_click", -6.0))


func _install_ambience() -> void:
	if _slot_streams[0] != AMBIENCE_NAME:
		return  # a region crossfade already replaced slot A before the lazy web load got to it
	var stream := _load_stream(AMBIENCE_NAME)
	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = _loop_end_frames(wav)
	if stream:
		_ambience.stream = stream
		if DisplayServer.get_name() != "headless":  # the dummy driver leaks looping playback at exit
			_ambience.play()


## Seconds between steps for a horizontal speed; 0 means "no steps at this speed".
func step_interval(horizontal_speed: float) -> float:
	if horizontal_speed < STEP_MIN_SPEED:
		return 0.0
	return STEP_INTERVAL_SPRINT if horizontal_speed >= STEP_SPRINT_SPEED else STEP_INTERVAL_WALK


## One footstep tick for `player` (any body with is_on_floor() and velocity; `state` != 0 means not FREE).
## Returns true when a step sound was played.
func tick_footsteps(delta: float, player: Node) -> bool:
	if player == null or get_tree().paused or not player.has_method("is_on_floor") or not player.is_on_floor() \
			or int(player.get("state")) != 0:
		_step_timer = 0.0
		return false
	var velocity: Vector3 = player.get("velocity")
	var interval := step_interval(Vector2(velocity.x, velocity.z).length())
	if interval <= 0.0:
		_step_timer = 0.0
		return false
	_step_timer -= delta
	if _step_timer > 0.0:
		return false
	_step_timer = interval
	play(&"footstep", -10.0, 0.15)
	return true


func _physics_process(delta: float) -> void:
	tick_footsteps(delta, get_tree().get_first_node_in_group("player"))


## Subtitles double as radio chatter: a short static burst and beep before each caption appears.
func _connect_captions() -> void:
	var quests := get_node_or_null("/root/QuestManager")
	if quests and quests.has_signal("caption_requested"):
		quests.caption_requested.connect(_on_caption)


func _on_caption(_text: String, _seconds: float) -> void:
	play(&"radio_static", -12.0, 0.05)
	play(&"radio_beep", -14.0, 0.0)


# --- region ambience ---------------------------------------------------------
# Two loop slots crossfade on a region change (equal-power shape: both are never at full volume together).
# The state is plain data (ambience_state) so it can be tested without a sound device; the headless dummy
# driver is never asked to play loops.

## Crossfades to the loop for `region_ambience` (a RegionData.ambience name). Unknown names and missing
## streams leave the current ambience untouched. Called by RegionManager on every region change.
func set_region_ambience(region_ambience: StringName, fade_seconds: float = 2.0) -> void:
	var stream_name: StringName = REGION_AMBIENCE.get(region_ambience, &"")
	if stream_name == &"":
		return
	_region_ambience = region_ambience
	if _slot_streams[_active_slot] == stream_name:
		return
	var incoming := 1 - _active_slot
	var outgoing := _active_slot
	var stream := _load_stream(stream_name)  # web: one small WAV, loaded on demand rather than at boot
	if stream == null:
		return
	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = _loop_end_frames(wav)
	if _amb_tween != null and _amb_tween.is_valid():
		_amb_tween.kill()
	var player := _slot_player(incoming)
	player.stream = stream
	_slot_streams[incoming] = stream_name
	var in_start: float = _slot_gain[incoming]  # residual volume if a fade was interrupted: no pop
	_apply_slot_volume(incoming)
	if DisplayServer.get_name() != "headless":  # the dummy driver leaks looping playback at exit
		player.play()
	_active_slot = incoming
	var out_start: float = _slot_gain[outgoing]
	if fade_seconds <= 0.0:
		_crossfade_step(1.0, incoming, outgoing, in_start, out_start)
		return
	_amb_tween = create_tween()
	_amb_tween.tween_method(func(p: float) -> void: _crossfade_step(p, incoming, outgoing, in_start, out_start), 0.0, 1.0, fade_seconds)


func _crossfade_step(progress: float, incoming: int, outgoing: int, in_start: float, out_start: float) -> void:
	var shaped := progress * PI * 0.5
	_slot_gain[incoming] = lerpf(in_start, 1.0, sin(shaped))
	_slot_gain[outgoing] = out_start * cos(shaped)
	_apply_slot_volume(incoming)
	_apply_slot_volume(outgoing)
	if progress >= 1.0:
		_slot_gain[outgoing] = 0.0
		_slot_streams[outgoing] = &""
		var player := _slot_player(outgoing)
		player.stop()
		player.stream = null
		_apply_slot_volume(outgoing)


func _slot_player(slot: int) -> AudioStreamPlayer:
	return _ambience if slot == 0 else _ambience_b


func _apply_slot_volume(slot: int) -> void:
	_slot_player(slot).volume_db = AMBIENCE_DB + linear_to_db(maxf(_slot_gain[slot], 0.0001))


## For tests and tools: which loop is in which slot and at what gain (linear, 1.0 = normal ambience level).
func ambience_state() -> Dictionary:
	return {
		"region": _region_ambience,
		"active_slot": _active_slot,
		"streams": _slot_streams.duplicate(),
		"gains": _slot_gain.duplicate(),
		"fading": _amb_tween != null and _amb_tween.is_valid() and _amb_tween.is_running(),
	}


## Loop end in sample frames. The project imports WAVs as QOA, where `data.size() / 2` is the compressed
## byte count over two and cuts a loop short (it was about 1 s of the 5 s Outpost ambience and 2.4 s of
## the 12 s music). get_length() is right for every format.
func _loop_end_frames(wav: AudioStreamWAV) -> int:
	return int(round(wav.get_length() * float(wav.mix_rate)))
