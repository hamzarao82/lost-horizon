class_name AnimationDriver
extends RefCounted
## Plays the clips of an imported character (AnimationPlayer + AnimationTree built in code).
##
## Two ways of driving the skeleton, switched on demand:
##  * TREE mode: an AnimationTree state machine with a speed-driven BlendSpace1D (idle/walk/run/sprint)
##    plus fall, jump_start, land, hit, death and guard states. Used for everything free-running.
##  * SCRUB mode: the AnimationPlayer holds still and is seeked to an exact position every frame.
##    Used for attacks, dodge and boss moves, so the pose follows the combat system's frame counter
##    (hit-stop, time scale and attack speed included) and a clip can never replay on its own.
## Clip names are canonical (idle, walk, light_1 ...); missing clips fall back along FALLBACKS.

const LOOPING: PackedStringArray = ["idle", "walk", "run", "sprint", "fall", "guard"]
## Where the strike lands inside every attack clip (art contract: 35 % of the clip length).
const STRIKE_FRACTION: float = 0.35
const XFADE: float = 0.12
const TREE_STATES: PackedStringArray = ["loco", "fall", "jump_start", "land", "hit", "death", "guard"]
## Speed (m/s) at which each locomotion clip is at full weight.
const LOCO_POINTS: Array = [["idle", 0.0], ["walk", 2.0], ["run", 5.0], ["sprint", 8.5]]
const FALLBACKS: Dictionary = {
	"sprint": ["run", "walk", "idle"], "run": ["walk", "idle"], "walk": ["idle"], "guard": ["idle"],
	"jump_start": ["fall", "idle"], "fall": ["idle"], "land": ["idle"], "hit": ["idle"],
	"death": ["hit", "idle"], "dodge": ["run", "idle"],
	"light_1": ["heavy", "idle"], "light_2": ["light_1", "heavy"], "light_3": ["light_1", "heavy"],
	"heavy": ["light_1"], "sprint_attack": ["heavy", "light_1"], "air_attack": ["heavy", "light_1"],
	"spin": ["heavy", "light_1"], "slam": ["heavy", "light_1"], "flurry": ["light_2", "light_1"],
	"shockwave_cast": ["heavy", "light_1"], "roar": ["idle"],
}

var player: AnimationPlayer
var tree: AnimationTree
var scrubbing: bool = false

var _names: Dictionary = {}      # canonical name -> actual animation name in the player
var _tree_states: Array[StringName] = []
var _playback: AnimationNodeStateMachinePlayback
var _current_state: StringName = &""


## Strike-aligned mapping from the combat system's frame counter to a clip position (seconds).
## With `align` the active-window start (`startup` frames) lands exactly on STRIKE_FRACTION of the clip.
static func attack_clip_position(frames: float, startup: float, total: float, length: float,
		align: bool = true) -> float:
	if total <= 0.0 or length <= 0.0:
		return 0.0
	frames = clampf(frames, 0.0, total)
	var u: float
	if align and startup > 0.0 and startup < total:
		if frames < startup:
			u = frames / startup * STRIKE_FRACTION
		else:
			u = STRIKE_FRACTION + (frames - startup) / (total - startup) * (1.0 - STRIKE_FRACTION)
	else:
		u = frames / total
	return u * length


static func canonical(raw_name: String) -> String:
	var n := raw_name
	var bar := n.rfind("|")
	if bar >= 0:
		n = n.substr(bar + 1)
	return n.to_lower().strip_edges()


## Returns false (and does nothing) when the player has no usable animations.
func setup(anim_player: AnimationPlayer, host: Node) -> bool:
	player = anim_player
	if player == null:
		return false
	for raw: StringName in player.get_animation_list():
		var key := canonical(String(raw))
		if key != "" and not _names.has(key):
			_names[key] = raw
			var anim := player.get_animation(raw)
			anim.loop_mode = Animation.LOOP_LINEAR if LOOPING.has(key) else Animation.LOOP_NONE
	if _names.is_empty():
		return false
	_build_tree(host)
	return true


func has_clip(name: String) -> bool:
	return resolve(name) != &""


