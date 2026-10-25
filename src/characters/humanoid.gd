class_name Humanoid
extends Node3D
## Stylised articulated character (17 joints) with fully procedural animation:
## walk/run cycle locked to travelled distance (no foot sliding), sitting, typing,
## carrying, crouching, looking at things, emotions, stumbling, falling and getting up.
## Origin = between the feet. Faces -Z.

const JOINTS := ["pelvis", "spine", "chest", "neck", "head", "shoulder_l", "elbow_l", "hand_l", "shoulder_r", "elbow_r", "hand_r",
	"hip_l", "knee_l", "foot_l", "hip_r", "knee_r", "foot_r"]

var j: Dictionary = {}          # joint name -> Node3D
var look: Dictionary = {}
var face: Dictionary = {}
var accessories: Dictionary = {}

# --- animation inputs (written by Character every frame)
var phase := 0.0                # walk cycle phase (radians), advanced by distance
var speed := 0.0                # horizontal speed m/s
var sit := 0.0                  # 0..1 blend
var seat_low := false
var typing := false
var carrying := false
var crouch := 0.0
var busy := false               # manipulating something with the hands
var look_target := Vector3.INF  # world position to look at
var emote := ""
var emote_t := 0.0
var posture := 0.0              # -1 slouched/nervous .. +1 very straight (director)
var fall := 0.0                 # 0 upright .. 1 lying
var fall_dir := 1.0             # -1 forward (face down), +1 backward
var getting_up := 0.0
var spin := 0.0                 # cartoon somersault while falling (radians)
var stumble := 0.0
var talking := 0.0
var _t := 0.0
var _blink := 2.0
var _cur: Dictionary = {}
var _pelvis_base := 0.95


static var _mats: Dictionary = {}


## Character material: soft rim light for a polished stylised look (cached & shared).
static func cmat(c: Color, rough := 0.75, rim := 0.35, metal := 0.0) -> StandardMaterial3D:
	var key := "%s_%.2f_%.2f_%.2f" % [c.to_html(), rough, rim, metal]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	if rim > 0.0:
		m.rim_enabled = true
		m.rim = rim
		m.rim_tint = 0.55
	_mats[key] = m
	return m


