class_name Furniture
## Static furniture models (visual + collision). Everything is parented to a pivot whose
## local -Z is the "front" of the piece.

const BLOCK := Layers.STATIC | Layers.OCCLUDERS | Layers.SOUND


static func pivot(parent: Node3D, pos: Vector3, rot_y_deg := 0.0, name := "") -> Node3D:
	var n := Node3D.new()
	if name != "":
		n.name = name
	parent.add_child(n)
	n.position = pos
	n.rotation_degrees.y = rot_y_deg
	return n


static func solid(parent: Node3D, size: Vector3, pos: Vector3, layers := Layers.STATIC | Layers.OCCLUDERS, rot := Vector3.ZERO) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = layers
	sb.collision_mask = 0
	sb.position = pos
	sb.rotation_degrees = rot
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	sb.add_child(cs)
	parent.add_child(sb)
	return sb


static func wood() -> Material:
	return Mats.textured("wood", 1.5, 0.55)


static func metal(c := Color(0.6, 0.62, 0.66)) -> Material:
	return Mats.textured("metal", 2.0, 0.4, 0.5, true, c)


## Office desk with modesty panel, partition, drawer pedestal, monitor, keyboard, mouse,
## phone and clutter. Returns handles for devices.
static func desk(parent: Node3D, pos: Vector3, rot_y: float, rng: RandomNumberGenerator, occupied: bool) -> Dictionary:
	var p := pivot(parent, pos, rot_y)
	var top := wood()
	var frame := Mats.color(Color(0.2, 0.21, 0.23), 0.4, 0.6)
	MeshKit.add_box(p, Vector3(1.6, 0.04, 0.78), top, Vector3(0, 0.74, 0), 0.012)
	for sx in [-1, 1]:
		MeshKit.add_box(p, Vector3(0.05, 0.72, 0.7), frame, Vector3(sx * 0.76, 0.36, 0), 0.01)
	MeshKit.add_box(p, Vector3(1.48, 0.4, 0.02), frame, Vector3(0, 0.5, -0.36), 0.005)
	solid(p, Vector3(1.6, 0.06, 0.78), Vector3(0, 0.74, 0))
	solid(p, Vector3(0.06, 0.72, 0.7), Vector3(-0.76, 0.36, 0))
	solid(p, Vector3(0.06, 0.72, 0.7), Vector3(0.76, 0.36, 0))
	solid(p, Vector3(1.48, 0.4, 0.04), Vector3(0, 0.5, -0.36))
	# fabric partition at the back
	var fab := Mats.textured("fabric", 1.5, 0.95)
	MeshKit.add_box(p, Vector3(1.6, 0.5, 0.05), fab, Vector3(0, 1.0, -0.42), 0.02)
	MeshKit.add_box(p, Vector3(1.62, 0.03, 0.07), frame, Vector3(0, 1.26, -0.42), 0.01)
	solid(p, Vector3(1.6, 0.55, 0.06), Vector3(0, 0.98, -0.42))
	# drawer pedestal (container)
	var ped := MeshKit.add_box(p, Vector3(0.4, 0.58, 0.55), Mats.color(Color(0.82, 0.83, 0.85), 0.5), Vector3(0.5, 0.3, -0.05), 0.01)
	for k in 3:
		MeshKit.add_box(p, Vector3(0.36, 0.16, 0.01), Mats.color(Color(0.88, 0.89, 0.9), 0.5), Vector3(0.5, 0.12 + k * 0.18, 0.225), 0.004)
		MeshKit.add_box(p, Vector3(0.1, 0.015, 0.02), frame, Vector3(0.5, 0.17 + k * 0.18, 0.24), 0.005)
	solid(p, Vector3(0.4, 0.58, 0.55), Vector3(0.5, 0.3, -0.05))
	# monitor
	var mon := Node3D.new()
	p.add_child(mon)
	mon.position = Vector3(-0.05, 0.76, -0.2)
	MeshKit.add_box(mon, Vector3(0.22, 0.015, 0.16), frame, Vector3(0, 0.008, 0), 0.006)
	MeshKit.add_box(mon, Vector3(0.04, 0.22, 0.03), frame, Vector3(0, 0.12, 0.02), 0.008)
	MeshKit.add_box(mon, Vector3(0.62, 0.38, 0.03), Mats.color(Color(0.08, 0.08, 0.09), 0.3), Vector3(0, 0.36, 0), 0.012)
	var screen := MeshKit.add(mon, MeshKit.quad(Vector2(0.58, 0.34)), Mats.screen("screen_work"), Vector3(0, 0.36, 0.0165), Vector3.ZERO, false)
	# keyboard + mouse
	MeshKit.add_box(p, Vector3(0.44, 0.02, 0.15), Mats.color(Color(0.15, 0.15, 0.17), 0.5), Vector3(-0.05, 0.77, 0.12), 0.006)
	MeshKit.add(p, MeshKit.quad(Vector2(0.42, 0.13)), Mats.decal_tex("keyboard_albedo"), Vector3(-0.05, 0.781, 0.12), Vector3(-90, 0, 0), false)
	MeshKit.add(p, MeshKit.sphere(0.03, 10, 0.5), Mats.color(Color(0.15, 0.15, 0.17), 0.4), Vector3(0.28, 0.77, 0.12)).scale = Vector3(0.8, 1, 1.3)
	# desk phone
	var phone := Node3D.new()
	p.add_child(phone)
	phone.position = Vector3(-0.6, 0.76, -0.15)
	MeshKit.add_box(phone, Vector3(0.18, 0.05, 0.16), Mats.color(Color(0.2, 0.2, 0.22), 0.5), Vector3(0, 0.025, 0), 0.015, Vector3(-12, 0, 0))
	MeshKit.add_box(phone, Vector3(0.05, 0.04, 0.18), Mats.color(Color(0.15, 0.15, 0.16), 0.5), Vector3(-0.07, 0.07, 0), 0.015)
	# cable bundle under desk
	MeshKit.add(p, MeshKit.cylinder(0.012, 0.75, 6), Mats.color(Color(0.05, 0.05, 0.05)), Vector3(-0.2, 0.37, -0.33), Vector3(0, 0, 4))
	# clutter
	if occupied or rng.randf() < 0.5:
		var c := rng.randi() % 4
		match c:
			0:
				MeshKit.add_box(p, Vector3(0.12, 0.16, 0.02), Mats.color(Color(0.3, 0.2, 0.1), 0.6), Vector3(0.35, 0.84, -0.25), 0.005, Vector3(-10, -20, 0))
			1:
				MeshKit.add(p, MeshKit.cylinder(0.035, 0.1, 10), Mats.color(Color.from_hsv(rng.randf(), 0.4, 0.8)), Vector3(0.62, 0.81, -0.28))
				for k in 4:
					MeshKit.add(p, MeshKit.cylinder(0.004, 0.14, 4), Mats.color(Color.from_hsv(rng.randf(), 0.7, 0.8)), Vector3(0.62 + (k - 1.5) * 0.01, 0.88, -0.28), Vector3(rng.randf_range(-12, 12), 0, rng.randf_range(-12, 12)))
			2:
				MeshKit.add(p, MeshKit.sphere(0.04, 10), Mats.color(Color.from_hsv(rng.randf(), 0.7, 0.9)), Vector3(0.65, 0.8, -0.25))
				MeshKit.add(p, MeshKit.sphere(0.03, 10), Mats.color(Color(0.95, 0.85, 0.7)), Vector3(0.65, 0.86, -0.25))
			3:
				for k in 3:
					MeshKit.add_box(p, Vector3(0.04, 0.03, 0.04), Mats.color(Color.from_hsv(rng.randf(), 0.6, 0.9)), Vector3(0.3 + k * 0.05, 0.775, -0.3), 0.004)
	# post-it on monitor bezel
	MeshKit.add(mon, MeshKit.quad(Vector2(0.05, 0.05)), Mats.color(Color(1.0, 0.92, 0.35)), Vector3(0.27, 0.5, 0.017), Vector3(0, 0, rng.randf_range(-10, 10)), false)
	return {"pivot": p, "screen": screen, "monitor": mon, "phone": phone, "pedestal": ped}


