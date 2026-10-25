class_name Prop
extends RigidBody3D
## A physical, interactive object. Mass / friction / restitution come from its kind.
## Impacts make material-dependent sounds that also feed the AI hearing system.

const SOUND_FOR := {
	"wood": ["hit_wood_light", "hit_wood_heavy"], "metal": ["hit_metal", "hit_metal"],
	"plastic": ["hit_plastic", "hit_plastic"], "cardboard": ["hit_cardboard", "hit_cardboard"],
	"paper": ["hit_paper", "hit_paper"], "ceramic": ["hit_ceramic", "hit_ceramic"],
	"fabric": ["bump", "bump"], "chair": ["hit_plastic", "chair_fall"], "rubber": ["duck_squeak", "boing"],
}

var kind := ""
var display := ""
var tags: PackedStringArray = []
var mat_kind := "plastic"
var carry := "light"            # light (pocket/hold), medium (hold, slower), heavy (push only)
var pocketable := false
var item_id := ""               # inventory item this prop corresponds to
var fragile := false
var contraband := 0.0
var owner_id := ""              # character owning the object (desk chair, stapler...)
var home: Transform3D
var last_touched_by := ""
var last_touched_time := -100.0
var held_by: Node = null
var inside_of := ""             # container ent id when hidden
var remote := false             # client replica in multiplayer
var placed_by := ""             # who placed a trap/gadget

# chair specifics
var seat_height := 0.0
var occupant := ""
var seat_low := false
var cushion_id := ""
var seat_mesh: Node3D

var _prev_vel := Vector3.ZERO
var _last_sound_t := -10.0
var _roll_player: AudioStreamPlayer3D
var _hold_point := Vector3.ZERO
var _hold_basis := Basis()
var _broken := false


func _ready() -> void:
	contact_monitor = true
	max_contacts_reported = 3
	body_entered.connect(_on_body_entered)
	can_sleep = true
	home = global_transform
	if "chair" in tags:
		_roll_player = SoundFx.make_loop_emitter(self, "chair_roll_loop")
		_roll_player.volume_db = -60.0


func ent_id() -> String:
	return get_meta("ent_id", name)


func display_name() -> String:
	return display


func interact_point() -> Vector3:
	return global_position + Vector3(0, 0.3 if seat_height > 0 else 0.0, 0)


func is_available() -> bool:
	return inside_of == "" and visible and not _broken


func home_distance() -> float:
	return global_position.distance_to(home.origin)


var net_xform := Transform3D()
var _has_net := false


func apply_net(t: Transform3D) -> void:
	net_xform = t
	_has_net = true


func _physics_process(delta: float) -> void:
	if remote:
		if _has_net:
			var t := global_transform
			if t.origin.distance_to(net_xform.origin) > 2.5:
				global_transform = net_xform
			else:
				t.origin = t.origin.lerp(net_xform.origin, clampf(delta * 15.0, 0.0, 1.0))
				t.basis = t.basis.slerp(net_xform.basis.orthonormalized(), clampf(delta * 15.0, 0.0, 1.0))
				global_transform = t
		return
	_prev_vel = linear_velocity
	if _roll_player:
		var sp := Vector2(linear_velocity.x, linear_velocity.z).length()
		var target := -60.0 if sp < 0.25 or freeze else lerpf(-18.0, -2.0, clampf(sp / 3.0, 0, 1))
		_roll_player.volume_db = lerpf(_roll_player.volume_db, target, 0.2)
		if target > -50.0 and not _roll_player.playing:
			_roll_player.play()
		elif target <= -50.0 and _roll_player.playing and _roll_player.volume_db < -45.0:
			_roll_player.stop()
	if global_position.y < -5.0:
		# safety net: never lose an object through the floor
		reset_home()


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if held_by == null or remote:
		return
	# Physical carry: a spring pulls the object to the hold point, so it still collides.
	var to := _hold_point - state.transform.origin
	var want := to * 14.0
	if want.length() > 7.0:
		want = want.normalized() * 7.0
	state.linear_velocity = state.linear_velocity.lerp(want, 0.5)
	var q_cur := state.transform.basis.get_rotation_quaternion()
	var q_tgt := _hold_basis.get_rotation_quaternion()
	var dq := q_tgt * q_cur.inverse()
	var ang := dq.get_angle()
	if ang > PI:
		ang -= TAU
	state.angular_velocity = dq.get_axis() * ang * 8.0 if absf(ang) > 0.01 else Vector3.ZERO