func build(appearance: Dictionary) -> void:
	look = appearance
	for c in get_children():
		c.queue_free()
	j.clear()
	var skin_c := Color(appearance.get("skin", "#e9bb98"))
	var shirt_c := Color(appearance.get("shirt", "#3fa7d6"))
	var pants_c := Color(appearance.get("pants", "#2b2f3a"))
	var skin := cmat(skin_c, 0.55, 0.3)
	var shirt := cmat(shirt_c, 0.85)
	var shirt_dark := cmat(shirt_c.darkened(0.18), 0.85)
	var shirt_light := cmat(shirt_c.lightened(0.18), 0.85)
	var pants := cmat(pants_c, 0.85)
	var hair_c := cmat(Color(appearance.get("hair_color", "#3b2a1e")), 0.6, 0.45)
	var b: float = appearance.get("build", 1.0)
	var jacket: bool = appearance.get("jacket", false)
	var sneakers := shirt_c.v > 0.6 and shirt_c.s > 0.5 and not jacket
	var shoe_up := cmat(Color(0.95, 0.95, 0.95) if sneakers else Color(0.2, 0.13, 0.09), 0.45, 0.2)
	var sole := cmat(Color(0.12, 0.12, 0.12) if not sneakers else Color(0.85, 0.3, 0.25), 0.7, 0.0)
	scale = Vector3.ONE * float(appearance.get("height", 1.0))

	# --- hips & belt
	var pelvis := _joint("pelvis", self, Vector3(0, _pelvis_base, 0))
	MeshKit.add(pelvis, MeshKit.rounded_box(Vector3(0.34 * b, 0.2, 0.21), 0.08, 3), pants, Vector3(0, -0.03, 0))
	MeshKit.add(pelvis, MeshKit.rounded_box(Vector3(0.335 * b, 0.04, 0.205), 0.018, 2), cmat(Color(0.12, 0.09, 0.07), 0.5), Vector3(0, 0.0, 0))
	MeshKit.add(pelvis, MeshKit.rounded_box(Vector3(0.05, 0.035, 0.02), 0.006, 1), cmat(Color(0.95, 0.75, 0.3), 0.25, 0.1, 0.9), Vector3(0, 0.0, -0.104))
	if appearance.get("skirt", false):
		var sk := MeshKit.add(pelvis, MeshKit.cylinder(0.205 * b, 0.42, 20, 0.175 * b), pants, Vector3(0, -0.2, 0))
		sk.scale = Vector3(1, 1, 0.78)
	# --- torso
	var spine := _joint("spine", pelvis, Vector3(0, 0.08, 0))
	var torso_w := 0.36 * b
	MeshKit.add(spine, MeshKit.rounded_box(Vector3(torso_w, 0.44, 0.215 * maxf(b, 0.9)), 0.09, 4), shirt, Vector3(0, 0.13, 0))
	if b > 1.1:
		MeshKit.add(spine, MeshKit.sphere(0.17 * b, 18), shirt, Vector3(0, 0.08, -0.045)).scale = Vector3(1.0, 0.9, 0.85)
	var front_z := -0.11 * maxf(b, 0.9) - (0.04 if b > 1.1 else 0.0)
	if not jacket:
		MeshKit.add(spine, MeshKit.rounded_box(Vector3(0.035, 0.34, 0.01), 0.004, 1), shirt_dark, Vector3(0, 0.17, front_z - 0.002))
		for k in 3:
			MeshKit.add(spine, MeshKit.sphere(0.009, 6), cmat(Color(0.95, 0.95, 0.92), 0.4, 0.0), Vector3(0, 0.07 + k * 0.1, front_z - 0.008))
		MeshKit.add(spine, MeshKit.rounded_box(Vector3(0.075, 0.07, 0.01), 0.008, 1), shirt_dark, Vector3(-0.08 * b, 0.27, front_z + 0.004))
	var chest := _joint("chest", spine, Vector3(0, 0.3, 0))
	MeshKit.add(chest, MeshKit.rounded_box(Vector3(0.41 * b, 0.21, 0.23), 0.1, 4), shirt, Vector3(0, 0.0, 0))
	var collar_m := cmat(Color(0.97, 0.97, 0.95), 0.7) if (jacket or appearance.get("tie", "") != "") else shirt_light
	for sx in [-1, 1]:
		var col := MeshKit.add(chest, MeshKit.rounded_box(Vector3(0.07, 0.05, 0.02), 0.01, 1), collar_m, Vector3(sx * 0.045, 0.1, -0.1))
		col.rotation = Vector3(-0.4, 0, sx * -0.5)
	if jacket:
		MeshKit.add(spine, MeshKit.rounded_box(Vector3(0.12, 0.42, 0.01), 0.004, 1), cmat(Color(0.96, 0.96, 0.96), 0.6), Vector3(0, 0.2, front_z - 0.008))
		for sx in [-1, 1]:
			var lap := MeshKit.add(chest, MeshKit.rounded_box(Vector3(0.075, 0.22, 0.02), 0.008, 1), shirt_light, Vector3(sx * 0.075, -0.02, -0.12))
			lap.rotation.z = sx * 0.35
		MeshKit.add(spine, MeshKit.sphere(0.012, 6), cmat(Color(0.1, 0.1, 0.1), 0.3), Vector3(0.0, 0.02, front_z - 0.012))
		MeshKit.add(chest, MeshKit.rounded_box(Vector3(0.05, 0.03, 0.01), 0.004, 1), cmat(Color(0.95, 0.95, 0.95), 0.5), Vector3(-0.12, 0.0, -0.118))
	if appearance.get("tie", "") != "":
		var tm := cmat(Color(appearance.tie), 0.45, 0.25)
		MeshKit.add(chest, MeshKit.rounded_box(Vector3(0.05, 0.05, 0.03), 0.012, 1), tm, Vector3(0, 0.07, -0.118))
		var tie := MeshKit.add(spine, MeshKit.rounded_box(Vector3(0.065, 0.32, 0.015), 0.006, 1), tm, Vector3(0, 0.21, front_z - 0.012))
		accessories["tie"] = tie
	var neck := _joint("neck", chest, Vector3(0, 0.12, 0))
	MeshKit.add(neck, MeshKit.cylinder(0.055, 0.11, 12), skin, Vector3(0, 0.02, 0))
	var head := _joint("head", neck, Vector3(0, 0.07, 0))
	_build_head(head, skin, hair_c, appearance)
	# --- arms
	var sleeves: bool = appearance.get("long_sleeves", true)
	for side in ["l", "r"]:
		var sx := -1.0 if side == "l" else 1.0
		var sh := _joint("shoulder_" + side, chest, Vector3(sx * (0.19 * b + 0.04), 0.04, 0))
		MeshKit.add(sh, MeshKit.sphere(0.064, 12), shirt, Vector3.ZERO)
		MeshKit.add(sh, MeshKit.capsule(0.06, 0.33), shirt, Vector3(0, -0.14, 0))
		var el := _joint("elbow_" + side, sh, Vector3(0, -0.28, 0))
		MeshKit.add(el, MeshKit.sphere(0.056, 10), shirt if sleeves else skin, Vector3.ZERO)
		MeshKit.add(el, MeshKit.capsule(0.052, 0.28), shirt if sleeves else skin, Vector3(0, -0.12, 0))
		MeshKit.add(el, MeshKit.cylinder(0.056, 0.035, 12), shirt_dark, Vector3(0, -0.235, 0))
		var hand := _joint("hand_" + side, el, Vector3(0, -0.26, 0))
		MeshKit.add(hand, MeshKit.rounded_box(Vector3(0.075, 0.09, 0.04), 0.02, 2), skin, Vector3(0, -0.035, 0))
		MeshKit.add(hand, MeshKit.rounded_box(Vector3(0.07, 0.05, 0.035), 0.016, 2), skin, Vector3(0, -0.09, 0.004))
		var th := MeshKit.add(hand, MeshKit.capsule(0.014, 0.06), skin, Vector3(0.0, -0.035, -0.03))
		th.rotation = Vector3(0.6, 0, sx * 0.2)
		# --- legs
		var hip := _joint("hip_" + side, pelvis, Vector3(sx * 0.095 * b, -0.07, 0))
		MeshKit.add(hip, MeshKit.capsule(0.08 * minf(b, 1.15), 0.46), pants, Vector3(0, -0.2, 0))
		var knee := _joint("knee_" + side, hip, Vector3(0, -0.41, 0))
		var leg_m: Material = pants if not appearance.get("skirt", false) else skin
		MeshKit.add(knee, MeshKit.sphere(0.068, 10), leg_m, Vector3.ZERO)
		MeshKit.add(knee, MeshKit.capsule(0.066, 0.44), leg_m, Vector3(0, -0.19, 0))
		var foot := _joint("foot_" + side, knee, Vector3(0, -0.4, 0))
		MeshKit.add(foot, MeshKit.rounded_box(Vector3(0.115, 0.03, 0.26), 0.012, 2), sole, Vector3(0, -0.062, -0.05))
		MeshKit.add(foot, MeshKit.rounded_box(Vector3(0.105, 0.07, 0.22), 0.035, 3), shoe_up, Vector3(0, -0.025, -0.035))
		MeshKit.add(foot, MeshKit.sphere(0.052, 10, 0.7), shoe_up, Vector3(0, -0.035, -0.135)).scale = Vector3(1.0, 1.0, 0.9)
	for n in JOINTS:
		_cur[n] = Vector3.ZERO