static func filing_cabinet(parent: Node3D, pos: Vector3, rot_y: float, h := 1.3) -> Node3D:
	var p := pivot(parent, pos, rot_y)
	var m := Mats.color(Color(0.55, 0.58, 0.6), 0.45, 0.4)
	MeshKit.add_box(p, Vector3(0.48, h, 0.6), m, Vector3(0, h * 0.5, 0), 0.01)
	var n := int(h / 0.32)
	for k in n:
		MeshKit.add_box(p, Vector3(0.42, 0.28, 0.01), Mats.color(Color(0.6, 0.63, 0.65), 0.4, 0.4), Vector3(0, 0.18 + k * 0.32, -0.3), 0.004)
		MeshKit.add_box(p, Vector3(0.12, 0.02, 0.03), Mats.color(Color(0.3, 0.3, 0.32), 0.3, 0.8), Vector3(0, 0.26 + k * 0.32, -0.31), 0.006)
	solid(p, Vector3(0.48, h, 0.6), Vector3(0, h * 0.5, 0))
	return p


static func shelf(parent: Node3D, pos: Vector3, rot_y: float, w := 1.8, h := 2.0, rng: RandomNumberGenerator = null, boxes := false) -> Node3D:
	var p := pivot(parent, pos, rot_y)
	var m := metal(Color(0.45, 0.48, 0.52)) if boxes else wood()
	var d := 0.45
	for sx in [-1, 1]:
		MeshKit.add_box(p, Vector3(0.04, h, d), m, Vector3(sx * w * 0.5, h * 0.5, 0), 0.008)
	var levels := 5
	for k in levels:
		var y := 0.08 + k * (h - 0.1) / (levels - 1)
		MeshKit.add_box(p, Vector3(w, 0.03, d), m, Vector3(0, y, 0), 0.006)
		if k == levels - 1 or rng == null:
			continue
		var x := -w * 0.5 + 0.06
		while x < w * 0.5 - 0.12:
			if boxes:
				var bw := rng.randf_range(0.3, 0.42)
				if x + bw > w * 0.5 - 0.05:
					break
				MeshKit.add_box(p, Vector3(bw - 0.02, 0.28, 0.36), Mats.textured("cardboard", 1.0, 0.95, 0.0, false), Vector3(x + bw * 0.5, y + 0.155, 0), 0.008)
				x += bw
			else:
				var bw := rng.randf_range(0.05, 0.09)
				var bh := rng.randf_range(0.24, 0.32)
				MeshKit.add_box(p, Vector3(bw - 0.006, bh, 0.28), Mats.color(Color.from_hsv(rng.randf(), rng.randf_range(0.3, 0.7), rng.randf_range(0.4, 0.8)), 0.5), Vector3(x + bw * 0.5, y + 0.015 + bh * 0.5, 0), 0.004)
				x += bw
				if rng.randf() < 0.08:
					x += 0.15
	solid(p, Vector3(w + 0.04, h, d), Vector3(0, h * 0.5, 0))
	return p


