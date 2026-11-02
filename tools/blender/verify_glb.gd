extends SceneTree
## Verifies the generated character GLBs against the engine contract.
##   Godot_v4.7.2-stable_win64_console.exe --headless --path <project> -s tools/blender/verify_glb.gd
## Exit code 1 if anything fails.

const NAMES: Array[String] = ["player", "soldier", "heavy", "elite", "warden"]
const BONES: Array[String] = ["Hips", "Spine", "Chest", "Neck", "Head", "UpperArm_R", "LowerArm_R", "Hand_R",
	"UpperArm_L", "LowerArm_L", "Hand_L", "UpperLeg_R", "LowerLeg_R", "Foot_R", "UpperLeg_L", "LowerLeg_L", "Foot_L"]
const CLIPS: Dictionary = {
	"idle": 2.0, "walk": 1.0, "run": 0.7, "sprint": 0.55, "jump_start": 0.3, "fall": 0.6, "land": 0.3,
	"light_1": 0.5, "light_2": 0.5, "light_3": 0.6, "heavy": 0.8, "sprint_attack": 0.6, "air_attack": 0.5,
	"spin": 0.7, "dodge": 0.5, "hit": 0.35, "death": 1.2, "guard": 1.0,
	"slam": 1.2, "flurry": 0.8, "shockwave_cast": 1.0, "roar": 1.5,
}
const LOOPS: Array[String] = ["idle", "walk", "run", "sprint", "fall", "guard"]
# name: [expected height (m), tri budget]
const SPEC: Dictionary = {
	"player": [1.80, 8000], "soldier": [1.78, 6000], "heavy": [1.95, 7000], "elite": [1.82, 6000],
	"warden": [2.25, 12000],
}

var _fail: int = 0


func _check(ok: bool, msg: String) -> void:
	if not ok:
		_fail += 1
		print("  FAIL ", msg)


func _find(node: Node, type_name: String) -> Array[Node]:
	var out: Array[Node] = []
	if node.is_class(type_name):
		out.append(node)
	for child in node.get_children():
		out.append_array(_find(child, type_name))
	return out


func _initialize() -> void:
	print("%-8s %6s %6s %5s %6s %5s %-7s %s" % ["char", "tris", "KB", "bones", "clips", "mats", "height", "facing (toe/heel z)"])
	var sockets: Dictionary = {}
	var sock_path := ProjectSettings.globalize_path("res://assets/characters/sockets.json")
	if FileAccess.file_exists(sock_path):
		sockets = JSON.parse_string(FileAccess.get_file_as_string(sock_path))
	for n in NAMES:
		_verify(n, sockets.get(n, {}))
	print("%s" % ("ALL OK" if _fail == 0 else "%d failure(s)" % _fail))
	quit(1 if _fail > 0 else 0)


