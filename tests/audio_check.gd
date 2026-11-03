extends SceneTree
## Headless check for the Milestone 4 audio additions (footsteps, ambience, radio blips):
##   godot --headless --path . -s tests/audio_check.gd
## Exits non-zero on failure. Cannot judge how the sounds sound, only that they exist, load and are wired.

const NEW_SOUNDS: Array[String] = ["footstep", "ambience_loop", "radio_static", "radio_beep"]

var _failures: int = 0
var _checks: int = 0


## Stands in for the Player: the manager only needs is_on_floor(), velocity and state.
class FakePlayer extends Node:
	var state: int = 0
	var velocity: Vector3 = Vector3.ZERO
	var on_floor: bool = true

	func is_on_floor() -> bool:
		return on_floor


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		print("  FAIL ", message)


func _run() -> void:
	for sound in NEW_SOUNDS:
		var path := "res://assets/audio/%s.wav" % sound
		_check(ResourceLoader.exists(path), "%s.wav exists" % sound)
		_check(load(path) is AudioStreamWAV, "%s.wav loads as a WAV stream" % sound)
	var total := 0
	for file in DirAccess.get_files_at("res://assets/audio"):
		if file.ends_with(".wav"):
			total += FileAccess.get_file_as_bytes("res://assets/audio/" + file).size()
	_check(total < 3 * 1024 * 1024, "all audio is under 3 MB (%d KB)" % (total / 1024))
	var ambience := load("res://assets/audio/ambience_loop.wav") as AudioStreamWAV
	_check(ambience != null and ambience.get_length() <= 6.0, "ambience loop is 6 s or shorter")

	var am := root.get_node_or_null("AudioManager")
	_check(am != null, "AudioManager autoload exists")
	if am == null:
		_finish()
		return
	for sound in ["footstep", "radio_static", "radio_beep"]:
		_check(am.warm_up_names().has(StringName(sound)), "%s is registered with the manager" % sound)

	# Step interval by speed.
	_check(am.step_interval(0.0) == 0.0 and am.step_interval(1.9) == 0.0, "no steps below 2 m/s")
	var walk: float = am.step_interval(5.0)
	var sprint: float = am.step_interval(8.5)
	_check(walk > 0.0 and sprint > 0.0 and sprint < walk, "sprinting steps faster than walking")

	# Footstep timer with a fake player.
	var player := FakePlayer.new()
	root.add_child(player)
	player.velocity = Vector3(5.0, 0.0, 0.0)
	_check(am.tick_footsteps(0.016, player), "a step plays at once when walking starts")
	_check(not am.tick_footsteps(0.016, player), "no second step within the stride")
	var steps := 0
	for i in 60:  # one second at 60 Hz
		if am.tick_footsteps(1.0 / 60.0, player):
			steps += 1
	_check(steps >= 2 and steps <= 3, "walking for 1 s gives 2-3 steps (%d)" % steps)
	player.velocity = Vector3(8.5, 0.0, 0.0)
	am.set("_step_timer", 0.0)
	steps = 0
	for i in 60:
		if am.tick_footsteps(1.0 / 60.0, player):
			steps += 1
	_check(steps >= 3 and steps <= 4, "sprinting for 1 s gives 3-4 steps (%d)" % steps)
	player.velocity = Vector3(1.0, 0.0, 0.0)
	_check(not am.tick_footsteps(0.5, player), "no step when nearly standing still")
	player.velocity = Vector3(5.0, 0.0, 0.0)
	player.on_floor = false
	_check(not am.tick_footsteps(0.5, player), "no step in the air")
	player.on_floor = true
	player.state = 4  # DEAD
	_check(not am.tick_footsteps(0.5, player), "no step while dead")
	player.state = 1  # DODGE
	_check(not am.tick_footsteps(0.5, player), "no step while dodging")
	player.state = 0
	paused = true
	_check(not am.tick_footsteps(0.5, player), "no step while the tree is paused")
	paused = false
	_check(not am.tick_footsteps(0.5, null), "no step without a player")
	player.queue_free()

	# Ambience stream, loop and volume; mute is the master bus, which the ambience player shares.
	var amb: AudioStreamPlayer = am.get("_ambience")
	_check(amb != null and amb.stream != null, "ambience player has its stream")
	if amb != null and amb.stream is AudioStreamWAV:
		_check((amb.stream as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_FORWARD, "ambience loops")
	if amb != null:
		_check(is_equal_approx(amb.volume_db, -24.0), "ambience is quiet (-24 dB)")
		_check(amb.bus == &"Master", "ambience plays on the master bus, so mute and master volume apply")
	am.set_muted(true)
	_check(AudioServer.is_bus_mute(0), "mute silences the bus the ambience uses")
	am.set_muted(false)
	_check(not AudioServer.is_bus_mute(0), "unmute restores it")

	_finish()


func _finish() -> void:
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