static func table(parent: Node3D, pos: Vector3, size: Vector3, mat: Material, rot_y := 0.0) -> Node3D:
	var p := pivot(parent, pos, rot_y)
	MeshKit.add_box(p, Vector3(size.x, 0.05, size.z), mat, Vector3(0, size.y, 0), 0.02)
	var leg := Mats.color(Color(0.2, 0.2, 0.22), 0.35, 0.7)
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			MeshKit.add(p, MeshKit.cylinder(0.03, size.y, 10), leg, Vector3(sx * (size.x * 0.5 - 0.12), size.y * 0.5, sz * (size.z * 0.5 - 0.12)))
	solid(p, Vector3(size.x, 0.06, size.z), Vector3(0, size.y, 0), Layers.STATIC)
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			solid(p, Vector3(0.08, size.y, 0.08), Vector3(sx * (size.x * 0.5 - 0.12), size.y * 0.5, sz * (size.z * 0.5 - 0.12)), Layers.STATIC)
	return p


static func round_table(parent: Node3D, pos: Vector3, r := 0.6) -> Node3D:
	var p := pivot(parent, pos)
	MeshKit.add(p, MeshKit.cylinder(r, 0.04, 28), Mats.color(Color(0.95, 0.95, 0.93), 0.3), Vector3(0, 0.74, 0))
	MeshKit.add(p, MeshKit.cylinder(0.05, 0.72, 12), Mats.color(Color(0.2, 0.2, 0.22), 0.3, 0.8), Vector3(0, 0.37, 0))
	MeshKit.add(p, MeshKit.cylinder(0.3, 0.03, 20), Mats.color(Color(0.2, 0.2, 0.22), 0.3, 0.8), Vector3(0, 0.015, 0))
	var sb := StaticBody3D.new()
	sb.collision_layer = Layers.STATIC
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = r
	cyl.height = 0.76
	cs.shape = cyl
	cs.position = Vector3(0, 0.38, 0)
	sb.add_child(cs)
	p.add_child(sb)
	return p