func set_hold_target(p: Vector3, b: Basis) -> void:
	_hold_point = p
	_hold_basis = b


func begin_hold(by: Node) -> void:
	held_by = by
	gravity_scale = 0.0
	linear_damp = 4.0
	angular_damp = 6.0
	freeze = false
	sleeping = false
	touch(by)


func end_hold() -> void:
	held_by = null
	gravity_scale = 1.0
	linear_damp = get_meta("base_ldamp", 0.1)
	angular_damp = get_meta("base_adamp", 0.2)


func touch(by: Node) -> void:
	if by and by.has_method("char_id"):
		last_touched_by = by.char_id()
		last_touched_time = Game.time()


func reset_home() -> void:
	global_transform = home
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO


func hide_inside(container_id: String) -> void:
	inside_of = container_id
	visible = false
	freeze = true
	collision_layer = 0
	collision_mask = 0


func reveal_at(t: Transform3D) -> void:
	inside_of = ""
	visible = true
	collision_layer = get_meta("base_layer", Layers.PROPS)
	collision_mask = get_meta("base_mask", Layers.STATIC | Layers.PROPS | Layers.CHARACTERS)
	global_transform = t
	freeze = false
	sleeping = false
	linear_velocity = Vector3.ZERO


func _on_body_entered(body: Node) -> void:
	if remote or held_by != null:
		return
	var other_v := Vector3.ZERO
	if body is RigidBody3D:
		other_v = (body as RigidBody3D).linear_velocity
	var speed := (_prev_vel - other_v).length()
	if speed < 0.9:
		return
	var now := Game.time()
	if has_meta("ball_by") and body is Character and Game.session and Game.session.is_authority():
		var by := String(get_meta("ball_by"))
		remove_meta("ball_by")
		Game.session.paper_ball_hit(body as Character, by)
	if has_meta("thrown_t") and Game.session and Game.session.is_authority():
		if now - float(get_meta("thrown_t")) < 3.0:
			Game.session.on_throw_landed(self, String(get_meta("thrown_by", "")))
		remove_meta("thrown_t")
	if seat_height > 0.0 and occupant != "" and has_meta("ride_t") and speed > 2.3 and not body is Character and Game.session and Game.session.is_authority():
		Game.session.chair_crash(self, _prev_vel)
	if body is Character and speed > 2.6 and mass * speed > 12.0:
		(body as Character).take_hit(_prev_vel * mass * 0.08, self)
	if now - _last_sound_t < 0.12:
		return
	_last_sound_t = now
	var energy := clampf(speed * sqrt(mass) / 6.0, 0.0, 1.5)
	var heavy := energy > 0.55
	var names: Array = SOUND_FOR.get(mat_kind, ["bump", "bump"])
	var loud := clampf(18.0 + energy * 55.0, 10.0, 92.0)
	if fragile and speed > 3.2 and not _broken:
		shatter()
		return
	if "papers" in tags and speed > 1.6 and not _broken:
		scatter()
		return
	var s: String = names[1] if heavy else names[0]
	var sess := Game.session
	if sess and now >= float(sess.quiet_until):
		sess.emit_sound(global_position, loud, s, last_touched_by if now - last_touched_time < 6.0 else "", ent_id())