func _joint(n: String, parent: Node3D, pos: Vector3) -> Node3D:
	var node := Node3D.new()
	node.name = n
	node.position = pos
	parent.add_child(node)
	j[n] = node
	return node


func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


func _build_head(head: Node3D, skin: Material, hair_c: Material, a: Dictionary) -> void:
	var r := 0.155
	var skin_c := Color(a.get("skin", "#e9bb98"))
	MeshKit.add(head, MeshKit.sphere(r, 24), skin, Vector3(0, 0.13, 0)).scale = Vector3(0.96, 1.04, 0.98)
	MeshKit.add(head, MeshKit.sphere(r * 0.82, 20), skin, Vector3(0, 0.075, -0.025)).scale = Vector3(0.95, 0.85, 0.95)   # jaw / chin
	for sx in [-1, 1]:
		MeshKit.add(head, MeshKit.sphere(0.036, 10), skin, Vector3(sx * 0.148, 0.12, 0.012)).scale = Vector3(0.55, 1, 0.85)
		MeshKit.add(head, MeshKit.sphere(0.022, 8), Humanoid.cmat(skin_c.lerp(Color(1.0, 0.45, 0.45), 0.4), 0.7, 0.0), Vector3(sx * 0.088, 0.095, -0.118)).scale = Vector3(1.2, 0.8, 0.5)
	MeshKit.add(head, MeshKit.sphere(0.03, 12), Humanoid.cmat(skin_c.darkened(0.06), 0.55, 0.2), Vector3(0, 0.115, -0.158)).scale = Vector3(0.95, 1.15, 1.25)
	# eyes: sclera + iris + pupil + highlight, on pivots the face animation can scale (blink)
	var hseed := int(Color(a.get("hair_color", "#333333")).h * 100.0 + Color(a.get("skin", "#888888")).v * 50.0)
	var iris_c: Color = [Color(0.36, 0.22, 0.12), Color(0.2, 0.45, 0.75), Color(0.25, 0.5, 0.3), Color(0.45, 0.32, 0.18)][hseed % 4]
	var eyes: Array = []
	var brows: Array = []
	for sx in [-1, 1]:
		var ep := _pivot(head, Vector3(sx * 0.056, 0.152, -0.132))
		ep.scale = Vector3(1, 1.15, 1)
		MeshKit.add(ep, MeshKit.sphere(0.031, 12), Humanoid.cmat(Color(0.99, 0.99, 0.99), 0.25, 0.0), Vector3.ZERO).scale = Vector3(1, 1, 0.6)
		MeshKit.add(ep, MeshKit.sphere(0.019, 10), Humanoid.cmat(iris_c, 0.3, 0.0), Vector3(0, -0.002, -0.015)).scale = Vector3(1, 1, 0.5)
		MeshKit.add(ep, MeshKit.sphere(0.0105, 8), Humanoid.cmat(Color(0.03, 0.03, 0.04), 0.15, 0.0), Vector3(0, -0.002, -0.0235)).scale = Vector3(1, 1, 0.5)
		MeshKit.add(ep, MeshKit.sphere(0.0045, 6), Mats.unshaded(Color(1, 1, 1)), Vector3(0.006, 0.006, -0.027))
		eyes.append(ep)
		var bp := _pivot(head, Vector3(sx * 0.058, 0.195, -0.142))
		MeshKit.add(bp, MeshKit.capsule(0.012, 0.064), hair_c, Vector3.ZERO, Vector3(0, 0, 90))
		brows.append(bp)
	var mouth := _pivot(head, Vector3(0, 0.062, -0.146))
	MeshKit.add(mouth, MeshKit.capsule(0.011, 0.062), Humanoid.cmat(Color(0.22, 0.05, 0.07), 0.5, 0.0), Vector3.ZERO, Vector3(0, 0, 90))
	face = {"eyes": eyes, "brows": brows, "mouth": mouth}
	_build_hair(head, hair_c, r, String(a.get("hair", "short")))
	match a.get("beard", ""):
		"mustache":
			for sx in [-1, 1]:
				var m := MeshKit.add(head, MeshKit.capsule(0.017, 0.07), hair_c, Vector3(sx * 0.028, 0.085, -0.155))
				m.rotation = Vector3(0, 0, sx * 1.25)
		"beard":
			MeshKit.add(head, MeshKit.sphere(0.13, 16, 0.75), hair_c, Vector3(0, 0.045, -0.055)).scale = Vector3(1.05, 0.95, 1.0)
			for sx in [-1, 1]:
				MeshKit.add(head, MeshKit.capsule(0.015, 0.06), hair_c, Vector3(sx * 0.028, 0.088, -0.158), Vector3(0, 0, sx * 70))
	if a.get("glasses", false):
		var fm := Humanoid.cmat(Color(0.08, 0.08, 0.1), 0.3, 0.0, 0.4)
		var lens := StandardMaterial3D.new()
		lens.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		lens.albedo_color = Color(0.75, 0.88, 1.0, 0.18)
		lens.roughness = 0.05
		for sx in [-1, 1]:
			MeshKit.add(head, MeshKit.torus(0.028, 0.037, 16), fm, Vector3(sx * 0.056, 0.152, -0.158), Vector3(90, 0, 0))
			MeshKit.add(head, MeshKit.cylinder(0.03, 0.002, 16), lens, Vector3(sx * 0.056, 0.152, -0.158), Vector3(90, 0, 0), false)
			MeshKit.add(head, MeshKit.rounded_box(Vector3(0.006, 0.006, 0.14), 0.002, 1), fm, Vector3(sx * 0.093, 0.155, -0.09))
		MeshKit.add(head, MeshKit.rounded_box(Vector3(0.036, 0.007, 0.007), 0.003, 1), fm, Vector3(0, 0.158, -0.162))
	# disguise moustache (hidden until worn) + cosmetic slots
	var dm := Node3D.new()
	head.add_child(dm)
	for sx in [-1, 1]:
		var piece := MeshKit.add(dm, MeshKit.capsule(0.03, 0.12), Humanoid.cmat(Color(0.15, 0.08, 0.05), 0.8, 0.0), Vector3(sx * 0.04, 0.085, -0.165))
		piece.rotation = Vector3(0, 0, sx * 1.2)
	dm.visible = false
	accessories["disguise"] = dm
	var hat := Node3D.new()
	head.add_child(hat)
	MeshKit.add(hat, MeshKit.cylinder(0.24, 0.02, 24), Humanoid.cmat(Color(0.1, 0.1, 0.1), 0.6), Vector3(0, 0.27, 0))
	MeshKit.add(hat, MeshKit.cylinder(0.14, 0.17, 24, 0.13), Humanoid.cmat(Color(0.1, 0.1, 0.1), 0.6), Vector3(0, 0.36, 0))
	MeshKit.add(hat, MeshKit.cylinder(0.142, 0.035, 24), Humanoid.cmat(Color(0.7, 0.1, 0.1), 0.6), Vector3(0, 0.3, 0))
	hat.visible = false
	accessories["chapeau"] = hat
	var sun := Node3D.new()
	head.add_child(sun)
	for sx in [-1, 1]:
		MeshKit.add(sun, MeshKit.sphere(0.036, 12, 0.7), Humanoid.cmat(Color(0.02, 0.02, 0.02), 0.05, 0.5, 0.6), Vector3(sx * 0.056, 0.152, -0.162))
	MeshKit.add(sun, MeshKit.rounded_box(Vector3(0.04, 0.008, 0.008), 0.003, 1), Humanoid.cmat(Color(0.02, 0.02, 0.02), 0.2), Vector3(0, 0.16, -0.165))
	sun.visible = false
	accessories["lunettes"] = sun