static func sofa(parent: Node3D, pos: Vector3, rot_y: float, c: Color, w := 1.9) -> Node3D:
	var p := pivot(parent, pos, rot_y)
	var m := Mats.textured("fabric", 2.0, 0.95, 0.0, true, c)
	MeshKit.add_box(p, Vector3(w, 0.4, 0.85), m, Vector3(0, 0.2, 0), 0.06)
	MeshKit.add_box(p, Vector3(w, 0.5, 0.2), m, Vector3(0, 0.6, 0.33), 0.08)
	for sx in [-1, 1]:
		MeshKit.add_box(p, Vector3(0.2, 0.3, 0.85), m, Vector3(sx * (w * 0.5 - 0.1), 0.5, 0), 0.08)
	for k in 2:
		MeshKit.add_box(p, Vector3(w * 0.5 - 0.25, 0.12, 0.6), m, Vector3((k - 0.5) * (w * 0.5 - 0.2), 0.46, -0.05), 0.05)
	solid(p, Vector3(w, 0.5, 0.85), Vector3(0, 0.25, 0))
	solid(p, Vector3(w, 0.9, 0.2), Vector3(0, 0.45, 0.33))
	return p


static func counter(parent: Node3D, pos: Vector3, rot_y: float, w: float) -> Node3D:
	var p := pivot(parent, pos, rot_y)
	var cab := Mats.color(Color(0.93, 0.93, 0.9), 0.5)
	MeshKit.add_box(p, Vector3(w, 0.86, 0.62), cab, Vector3(0, 0.43, 0), 0.01)
	MeshKit.add_box(p, Vector3(w + 0.02, 0.04, 0.65), Mats.textured("concrete", 2.0, 0.35, 0.0, true, Color(0.6, 0.58, 0.55)), Vector3(0, 0.88, 0), 0.008)
	var n := int(w / 0.6)
	for k in n:
		var x := -w * 0.5 + 0.3 + k * 0.6
		MeshKit.add_box(p, Vector3(0.56, 0.7, 0.01), Mats.color(Color(0.96, 0.96, 0.94), 0.4), Vector3(x, 0.42, -0.315), 0.004)
		MeshKit.add_box(p, Vector3(0.12, 0.015, 0.02), Mats.color(Color(0.3, 0.3, 0.32), 0.3, 0.8), Vector3(x, 0.72, -0.33), 0.005)
	solid(p, Vector3(w, 0.9, 0.62), Vector3(0, 0.45, 0))
	return p


static func fridge(parent: Node3D, pos: Vector3, rot_y: float) -> Node3D:
	var p := pivot(parent, pos, rot_y)
	var m := Mats.color(Color(0.88, 0.9, 0.92), 0.25, 0.3)
	MeshKit.add_box(p, Vector3(0.7, 1.85, 0.68), m, Vector3(0, 0.925, 0), 0.04)
	MeshKit.add_box(p, Vector3(0.66, 0.01, 0.01), Mats.color(Color(0.5, 0.5, 0.5)), Vector3(0, 1.25, -0.345), 0.003)
	for y in [0.9, 1.55]:
		MeshKit.add_box(p, Vector3(0.03, 0.3, 0.04), Mats.color(Color(0.7, 0.7, 0.72), 0.2, 0.9), Vector3(-0.28, y, -0.36), 0.01)
	# magnets & note
	MeshKit.add(p, MeshKit.quad(Vector2(0.12, 0.12)), Mats.color(Color(1, 0.95, 0.5)), Vector3(0.1, 1.5, -0.341), Vector3(0, 180, 4), false)
	solid(p, Vector3(0.7, 1.85, 0.68), Vector3(0, 0.925, 0))
	return p


