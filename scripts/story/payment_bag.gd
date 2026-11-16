class_name PaymentBag
extends RefCounted
## The protagonist's payment bag as a 3D prop: a leather sack with a belt, straps and a brass buckle, a lid that lifts
## cinematic (`OpeningCinematic._build_bag`), plus a flap that lifts and a hidden stash of gold and diamonds
## that is revealed when the flap opens. The cinematic keeps its own copy of the shape.

const OPEN_SECONDS: float = 0.9

const SACK_COLOR: Color = Color(0.4, 0.3, 0.18)
const FLAP_COLOR: Color = Color(0.3, 0.22, 0.12)
const GOLD_COLOR: Color = Color(0.95, 0.78, 0.2)
const DIAMOND_COLOR: Color = Color(0.7, 0.9, 1.0)


const LEATHER: Color = Color(0.34, 0.22, 0.11)
const LEATHER_LIGHT: Color = Color(0.46, 0.31, 0.16)
const STRAP: Color = Color(0.17, 0.11, 0.06)
const BRASS: Color = Color(0.78, 0.6, 0.22)


static func build() -> Node3D:
	var root := Node3D.new()
	root.name = "PaymentBag"
	var sack := MeshInstance3D.new()
	sack.name = "Sack"
	sack.mesh = _sack_mesh()
	sack.material_override = OpeningArt.material(true, 0.85, 0.0)
	root.add_child(sack)

	var flap := MeshInstance3D.new()
	flap.name = "Flap"
	var lid := ArenaDecor.Builder.new()
	lid.prism(Vector3(0.0, 0.0, 0.0), 0.17, 0.15, 0.035, 10, LEATHER_LIGHT, Basis.IDENTITY, LEATHER)
	lid.box(Vector3(0.0, 0.045, 0.1), Vector3(0.07, 0.025, 0.05), BRASS)  # the buckle on the lid
	flap.mesh = lid.finish()
	flap.material_override = OpeningArt.material(true, 0.7, 0.1)
	flap.position = Vector3(0.0, 0.17, 0.0)
	root.add_child(flap)

	var contents := Node3D.new()
	contents.name = "Contents"
	contents.visible = false
	root.add_child(contents)
	var gold := MeshInstance3D.new()
	gold.name = "Gold"
	var bars := ArenaDecor.Builder.new()
	for row in 2:
		for col in 3:
			var x := (float(col) - 1.0) * 0.085
			bars.box(Vector3(x, 0.2 + 0.045 * float(row), (-0.03 if row == 0 else 0.03)), Vector3(0.075, 0.04, 0.045), GOLD_COLOR.lightened(0.05 * float(col)),
					Basis(Vector3.UP, 0.12 * float(col - 1) + 0.2 * float(row)))
	gold.mesh = bars.finish()
	gold.material_override = _glow_material(0.7, true)
	contents.add_child(gold)
	var gems := MeshInstance3D.new()
	gems.name = "Gems"
	var cut := ArenaDecor.Builder.new()
	for i in 5:
		var angle := float(i) * 1.25 + 0.4
		var base := Vector3(0.09 * cos(angle), 0.275 + 0.01 * float(i % 2), 0.09 * sin(angle))
		cut.prism(base, 0.035, 0.0, 0.045, 6, DIAMOND_COLOR)  # crown
		cut.prism(base, 0.035, 0.0, -0.035, 6, DIAMOND_COLOR.darkened(0.15))  # pavilion
	gems.mesh = cut.finish()
	gems.material_override = _glow_material(1.1, false)
	contents.add_child(gems)
	return root


## The sack as a lathe-style stack of frustums with a belt, two straps and a buckle, all vertex-coloured.
static func _sack_mesh() -> ArrayMesh:
	var b := ArenaDecor.Builder.new()
	b.prism(Vector3(0.0, -0.2, 0.0), 0.17, 0.23, 0.12, 10, LEATHER.darkened(0.15), Basis.IDENTITY, LEATHER)
	b.prism(Vector3(0.0, -0.08, 0.0), 0.23, 0.2, 0.15, 10, LEATHER, Basis.IDENTITY, LEATHER_LIGHT)
	b.prism(Vector3(0.0, 0.07, 0.0), 0.2, 0.13, 0.11, 10, LEATHER_LIGHT, Basis.IDENTITY, LEATHER)
	b.prism(Vector3(0.0, -0.045, 0.0), 0.232, 0.232, 0.05, 10, STRAP)  # belt
	for side: float in [-0.07, 0.07]:
		b.box(Vector3(side, -0.02, 0.215), Vector3(0.035, 0.3, 0.022), STRAP)  # straps
	b.box(Vector3(0.0, -0.02, 0.232), Vector3(0.07, 0.06, 0.02), BRASS)  # buckle plate
	b.box(Vector3(0.0, -0.02, 0.246), Vector3(0.035, 0.03, 0.012), STRAP)  # buckle tongue
	return b.finish()


static func _glow_material(energy: float, metal: bool) -> StandardMaterial3D:
	var m := OpeningArt.material(true, 0.25 if metal else 0.1, 0.8 if metal else 0.2)
	m.emission_enabled = true
	m.emission = Color(0.7, 0.5, 0.1) if metal else Color(0.5, 0.8, 1.0)
	m.emission_energy_multiplier = energy
	return m


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
