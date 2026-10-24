class_name Door
extends Node3D
## Hinged door. Opens automatically for characters walking through, keeps the state the
## player chose otherwise. Closed doors block sight and muffle sound. Slamming is loud.

var leaf: AnimatableBody3D
var width := 1.0
var want_open := false
var amount := 0.0          # 0 closed .. 1 open (90°)
var _auto_t := 0.0
var _was_open := false
var display := "Porte"
var swing := 1.0
var _zone_a := ""


func setup(w: float, wood: Material, swing_dir := 1.0) -> void:
	width = w
	swing = swing_dir
	leaf = AnimatableBody3D.new()
	leaf.sync_to_physics = true
	leaf.collision_layer = Layers.STATIC | Layers.OCCLUDERS | Layers.SOUND
	leaf.collision_mask = 0
	add_child(leaf)
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(w - 0.04, 2.1, 0.05)
	cs.shape = b
	cs.position = Vector3((w - 0.04) * 0.5, 1.05, 0)
	leaf.add_child(cs)
	MeshKit.add(leaf, MeshKit.rounded_box(Vector3(w - 0.04, 2.1, 0.05), 0.012, 2), wood, Vector3((w - 0.04) * 0.5, 1.05, 0))
	var chrome := Mats.color(Color(0.8, 0.8, 0.82), 0.2, 0.9)
	for sz in [-1, 1]:
		MeshKit.add(leaf, MeshKit.rounded_box(Vector3(0.14, 0.025, 0.025), 0.01, 2), chrome, Vector3(w - 0.16, 1.0, sz * 0.05))
	MeshKit.add(leaf, MeshKit.rounded_box(Vector3(0.12, 0.2, 0.004), 0.002, 1), Mats.color(Color(0.95, 0.95, 0.9)), Vector3(w * 0.5, 1.55, 0.028))


func ent_id() -> String:
	return get_meta("ent_id", name)


func display_name() -> String:
	return display


func interact_point() -> Vector3:
	return global_position + global_basis.x * width * 0.5 + Vector3(0, 1.0, 0)


func is_open() -> bool:
	return amount > 0.3


func _physics_process(delta: float) -> void:
	var target := 1.0 if want_open else 0.0
	_auto_t -= delta
	if _auto_t > 0.0:
		target = 1.0
	elif Game.session and Game.session.is_authority():
		for c in Game.session.characters.values():
			if is_instance_valid(c) and c.global_position.distance_to(interact_point() - Vector3(0, 1, 0)) < 1.4 and c.wants_door():
				_auto_t = 1.2
				target = 1.0
				break
	var prev := amount
	amount = move_toward(amount, target, delta * 2.2)
	if prev != amount:
		leaf.rotation.y = -amount * PI * 0.5 * swing
	var open_now := amount > 0.05
	if open_now != _was_open:
		_was_open = open_now
		if Game.session and Game.session.is_authority():
			if open_now:
				Game.session.emit_sound(interact_point(), 22.0, "door_open", "", ent_id())
			elif not get_meta("slammed", false):
				Game.session.emit_sound(interact_point(), 35.0, "door_close", "", ent_id())
			set_meta("slammed", false)
	# Opaque only when (nearly) closed
	leaf.collision_layer = Layers.STATIC | ((Layers.OCCLUDERS | Layers.SOUND) if amount < 0.6 else 0)


func get_actions(_actor: Node) -> Array:
	var out: Array = []
	if want_open:
		out.append({"id": "close", "label": "Fermer la porte", "time": 0.0})
		out.append({"id": "slam", "label": "Claquer la porte", "time": 0.0, "noise": 0.0, "sus": 0.4, "act": "slam_door", "sev": 1})
	else:
		out.append({"id": "open", "label": "Ouvrir la porte", "time": 0.0})
	return out


func perform(actor: Node, action: String, _params: Dictionary) -> Dictionary:
	match action:
		"open":
			want_open = true
		"close":
			want_open = false
			_auto_t = 0.0
		"slam":
			want_open = false
			_auto_t = 0.0
			amount = 0.12
			set_meta("slammed", true)
			Game.session.emit_sound(interact_point(), 78.0, "door_slam", actor.char_id(), ent_id())
	return {"ok": true}
