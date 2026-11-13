class_name MenuStorm
extends Control
## Cheap stormy-ocean background for the title menu: a drawn sky and sea, a wave-lit island silhouette,
## scheduled lightning with a delayed thunder clap, and quality-scaled rain. All drawing is one Control
## redrawn at most 30 times a second; nothing heavy is built on a headless run (tests, CI).
##
## `advance(delta)` is the real clock: `_process` just calls it, so a test can step the storm without
## real frames or a window, and get the same schedule every time for a given seed.

const STEP: float = 1.0 / 30.0
const SKY_TOP: Color = Color(0.03, 0.035, 0.05)
const SKY_HORIZON: Color = Color(0.09, 0.10, 0.14)
const SEA_FAR: Color = Color(0.02, 0.03, 0.05)
const SEA_NEAR: Color = Color(0.05, 0.07, 0.10)
const ISLAND_COLOR: Color = Color(0.015, 0.02, 0.03)
const FLASH_COLOR: Color = Color(0.85, 0.9, 1.0)
const RAIN_COLOR: Color = Color(0.6, 0.7, 0.8, 0.12)

const LIGHTNING_MIN: float = 4.0
const LIGHTNING_MAX: float = 9.0
const THUNDER_DELAY_MIN: float = 0.4
const THUNDER_DELAY_MAX: float = 1.6
const FLASH_DECAY: float = 2.6  ## 1.0 -> 0.0 in well under a second

var _rng := RandomNumberGenerator.new()
var _acc: float = 0.0
var _clock: float = 0.0
var _next_lightning: float = 0.0
var _flash: float = 0.0             ## current flash intensity, 0..1
var _pending_thunder: float = -1.0  ## seconds until the delayed thunder fires; -1 = none pending
var _rain: Array = []
var _wind_player: AudioStreamPlayer
var _wave_player: AudioStreamPlayer
var _headless: bool = false


func _init(seed_value: int = 11) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_rng.seed = seed_value
	_headless = DisplayServer.get_name() == "headless"
	_schedule_lightning()


func _ready() -> void:
	_build_rain()
	if not _headless:
		_build_audio()


func _exit_tree() -> void:
	set_process(false)


func _build_audio() -> void:
	_wind_player = AudioStreamPlayer.new()
	_wave_player = AudioStreamPlayer.new()
	_wind_player.bus = "Master"
	_wave_player.bus = "Master"
	_wind_player.volume_db = -16.0
	_wave_player.volume_db = -11.0
	add_child(_wind_player)
	add_child(_wave_player)
	_loop(_wind_player, "res://assets/audio/menu_wind.wav")
	_loop(_wave_player, "res://assets/audio/menu_waves.wav")


func _loop(player: AudioStreamPlayer, path: String) -> void:
	var stream := load(path) as AudioStream
	if stream == null:
		return
	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(round(wav.get_length() * float(wav.mix_rate)))
	player.stream = stream
	player.play()  # never reached on headless: the dummy audio driver leaks looping playback at exit


func _build_rain() -> void:
	_rain.clear()
	for i in _rain_count():
		_rain.append({"x": _rng.randf(), "y": _rng.randf(), "speed": _rng.randf_range(1.3, 2.2), "len": _rng.randf_range(10.0, 22.0)})


## Rain line count by quality preset; 0 on headless and on Low (cheap on web/mobile too).
func _rain_count() -> int:
	if _headless:
		return 0
	var settings := get_node_or_null("/root/Settings")
	var quality: int = settings.quality if settings != null else 2
	match quality:
		0: return 0
		1: return 20
		_: return 45


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	advance(delta)


## The real storm clock; public so tests can step it deterministically.
func advance(delta: float) -> void:
	_clock += delta
	if _flash > 0.0:
		_flash = maxf(_flash - delta * FLASH_DECAY, 0.0)
	if _clock >= _next_lightning:
		_trigger_flash()  # set after this step's decay, so the strike reads as a full flash this frame
		_schedule_lightning()
	if _pending_thunder >= 0.0:
		_pending_thunder -= delta
		if _pending_thunder <= 0.0:
			_pending_thunder = -1.0
			_play_thunder()
	for drop in _rain:
		drop["y"] += drop["speed"] * delta * 0.3
		if drop["y"] > 1.05:
			drop["y"] = -0.05
			drop["x"] = _rng.randf()
	_acc += delta
	if _acc >= STEP:
		_acc = 0.0
		if not _headless:
			queue_redraw()


func _schedule_lightning() -> void:
	_next_lightning = _clock + _rng.randf_range(LIGHTNING_MIN, LIGHTNING_MAX)


func _trigger_flash() -> void:
	_flash = 1.0
	_pending_thunder = _rng.randf_range(THUNDER_DELAY_MIN, THUNDER_DELAY_MAX)


func _play_thunder() -> void:
	var audio := get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("play"):
		audio.call("play", &"menu_thunder", -6.0)


## Test hooks: the real state, not a guess from the outside.
func flash_intensity() -> float:
	return _flash


func thunder_pending() -> bool:
	return _pending_thunder >= 0.0


func rain_count() -> int:
	return _rain.size()


func _draw() -> void:
	var size := get_rect().size
	if size.x <= 0.0 or size.y <= 0.0:
		return
	draw_rect(Rect2(Vector2.ZERO, Vector2(size.x, size.y * 0.62)), SKY_TOP)
	draw_rect(Rect2(Vector2(0.0, size.y * 0.5), Vector2(size.x, size.y * 0.12)), SKY_HORIZON)
	draw_rect(Rect2(Vector2(0.0, size.y * 0.62), Vector2(size.x, size.y * 0.38)), SEA_FAR)
	for i in 5:
		var yy := size.y * 0.66 + i * size.y * 0.07
		var pts := PackedVector2Array()
		var n := 24
		for p in n + 1:
			var x := size.x * float(p) / n
			var wobble := sin(x * 0.02 + _clock * 1.2 + i) * 3.0
			pts.append(Vector2(x, yy + wobble))
		draw_polyline(pts, SEA_NEAR.lightened(0.05 * (i + 1)), 1.5)
	var island_y := size.y * 0.58
	var island := PackedVector2Array([
		Vector2(size.x * 0.58, island_y), Vector2(size.x * 0.66, island_y - size.y * 0.035),
		Vector2(size.x * 0.74, island_y - size.y * 0.015), Vector2(size.x * 0.82, island_y),
		Vector2(size.x * 0.82, island_y + 4.0), Vector2(size.x * 0.58, island_y + 4.0),
	])
	draw_colored_polygon(island, ISLAND_COLOR.lightened(_flash * 0.5))
	for drop in _rain:
		var x := float(drop["x"]) * size.x
		var y := float(drop["y"]) * size.y
		draw_line(Vector2(x, y), Vector2(x - 2.0, y + float(drop["len"])), RAIN_COLOR, 1.0)
	if _flash > 0.01:
		draw_rect(Rect2(Vector2.ZERO, size), Color(FLASH_COLOR.r, FLASH_COLOR.g, FLASH_COLOR.b, _flash * 0.35))
