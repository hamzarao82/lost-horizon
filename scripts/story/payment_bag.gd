class_name PaymentBag
extends RefCounted
## The protagonist's payment bag as a 3D prop: the same sack, colours and gold discs as the bag in the opening
## cinematic (`OpeningCinematic._build_bag`), plus a flap that lifts and a hidden stash of gold and diamonds
## that is revealed when the flap opens. The cinematic keeps its own copy of the shape.

const OPEN_SECONDS: float = 0.9

const SACK_COLOR: Color = Color(0.4, 0.3, 0.18)
const FLAP_COLOR: Color = Color(0.3, 0.22, 0.12)
const GOLD_COLOR: Color = Color(0.95, 0.78, 0.2)
const DIAMOND_COLOR: Color = Color(0.7, 0.9, 1.0)


static func build() -> Node3D:
	var root := Node3D.new()
	root.name = "PaymentBag"
	var sack := MeshInstance3D.new()
	sack.name = "Sack"
	var sphere := SphereMesh.new()
	sphere.radius = 0.22
	sphere.height = 0.36
	sack.mesh = sphere
	var sack_mat := StandardMaterial3D.new()
	sack_mat.albedo_color = SACK_COLOR
	sack.material_override = sack_mat
	root.add_child(sack)

	var flap := MeshInstance3D.new()
	flap.name = "Flap"
	var disc := CylinderMesh.new()
	disc.top_radius = 0.15
	disc.bottom_radius = 0.15
	disc.height = 0.03
	flap.mesh = disc
	var flap_mat := StandardMaterial3D.new()
	flap_mat.albedo_color = FLAP_COLOR
	flap.material_override = flap_mat
	flap.position = Vector3(0.0, 0.17, 0.0)
	root.add_child(flap)

	var contents := Node3D.new()
	contents.name = "Contents"
	contents.visible = false
	root.add_child(contents)
	var gold_mat := StandardMaterial3D.new()
	gold_mat.albedo_color = GOLD_COLOR
	gold_mat.emission_enabled = true
	gold_mat.emission = Color(0.7, 0.5, 0.1)
	gold_mat.emission_energy_multiplier = 0.6
	for i in 4:
		var coin := MeshInstance3D.new()
		var coin_mesh := CylinderMesh.new()
		coin_mesh.top_radius = 0.05
		coin_mesh.bottom_radius = 0.05
		coin_mesh.height = 0.015
		coin.mesh = coin_mesh
		coin.material_override = gold_mat
		coin.position = Vector3(0.11 * cos(i * 1.6), 0.21 + 0.035 * i, 0.11 * sin(i * 1.6))
		contents.add_child(coin)
	var gem_mat := StandardMaterial3D.new()
	gem_mat.albedo_color = DIAMOND_COLOR
	gem_mat.emission_enabled = true
	gem_mat.emission = Color(0.5, 0.8, 1.0)
	gem_mat.emission_energy_multiplier = 0.8
	for i in 3:
		var gem := MeshInstance3D.new()
		var gem_mesh := SphereMesh.new()
		gem_mesh.radius = 0.05
		gem_mesh.height = 0.1
		gem_mesh.radial_segments = 6
		gem_mesh.rings = 3
		gem.mesh = gem_mesh
		gem.material_override = gem_mat
		gem.position = Vector3(0.09 * cos(i * 2.1 + 0.5), 0.27, 0.09 * sin(i * 2.1 + 0.5))
		contents.add_child(gem)
	return root


static func is_open(bag: Node3D) -> bool:
	var contents := bag.get_node_or_null("Contents") as Node3D
	return contents != null and contents.visible


## Lifts the flap aside and shows the gold and diamonds. Returns the tween (null when it was applied at once).
static func open(bag: Node3D, animate: bool = true) -> Tween:
	var flap := bag.get_node_or_null("Flap") as Node3D
	var contents := bag.get_node_or_null("Contents") as Node3D
	if contents != null:
		contents.visible = true
	if flap == null:
		return null
	var target_pos := Vector3(0.0, 0.1, 0.27)
	var target_rot := Vector3(deg_to_rad(80.0), 0.0, 0.0)
	if animate and bag.is_inside_tree():
		var tween := bag.create_tween()
		tween.set_parallel(true)
		tween.tween_property(flap, "position", target_pos, OPEN_SECONDS)
		tween.tween_property(flap, "rotation", target_rot, OPEN_SECONDS)
		return tween
	flap.position = target_pos
	flap.rotation = target_rot
	return null
