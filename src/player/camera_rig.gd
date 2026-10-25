class_name CameraRig
extends Node3D
## Third-person orbit camera: smooth follow, yaw/pitch, spring arm against walls,
## zoom, small shake for impacts. Driven by mouse, gamepad stick or touch drags.

var target: Character
var yaw := 0.0
var pitch := -0.32
var distance := 3.3
var cam: Camera3D
var arm: SpringArm3D
var _pitch_node: Node3D
var _shake := 0.0
var _follow := Vector3.ZERO
var auto_follow := false          # phones: swing behind the character while walking
var _manual_t := 0.0


func _ready() -> void:
	top_level = true
	_pitch_node = Node3D.new()
	add_child(_pitch_node)
	arm = SpringArm3D.new()
	arm.collision_mask = Layers.STATIC
	arm.margin = 0.25
	var sph := SphereShape3D.new()
	sph.radius = 0.2
	arm.shape = sph
	_pitch_node.add_child(arm)
	var holder := Node3D.new()
	arm.add_child(holder)
	cam = Camera3D.new()
	cam.fov = 68.0
	cam.near = 0.08
	cam.far = 160.0
	holder.add_child(cam)
	cam.current = true


func attach(c: Character) -> void:
	target = c
	_follow = c.global_position + Vector3(0, 1.5, 0)
	global_position = _follow
	yaw = c.rotation.y
	arm.add_excluded_object(c.get_rid())


func add_look(dx: float, dy: float) -> void:
	yaw -= dx
	pitch = clampf(pitch - dy * (-1.0 if Settings.get_v("invert_y") else 1.0), -1.15, 0.55)


func note_manual_look() -> void:
	_manual_t = 1.5


func zoom(delta: float) -> void:
	distance = clampf(distance + delta, 1.6, 6.0)


func shake(amount: float) -> void:
	if not Settings.get_v("reduce_effects"):
		_shake = maxf(_shake, amount)


func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var h := 1.55
	if target.seated_on:
		h = 1.2
	elif target.want_crouch:
		h = 1.05
	if target.is_down():
		h = 0.7
	var goal := target.global_position + Vector3(0, h, 0)
	_follow = _follow.lerp(goal, clampf(delta * 12.0, 0, 1))
	global_position = _follow
	_manual_t -= delta
	if auto_follow and _manual_t <= 0.0 and not target.seated_on:
		var v := Vector2(target.velocity.x, target.velocity.z)
		if v.length() > 0.8:
			var want := atan2(-v.x, -v.y)
			# only nudge when not walking towards the camera (avoids spinning)
			if absf(angle_difference(yaw, want)) < 2.2:
				yaw = lerp_angle(yaw, want, clampf(delta * 1.2, 0, 1))
	rotation = Vector3(0, yaw, 0)
	_pitch_node.rotation.x = pitch
	arm.spring_length = lerpf(arm.spring_length, distance, clampf(delta * 6.0, 0, 1))
	cam.position = Vector3(0.35, 0, 0)
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 2.5)
		cam.position += Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * _shake * 0.08
	# don't let the camera poke through the ceiling
	if cam.global_position.y > 2.85:
		cam.global_position.y = 2.85


func forward_flat() -> Vector3:
	return Vector3(-sin(yaw), 0, -cos(yaw))


func right_flat() -> Vector3:
	return Vector3(cos(yaw), 0, -sin(yaw))