static func coffee_machine(parent: Node3D, pos: Vector3, rot_y: float) -> Node3D:
	var p := pivot(parent, pos, rot_y)
	MeshKit.add_box(p, Vector3(0.38, 0.5, 0.42), Mats.color(Color(0.12, 0.12, 0.13), 0.3, 0.4), Vector3(0, 0.25, 0), 0.03)
	MeshKit.add_box(p, Vector3(0.3, 0.12, 0.02), Mats.emissive(Color(0.3, 0.7, 1.0), 1.2), Vector3(0, 0.4, -0.215), 0.01)
	MeshKit.add(p, MeshKit.cylinder(0.04, 0.09, 12), Mats.color(Color(0.95, 0.95, 0.95), 0.2), Vector3(0, 0.08, -0.12))
	MeshKit.add_box(p, Vector3(0.2, 0.02, 0.12), Mats.color(Color(0.6, 0.6, 0.62), 0.2, 0.9), Vector3(0, 0.02, -0.14), 0.005)
	return p


static func microwave(parent: Node3D, pos: Vector3, rot_y: float) -> Node3D:
	var p := pivot(parent, pos, rot_y)
	MeshKit.add_box(p, Vector3(0.5, 0.3, 0.38), Mats.color(Color(0.85, 0.85, 0.87), 0.3, 0.3), Vector3(0, 0.15, 0), 0.02)
	MeshKit.add_box(p, Vector3(0.32, 0.22, 0.01), Mats.color(Color(0.1, 0.1, 0.12), 0.1), Vector3(-0.06, 0.15, -0.19), 0.005)
	MeshKit.add_box(p, Vector3(0.08, 0.04, 0.01), Mats.emissive(Color(0.2, 1.0, 0.3), 1.0), Vector3(0.17, 0.22, -0.19), 0.003)
	return p


static func radio(parent: Node3D, pos: Vector3, rot_y: float) -> Node3D:
	var p := pivot(parent, pos, rot_y)
	MeshKit.add_box(p, Vector3(0.36, 0.2, 0.14), Mats.color(Color(0.7, 0.25, 0.2), 0.4), Vector3(0, 0.1, 0), 0.04)
	MeshKit.add(p, MeshKit.cylinder(0.06, 0.01, 16), Mats.color(Color(0.15, 0.15, 0.15), 0.8), Vector3(-0.08, 0.1, -0.072), Vector3(90, 0, 0))
	MeshKit.add(p, MeshKit.cylinder(0.015, 0.02, 8), Mats.color(Color(0.9, 0.85, 0.7), 0.3, 0.6), Vector3(0.1, 0.12, -0.075), Vector3(90, 0, 0))
	MeshKit.add(p, MeshKit.cylinder(0.004, 0.3, 4), Mats.color(Color(0.8, 0.8, 0.8), 0.2, 0.9), Vector3(0.14, 0.32, 0.03), Vector3(0, 0, -20))
	return p


static func printer(parent: Node3D, pos: Vector3, rot_y: float) -> Node3D:
	var p := pivot(parent, pos, rot_y)
	var body := Mats.color(Color(0.9, 0.9, 0.88), 0.4)
	MeshKit.add_box(p, Vector3(0.9, 0.8, 0.7), body, Vector3(0, 0.4, 0), 0.03)
	MeshKit.add_box(p, Vector3(0.92, 0.25, 0.72), Mats.color(Color(0.3, 0.32, 0.36), 0.4), Vector3(0, 0.95, 0), 0.03)
	MeshKit.add_box(p, Vector3(0.5, 0.03, 0.3), Mats.color(Color(0.3, 0.32, 0.36), 0.4), Vector3(0.1, 0.84, -0.42), 0.01)
	MeshKit.add_box(p, Vector3(0.22, 0.12, 0.02), Mats.emissive(Color(0.4, 0.8, 1.0), 1.0), Vector3(-0.28, 1.0, -0.36), 0.01, Vector3(-25, 0, 0))
	for k in 3:
		MeshKit.add_box(p, Vector3(0.84, 0.01, 0.01), Mats.color(Color(0.6, 0.6, 0.6)), Vector3(0, 0.2 + k * 0.2, -0.351), 0.003)
	solid(p, Vector3(0.92, 1.1, 0.72), Vector3(0, 0.55, 0))
	return p