## A falling stack of documents bursts into individual sheets (slippery!).
func scatter() -> void:
	_broken = true
	var sess := Game.session
	if sess:
		var who := last_touched_by if Game.time() - last_touched_time < 8.0 else ""
		sess.emit_sound(global_position, 55.0, "papers_fall", who, ent_id())
		sess.spawn_paper_mess(global_position, 6, who)
	visible = false
	collision_layer = 0
	collision_mask = 0
	freeze = true
	# the stack comes back to its desk after a while (someone tidies up)
	get_tree().create_timer(90.0).timeout.connect(func():
		_broken = false
		visible = true
		collision_layer = get_meta("base_layer", Layers.PROPS)
		collision_mask = get_meta("base_mask", Layers.STATIC)
		freeze = false
		reset_home())


func shatter() -> void:
	_broken = true
	var sess := Game.session
	if sess:
		sess.emit_sound(global_position, 75.0, "break_ceramic", last_touched_by if Game.time() - last_touched_time < 8.0 else "", ent_id())
		sess.on_prop_broken(self)
	visible = false
	collision_layer = 0
	collision_mask = 0
	freeze = true


# ------------------------------------------------------------------ interaction
func get_actions(actor: Node) -> Array:
	var out: Array = []
	if not is_available() or held_by != null:
		return out
	if seat_height > 0.0:
		if global_basis.y.dot(Vector3.UP) < 0.8:
			# tipped over: put it back on its wheels first (or drag it as it is)
			out.append({"id": "straighten", "label": "Redresser la chaise", "time": 0.6})
			out.append({"id": "hold", "label": "Traîner", "time": 0.3})
			out.append({"id": "push", "label": "Pousser", "time": 0.0})
			return out
		if occupant != "":
			# someone is sitting on it: send them for a ride
			if occupant != actor.char_id():
				out.append({"id": "chair_ride", "label": "Pousser la chaise (avec quelqu'un dessus !)", "time": 0.0, "noise": 15.0, "sus": 0.6, "prank": true, "act": "chair_ride", "sev": 2})
			return out
		if occupant == "":
			out.append({"id": "sit", "label": "S'asseoir", "time": 0.0})
			if owner_id != "" and actor.char_id() != owner_id and not seat_low:
				out.append({"id": "lower_seat", "label": "Baisser le siège", "time": 2.5, "noise": 12.0, "sus": 0.7, "prank": true, "act": "lower_seat", "sev": 1})
			if not has_meta("itch_by") and actor.has_method("has_item") and actor.has_item("poil_gratter"):
				out.append({"id": "itch_powder", "label": "Saupoudrer de poil à gratter", "time": 1.5, "noise": 4.0, "sus": 0.8, "prank": true, "act": "itch_trap", "sev": 2})
			if cushion_id == "" and actor.has_method("has_item") and actor.has_item("coussin_peteur"):
				out.append({"id": "place_cushion", "label": "Poser le coussin péteur", "time": 1.5, "noise": 6.0, "sus": 0.9, "prank": true, "act": "cushion", "sev": 3})
		out.append({"id": "push", "label": "Pousser", "time": 0.0, "noise": 0.0})
		out.append({"id": "kick", "label": "Lancer la chaise", "time": 0.0, "noise": 20.0, "sus": 0.5, "act": "kick_chair", "sev": 1})
		if carry != "heavy":
			out.append({"id": "hold", "label": "Traîner", "time": 0.3})
		return out
	if pocketable:
		out.append({"id": "take", "label": "Prendre", "time": 0.4, "noise": 4.0, "sus": contraband * 0.8, "act": "steal" if owner_id != "" and owner_id != actor.char_id() else ""})
	if carry in ["light", "medium"] and not pocketable:
		out.append({"id": "hold", "label": "Porter", "time": 0.3, "noise": 4.0, "sus": contraband})
	if "duck" in tags:
		out.append({"id": "squeak", "label": "Couiner", "time": 0.0, "noise": 35.0})
	if "trash" in tags:
		out.append({"id": "kick_over", "label": "Renverser", "time": 0.0, "noise": 45.0, "sus": 0.6, "act": "vandalism", "sev": 1})
	if "coffee" in tags:
		out.append({"id": "drink", "label": "Boire", "time": 1.5, "noise": 8.0})
	if "boxes" in tags or carry == "heavy" or "plant" in tags:
		out.append({"id": "shove", "label": "Bousculer", "time": 0.0, "noise": 10.0, "sus": 0.3})
	if carry != "heavy" and not pocketable:
		out.append({"id": "push", "label": "Pousser", "time": 0.0})
	return out