## The real animation name for a canonical clip, following the fallback chain (&"" when nothing fits).
func resolve(name: String) -> StringName:
	if _names.has(name):
		return _names[name]
	for alt: String in FALLBACKS.get(name, []):
		if _names.has(alt):
			return _names[alt]
	return &""


func clip_length(name: String) -> float:
	var actual := resolve(name)
	return player.get_animation(actual).length if actual != &"" else 0.0


# --- tree ------------------------------------------------------------------------

func _build_tree(host: Node) -> void:
	var root := AnimationNodeStateMachine.new()

	var loco := AnimationNodeBlendSpace1D.new()
	loco.min_space = 0.0
	loco.max_space = 8.5
	for point: Array in LOCO_POINTS:
		var actual := resolve(point[0])
		if actual == &"":
			continue
		var clip := AnimationNodeAnimation.new()
		clip.animation = actual
		loco.add_blend_point(clip, point[1], -1, StringName(point[0]))
	if loco.get_blend_point_count() == 0:
		return  # nothing to blend: the driver still scrubs
	root.add_node("loco", loco, Vector2(0, 0))
	_tree_states.append(&"loco")

	var column := 1
	for state in TREE_STATES:
		if state == "loco":
			continue
		var actual := resolve(state)
		if actual == &"":
			continue
		var clip := AnimationNodeAnimation.new()
		clip.animation = actual
		root.add_node(state, clip, Vector2(220 * column, 0))
		_tree_states.append(StringName(state))
		column += 1

	for from_state in _tree_states:
		for to_state in _tree_states:
			if from_state == to_state:
				continue
			var transition := AnimationNodeStateMachineTransition.new()
			transition.xfade_time = 0.05 if to_state == &"hit" or to_state == &"death" else XFADE
			transition.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE
			transition.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED
			root.add_transition(from_state, to_state, transition)
	root.set_graph_offset(Vector2.ZERO)

	tree = AnimationTree.new()
	tree.name = "AnimationTree"
	host.add_child(tree)
	tree.tree_root = root
	var anim_root := player.get_node_or_null(player.root_node)
	if anim_root:
		tree.root_node = tree.get_path_to(anim_root)
	tree.anim_player = tree.get_path_to(player)
	tree.active = true
	player.active = false
	_playback = tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
	if _playback:
		_playback.start(&"loco")
		_current_state = &"loco"


func has_tree() -> bool:
	return tree != null and _playback != null


## Blend position of the locomotion blend space (horizontal speed in m/s).
func set_speed(speed: float) -> void:
	if tree and _tree_states.has(&"loco"):
		tree.set("parameters/loco/blend_position", clampf(speed, 0.0, 8.5))


## Switch to a tree state ("loco", "fall", "hit", ...). Unknown states fall back to "loco".
func play_state(state: StringName) -> void:
	if not has_tree():
		return
	if scrubbing:
		end_scrub()
	if not _tree_states.has(state):
		state = &"loco"
	if state == _current_state:
		return
	_current_state = state
	_playback.travel(state)


func current_state() -> StringName:
	if _playback == null:
		return &""
	return _playback.get_current_node()


# --- scrub -----------------------------------------------------------------------

## Holds `name` at `position` seconds (clamped to its length). Returns false when no clip exists.
func scrub(name: String, position: float) -> bool:
	var actual := resolve(name)
	if actual == &"":
		return false
	if not scrubbing:
		scrubbing = true
		if tree:
			tree.active = false
		player.active = true
		player.stop()
	var length := player.get_animation(actual).length
	if player.current_animation != String(actual):
		player.play(actual, 0.0, 0.0)  # speed 0: it never advances on its own
	player.seek(clampf(position, 0.0, length), true)
	return true


func scrub_progress(name: String, progress: float) -> bool:
	return scrub(name, clampf(progress, 0.0, 1.0) * clip_length(name))


func end_scrub() -> void:
	if not scrubbing:
		return
	scrubbing = false
	if player:
		player.stop()
		player.active = false
	if tree:
		tree.active = true
		_current_state = &""  # force the next play_state() to travel


## True only when the model really contains this clip (no fallback).
func has_exact(name: String) -> bool:
	return _names.has(name)