static func vending(parent: Node3D, pos: Vector3, rot_y: float) -> Node3D:
	var p := pivot(parent, pos, rot_y)
	MeshKit.add_box(p, Vector3(0.9, 1.85, 0.8), Mats.color(Color(0.75, 0.12, 0.15), 0.3, 0.2), Vector3(0, 0.925, 0), 0.03)
	MeshKit.add_box(p, Vector3(0.6, 1.3, 0.02), Mats.glass(), Vector3(-0.1, 1.1, -0.405), 0.01)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for r in 5:
		for c in 4:
			MeshKit.add_box(p, Vector3(0.1, 0.16, 0.08), Mats.color(Color.from_hsv(rng.randf(), 0.7, 0.9), 0.4), Vector3(-0.32 + c * 0.14, 0.6 + r * 0.25, -0.3), 0.01)
	MeshKit.add_box(p, Vector3(0.15, 0.4, 0.02), Mats.color(Color(0.2, 0.2, 0.2)), Vector3(0.33, 1.2, -0.41), 0.01)
	solid(p, Vector3(0.9, 1.85, 0.8), Vector3(0, 0.925, 0))
	return p


static func water_cooler(parent: Node3D, pos: Vector3) -> Node3D:
	var p := pivot(parent, pos)
	MeshKit.add_box(p, Vector3(0.32, 1.0, 0.32), Mats.color(Color(0.92, 0.92, 0.92), 0.4), Vector3(0, 0.5, 0), 0.03)
	var blue := Mats.color(Color(0.5, 0.75, 1.0, 1), 0.1)
	MeshKit.add(p, MeshKit.cylinder(0.14, 0.4, 16), blue, Vector3(0, 1.22, 0))
	MeshKit.add(p, MeshKit.sphere(0.14, 16, 0.5), blue, Vector3(0, 1.42, 0))
	solid(p, Vector3(0.34, 1.2, 0.34), Vector3(0, 0.6, 0))
	return p


static func whiteboard(parent: Node3D, pos: Vector3, rot_y: float) -> Dictionary:
	var p := pivot(parent, pos, rot_y)
	MeshKit.add_box(p, Vector3(2.9, 1.3, 0.04), Mats.color(Color(0.75, 0.76, 0.78), 0.3, 0.7), Vector3(0, 1.55, 0), 0.01)
	var surf := MeshKit.add(p, MeshKit.quad(Vector2(2.8, 1.2)), Mats.decal_tex("whiteboard_albedo"), Vector3(0, 1.55, -0.021), Vector3(0, 180, 0), false)
	MeshKit.add_box(p, Vector3(2.2, 0.03, 0.08), Mats.color(Color(0.7, 0.7, 0.72), 0.3, 0.7), Vector3(0, 0.88, -0.04), 0.008)
	return {"pivot": p, "surface": surf}


static func wall_poster(parent: Node3D, pos: Vector3, rot_y: float, tex: String, size := Vector2(0.6, 0.8)) -> void:
	var p := pivot(parent, pos, rot_y)
	MeshKit.add_box(p, Vector3(size.x + 0.04, size.y + 0.04, 0.02), Mats.color(Color(0.12, 0.12, 0.12), 0.4), Vector3.ZERO, 0.005)
	MeshKit.add(p, MeshKit.quad(size), Mats.decal_tex(tex), Vector3(0, 0, -0.011), Vector3(0, 180, 0), false)


static func wall_clock(parent: Node3D, pos: Vector3, rot_y: float) -> Dictionary:
	var p := pivot(parent, pos, rot_y)
	MeshKit.add(p, MeshKit.cylinder(0.2, 0.04, 28), Mats.color(Color(0.1, 0.1, 0.1), 0.4), Vector3.ZERO, Vector3(90, 0, 0))
	MeshKit.add(p, MeshKit.cylinder(0.18, 0.01, 28), Mats.color(Color(0.98, 0.98, 0.96), 0.5), Vector3(0, 0, -0.022), Vector3(90, 0, 0), false)
	var hands := []
	for spec in [[0.1, 0.012], [0.15, 0.007]]:
		var h := Node3D.new()
		p.add_child(h)
		h.position = Vector3(0, 0, -0.03)
		MeshKit.add(h, MeshKit.rounded_box(Vector3(spec[1], spec[0], 0.004), 0.001, 1), Mats.color(Color(0.1, 0.1, 0.1)), Vector3(0, spec[0] * 0.5, 0), Vector3.ZERO, false)
		hands.append(h)
	return {"hour": hands[0], "minute": hands[1]}


static func toilet(parent: Node3D, pos: Vector3, rot_y: float) -> Node3D:
	var p := pivot(parent, pos, rot_y)
	var white := Mats.color(Color(0.97, 0.97, 0.97), 0.15)
	MeshKit.add(p, MeshKit.cylinder(0.17, 0.4, 20, 0.2), white, Vector3(0, 0.2, -0.05))
	MeshKit.add(p, MeshKit.torus(0.12, 0.2, 20), white, Vector3(0, 0.41, -0.05))
	MeshKit.add_box(p, Vector3(0.42, 0.4, 0.18), white, Vector3(0, 0.6, 0.18), 0.04)
	solid(p, Vector3(0.42, 0.8, 0.6), Vector3(0, 0.4, 0.05), Layers.STATIC)
	return p


static func sink(parent: Node3D, pos: Vector3, rot_y: float) -> Node3D:
	var p := pivot(parent, pos, rot_y)
	var white := Mats.color(Color(0.97, 0.97, 0.97), 0.15)
	MeshKit.add_box(p, Vector3(0.55, 0.15, 0.45), white, Vector3(0, 0.82, 0), 0.05)
	MeshKit.add(p, MeshKit.cylinder(0.04, 0.75, 10), white, Vector3(0, 0.38, 0.1))
	MeshKit.add(p, MeshKit.cylinder(0.015, 0.18, 8), Mats.color(Color(0.85, 0.85, 0.88), 0.15, 1.0), Vector3(0, 0.95, 0.15))
	MeshKit.add_box(p, Vector3(0.5, 0.7, 0.02), Mats.color(Color(0.8, 0.88, 0.92), 0.02, 1.0), Vector3(0, 1.55, 0.22), 0.01)
	solid(p, Vector3(0.55, 0.9, 0.45), Vector3(0, 0.45, 0), Layers.STATIC)
	return p


static func plant_static(parent: Node3D, pos: Vector3, s := 1.2) -> void:
	var p := pivot(parent, pos)
	MeshKit.add(p, MeshKit.cylinder(0.22 * s, 0.45 * s, 16, 0.26 * s), Mats.color(Color(0.25, 0.25, 0.27), 0.5), Vector3(0, 0.225 * s, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(pos.x * 13 + pos.z * 7)
	for i in 18:
		var a := rng.randf() * TAU
		var h := rng.randf_range(0.6, 1.6) * s
		var leaf := MeshKit.add(p, MeshKit.sphere(0.12 * s, 10, 0.4), Mats.color(Color(0.15 + rng.randf() * 0.1, 0.45 + rng.randf() * 0.2, 0.2), 0.7), Vector3(cos(a) * 0.2 * s, h, sin(a) * 0.2 * s))
		leaf.rotation = Vector3(rng.randf_range(-0.8, 0.8), a, rng.randf_range(-0.6, 0.6))
		leaf.scale = Vector3(1, 1, 2.6)
	solid(p, Vector3(0.5 * s, 1.2 * s, 0.5 * s), Vector3(0, 0.6 * s, 0))


static func coat_rack(parent: Node3D, pos: Vector3) -> void:
	var p := pivot(parent, pos)
	var m := Mats.color(Color(0.15, 0.15, 0.15), 0.4, 0.6)
	MeshKit.add(p, MeshKit.cylinder(0.025, 1.8, 8), m, Vector3(0, 0.9, 0))
	MeshKit.add(p, MeshKit.cylinder(0.22, 0.03, 16), m, Vector3(0, 0.015, 0))
	MeshKit.add(p, MeshKit.capsule(0.12, 0.7), Mats.color(Color(0.4, 0.3, 0.2), 0.9), Vector3(0.12, 1.35, 0), Vector3(0, 0, 8))
	MeshKit.add(p, MeshKit.capsule(0.1, 0.6), Mats.color(Color(0.2, 0.3, 0.5), 0.9), Vector3(-0.1, 1.4, 0.05), Vector3(0, 0, -6))
	solid(p, Vector3(0.3, 1.8, 0.3), Vector3(0, 0.9, 0), Layers.STATIC)


static func extinguisher(parent: Node3D, pos: Vector3) -> void:
	var p := pivot(parent, pos)
	MeshKit.add(p, MeshKit.capsule(0.08, 0.5), Mats.color(Color(0.85, 0.08, 0.08), 0.3), Vector3(0, 0.25, 0))
	MeshKit.add(p, MeshKit.cylinder(0.02, 0.08, 8), Mats.color(Color(0.15, 0.15, 0.15)), Vector3(0, 0.53, 0))