## Hair with volume: a skull cap plus clumps, fringe and style-specific shapes.
func _build_hair(head: Node3D, hair_c: Material, r: float, style: String) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(style) + int(r * 1000)
	var cap_needed := style != "bald" and style != "curly"
	if cap_needed:
		MeshKit.add(head, MeshKit.sphere(r * 1.07, 22, 0.78), hair_c, Vector3(0, 0.19, 0.018)).scale = Vector3(1.0, 1.0, 1.03)
		# back of the head + sides down to the ears
		MeshKit.add(head, MeshKit.sphere(r * 1.02, 18), hair_c, Vector3(0, 0.14, 0.035)).scale = Vector3(1.0, 0.95, 0.95)
	match style:
		"short", "slick", "messy":
			if style != "slick":
				for i in 3:
					var x := (i - 1) * 0.06
					var f := MeshKit.add(head, MeshKit.sphere(0.055, 12), hair_c, Vector3(x, 0.235 - absf(x) * 0.2, -0.095 + absf(x) * 0.2))
					f.scale = Vector3(1.25, 0.42, 0.8)
			else:
				MeshKit.add(head, MeshKit.rounded_box(Vector3(0.3, 0.06, 0.24), 0.03, 2), hair_c, Vector3(0, 0.262, 0.01), Vector3(-8, 0, 0))
				MeshKit.add(head, MeshKit.capsule(0.03, 0.2), hair_c, Vector3(-0.06, 0.29, 0.0), Vector3(90, 0, 0))
			if style == "messy":
				for i in 10:
					var a := rng.randf() * TAU
					var spike := MeshKit.add(head, MeshKit.capsule(0.022, 0.1), hair_c, Vector3(cos(a) * 0.08, 0.27 + rng.randf() * 0.03, sin(a) * 0.08 + 0.02))
					spike.rotation = Vector3(sin(a) * 0.9, 0, -cos(a) * 0.9)
		"bun", "ponytail", "long":
			for i in 4:
				var x := (i - 1.5) * 0.05
				MeshKit.add(head, MeshKit.sphere(0.05, 10), hair_c, Vector3(x, 0.24, -0.105 + absf(x) * 0.3)).scale = Vector3(1.0, 0.55, 0.85)
			for sx in [-1, 1]:
				MeshKit.add(head, MeshKit.capsule(0.035, 0.16 if style != "long" else 0.3), hair_c, Vector3(sx * 0.135, 0.12 if style != "long" else 0.05, -0.02))
			if style == "bun":
				MeshKit.add(head, MeshKit.sphere(0.075, 14), hair_c, Vector3(0, 0.31, 0.09))
				MeshKit.add(head, MeshKit.torus(0.06, 0.075, 14), Humanoid.cmat(Color(0.85, 0.2, 0.3), 0.5), Vector3(0, 0.29, 0.07), Vector3(40, 0, 0))
			elif style == "ponytail":
				MeshKit.add(head, MeshKit.torus(0.025, 0.04, 10), Humanoid.cmat(Color(0.2, 0.4, 0.9), 0.5), Vector3(0, 0.2, 0.16), Vector3(70, 0, 0))
				var pt := MeshKit.add(head, MeshKit.capsule(0.048, 0.3), hair_c, Vector3(0, 0.1, 0.2), Vector3(20, 0, 0))
				accessories["ponytail"] = pt
			else:
				MeshKit.add(head, MeshKit.rounded_box(Vector3(0.31, 0.38, 0.13), 0.06, 3), hair_c, Vector3(0, 0.04, 0.095))
		"curly":
			for i in 34:
				var ang := rng.randf() * TAU
				var el := rng.randf_range(-0.25, 1.3)
				var p := Vector3(cos(ang) * cos(el), sin(el), sin(ang) * cos(el)) * (r * 1.08)
				if p.z < -0.06 and p.y < 0.07:
					continue
				MeshKit.add(head, MeshKit.sphere(0.06 + rng.randf() * 0.015, 10), hair_c, Vector3(p.x, 0.15 + p.y, p.z + 0.02))
		"bald":
			MeshKit.add(head, MeshKit.sphere(r * 1.0, 18), Humanoid.cmat(Color(look.get("skin", "#e9bb98")).lightened(0.05), 0.35, 0.4), Vector3(0, 0.15, 0.005))
			for i in 9:
				var ang2 := PI * 0.15 + i * PI * 0.7 / 8.0
				MeshKit.add(head, MeshKit.sphere(0.04, 8), hair_c, Vector3(cos(ang2) * 0.15, 0.13, sin(ang2) * 0.12 + 0.02)).scale = Vector3(1, 0.8, 1)