func _verify(n: String, socket: Dictionary) -> void:
	var path := ProjectSettings.globalize_path("res://assets/characters/%s.glb" % n)
	if not FileAccess.file_exists(path):
		_check(false, "%s: file missing" % n)
		return
	var kb := int(FileAccess.get_file_as_bytes(path).size() / 1024)
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(path, state)
	_check(err == OK, "%s: glTF load error %d" % [n, err])
	var root := doc.generate_scene(state)
	_check(root != null, "%s: no scene" % n)
	if root == null:
		return
	var skels := _find(root, "Skeleton3D")
	_check(skels.size() == 1, "%s: expected one Skeleton3D, found %d" % [n, skels.size()])
	var skel := skels[0] as Skeleton3D
	var bone_names: Array[String] = []
	for i in skel.get_bone_count():
		bone_names.append(skel.get_bone_name(i))
	var bones_ok := bone_names.size() == BONES.size()
	for b in BONES:
		bones_ok = bones_ok and bone_names.has(b)
	_check(bones_ok, "%s: bones differ: %s" % [n, str(bone_names)])

	var players := _find(root, "AnimationPlayer")
	_check(players.size() == 1, "%s: expected one AnimationPlayer" % n)
	var ap := players[0] as AnimationPlayer
	var clip_count := 0
	for clip in CLIPS:
		if not ap.has_animation(clip):
			_check(false, "%s: missing clip %s" % [n, clip])
			continue
		clip_count += 1
		var anim := ap.get_animation(clip)
		var expect: float = CLIPS[clip]
		_check(absf(anim.length - expect) <= expect * 0.10 + 0.034, "%s: clip %s length %.3f vs %.2f" % [n, clip, anim.length, expect])
		if LOOPS.has(clip):
			var worst := 0.0
			for t in anim.get_track_count():
				if anim.track_get_type(t) == Animation.TYPE_ROTATION_3D and anim.track_get_key_count(t) > 1:
					var a: Quaternion = anim.track_get_key_value(t, 0)
					var z: Quaternion = anim.track_get_key_value(t, anim.track_get_key_count(t) - 1)
					worst = maxf(worst, 1.0 - absf(a.dot(z)))
			_check(worst < 0.002, "%s: loop clip %s does not close (seam %.4f)" % [n, clip, worst])
	for anim_name in ap.get_animation_list():
		if not CLIPS.has(anim_name) and anim_name != "RESET":
			print("  note: %s has extra clip '%s'" % [n, anim_name])

	var meshes := _find(root, "MeshInstance3D")
	_check(meshes.size() >= 1, "%s: no mesh" % n)
	var tris := 0
	var mats := 0
	var has_color := false
	var foot_min := 1e9
	var foot_max := -1e9
	var arm_n := 0
	var torso_z := 0.0
	var torso_n := 0
	var miny := 1e9
	var maxy := -1e9
	for mi: MeshInstance3D in meshes:
		var mesh := mi.mesh
		mats += mesh.get_surface_count()
		var xf: Transform3D = _to_root(mi, root)
		for s in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(s)
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			tris += idx.size() / 3
			has_color = has_color or arrays[Mesh.ARRAY_COLOR] != null
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for v in verts:
				var p: Vector3 = xf * v
				miny = minf(miny, p.y)
				maxy = maxf(maxy, p.y)
				if p.y < 0.10 and absf(p.x) > 0.03:
					foot_min = minf(foot_min, p.z)
					foot_max = maxf(foot_max, p.z)
					arm_n += 1
				elif absf(p.x) < 0.1 and p.y > 1.1 and p.y < 1.4:
					torso_z += p.z
					torso_n += 1
	var spec: Array = SPEC[n]
	var height := maxy - miny
	_check(mats == 1, "%s: expected 1 surface/material, got %d" % [n, mats])
	_check(has_color, "%s: no vertex colours" % n)
	_check(tris <= int(spec[1]), "%s: %d tris over budget %d" % [n, tris, spec[1]])
	_check(absf(height - float(spec[0])) <= float(spec[0]) * 0.06, "%s: height %.2f vs %.2f" % [n, height, spec[0]])
	_check(absf(miny) <= 0.06, "%s: feet at y=%.3f (expected 0)" % [n, miny])
	_check(kb <= 1536, "%s: file %d KB over 1.5 MB" % [n, kb])
	var arms_forward := arm_n > 0 and (foot_min + foot_max) < -0.04
	_check(arms_forward, "%s: does not face -Z (boot toe z %.3f, heel z %.3f)" % [n, foot_min, foot_max])

	# Hand_R rest basis must match what the weapon-socket JSON was computed from (axes carry over to Godot)
	if not socket.is_empty():
		var hi := skel.find_bone("Hand_R")
		var rest := skel.get_bone_global_rest(hi).basis
		var exp: Array = socket["hand_r_rest_basis_godot_columns"]
		var worst := 0.0
		for c in 3:
			var col := Vector3(exp[c][0], exp[c][1], exp[c][2])
			worst = maxf(worst, (rest[c] - col).length())
		_check(worst < 0.05, "%s: Hand_R rest basis differs from Blender by %.3f" % [n, worst])
	print("%-8s %6d %6d %5d %6d %5d %-7.2f %s" % [n, tris, kb, bone_names.size(), clip_count, mats, height,
		"ok (boot toe z %.2f, heel z %.2f)" % [foot_min, foot_max] if arms_forward else "NO"])
	root.free()


## Transform of a node relative to the scene root (the generated scene is not in the tree).
func _to_root(node: Node3D, root: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = node
	while cur != null and cur != root:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf
