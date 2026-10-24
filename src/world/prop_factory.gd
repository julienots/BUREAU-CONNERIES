class_name PropFactory
## Builds every physical prop: visual model + collision + physical properties.

const POCKET_ITEMS := {
	"duck": "canard", "banana": "banane", "buzzer": "buzzer", "stapler": "agrafeuse", "salt": "sel",
	"marker": "marqueur", "fish_box": "poisson", "mug_boss": "mug_boss", "coffee_cup": "cafe", "folder": "dossier",
}
## Inventory item -> prop kind spawned when the item is dropped in the world
const ITEM_TO_PROP := {
	"canard": "duck", "banane": "banana", "buzzer": "buzzer", "agrafeuse": "stapler", "sel": "salt",
	"marqueur": "marker", "poisson": "fish_box", "mug_boss": "mug_boss", "cafe": "coffee_cup", "dossier": "folder",
	"coussin_peteur": "cushion",
}


static func make(kind: String) -> Prop:
	var p := Prop.new()
	p.kind = kind
	p.name = kind
	var pm := PhysicsMaterial.new()
	pm.friction = 0.6
	pm.bounce = 0.1
	var vis := Node3D.new()
	vis.name = "Visual"
	p.add_child(vis)
	match kind:
		"chair", "chair_meeting":
			_chair(p, vis, pm, kind == "chair_meeting")
		"chair_boss":
			_boss_chair(p, vis, pm)
		"mug":
			_mug(p, vis, Color(0.95, 0.95, 0.95) if randf() > 0.5 else Color.from_hsv(randf(), 0.5, 0.85))
			p.display = "Tasse"
		"mug_boss":
			_mug(p, vis, Color(0.85, 0.12, 0.15))
			MeshKit.add(vis, MeshKit.cylinder(0.047, 0.03, 16), Mats.color(Color(1, 0.8, 0.2), 0.3, 0.8), Vector3(0, 0.06, 0))
			p.display = "Mug « Meilleur Chef »"
			p.tags.append("boss_mug")
			p.contraband = 0.9
		"papers":
			_box_prop(p, vis, Vector3(0.23, 0.07, 0.31), Mats.textured("paper", 1.0, 0.9, 0.0, false), 1.2, "paper")
			p.display = "Pile de documents"
			p.tags.append("papers")
		"paper_sheet":
			_box_prop(p, vis, Vector3(0.21, 0.004, 0.297), Mats.textured("paper", 1.0, 0.9, 0.0, false), 0.02, "paper", 0.0)
			p.display = "Feuille"
			p.tags.append_array(["sheet", "slippery"])
			p.set_meta("base_ldamp", 2.5)
			p.set_meta("base_adamp", 2.0)
			pm.friction = 0.25
		"box", "box_small":
			var s := Vector3(0.46, 0.36, 0.36) if kind == "box" else Vector3(0.34, 0.26, 0.28)
			_box_prop(p, vis, s, Mats.textured("cardboard", 1.0, 0.95, 0.0, false), 4.5 if kind == "box" else 2.5, "cardboard", 0.01)
			p.display = "Carton"
			p.tags.append("boxes")
			p.carry = "medium"
			p.set_meta("occludes", true)
		"trash":
			_trash(p, vis)
			p.display = "Poubelle"
			p.tags.append_array(["trash", "container"])
		"plant_small", "plant_big":
			_plant(p, vis, kind == "plant_big")
			p.display = "Plante verte"
			p.tags.append("plant")
			p.carry = "light" if kind == "plant_small" else "medium"
		"duck":
			_duck(p, vis)
			p.display = "Canard en plastique"
			p.tags.append("duck")
		"cushion":
			MeshKit.add(vis, MeshKit.sphere(0.16, 16, 0.25), Mats.color(Color(0.95, 0.4, 0.6), 0.5))
			MeshKit.add(vis, MeshKit.cylinder(0.025, 0.06, 8), Mats.color(Color(0.95, 0.4, 0.6), 0.5), Vector3(0, 0, 0.17), Vector3(90, 0, 0))
			_shape_box(p, Vector3(0.3, 0.06, 0.3))
			p.mass = 0.2
			p.mat_kind = "fabric"
			p.display = "Coussin péteur"
			p.tags.append("cushion")
			p.contraband = 0.9
		"banana":
			var ym := Mats.color(Color(0.98, 0.85, 0.2), 0.6)
			for i in 3:
				var a := (i - 1) * 25.0
				MeshKit.add(vis, MeshKit.capsule(0.022, 0.1), ym, Vector3(sin(deg_to_rad(a)) * 0.08, 0.02, 0), Vector3(0, 0, 90 + a))
			_shape_box(p, Vector3(0.22, 0.04, 0.06))
			p.mass = 0.12
			p.display = "Peau de banane"
			p.tags.append_array(["banana", "slippery"])
			pm.friction = 0.05
		"buzzer":
			MeshKit.add_box(vis, Vector3(0.12, 0.05, 0.12), Mats.color(Color(0.1, 0.1, 0.1)), Vector3(0, 0.025, 0), 0.015)
			MeshKit.add(vis, MeshKit.cylinder(0.035, 0.025, 16), Mats.color(Color(0.9, 0.1, 0.1), 0.4), Vector3(0, 0.06, 0))
			_shape_box(p, Vector3(0.12, 0.07, 0.12), Vector3(0, 0.035, 0))
			p.mass = 0.3
			p.display = "Buzzer"
			p.tags.append("buzzer")
			p.contraband = 0.6
		"stapler":
			MeshKit.add_box(vis, Vector3(0.05, 0.02, 0.17), Mats.color(Color(0.15, 0.15, 0.15), 0.4, 0.5), Vector3(0, 0.01, 0), 0.006)
			MeshKit.add_box(vis, Vector3(0.045, 0.03, 0.16), Mats.color(Color(0.8, 0.1, 0.1), 0.35), Vector3(0, 0.035, -0.005), 0.01, Vector3(-4, 0, 0))
			_shape_box(p, Vector3(0.05, 0.05, 0.17), Vector3(0, 0.025, 0))
			p.mass = 0.4
			p.mat_kind = "metal"
			p.display = "Agrafeuse rouge"
			p.tags.append("stapler")
		"salt":
			MeshKit.add(vis, MeshKit.cylinder(0.025, 0.09, 12), Mats.color(Color(0.95, 0.95, 0.95), 0.3), Vector3(0, 0.045, 0))
			MeshKit.add(vis, MeshKit.sphere(0.026, 12, 0.6), Mats.color(Color(0.7, 0.7, 0.75), 0.3, 0.8), Vector3(0, 0.09, 0))
			_shape_box(p, Vector3(0.05, 0.11, 0.05), Vector3(0, 0.055, 0))
			p.mass = 0.15
			p.mat_kind = "ceramic"
			p.display = "Salière"
		"marker":
			MeshKit.add(vis, MeshKit.cylinder(0.01, 0.13, 8), Mats.color(Color(0.95, 0.95, 0.95)), Vector3.ZERO, Vector3(0, 0, 90))
			MeshKit.add(vis, MeshKit.cylinder(0.011, 0.04, 8), Mats.color(Color(0.1, 0.2, 0.8)), Vector3(0.06, 0, 0), Vector3(0, 0, 90))
			_shape_box(p, Vector3(0.14, 0.022, 0.022))
			p.mass = 0.05
			p.display = "Marqueur"
		"fish_box":
			MeshKit.add_box(vis, Vector3(0.18, 0.07, 0.12), Mats.color(Color(0.85, 0.9, 0.95, 1), 0.3), Vector3(0, 0.035, 0), 0.015)
			MeshKit.add_box(vis, Vector3(0.185, 0.015, 0.125), Mats.color(Color(0.2, 0.5, 0.9), 0.4), Vector3(0, 0.075, 0), 0.006)
			_shape_box(p, Vector3(0.18, 0.085, 0.12), Vector3(0, 0.04, 0))
			p.mass = 0.4
			p.display = "Poisson de Gérard"
			p.tags.append("fish")
		"coffee_cup":
			_mug(p, vis, Color(0.95, 0.95, 0.95))
			MeshKit.add(vis, MeshKit.cylinder(0.041, 0.005, 16), Mats.color(Color(0.3, 0.17, 0.08), 0.2), Vector3(0, 0.09, 0))
			p.display = "Café"
			p.tags.append("coffee")
		"folder":
			_box_prop(p, vis, Vector3(0.24, 0.03, 0.32), Mats.color(Color(0.95, 0.75, 0.3), 0.7), 0.5, "paper")
			p.display = "Dossier urgent"
		"binder":
			_box_prop(p, vis, Vector3(0.07, 0.3, 0.26), Mats.color(Color.from_hsv(randf(), 0.6, 0.6), 0.5), 0.7, "plastic")
			p.display = "Classeur"
		"shard":
			_box_prop(p, vis, Vector3(0.03, 0.01, 0.04), Mats.color(Color(0.9, 0.9, 0.9), 0.3), 0.02, "ceramic", 0.0)
		_:
			push_warning("unknown prop kind " + kind)
			_box_prop(p, vis, Vector3(0.2, 0.2, 0.2), Mats.color(Color.MAGENTA), 1.0, "plastic")
	if POCKET_ITEMS.has(kind):
		p.pocketable = true
		p.item_id = POCKET_ITEMS[kind]
		if p.contraband == 0.0:
			p.contraband = float(Data.item_info(p.item_id).get("contraband", 0.0))
	p.physics_material_override = pm
	p.linear_damp = p.get_meta("base_ldamp", 0.1)
	p.angular_damp = p.get_meta("base_adamp", 0.3)
	p.set_meta("base_ldamp", p.linear_damp)
	p.set_meta("base_adamp", p.angular_damp)
	if p.mass < 0.5:
		p.continuous_cd = true
	var layer := Layers.PROPS | (Layers.OCCLUDERS if p.get_meta("occludes", false) else 0)
	p.collision_layer = layer
	p.collision_mask = Layers.STATIC | Layers.PROPS | Layers.CHARACTERS
	p.set_meta("base_layer", layer)
	p.set_meta("base_mask", p.collision_mask)
	return p