func set_accessory(id: String, on: bool) -> void:
	if accessories.has(id):
		accessories[id].visible = on
	if id == "cravate_or" and accessories.has("tie"):
		accessories.tie.material_override = Mats.color(Color(1.0, 0.78, 0.15), 0.25, 0.8) if on else Mats.hex(look.get("tie", "#b81f2c"), 0.5)


# ------------------------------------------------------------------ animation
func _process(delta: float) -> void:
	_t += delta
	var pose := _compute_pose()
	var k := clampf(delta * 14.0, 0.0, 1.0)
	for n in pose:
		if n.begins_with("_"):
			continue
		var target: Vector3 = pose[n]
		_cur[n] = (_cur[n] as Vector3).lerp(target, k)
		(j[n] as Node3D).rotation = _cur[n]
	var py: float = pose.get("_pelvis_y", _pelvis_base)
	(j.pelvis as Node3D).position.y = lerpf((j.pelvis as Node3D).position.y, py, k)
	(j.pelvis as Node3D).position.z = lerpf((j.pelvis as Node3D).position.z, float(pose.get("_pelvis_z", 0.0)), k)
	# falling: whole body pivots around the feet
	rotation.x = fall * PI * 0.5 * fall_dir + spin
	position.y = fall * 0.12 + absf(sin(spin * 0.5)) * 0.6
	_face(delta)


func _compute_pose() -> Dictionary:
	var p := {}
	for n in JOINTS:
		p[n] = Vector3.ZERO
	var run := clampf((speed - 2.0) / 1.5, 0.0, 1.0)
	var walk := clampf(speed / 1.4, 0.0, 1.0) * (1.0 - sit)
	var amp := lerpf(0.42, 0.78, run) * walk
	var s := sin(phase)
	var c := cos(phase)
	# --- locomotion
	p.hip_l = Vector3(amp * s, 0, 0)
	p.hip_r = Vector3(-amp * s, 0, 0)
	p.knee_l = Vector3(-(0.08 + lerpf(0.7, 1.3, run) * maxf(0.0, c)) * walk, 0, 0)
	p.knee_r = Vector3(-(0.08 + lerpf(0.7, 1.3, run) * maxf(0.0, -c)) * walk, 0, 0)
	p.foot_l = Vector3(-(p.hip_l.x + p.knee_l.x) * 0.5, 0, 0)
	p.foot_r = Vector3(-(p.hip_r.x + p.knee_r.x) * 0.5, 0, 0)
	p.shoulder_l = Vector3(-amp * 0.8 * s, 0, -0.08)
	p.shoulder_r = Vector3(amp * 0.8 * s, 0, 0.08)
	p.elbow_l = Vector3(0.15 + run * 1.1 + walk * 0.15, 0, 0)
	p.elbow_r = Vector3(0.15 + run * 1.1 + walk * 0.15, 0, 0)
	p.spine = Vector3(-0.05 * walk - 0.18 * run, 0.12 * amp * s, 0)
	p.chest = Vector3(0, -0.1 * amp * s, 0)
	p._pelvis_y = _pelvis_base - 0.035 * absf(s) * walk - 0.04 * run
	# idle breathing + posture
	var breathe := sin(_t * 1.8) * 0.02
	p.chest.x += breathe - posture * 0.04
	p.neck = Vector3(posture * -0.05, 0, 0)
	if posture > 0.5 and walk > 0.1 and not carrying:
		# director: hands behind the back while walking
		p.shoulder_l = Vector3(-0.35, 0, -0.25)
		p.shoulder_r = Vector3(-0.35, 0, 0.25)
		p.elbow_l = Vector3(0.9, 0, 0.6)
		p.elbow_r = Vector3(0.9, 0, -0.6)
	elif posture < -0.3 and walk < 0.1:
		p.spine.x += 0.08
		p.neck.y = sin(_t * 0.9) * 0.6  # nervous glances
	# --- crouch
	if crouch > 0.0:
		p._pelvis_y = lerpf(p._pelvis_y, 0.55, crouch)
		p.hip_l.x += 1.25 * crouch
		p.hip_r.x += 1.25 * crouch
		p.knee_l.x -= 1.9 * crouch
		p.knee_r.x -= 1.9 * crouch
		p.foot_l.x += 0.6 * crouch
		p.foot_r.x += 0.6 * crouch
		p.spine.x -= 0.45 * crouch
		p.neck.x += 0.35 * crouch
	# --- sitting
	if sit > 0.0:
		var low := 1.0 if seat_low else 0.0
		p._pelvis_y = lerpf(p._pelvis_y, 0.58 - 0.18 * low, sit)
		p._pelvis_z = 0.06 * sit
		for side in ["l", "r"]:
			var spread := 0.08 if side == "l" else -0.08
			p["hip_" + side] = (p["hip_" + side] as Vector3).lerp(Vector3(1.5 + 0.35 * low, 0, spread), sit)
			p["knee_" + side] = (p["knee_" + side] as Vector3).lerp(Vector3(-1.45 - 0.25 * low, 0, 0), sit)
			p["foot_" + side] = (p["foot_" + side] as Vector3).lerp(Vector3(0.0, 0, 0), sit)
		p.spine = p.spine.lerp(Vector3(0.12, 0, 0), sit)
		if not typing:
			p.shoulder_l = p.shoulder_l.lerp(Vector3(0.35, 0, -0.1), sit)
			p.shoulder_r = p.shoulder_r.lerp(Vector3(0.35, 0, 0.1), sit)
			p.elbow_l = p.elbow_l.lerp(Vector3(0.7, 0, 0), sit)
			p.elbow_r = p.elbow_r.lerp(Vector3(0.7, 0, 0), sit)
	# --- hands busy
	if typing:
		var jit := sin(_t * 23.0) * 0.06
		p.shoulder_l = Vector3(0.75 + jit, 0, -0.12)
		p.shoulder_r = Vector3(0.75 - jit, 0, 0.12)
		p.elbow_l = Vector3(0.95, 0, 0.25)
		p.elbow_r = Vector3(0.95, 0, -0.25)
		p.neck.x += 0.15
		p.spine.x -= 0.08
	elif carrying:
		p.shoulder_l = Vector3(1.15, 0, -0.25)
		p.shoulder_r = Vector3(1.15, 0, 0.25)
		p.elbow_l = Vector3(0.45, 0, 0.35)
		p.elbow_r = Vector3(0.45, 0, -0.35)
		p.spine.x += 0.06
	elif busy:
		var w := sin(_t * 9.0) * 0.15
		p.shoulder_l = Vector3(1.0 + w, 0, -0.15)
		p.shoulder_r = Vector3(1.0 - w, 0, 0.15)
		p.elbow_l = Vector3(0.8, 0, 0.2)
		p.elbow_r = Vector3(0.8, 0, -0.2)
		p.spine.x -= 0.25
		p.neck.x += 0.3
	if talking > 0.0 and emote == "" and not typing and not carrying and sit < 0.5:
		p.shoulder_r.x += 0.4 + sin(_t * 5.0) * 0.25
		p.elbow_r.x += 0.6 + sin(_t * 4.0) * 0.3
		p.shoulder_r.z += 0.2
	# --- look at
	if look_target != Vector3.INF and fall < 0.1:
		var to := global_transform.affine_inverse() * look_target
		var head_h := lerpf(1.55, 1.15, sit)
		var yaw := atan2(-to.x, -to.z)
		var dist := Vector2(to.x, to.z).length()
		var pitch := atan2(to.y - head_h, maxf(dist, 0.2))
		yaw = clampf(yaw, -1.3, 1.3)
		p.neck.y += yaw * 0.6
		p.head = Vector3(clampf(pitch, -0.7, 0.6), yaw * 0.4, 0)
		p.chest.y += yaw * 0.2
	# --- emotes
	_apply_emote(p)
	# --- stumble: windmill
	if stumble > 0.0:
		var wm := sin(_t * 18.0)
		p.spine.x -= 0.5 * stumble
		p.shoulder_l = p.shoulder_l.lerp(Vector3(1.8 + wm, 0, -1.2), stumble)
		p.shoulder_r = p.shoulder_r.lerp(Vector3(1.8 - wm, 0, 1.2), stumble)
	# --- lying on the floor
	if fall > 0.5:
		var f := (fall - 0.5) * 2.0
		p.shoulder_l = p.shoulder_l.lerp(Vector3(0.3, 0, -1.3), f)
		p.shoulder_r = p.shoulder_r.lerp(Vector3(0.3, 0, 1.3), f)
		p.hip_l = p.hip_l.lerp(Vector3(0.2, 0, -0.25), f)
		p.hip_r = p.hip_r.lerp(Vector3(0.1, 0, 0.25), f)
		p.knee_l = p.knee_l.lerp(Vector3(-0.3, 0, 0), f)
		p.neck = p.neck.lerp(Vector3(0.3 * -fall_dir, sin(_t * 2) * 0.3, 0), f)
	if getting_up > 0.0:
		# kneel-and-push transition
		var g := sin(getting_up * PI)
		p.hip_l.x += 1.4 * g
		p.knee_l.x -= 1.8 * g
		p.hip_r.x += 0.4 * g
		p.knee_r.x -= 1.2 * g
		p.spine.x -= 0.6 * g
		p.shoulder_l.x += 0.8 * g
		p.shoulder_r.x += 0.8 * g
	return p


func _apply_emote(p: Dictionary) -> void:
	if emote == "":
		return
	var t := _t
	match emote:
		"panic":
			p.shoulder_l = Vector3(2.6 + sin(t * 16) * 0.4, 0, -0.6)
			p.shoulder_r = Vector3(2.6 + cos(t * 16) * 0.4, 0, 0.6)
			p.elbow_l = Vector3(0.3, 0, 0)
			p.elbow_r = Vector3(0.3, 0, 0)
			p.neck.y = sin(t * 9) * 0.5
		"angry":
			p.shoulder_l = Vector3(0.9, 0, -0.5)
			p.shoulder_r = Vector3(0.9 + absf(sin(t * 10)) * 0.5, 0, 0.5)
			p.elbow_l = Vector3(1.6, 0, 0.3)
			p.elbow_r = Vector3(1.8, 0, -0.3)
			p.spine.x -= 0.15
			p.neck.x += 0.1 + sin(t * 10) * 0.05
		"laugh":
			p.spine.x += 0.25 + absf(sin(t * 12)) * 0.12
			p.neck.x -= 0.35
			p.shoulder_l = Vector3(0.6, 0, -0.2)
			p.elbow_l = Vector3(1.4, 0, 0.8)
			p.shoulder_r = Vector3(0.5, 0, 0.3)
			p.elbow_r = Vector3(1.0, 0, -0.5)
		"surprised":
			p.shoulder_l = Vector3(0.4, 0, -1.2)
			p.shoulder_r = Vector3(0.4, 0, 1.2)
			p.elbow_l = Vector3(0.6, 0, 0)
			p.elbow_r = Vector3(0.6, 0, 0)
			p.spine.x += 0.15
			p.neck.x -= 0.2
			p._pelvis_y = float(p._pelvis_y) + maxf(0.0, sin(minf(emote_t * 6.0, PI))) * 0.08
		"suspicious":
			p.shoulder_r = Vector3(1.0, 0, 0.35)
			p.elbow_r = Vector3(2.0, 0, -0.4)
			p.shoulder_l = Vector3(0.3, 0, -0.1)
			p.elbow_l = Vector3(1.3, 0, 0.7)
			p.spine.x -= 0.12
			p.neck.z = 0.2
		"embarrassed":
			p.shoulder_r = Vector3(2.4, 0, 0.6)
			p.elbow_r = Vector3(1.8, 0, -0.4)
			p.neck.x += 0.4
			p.spine.x -= 0.05
		"point":
			p.shoulder_r = Vector3(1.55, 0, 0.1)
			p.elbow_r = Vector3(0.05, 0, 0)
			p.spine.y = -0.2
		"shrug":
			p.shoulder_l = Vector3(0.3, 0, -0.8)
			p.shoulder_r = Vector3(0.3, 0, 0.8)
			p.elbow_l = Vector3(1.4, 0, 0.6)
			p.elbow_r = Vector3(1.4, 0, -0.6)
			p.neck.z = 0.15
		"phone":
			p.shoulder_r = Vector3(1.2, 0, 0.6)
			p.elbow_r = Vector3(2.3, 0, -0.3)
			p.shoulder_l = Vector3(0.2 + sin(t * 2) * 0.3, 0, -0.2)
			p.elbow_l = Vector3(0.6, 0, 0)
		"drink":
			p.shoulder_r = Vector3(1.0 + sin(t * 1.5) * 0.4, 0, 0.3)
			p.elbow_r = Vector3(2.0, 0, -0.3)
		"dance":
			p.spine.y = sin(t * 6) * 0.4
			p.shoulder_l = Vector3(2.0 + sin(t * 6) * 0.6, 0, -0.5)
			p.shoulder_r = Vector3(2.0 - sin(t * 6) * 0.6, 0, 0.5)
			p._pelvis_y = float(p._pelvis_y) - absf(sin(t * 6)) * 0.06
		"sleep":
			p.neck.x += 0.9
			p.spine.x -= 0.4
		"wave":
			p.shoulder_r = Vector3(2.6, 0, 0.4)
			p.elbow_r = Vector3(0.4 + sin(t * 10) * 0.4, 0, 0)
		"search":
			p.spine.x -= 0.5
			p.neck.y = sin(t * 2.5) * 0.7
			p.shoulder_l = Vector3(0.6, 0, -0.2)
			p.shoulder_r = Vector3(0.6 + sin(t * 4) * 0.3, 0, 0.2)
		"disgust":
			p.shoulder_r = Vector3(1.4, 0, 0.2)
			p.elbow_r = Vector3(2.2, 0, -0.5)
			p.spine.x += 0.15
			p.neck.y = 0.6
		"itch":
			var f := sin(t * 22.0)
			p.shoulder_l = Vector3(0.6 + f * 0.4, 0, -0.3)
			p.elbow_l = Vector3(1.9, 0, 0.6 + f * 0.3)
			p.shoulder_r = Vector3(-0.3 - f * 0.3, 0, 0.4)
			p.elbow_r = Vector3(1.6, 0, -0.6)
			p.spine.y = sin(t * 9.0) * 0.35
			p.spine.z = sin(t * 7.0) * 0.12
			p._pelvis_y = float(p._pelvis_y) + absf(sin(t * 11.0)) * 0.04
		"stretch":
			p.shoulder_l = Vector3(2.9, 0, -0.2)
			p.shoulder_r = Vector3(2.9, 0, 0.2)
			p.spine.x += 0.15


func _face(delta: float) -> void:
	if face.is_empty():
		return
	_blink -= delta
	var blink := _blink < 0.12
	if _blink < 0.0:
		_blink = randf_range(2.0, 5.0)
	var brow_rot := 0.0
	var brow_y := 0.0
	var mouth_scale := Vector3.ONE
	match emote:
		"angry":
			brow_rot = 0.45
			brow_y = -0.008
			mouth_scale = Vector3(1.1, 1.0, 1.0)
		"suspicious":
			brow_rot = 0.25
		"surprised", "panic":
			brow_y = 0.02
			mouth_scale = Vector3(0.6, 2.4, 1.0)
		"laugh", "dance":
			mouth_scale = Vector3(1.2, 2.0, 1.0)
		"embarrassed", "disgust":
			brow_rot = -0.35
			mouth_scale = Vector3(0.8, 0.8, 1.0)
	if talking > 0.0 and emote == "":
		mouth_scale.y = 1.0 + absf(sin(_t * 14.0)) * 1.4
	for i in 2:
		var br: Node3D = face.brows[i]
		var sx := -1.0 if i == 0 else 1.0
		br.rotation.z = lerpf(br.rotation.z, -brow_rot * sx, 0.3)
		br.position.y = lerpf(br.position.y, 0.195 + brow_y, 0.3)
		(face.eyes[i] as Node3D).scale.y = 0.1 if blink or fall > 0.9 and getting_up == 0.0 and emote == "sleep" else 1.15
	(face.mouth as Node3D).scale = (face.mouth as Node3D).scale.lerp(mouth_scale, 0.3)


func head_position() -> Vector3:
	return (j.head as Node3D).global_position + Vector3(0, 0.15 * scale.y, 0)


func hand_position(side := "r") -> Vector3:
	return (j["hand_" + side] as Node3D).global_position
