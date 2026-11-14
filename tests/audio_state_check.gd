extends SceneTree
## Music mode state machine (headless): explore, boss, ending, silent (death) and back to explore.
##   godot --headless --path . -s tests/audio_state_check.gd
## Nothing here can judge how anything sounds: it checks the state AudioManager reports and the files.

const WARDEN: String = "res://scenes/enemies/Warden.tscn"
const PLAYER: String = "res://scenes/player/Player.tscn"
const ENDING: String = "res://scripts/story/campaign_ending.gd"

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		print("  FAIL ", message)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _mode(audio: Node) -> StringName:
	return audio.music_state()["mode"]


func _run() -> void:
	var audio := root.get_node_or_null("AudioManager")
	_check(audio != null, "the AudioManager autoload exists")
	if audio == null:
		quit(1)
		return

	print("-- files and tracks")
	_check(ResourceLoader.exists("res://assets/audio/music_loop.wav"), "music_loop.wav exists (boss and ending reuse it: the 3 MB audio budget)")

	print("-- direct mode switches")
	_check(_mode(audio) == &"explore" and audio.music_state()["stream"] == &"music_loop" and is_equal_approx(audio._music.pitch_scale, 1.0), "the game starts in explore with music_loop at normal pitch")
	audio.set_music_mode(&"boss", 0.0)
	_check(_mode(audio) == &"boss" and audio.music_state()["pitch"] > 1.0 and is_equal_approx(audio._music.pitch_scale, 1.25), "boss mode plays the loop faster")
	_check(audio.music_state()["has_stream"], "boss mode has a stream loaded")
	audio.set_music_mode(&"silent", 0.0)
	_check(_mode(audio) == &"silent" and not audio.music_state()["has_stream"], "silent mode stops the music (no stream)")
	audio.set_music_mode(&"nonsense", 0.0)
	_check(_mode(audio) == &"silent", "an unknown mode is ignored")
	audio.set_music_mode(&"explore", 0.0)
	_check(_mode(audio) == &"explore" and audio.music_state()["has_stream"], "explore brings music_loop back")
	audio.set_music_mode(&"ending", 0.0)
	_check(audio.music_state()["pitch"] < 1.0 and is_equal_approx(audio._music.pitch_scale, 0.75), "ending mode plays the loop slower")
	audio.set_ambience_duck(0.0)
	_check(is_equal_approx(audio._music.volume_db, audio.MUSIC_DB), "the ending's duck does not silence the ending music")
	audio.set_ambience_duck(1.0)
	audio.set_music_mode(&"explore", 0.0)
	audio.set_ambience_duck(0.0)
	_check(audio._music.volume_db < audio.MUSIC_DB - 40.0, "a duck still silences the explore music")
	audio.set_ambience_duck(1.0)

	print("-- a real boss fight")
	var area := Node3D.new()
	root.add_child(area)
	var boss := (load(WARDEN) as PackedScene).instantiate() as Enemy
	area.add_child(boss)
	await _frames(3)
	_check(_mode(audio) == &"explore", "a boss that is merely present does not start the boss music")
	boss.damaged.emit(5.0, Vector3.ZERO, false)
	_check(_mode(audio) == &"boss", "the first damage to a boss starts the boss music")
	boss.damaged.emit(5.0, Vector3.ZERO, false)
	_check(_mode(audio) == &"boss", "more damage keeps it")
	boss.defeated.emit()
	_check(_mode(audio) == &"explore", "defeating the boss restores explore music")

	var boss2 := (load(WARDEN) as PackedScene).instantiate() as Enemy
	area.add_child(boss2)
	await _frames(3)
	boss2.damaged.emit(5.0, Vector3.ZERO, true)
	_check(_mode(audio) == &"boss", "a second boss starts it again")
	boss2.queue_free()
	await _frames(3)
	_check(_mode(audio) == &"explore", "a boss leaving the scene mid-fight (a region change) restores explore music")

	print("-- death and a fresh life")
	var player := (load(PLAYER) as PackedScene).instantiate() as Player
	area.add_child(player)
	await _frames(3)
	_check(_mode(audio) == &"explore", "a player entering the world starts explore music")
	audio.set_music_mode(&"boss", 0.0)
	player.health.died.emit()
	_check(_mode(audio) == &"silent", "the player dying silences the music")
	player.queue_free()
	await _frames(2)
	var player2 := (load(PLAYER) as PackedScene).instantiate() as Player
	area.add_child(player2)
	await _frames(3)
	_check(_mode(audio) == &"explore", "the respawned player brings explore music back")

	print("-- ending")
	var ending := CampaignEnding.start(self, true, {})
	await _frames(2)
	_check(_mode(audio) == &"ending", "the ending sequence switches to the ending music")
	ending.queue_free()
	await _frames(3)
	_check(_mode(audio) == &"explore", "closing the ending restores explore music")
	paused = false

	print("-- main menu")
	audio.set_music_mode(&"silent", 0.0)
	var menu := MainMenu.new()
	root.add_child(menu)
	await _frames(3)
	_check(_mode(audio) == &"explore", "arriving at the main menu always restores explore music")
	menu.queue_free()
	area.queue_free()
	await _frames(2)

	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
