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
var stumble := 0.0
var talking := 0.0
var _t := 0.0
var _blink := 2.0
var _cur: Dictionary = {}
var _pelvis_base := 0.95


func build(appearance: Dictionary) -> void:
	look = appearance
	for c in get_children():
		c.queue_free()
	j.clear()
	var skin := Mats.hex(appearance.get("skin", "#e9bb98"), 0.65)
	var shirt := Mats.hex(appearance.get("shirt", "#3fa7d6"), 0.85)
	var pants := Mats.hex(appearance.get("pants", "#2b2f3a"), 0.85)
	var shoes := Mats.color(Color(0.1, 0.09, 0.09), 0.4, 0.1)
	var hair_c := Mats.hex(appearance.get("hair_color", "#3b2a1e"), 0.75)
	var b: float = appearance.get("build", 1.0)
	var jacket: bool = appearance.get("jacket", false)
	scale = Vector3.ONE * float(appearance.get("height", 1.0))

	var pelvis := _joint("pelvis", self, Vector3(0, _pelvis_base, 0))
	MeshKit.add(pelvis, MeshKit.rounded_box(Vector3(0.34 * b, 0.2, 0.21), 0.07, 3), pants, Vector3(0, -0.02, 0))
	if appearance.get("skirt", false):
		var sk := MeshKit.add(pelvis, MeshKit.cylinder(0.2 * b, 0.42, 16, 0.17 * b), pants, Vector3(0, -0.2, 0))
		sk.scale = Vector3(1, 1, 0.75)
	var spine := _joint("spine", pelvis, Vector3(0, 0.08, 0))
	var torso_mat := shirt
	MeshKit.add(spine, MeshKit.rounded_box(Vector3(0.36 * b, 0.36, 0.22 * maxf(b, 0.9)), 0.09, 3), torso_mat, Vector3(0, 0.16, 0.0))
	if b > 1.1:
		MeshKit.add(spine, MeshKit.sphere(0.17 * b, 16), torso_mat, Vector3(0, 0.08, -0.04)).scale = Vector3(1.0, 0.9, 0.85)  # belly
	var chest := _joint("chest", spine, Vector3(0, 0.3, 0))
	MeshKit.add(chest, MeshKit.rounded_box(Vector3(0.4 * b, 0.2, 0.23), 0.09, 3), torso_mat, Vector3(0, 0.0, 0))
	if jacket:
		var jm := Mats.hex(appearance.get("shirt", "#3a3f4a"), 0.7)
		MeshKit.add(spine, MeshKit.rounded_box(Vector3(0.12, 0.42, 0.01), 0.004, 1), Mats.color(Color(0.95, 0.95, 0.95), 0.6), Vector3(0, 0.2, -0.118))
		for sx in [-1, 1]:
			var lap := MeshKit.add(chest, MeshKit.rounded_box(Vector3(0.07, 0.2, 0.02), 0.008, 1), jm, Vector3(sx * 0.07, -0.02, -0.12))
			lap.rotation.z = sx * 0.35
	if appearance.get("tie", "") != "":
		var tm := Mats.hex(appearance.tie, 0.5)
		MeshKit.add(chest, MeshKit.rounded_box(Vector3(0.05, 0.05, 0.03), 0.01, 1), tm, Vector3(0, 0.05, -0.115))
		var tie := MeshKit.add(spine, MeshKit.rounded_box(Vector3(0.065, 0.32, 0.015), 0.006, 1), tm, Vector3(0, 0.2, -0.122))
		accessories["tie"] = tie
	var neck := _joint("neck", chest, Vector3(0, 0.12, 0))
	MeshKit.add(neck, MeshKit.cylinder(0.055, 0.1, 10), skin, Vector3(0, 0.02, 0))
	var head := _joint("head", neck, Vector3(0, 0.07, 0))
	_build_head(head, skin, hair_c, appearance)
	for side in ["l", "r"]:
		var sx := -1.0 if side == "l" else 1.0
		var sh := _joint("shoulder_" + side, chest, Vector3(sx * (0.19 * b + 0.04), 0.04, 0))
		MeshKit.add(sh, MeshKit.sphere(0.068, 10), torso_mat, Vector3.ZERO)
		MeshKit.add(sh, MeshKit.capsule(0.058, 0.32), torso_mat, Vector3(0, -0.14, 0))
		var el := _joint("elbow_" + side, sh, Vector3(0, -0.28, 0))
		MeshKit.add(el, MeshKit.capsule(0.052, 0.28), torso_mat if appearance.get("long_sleeves", true) else skin, Vector3(0, -0.12, 0))
		var hand := _joint("hand_" + side, el, Vector3(0, -0.26, 0))
		MeshKit.add(hand, MeshKit.sphere(0.055, 10), skin, Vector3(0, -0.03, 0)).scale = Vector3(0.9, 1.1, 0.7)
		var hip := _joint("hip_" + side, pelvis, Vector3(sx * 0.095 * b, -0.07, 0))
		MeshKit.add(hip, MeshKit.capsule(0.08 * minf(b, 1.15), 0.46), pants, Vector3(0, -0.2, 0))
		var knee := _joint("knee_" + side, hip, Vector3(0, -0.41, 0))
		MeshKit.add(knee, MeshKit.capsule(0.066, 0.44), pants if not appearance.get("skirt", false) else skin, Vector3(0, -0.19, 0))
		var foot := _joint("foot_" + side, knee, Vector3(0, -0.4, 0))
		MeshKit.add(foot, MeshKit.rounded_box(Vector3(0.11, 0.08, 0.25), 0.035, 2), shoes, Vector3(0, -0.035, -0.05))
	for n in JOINTS:
		_cur[n] = Vector3.ZERO