static func _shape_box(p: Prop, size: Vector3, pos := Vector3.ZERO) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	cs.position = pos
	p.add_child(cs)
	return cs


static func _box_prop(p: Prop, vis: Node3D, size: Vector3, mat: Material, mass: float, mk: String, r := 0.006) -> void:
	MeshKit.add(vis, MeshKit.rounded_box(size, r, 2), mat, Vector3(0, size.y * 0.5, 0))
	_shape_box(p, size, Vector3(0, size.y * 0.5, 0))
	p.mass = mass
	p.mat_kind = mk


static func _chair(p: Prop, vis: Node3D, pm: PhysicsMaterial, meeting: bool) -> void:
	var fabric := Mats.textured("fabric", 2.0, 0.95, 0.0, true, Color(0.55, 0.62, 0.8) if meeting else Color(0.8, 0.8, 0.85))
	var dark := Mats.color(Color(0.13, 0.13, 0.15), 0.5, 0.3)
	var chrome := Mats.color(Color(0.75, 0.76, 0.8), 0.25, 0.9)
	for i in 5:
		var a := TAU * i / 5.0
		var leg := MeshKit.add_box(vis, Vector3(0.05, 0.035, 0.3), dark, Vector3(sin(a) * 0.14, 0.07, cos(a) * 0.14), 0.012)
		leg.rotation.y = a
		MeshKit.add(vis, MeshKit.sphere(0.03, 8), dark, Vector3(sin(a) * 0.29, 0.03, cos(a) * 0.29))
	MeshKit.add(vis, MeshKit.cylinder(0.025, 0.3, 12), chrome, Vector3(0, 0.25, 0))
	var seat := Node3D.new()
	vis.add_child(seat)
	MeshKit.add_box(seat, Vector3(0.48, 0.08, 0.46), fabric, Vector3(0, 0.45, 0), 0.035)
	MeshKit.add_box(seat, Vector3(0.44, 0.5, 0.07), fabric, Vector3(0, 0.78, 0.24), 0.035, Vector3(-8, 0, 0))
	MeshKit.add_box(seat, Vector3(0.06, 0.25, 0.04), dark, Vector3(0, 0.55, 0.24), 0.01)
	for sx in [-1, 1]:
		MeshKit.add_box(seat, Vector3(0.04, 0.03, 0.26), dark, Vector3(sx * 0.25, 0.64, 0.02), 0.012)
		MeshKit.add_box(seat, Vector3(0.025, 0.17, 0.025), dark, Vector3(sx * 0.25, 0.55, 0.08), 0.008)
	p.seat_mesh = seat
	_shape_box(p, Vector3(0.6, 0.1, 0.6), Vector3(0, 0.06, 0))
	_shape_box(p, Vector3(0.48, 0.1, 0.46), Vector3(0, 0.45, 0))
	_shape_box(p, Vector3(0.44, 0.5, 0.08), Vector3(0, 0.78, 0.25))
	var pole := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.04
	cyl.height = 0.3
	pole.shape = cyl
	pole.position = Vector3(0, 0.25, 0)
	p.add_child(pole)
	p.mass = 12.0
	p.mat_kind = "chair"
	p.carry = "medium"
	p.seat_height = 0.5
	p.display = "Chaise de bureau"
	p.tags.append("chair")
	p.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	p.center_of_mass = Vector3(0, 0.22, 0)
	pm.friction = 0.18
	pm.bounce = 0.05
	p.set_meta("base_ldamp", 0.6)
	p.set_meta("base_adamp", 1.2)


static func _boss_chair(p: Prop, vis: Node3D, pm: PhysicsMaterial) -> void:
	var leather := Mats.textured("leather", 2.0, 0.45, 0.0, true)
	var dark := Mats.color(Color(0.1, 0.1, 0.1), 0.4, 0.5)
	for i in 5:
		var a := TAU * i / 5.0
		var leg := MeshKit.add_box(vis, Vector3(0.06, 0.04, 0.34), dark, Vector3(sin(a) * 0.16, 0.07, cos(a) * 0.16), 0.015)
		leg.rotation.y = a
		MeshKit.add(vis, MeshKit.sphere(0.035, 8), dark, Vector3(sin(a) * 0.33, 0.035, cos(a) * 0.33))
	MeshKit.add(vis, MeshKit.cylinder(0.03, 0.3, 12), Mats.color(Color(0.8, 0.8, 0.82), 0.2, 0.9), Vector3(0, 0.25, 0))
	var seat := Node3D.new()
	vis.add_child(seat)
	MeshKit.add_box(seat, Vector3(0.58, 0.12, 0.54), leather, Vector3(0, 0.47, 0), 0.05)
	MeshKit.add_box(seat, Vector3(0.56, 0.85, 0.12), leather, Vector3(0, 0.98, 0.28), 0.06, Vector3(-10, 0, 0))
	MeshKit.add_box(seat, Vector3(0.36, 0.14, 0.1), leather, Vector3(0, 1.36, 0.36), 0.05, Vector3(-10, 0, 0))
	for sx in [-1, 1]:
		MeshKit.add_box(seat, Vector3(0.08, 0.08, 0.42), leather, Vector3(sx * 0.32, 0.68, 0.04), 0.03)
	p.seat_mesh = seat
	_shape_box(p, Vector3(0.68, 0.1, 0.68), Vector3(0, 0.06, 0))
	_shape_box(p, Vector3(0.58, 0.14, 0.54), Vector3(0, 0.47, 0))
	_shape_box(p, Vector3(0.56, 0.9, 0.14), Vector3(0, 1.0, 0.29))
	p.mass = 20.0
	p.mat_kind = "chair"
	p.carry = "medium"
	p.seat_height = 0.54
	p.display = "Fauteuil du directeur"
	p.tags.append_array(["chair", "boss_chair"])
	p.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	p.center_of_mass = Vector3(0, 0.22, 0)
	pm.friction = 0.2
	p.set_meta("base_ldamp", 0.8)
	p.set_meta("base_adamp", 1.5)