## Executed by the authority (Session) once the action has been validated.
func perform(actor: Node, action: String, params: Dictionary) -> Dictionary:
	var sess := Game.session
	touch(actor)
	var dir: Vector3 = (global_position - actor.global_position)
	dir.y = 0
	dir = dir.normalized() if dir.length() > 0.01 else -actor.global_basis.z
	match action:
		"push":
			sleeping = false
			apply_central_impulse(dir * mass * 1.6 + Vector3.UP * mass * 0.1)
		"chair_ride":
			if occupant == "":
				return {"ok": false, "msg": "Plus personne dessus."}
			sess.launch_chair(self, actor.char_id(), dir, 6.5)
		"shove":
			sleeping = false
			apply_impulse(dir * mass * 2.4, Vector3(0, 0.6, 0))
		"kick":
			sleeping = false
			apply_central_impulse(dir * mass * 4.5)
			sess.emit_sound(global_position, 35.0, "chair_squeak", actor.char_id(), ent_id())
		"kick_over":
			sleeping = false
			apply_impulse(dir * mass * 3.0, Vector3(0, 0.5, 0))
			sess.spawn_paper_mess(global_position + dir * 0.4, 4, actor.char_id())
		"squeak":
			sess.emit_sound(global_position, 35.0, "duck_squeak", actor.char_id(), ent_id())
		"lower_seat":
			seat_low = true
			if seat_mesh:
				seat_mesh.position.y -= 0.18
			sess.emit_sound(global_position, 18.0, "chair_squeak", actor.char_id(), ent_id())
		"place_cushion":
			if not actor.consume_item("coussin_peteur"):
				return {"ok": false, "msg": "Tu n'as pas de coussin."}
			var cush: Prop = sess.spawn_prop("cushion", global_transform.origin + Vector3(0, seat_height + 0.05, 0), actor.char_id())
			cush.freeze = true
			cush.global_transform.basis = global_transform.basis
			cushion_id = cush.ent_id()
		"drink":
			sess.drink_coffee(actor, self)
		"itch_powder":
			if not actor.consume_item("poil_gratter"):
				return {"ok": false, "msg": "Tu n'as pas de poil à gratter."}
			set_meta("itch_by", actor.char_id())
		"straighten":
			sleeping = false
			global_transform = Transform3D(Basis(Vector3.UP, global_rotation.y), global_position + Vector3(0, 0.15, 0))
			linear_velocity = Vector3.ZERO
			angular_velocity = Vector3.ZERO
	return {"ok": true}


## Called when a character sits on this chair (authority side).
func on_sat(by: Node) -> void:
	occupant = by.char_id()
	freeze = true
	if seat_low and Game.session and Game.session.is_authority():
		Game.session.low_seat_triggered(by, self)
	if has_meta("itch_by") and Game.session and Game.session.is_authority():
		var who: String = get_meta("itch_by")
		remove_meta("itch_by")
		Game.session.itch_triggered(by, who)
	if cushion_id != "" and Game.session and Game.session.is_authority():
		var cush := Game.session.world.ent(cushion_id) as Prop
		cushion_id = ""
		if cush:
			Game.session.cushion_triggered(by, cush, self)


func on_stood() -> void:
	if seat_low and occupant == owner_id and occupant != "":
		# the victim fixes the seat height when getting up
		seat_low = false
		if seat_mesh:
			seat_mesh.position.y += 0.18
	occupant = ""
	freeze = false
	sleeping = false