func _joint(n: String, parent: Node3D, pos: Vector3) -> Node3D:
	var node := Node3D.new()
	node.name = n
	node.position = pos
	parent.add_child(node)
	j[n] = node
	return node


func _build_head(head: Node3D, skin: Material, hair_c: Material, a: Dictionary) -> void:
	var r := 0.155
	MeshKit.add(head, MeshKit.sphere(r, 20), skin, Vector3(0, 0.13, 0)).scale = Vector3(0.95, 1.05, 0.98)
	for sx in [-1, 1]:
		MeshKit.add(head, MeshKit.sphere(0.035, 8), skin, Vector3(sx * 0.148, 0.12, 0.01)).scale = Vector3(0.6, 1, 0.9)
	MeshKit.add(head, MeshKit.sphere(0.03, 10), skin, Vector3(0, 0.11, -0.155)).scale = Vector3(1, 1.1, 1.2)
	var white := Mats.color(Color(0.98, 0.98, 0.98), 0.3)
	var pupil := Mats.color(Color(0.08, 0.06, 0.05), 0.2)
	var eyes: Array = []
	var brows: Array = []
	for sx in [-1, 1]:
		var e := MeshKit.add(head, MeshKit.sphere(0.028, 10), white, Vector3(sx * 0.055, 0.15, -0.135))
		e.scale = Vector3(1, 1.15, 0.6)
		MeshKit.add(e, MeshKit.sphere(0.016, 8), pupil, Vector3(0, -0.002, -0.017))
		eyes.append(e)
		var br := MeshKit.add(head, MeshKit.rounded_box(Vector3(0.055, 0.012, 0.012), 0.005, 1), hair_c, Vector3(sx * 0.058, 0.195, -0.14))
		brows.append(br)
	var mouth := MeshKit.add(head, MeshKit.rounded_box(Vector3(0.06, 0.012, 0.012), 0.005, 1), Mats.color(Color(0.45, 0.15, 0.15), 0.5), Vector3(0, 0.06, -0.148))
	face = {"eyes": eyes, "brows": brows, "mouth": mouth}
	var style: String = a.get("hair", "short")
	match style:
		"short", "messy", "slick":
			var cap := MeshKit.add(head, MeshKit.sphere(r * 1.05, 18, 0.75), hair_c, Vector3(0, 0.19, 0.015))
			cap.scale = Vector3(1.0, 1.0, 1.02)
			if style == "messy":
				var rng := RandomNumberGenerator.new()
				rng.seed = 11
				for i in 7:
					MeshKit.add(head, MeshKit.sphere(0.045, 8), hair_c, Vector3(rng.randf_range(-0.1, 0.1), 0.27 + rng.randf() * 0.03, rng.randf_range(-0.08, 0.1)))
			if style == "slick":
				MeshKit.add(head, MeshKit.rounded_box(Vector3(0.3, 0.05, 0.22), 0.025, 2), hair_c, Vector3(0, 0.26, 0.02), Vector3(-6, 0, 0))
		"bun", "ponytail", "long":
			MeshKit.add(head, MeshKit.sphere(r * 1.07, 18, 0.8), hair_c, Vector3(0, 0.185, 0.02))
			if style == "bun":
				MeshKit.add(head, MeshKit.sphere(0.07, 12), hair_c, Vector3(0, 0.3, 0.09))
			elif style == "ponytail":
				var pt := MeshKit.add(head, MeshKit.capsule(0.045, 0.28), hair_c, Vector3(0, 0.12, 0.18), Vector3(20, 0, 0))
				accessories["ponytail"] = pt
			else:
				MeshKit.add(head, MeshKit.rounded_box(Vector3(0.3, 0.34, 0.12), 0.05, 2), hair_c, Vector3(0, 0.05, 0.09))
		"curly":
			var rng2 := RandomNumberGenerator.new()
			rng2.seed = 5
			for i in 16:
				var ang := rng2.randf() * TAU
				var el := rng2.randf_range(0.0, 1.2)
				var p := Vector3(cos(ang) * cos(el), sin(el), sin(ang) * cos(el)) * (r * 1.05)
				if p.z < -0.08 and p.y < 0.08:
					p.z = -0.02
				MeshKit.add(head, MeshKit.sphere(0.065, 10), hair_c, Vector3(p.x, 0.15 + p.y, p.z + 0.02))
		"bald":
			MeshKit.add(head, MeshKit.sphere(r * 1.02, 16, 0.5), hair_c, Vector3(0, 0.12, 0.04)).scale = Vector3(1.0, 0.6, 0.9)
			MeshKit.add(head, MeshKit.sphere(r * 0.96, 16), skin, Vector3(0, 0.15, 0))
	match a.get("beard", ""):
		"mustache":
			var m := MeshKit.add(head, MeshKit.capsule(0.018, 0.11), hair_c, Vector3(0, 0.085, -0.152), Vector3(0, 0, 90))
			m.scale = Vector3(1, 1, 0.6)
		"beard":
			MeshKit.add(head, MeshKit.sphere(0.12, 14, 0.7), hair_c, Vector3(0, 0.05, -0.06)).scale = Vector3(1.05, 0.9, 1.0)
	if a.get("glasses", false):
		var fm := Mats.color(Color(0.1, 0.1, 0.12), 0.3, 0.4)
		for sx in [-1, 1]:
			MeshKit.add(head, MeshKit.torus(0.026, 0.036, 14), fm, Vector3(sx * 0.055, 0.15, -0.15), Vector3(90, 0, 0))
		MeshKit.add(head, MeshKit.rounded_box(Vector3(0.04, 0.008, 0.008), 0.003, 1), fm, Vector3(0, 0.155, -0.152))
	# disguise moustache (hidden until worn) + cosmetic slots
	var dm := MeshKit.add(head, MeshKit.capsule(0.03, 0.16), Mats.color(Color(0.15, 0.08, 0.05), 0.8), Vector3(0, 0.085, -0.158), Vector3(0, 0, 90))
	dm.visible = false
	accessories["disguise"] = dm
	var hat := Node3D.new()
	head.add_child(hat)
	MeshKit.add(hat, MeshKit.cylinder(0.24, 0.02, 20), Mats.color(Color(0.1, 0.1, 0.1), 0.6), Vector3(0, 0.27, 0))
	MeshKit.add(hat, MeshKit.cylinder(0.14, 0.17, 20, 0.13), Mats.color(Color(0.1, 0.1, 0.1), 0.6), Vector3(0, 0.36, 0))
	MeshKit.add(hat, MeshKit.cylinder(0.142, 0.035, 20), Mats.color(Color(0.7, 0.1, 0.1), 0.6), Vector3(0, 0.3, 0))
	hat.visible = false
	accessories["chapeau"] = hat
	var sun := Node3D.new()
	head.add_child(sun)
	for sx in [-1, 1]:
		MeshKit.add(sun, MeshKit.sphere(0.035, 10, 0.7), Mats.color(Color(0.02, 0.02, 0.02), 0.05, 0.6), Vector3(sx * 0.055, 0.15, -0.155))
	sun.visible = false
	accessories["lunettes"] = sun


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
	rotation.x = fall * PI * 0.5 * fall_dir
	position.y = fall * 0.12
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
			mouth_scale = Vector3(0.6, 3.5, 1.0)
		"laugh", "dance":
			mouth_scale = Vector3(1.3, 3.0, 1.0)
		"embarrassed", "disgust":
			brow_rot = -0.35
			mouth_scale = Vector3(0.8, 0.8, 1.0)
	if talking > 0.0 and emote == "":
		mouth_scale.y = 1.0 + absf(sin(_t * 14.0)) * 2.5
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