static func _mug(p: Prop, vis: Node3D, c: Color) -> void:
	var m := Mats.color(c, 0.25)
	MeshKit.add(vis, MeshKit.cylinder(0.042, 0.095, 16), m, Vector3(0, 0.0475, 0))
	MeshKit.add(vis, MeshKit.torus(0.018, 0.03, 12), m, Vector3(0.05, 0.05, 0), Vector3(90, 0, 0))
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.045
	cyl.height = 0.095
	cs.shape = cyl
	cs.position = Vector3(0, 0.0475, 0)
	p.add_child(cs)
	p.mass = 0.3
	p.mat_kind = "ceramic"
	p.fragile = true


static func _trash(p: Prop, vis: Node3D) -> void:
	var m := Mats.textured("metal", 2.0, 0.45, 0.6, true, Color(0.5, 0.52, 0.56))
	MeshKit.add(vis, MeshKit.cylinder(0.14, 0.38, 20, 0.17), m, Vector3(0, 0.19, 0))
	MeshKit.add(vis, MeshKit.torus(0.165, 0.18, 20), m, Vector3(0, 0.38, 0))
	MeshKit.add(vis, MeshKit.sphere(0.06, 8), Mats.textured("paper", 1.0, 0.9, 0.0, false), Vector3(0.04, 0.34, 0.02))
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.16
	cyl.height = 0.38
	cs.shape = cyl
	cs.position = Vector3(0, 0.19, 0)
	p.add_child(cs)
	p.mass = 2.5
	p.mat_kind = "metal"


static func _plant(p: Prop, vis: Node3D, big: bool) -> void:
	var s := 1.6 if big else 1.0
	var pot := Mats.color(Color(0.75, 0.42, 0.25), 0.8)
	MeshKit.add(vis, MeshKit.cylinder(0.13 * s, 0.26 * s, 16, 0.16 * s), pot, Vector3(0, 0.13 * s, 0))
	MeshKit.add(vis, MeshKit.cylinder(0.15 * s, 0.02, 16), Mats.color(Color(0.25, 0.17, 0.1), 1.0), Vector3(0, 0.255 * s, 0))
	var greens := [Color(0.2, 0.55, 0.25), Color(0.25, 0.65, 0.3), Color(0.15, 0.45, 0.2)]
	var rng := RandomNumberGenerator.new()
	rng.seed = 42 if big else 7
	for i in (14 if big else 8):
		var a := rng.randf() * TAU
		var h := rng.randf_range(0.35, 0.8) * s
		var r := rng.randf_range(0.02, 0.14) * s
		var leaf := MeshKit.add(vis, MeshKit.sphere(0.09 * s, 10, 0.45), Mats.color(greens[i % 3], 0.7), Vector3(cos(a) * r, h, sin(a) * r))
		leaf.rotation = Vector3(rng.randf_range(-0.6, 0.6), a, rng.randf_range(-0.8, 0.8))
		leaf.scale = Vector3(1.0, 1.0, 2.2)
	MeshKit.add(vis, MeshKit.cylinder(0.012 * s, 0.6 * s, 6), Mats.color(Color(0.3, 0.4, 0.2)), Vector3(0, 0.5 * s, 0))
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.16 * s
	cyl.height = 0.9 * s
	cs.shape = cyl
	cs.position = Vector3(0, 0.45 * s, 0)
	p.add_child(cs)
	p.mass = 14.0 if big else 3.0
	p.mat_kind = "ceramic"
	p.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	p.center_of_mass = Vector3(0, 0.15 * s, 0)
	if big:
		p.set_meta("occludes", true)


static func _duck(p: Prop, vis: Node3D) -> void:
	var y := Mats.color(Color(1.0, 0.82, 0.1), 0.35)
	MeshKit.add(vis, MeshKit.sphere(0.06, 14, 0.8), y, Vector3(0, 0.05, 0)).scale = Vector3(1, 1, 1.3)
	MeshKit.add(vis, MeshKit.sphere(0.04, 12), y, Vector3(0, 0.12, -0.04))
	MeshKit.add(vis, MeshKit.sphere(0.022, 8, 0.5), Mats.color(Color(1, 0.45, 0.05), 0.4), Vector3(0, 0.115, -0.085)).scale = Vector3(1, 1, 1.6)
	for sx in [-1, 1]:
		MeshKit.add(vis, MeshKit.sphere(0.008, 6), Mats.color(Color.BLACK, 0.2), Vector3(sx * 0.022, 0.13, -0.07))
	_shape_box(p, Vector3(0.11, 0.16, 0.15), Vector3(0, 0.08, 0))
	p.mass = 0.12
	p.mat_kind = "rubber"
