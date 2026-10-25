class_name Character
extends CharacterBody3D
## Physical character shared by the player, coworkers and the director.
## Movement + collisions, pushing props, tripping/slipping/falling/getting up, sitting,
## carrying, footsteps (audible to AI), speech bubbles with gibberish voices, inventory.

signal fell(cause: String)
signal spoke(text: String)

enum KD { OK, STUMBLE, FALLING, FALLEN, GETUP }

const WALK := 1.55
const RUN := 3.7
const CROUCH := 0.85
const NPC_WALK := 1.3
const MAX_POCKET := 4

var id := ""
var nick := ""
var role := "employee"           # employee | director
var archetype := ""
var traits: Dictionary = {}
var voice_id := "player"
var voice_pitch := 1.0
var desk_index := -1
var appearance: Dictionary = {}
var is_player := false
var is_remote := false            # replica driven by network snapshots
var ai_driven := false

var humanoid: Humanoid
var nav: NavigationAgent3D
var bubble: Label3D
var alert_icon: Label3D

# movement intents
var move_dir := Vector3.ZERO
var want_run := false
var want_crouch := false
var face_dir := Vector3.ZERO      # optional facing override
var walk_speed := WALK
var nav_target := Vector3.INF
var _safe_vel := Vector3.ZERO
var _has_safe := false
var _stuck_t := 0.0
var _last_pos := Vector3.ZERO

# state
var kd := KD.OK
var _kd_t := 0.0
var _fall_cause := ""
var _fall_by := ""
var balance := 1.0
var seated_on: Prop = null
var held: Prop = null
var items: Array[String] = []
var passive: Array[String] = []   # owned passive gadgets (sac_sport...)
var cosmetics: Array[String] = []
var disguised_until := -1.0
var action: Dictionary = {}       # current timed action (set by Session)
var pretending_until := -1.0
var last_work_time := -999.0
var emote_until := 0.0
var _say_t := 0.0
var _step_sign := 1.0
var _last_slip_t := -10.0
var _last_bump_t := -10.0
var productivity := 60.0
var money := 0


func setup(p_id: String, p_nick: String, p_role: String, look: Dictionary, p_voice: String, pitch := 1.0) -> void:
	id = p_id
	nick = p_nick
	role = p_role
	appearance = look
	voice_id = p_voice
	voice_pitch = pitch
	name = "Char_" + p_id


func _ready() -> void:
	collision_layer = Layers.CHARACTERS
	collision_mask = Layers.STATIC | Layers.PROPS | Layers.CHARACTERS
	floor_snap_length = 0.3
	floor_max_angle = deg_to_rad(50)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.28
	cap.height = 1.7
	cs.shape = cap
	cs.position = Vector3(0, 0.85, 0)
	cs.name = "Shape"
	add_child(cs)
	humanoid = Humanoid.new()
	add_child(humanoid)
	humanoid.build(appearance)
	humanoid.posture = 0.8 if role == "director" else (-0.5 if traits.get("courage", 0.5) < 0.2 else 0.0)
	bubble = Label3D.new()
	bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bubble.no_depth_test = false
	bubble.fixed_size = false
	bubble.pixel_size = 0.0032
	bubble.font_size = 44
	bubble.outline_size = 14
	bubble.outline_modulate = Color(0.05, 0.05, 0.08, 0.95)
	bubble.modulate = Color(1, 1, 1)
	bubble.width = 520
	bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bubble.position = Vector3(0, 2.25, 0)
	bubble.visible = false
	var f: Font = load("res://assets/fonts/Fredoka.ttf")
	if f:
		bubble.font = f
	add_child(bubble)
	alert_icon = Label3D.new()
	alert_icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	alert_icon.font_size = 96
	alert_icon.outline_size = 18
	alert_icon.pixel_size = 0.004
	alert_icon.position = Vector3(0, 2.15, 0)
	alert_icon.visible = false
	var lf: Font = load("res://assets/fonts/LilitaOne-Regular.ttf")
	if lf:
		alert_icon.font = lf
	add_child(alert_icon)
	if ai_driven:
		nav = NavigationAgent3D.new()
		nav.path_desired_distance = 0.5
		nav.target_desired_distance = 0.45
		nav.radius = 0.35
		nav.height = 1.7
		nav.avoidance_enabled = true
		nav.max_speed = RUN
		nav.neighbor_distance = 4.0
		nav.time_horizon_agents = 1.2
		add_child(nav)
		nav.velocity_computed.connect(func(v: Vector3):
			_safe_vel = v
			_has_safe = true)
	walk_speed = NPC_WALK if ai_driven else WALK
	if role == "director":
		walk_speed = 1.45
	_last_pos = global_position


func char_id() -> String:
	return id


func is_director() -> bool:
	return role == "director"


func display_name() -> String:
	return nick


func is_down() -> bool:
	return kd in [KD.FALLING, KD.FALLEN, KD.GETUP]


func can_act() -> bool:
	return kd == KD.OK


func wants_door() -> bool:
	return velocity.length() > 0.3 or nav_target != Vector3.INF


func is_disguised() -> bool:
	return Game.time() < disguised_until


func eye_position() -> Vector3:
	var h := 1.55
	if seated_on:
		h = 1.1
	elif want_crouch:
		h = 0.95
	if is_down():
		h = 0.3
	return global_position + Vector3(0, h * (humanoid.scale.y if humanoid else 1.0), 0)


func forward() -> Vector3:
	return -global_basis.z


# ------------------------------------------------------------------ inventory
func has_item(item: String) -> bool:
	return item in items or item in passive


func add_item(item: String) -> bool:
	var cap := MAX_POCKET + (2 if "sac_sport" in passive else 0)
	if items.size() >= cap:
		return false
	items.append(item)
	return true


func consume_item(item: String) -> bool:
	var i := items.find(item)
	if i < 0:
		return false
	items.remove_at(i)
	return true


func pocket_items() -> Array[String]:
	return items


## Bulky suspicious things visible on the character (held prop or unconcealed gadgets).
func visible_contraband() -> float:
	var c := 0.0
	if held:
		c = held.contraband
	if not "sac_sport" in passive:
		for it in items:
			c = maxf(c, float(Data.item_info(it).get("contraband", 0.0)) * 0.6)
	return c


# ------------------------------------------------------------------ navigation (AI)
func go_to(p: Vector3, run := false) -> void:
	if nav == null:
		return
	nav_target = p
	nav.target_position = p
	want_run = run
	_stuck_t = 0.0


func stop() -> void:
	nav_target = Vector3.INF
	move_dir = Vector3.ZERO
	want_run = false


func arrived(tol := 0.6) -> bool:
	if nav_target == Vector3.INF:
		return true
	var d := Vector2(global_position.x - nav_target.x, global_position.z - nav_target.z).length()
	return d < tol or (nav.is_navigation_finished() and d < 1.6)


# ------------------------------------------------------------------ physics
# --- network replication
var net_pos := Vector3.INF          # replica: latest server position
var net_yaw := 0.0
var net_flags: Dictionary = {}
var net_drive := Vector3.INF        # server: position reported by the owning client
var net_drive_yaw := 0.0


func apply_net(pos: Vector3, yaw: float, flags: Dictionary) -> void:
	net_pos = pos
	net_yaw = yaw
	net_flags = flags


## Compact animation/state flags sent in snapshots.
func net_state() -> Dictionary:
	var f := {}
	if seated_on:
		f["s"] = seated_on.ent_id()
	if held:
		f["h"] = held.ent_id()
	if want_crouch:
		f["c"] = 1
	if humanoid.typing:
		f["t"] = 1
	if action.size() > 0:
		f["b"] = 1
	if humanoid.emote != "":
		f["e"] = humanoid.emote
	if humanoid.fall > 0.0:
		f["f"] = snappedf(humanoid.fall, 0.01)
		f["fd"] = humanoid.fall_dir
	if humanoid.getting_up > 0.0:
		f["g"] = snappedf(humanoid.getting_up, 0.01)
	if humanoid.stumble > 0.0:
		f["st"] = snappedf(humanoid.stumble, 0.01)
	if humanoid.look_target != Vector3.INF:
		f["l"] = humanoid.look_target
	if is_disguised():
		f["d"] = 1
	return f


func _remote_update(delta: float) -> void:
	if net_pos == Vector3.INF:
		return
	var prev := global_position
	if global_position.distance_to(net_pos) > 3.0:
		global_position = net_pos
	else:
		global_position = global_position.lerp(net_pos, clampf(delta * 12.0, 0.0, 1.0))
	rotation.y = lerp_angle(rotation.y, net_yaw, clampf(delta * 12.0, 0.0, 1.0))
	var f := net_flags
	humanoid.sit = move_toward(humanoid.sit, 1.0 if f.has("s") else 0.0, delta * 3.0)
	humanoid.crouch = move_toward(humanoid.crouch, 1.0 if f.has("c") else 0.0, delta * 4.0)
	humanoid.carrying = f.has("h")
	humanoid.typing = f.has("t")
	humanoid.busy = f.has("b") and not f.has("t")
	var e: String = f.get("e", "")
	if e != humanoid.emote:
		humanoid.emote = e
		humanoid.emote_t = 0.0
	humanoid.fall = float(f.get("f", 0.0))
	humanoid.fall_dir = float(f.get("fd", 1.0))
	humanoid.getting_up = float(f.get("g", 0.0))
	humanoid.stumble = float(f.get("st", 0.0))
	humanoid.look_target = f.get("l", Vector3.INF)
	humanoid.set_accessory("disguise", f.has("d"))
	var moved := Vector2(global_position.x - prev.x, global_position.z - prev.z).length()
	var hspeed := moved / maxf(delta, 0.0001)
	var stride := lerpf(0.68, 1.05, clampf((hspeed - 2.0) / 1.5, 0, 1))
	var ph := humanoid.phase
	humanoid.phase += moved / stride * PI
	if floor(ph / PI) != floor(humanoid.phase / PI) and hspeed > 0.3 and humanoid.sit < 0.5:
		_footstep(hspeed)
	humanoid.speed = lerpf(humanoid.speed, hspeed * (1.0 - humanoid.sit), 0.25)
	humanoid.talking = maxf(0.0, _say_t)
	_say_t -= delta
	if _say_t <= 0.0 and bubble.visible:
		bubble.visible = false


func _physics_process(delta: float) -> void:
	if is_remote:
		_remote_update(delta)
		return
	_update_kd(delta)
	if seated_on:
		if not is_instance_valid(seated_on) or not seated_on.is_available():
			stand_up()
		else:
			var b := seated_on.global_basis
			var sp := seated_on.global_position + b * Vector3(0, 0.0, 0.04)
			sp.y = seated_on.global_position.y if seated_on.global_position.y < 0.3 else 0.0
			global_position = sp
			var f := -b.z
			f.y = 0
			if f.length() > 0.1:
				rotation.y = lerp_angle(rotation.y, atan2(-f.x, -f.z), 0.3)
			velocity = Vector3.ZERO
			_anim(delta, 0.0)
			return
	if kd == KD.FALLING and _fling != Vector3.ZERO and not is_remote:
		# cartoon flight: slide/fly along the launch velocity until landing
		velocity.x = _fling.x
		velocity.z = _fling.z
		if _fling.y > 0.0:
			velocity.y = _fling.y
			_fling.y = 0.0
		velocity.y -= 9.8 * delta
		move_and_slide()
		var damp := 0.25 if is_on_floor() else 0.8
		_fling.x *= pow(damp, delta)
		_fling.z *= pow(damp, delta)
		if Vector2(_fling.x, _fling.z).length() < 0.1 and is_on_floor():
			_fling = Vector3.ZERO
		_anim(delta, 0.0)
		return
	if kd == KD.FALLING or kd == KD.FALLEN or kd == KD.GETUP:
		velocity = Vector3.ZERO
		_anim(delta, 0.0)
		return
	var dir := move_dir
	if ai_driven and nav_target != Vector3.INF and kd == KD.OK:
		var nxt := nav.get_next_path_position()
		var d := nxt - global_position
		d.y = 0
		dir = d.normalized() if d.length() > 0.05 else Vector3.ZERO
		if arrived():
			stop()
			dir = Vector3.ZERO
	var spd := walk_speed
	if want_run:
		spd = RUN if role != "director" else 3.0
	if want_crouch:
		spd = CROUCH
	if held and held.carry == "medium":
		spd *= 0.7
	if action.size() > 0:
		spd = 0.0
	if kd == KD.STUMBLE:
		spd *= 0.5
	elif kd != KD.OK:
		spd = 0.0
		dir = Vector3.ZERO
	var desired := dir * spd
	if net_drive != Vector3.INF and kd != KD.FALLING and kd != KD.FALLEN and kd != KD.GETUP:
		# authoritative server moving a remote human: chase the reported position at a
		# plausible speed; walls and props still collide (no teleporting through them)
		var to := net_drive - global_position
		to.y = 0
		desired = to / maxf(delta, 0.001)
		var cap := (RUN if want_run else walk_speed) * 1.35 + 0.3
		if kd == KD.STUMBLE:
			cap *= 0.5
		if desired.length() > cap:
			desired = desired.normalized() * cap
		if to.length() > 4.0:
			desired = Vector3.ZERO
	if ai_driven and nav and nav.avoidance_enabled:
		nav.velocity = desired
		if _has_safe:
			desired = _safe_vel
	var hv := Vector3(velocity.x, 0, velocity.z)
	var accel := 12.0 if desired.length() > 0.01 else 14.0
	if net_drive != Vector3.INF:
		accel = 200.0
	if kd == KD.STUMBLE:
		accel = 3.0
	hv = hv.move_toward(desired, accel * delta)
	velocity.x = hv.x
	velocity.z = hv.z
	if not is_on_floor():
		velocity.y -= 9.8 * delta
	else:
		velocity.y = maxf(velocity.y, -0.1)
	var before := global_position
	move_and_slide()
	_handle_collisions(hv)
	var moved := Vector2(global_position.x - before.x, global_position.z - before.z).length()
	# facing
	var fd := face_dir if face_dir != Vector3.ZERO else (hv if hv.length() > 0.15 else Vector3.ZERO)
	if net_drive != Vector3.INF and face_dir == Vector3.ZERO:
		fd = Vector3(-sin(net_drive_yaw), 0, -cos(net_drive_yaw))
	if fd != Vector3.ZERO and kd != KD.FALLEN and kd != KD.FALLING:
		rotation.y = lerp_angle(rotation.y, atan2(-fd.x, -fd.z), clampf(delta * 9.0, 0, 1))
	# stuck detection for AI
	if ai_driven and nav_target != Vector3.INF:
		if moved < 0.2 * delta * spd:
			_stuck_t += delta
			if _stuck_t > 2.5:
				_stuck_t = 0.0
				velocity += Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * 1.5
		else:
			_stuck_t = 0.0
	_anim(delta, moved)
	_update_hold()
	_unstick(delta)


var _high_t := 0.0
var _inside_check := 0.0
var _fling := Vector3.ZERO        # cartoon launch velocity while falling
var _flip := 0.0                  # extra somersaults during the fall
var _stars: Node3D = null
var _inside_t := 0.0


## Safety net: never stay perched on furniture/props (e.g. after a physics shove).
func _unstick(delta: float) -> void:
	if global_position.y > 0.35 and kd == KD.OK and seated_on == null:
		_high_t += delta
		if _high_t > 0.8 and Game.session:
			_high_t = 0.0
			var p: Vector3 = Game.session.world.nav_closest(global_position)
			p.y = 0.02
			global_position = p
			velocity = Vector3.ZERO
	else:
		_high_t = 0.0
	# inside furniture (off the walkable area) for a while -> back to the nearest walkable spot
	_inside_check -= delta
	if _inside_check <= 0.0 and Game.session and Game.session.player == self and kd == KD.OK and seated_on == null and not is_remote:
		_inside_check = 0.5
		var flat := Vector3(global_position.x, 0, global_position.z)
		var np: Vector3 = Game.session.world.nav_closest(flat)
		if Vector2(np.x - flat.x, np.z - flat.z).length() > 0.45:
			_inside_t += 0.5
			if _inside_t >= 1.0:
				_inside_t = 0.0
				global_position = Vector3(np.x, 0.02, np.z)
				velocity = Vector3.ZERO
		else:
			_inside_t = 0.0
	if global_position.y < -2.0 and Game.session:
		var p2: Vector3 = Game.session.world.nav_closest(Vector3(global_position.x, 0, global_position.z))
		global_position = p2 + Vector3(0, 0.05, 0)
		velocity = Vector3.ZERO


func _anim(delta: float, moved: float) -> void:
	var hspeed := moved / maxf(delta, 0.0001)
	var stride := lerpf(0.68, 1.05, clampf((hspeed - 2.0) / 1.5, 0, 1))
	var prev := humanoid.phase
	humanoid.phase += moved / stride * PI
	if floor(prev / PI) != floor(humanoid.phase / PI) and hspeed > 0.3:
		_footstep(hspeed)
	if hspeed < 0.2:
		# settle feet to a neutral phase so idle pose is clean
		humanoid.phase = lerpf(humanoid.phase, round(humanoid.phase / PI) * PI, 0.1)
	humanoid.speed = lerpf(humanoid.speed, hspeed, 0.25)
	humanoid.sit = move_toward(humanoid.sit, 1.0 if seated_on else 0.0, delta * 3.0)
	humanoid.seat_low = seated_on != null and seated_on.seat_low
	humanoid.crouch = move_toward(humanoid.crouch, 1.0 if want_crouch and not seated_on else 0.0, delta * 4.0)
	humanoid.carrying = held != null
	humanoid.busy = action.size() > 0 and not humanoid.typing
	humanoid.talking = maxf(0.0, _say_t)
	if Game.time() > emote_until and humanoid.emote != "":
		humanoid.emote = ""
	humanoid.emote_t += delta
	_say_t -= delta
	if _say_t <= 0.0 and bubble.visible:
		bubble.visible = false


func _footstep(hspeed: float) -> void:
	var sess: Node = Game.session
	if sess == null:
		return
	var zone: String = sess.world.zone_at(global_position)
	var hard := zone in ["corridor", "hall", "break", "toilets", "meeting", "boss_office", "archives"]
	var base := "step_tile" if hard else "step_carpet"
	var loud := 16.0 + (8.0 if hard else 0.0)
	if hspeed > 2.4:
		loud += 24.0
	if want_crouch:
		loud = 5.0
	if role == "director":
		base = "step_boss" if hard else "step_carpet"
		loud += 12.0
		if randf() < 0.08:
			sess.emit_sound(global_position + Vector3(0, 1, 0), loud * 0.7, "keys_jingle", "", "", "footstep")
	sess.emit_sound(global_position, loud, SoundFx.pick_variant(base, 4), id, "", "footstep")


func _handle_collisions(hv: Vector3) -> void:
	var now := Game.time()
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var other := col.get_collider()
		if other is Prop:
			var p := other as Prop
			if p.freeze or p.held_by == self:
				continue
			var n := col.get_normal()
			n.y = 0
			var into := -hv.dot(n)
			if into > 0.05:
				var push_mass := minf(p.mass, 35.0)
				p.sleeping = false
				p.apply_impulse(-n * into * push_mass * 0.12 * (0.5 if p.carry == "heavy" else 1.0), col.get_position() - p.global_position + Vector3(0, -0.05, 0))
				p.touch(self)
			if "slippery" in p.tags and hv.length() > 1.1 and now - _last_slip_t > 1.0:
				_last_slip_t = now
				var chance := 0.95 if "banana" in p.tags else 0.08 + 0.25 * float(traits.get("clumsiness", 0.3)) + (0.3 if want_run else 0.0)
				if randf() < chance:
					slip("banana" if "banana" in p.tags else "papers", p.placed_by if p.placed_by != "" else p.last_touched_by)
					return
			if hv.length() > 2.4 and into > 1.5 and now - _last_bump_t > 0.8:
				_last_bump_t = now
				if p.mass > 1.0:
					Game.session.emit_sound(global_position + Vector3(0, 0.5, 0), 40.0, "bump", id, p.ent_id())
					if randf() < 0.35 + 0.4 * float(traits.get("clumsiness", 0.3)):
						stumble("bump", p.last_touched_by if p.last_touched_by != id else "")
		elif other is Character and hv.length() > 2.5 and now - _last_bump_t > 1.0:
			_last_bump_t = now
			var oc := other as Character
			Game.session.emit_sound(global_position + Vector3(0, 1, 0), 38.0, "bump", id, "")
			oc.take_hit(hv * 6.0, self)
			stumble("collision", "")
			Game.session.on_bumped(oc, self)
		elif other is Character and hv.length() > 0.9 and now - _last_bump_t > 2.5:
			_last_bump_t = now
			Game.session.on_bumped(other as Character, self)


# ------------------------------------------------------------------ knockdowns
func take_hit(impulse: Vector3, source: Node) -> void:
	if is_down() or (Game.session and (not Game.session.is_authority() or Game.time() < float(Game.session.quiet_until))):
		return
	var mag := impulse.length()
	var by := ""
	if source is Prop:
		by = (source as Prop).last_touched_by
	elif source is Character:
		by = (source as Character).id
	if seated_on:
		if mag > 30.0:
			stand_up()
		else:
			return
	if mag > 22.0 or kd == KD.STUMBLE:
		var push := Vector3(impulse.x, 0, impulse.z).normalized() * clampf(mag / 10.0, 1.5, 5.0)
		fling(push + Vector3.UP * clampf(mag / 15.0, 1.0, 3.5), 0.0 if mag < 45.0 else 0.5)
		knock_down("hit", by, -1.0 if impulse.dot(forward()) > 0 else 1.0)
	elif mag > 5.0:
		stumble("hit", by)


func stumble(cause: String, by: String) -> void:
	if is_down() or seated_on:
		return
	if kd == KD.STUMBLE:
		knock_down(cause, by, -1.0)
		return
	kd = KD.STUMBLE
	_kd_t = 0.7
	humanoid.stumble = 1.0
	_fall_cause = cause
	_fall_by = by
	if Game.session:
		Game.session.on_character_stumble(self, cause, by)


func slip(cause: String, by: String) -> void:
	if is_down() or seated_on:
		return
	if by == id:
		by = ""
	Game.session.emit_sound(global_position, 30.0, "slip_whoosh", "", "")
	# banana peel: legs fly forward, full somersault, land on the back
	var hv := Vector3(velocity.x, 0, velocity.z)
	var f := hv.normalized() if hv.length() > 0.3 else forward()
	if cause == "banana":
		Game.session.emit_sound(global_position + Vector3(0, 1, 0), 40.0, "slide_up", "", "")
		fling(f * 3.2 + Vector3.UP * 4.2, 1.0)
	else:
		fling(f * 2.0 + Vector3.UP * 1.5, 0.0)
	knock_down(cause, by, 1.0)


## Cartoon launch: the next fall flies along `v` (with `flips` somersaults).
func fling(v: Vector3, flips := 0.0) -> void:
	if is_remote:
		return
	_fling = v
	_flip = flips


func _place_stars() -> void:
	if _stars == null:
		return
	var hj: Node3D = humanoid.j.get("head")
	_stars.global_position = (hj.global_position if hj else global_position + Vector3(0, 0.3, 0)) + Vector3(0, 0.3, 0)


## Little stars circling the head of someone knocked out.
func _show_stars(on: bool) -> void:
	if not on:
		if _stars:
			_stars.queue_free()
			_stars = null
		return
	if _stars or Settings.get_v("reduce_effects"):
		return
	_stars = Node3D.new()
	add_child(_stars)
	_place_stars()
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1, 0.88, 0.2)
	m.emission_enabled = true
	m.emission = Color(1, 0.8, 0.1)
	for k in 3:
		var st := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(0.09, 0.09, 0.03)
		st.mesh = pm
		st.material_override = m
		_stars.add_child(st)
		st.position = Vector3(cos(k * TAU / 3.0) * 0.25, 0, sin(k * TAU / 3.0) * 0.25)
	var tw := _stars.create_tween().set_loops()
	tw.tween_property(_stars, "rotation:y", TAU, 1.2).from(0.0)


func knock_down(cause: String, by: String, dir := 1.0) -> void:
	if is_down():
		return
	if held:
		drop_held(Vector3.ZERO)
	if seated_on:
		stand_up()
	stop()
	kd = KD.FALLING
	_kd_t = 0.0
	humanoid.fall_dir = dir
	humanoid.stumble = 0.0
	_fall_cause = cause
	_fall_by = by
	action = {}


func _update_kd(delta: float) -> void:
	match kd:
		KD.STUMBLE:
			_kd_t -= delta
			humanoid.stumble = clampf(_kd_t / 0.7, 0, 1)
			if _kd_t <= 0.0:
				kd = KD.OK
				humanoid.stumble = 0.0
		KD.FALLING:
			# gravity-like topple: slow start, fast end
			_kd_t += delta
			var air := 0.55 if _fling == Vector3.ZERO else 0.85
			humanoid.fall = clampf(pow(_kd_t / air, 2.2 if _fling == Vector3.ZERO else 1.2), 0.0, 1.0)
			humanoid.spin = _flip * TAU * humanoid.fall_dir * humanoid.fall
			if humanoid.fall >= 1.0 and (is_on_floor() or _kd_t > 2.0):
				_fling = Vector3.ZERO
				humanoid.spin = 0.0
				_show_stars(true)
				kd = KD.FALLEN
				_kd_t = randf_range(1.6, 2.6)
				(get_node("Shape") as CollisionShape3D).disabled = true
				if Game.session:
					Game.session.emit_sound(global_position, 55.0, "body_fall", "", "")
					Game.session.on_character_fell(self, _fall_cause, _fall_by)
				fell.emit(_fall_cause)
		KD.FALLEN:
			_place_stars()
			_kd_t -= delta
			if _kd_t <= 0.0:
				kd = KD.GETUP
				_kd_t = 1.0
				_show_stars(false)
				(get_node("Shape") as CollisionShape3D).disabled = false
		KD.GETUP:
			_kd_t -= delta
			humanoid.fall = clampf(_kd_t, 0.0, 1.0)
			humanoid.getting_up = clampf(_kd_t, 0.0, 1.0)
			if _kd_t <= 0.0:
				kd = KD.OK
				humanoid.fall = 0.0
				humanoid.getting_up = 0.0


# ------------------------------------------------------------------ seat / carry
func sit_on(chair: Prop) -> bool:
	if chair == null or chair.occupant != "" or not can_act():
		return false
	if held:
		drop_held(Vector3.ZERO)
	stop()
	seated_on = chair
	add_collision_exception_with(chair)
	chair.on_sat(self)
	velocity = Vector3.ZERO
	return true


func stand_up() -> void:
	if seated_on == null:
		return
	var chair := seated_on
	seated_on = null
	humanoid.typing = false
	if is_instance_valid(chair):
		var f := -chair.global_basis.z
		f.y = 0
		# step out BEHIND the chair: in front of it is the desk (standing up there put people inside it)
		var out := chair.global_position - f.normalized() * 0.8   # clear of the chair base
		chair.on_stood()
		out.y = 0.0
		if Game.session:
			out = Game.session.world.nav_closest(out)
			out.y = 0.0
		global_position = out
		velocity = Vector3.ZERO
		# keep ignoring the chair until we are clear of it
		get_tree().create_timer(1.2).timeout.connect(func():
			if is_instance_valid(chair) and seated_on != chair:
				remove_collision_exception_with(chair))


func pick_up(p: Prop) -> bool:
	if held or p.held_by or not can_act():
		return false
	if seated_on:
		stand_up()
	held = p
	add_collision_exception_with(p)
	p.begin_hold(self)
	return true


func drop_held(impulse: Vector3) -> void:
	if held == null:
		return
	var p := held
	held = null
	p.end_hold()
	get_tree().create_timer(0.6).timeout.connect(func():
		if is_instance_valid(p) and held != p and seated_on != p:
			remove_collision_exception_with(p))
	if impulse != Vector3.ZERO:
		p.apply_central_impulse(impulse)
	p.touch(self)


func _update_hold() -> void:
	if held == null:
		return
	if not is_instance_valid(held) or not held.is_available():
		held = null
		return
	var f := forward()
	var target: Vector3
	var b := Basis(Vector3.UP, rotation.y)
	if held.carry == "medium" and held.mass > 6.0:
		target = global_position + f * 0.85
		target.y = held.global_position.y if "chair" in held.tags else global_position.y + 0.55
		if "chair" in held.tags:
			b = held.global_basis
	else:
		target = global_position + f * 0.5 + Vector3(0, 1.05, 0)
	held.set_hold_target(target, b)
	if held.global_position.distance_to(target) > 1.8:
		drop_held(Vector3.ZERO)


# ------------------------------------------------------------------ speech / emotes
func say(text: String, emotion := "neutral", loud := 50.0) -> void:
	bubble.text = text
	bubble.visible = true
	_say_t = clampf(1.6 + text.length() * 0.055, 2.0, 6.0)
	bubble.font_size = int(44 * float(Settings.get_v("subtitles_size")))
	SoundFx.voice(voice_id, emotion, global_position + Vector3(0, 1.6, 0), voice_pitch, loud)
	spoke.emit(text)


func do_emote(e: String, dur := 2.0) -> void:
	humanoid.emote = e
	humanoid.emote_t = 0.0
	emote_until = Game.time() + dur


func look_at_point(p: Vector3) -> void:
	humanoid.look_target = p


func clear_look() -> void:
	humanoid.look_target = Vector3.INF


var _alert_until := 0.0

## Short-lived "!" / "?" above an NPC's head (they saw / heard something).
func flash_alert(text: String, c: Color, dur := 2.0) -> void:
	if alert_icon == null or (alert_icon.visible and alert_icon.text == "!" and text == "?"):
		return
	set_alert(text, c)
	_alert_until = Game.time() + dur
	get_tree().create_timer(dur).timeout.connect(func():
		if is_instance_valid(self) and Game.time() >= _alert_until - 0.05:
			set_alert(""))


func set_alert(text: String, c := Color(1, 0.8, 0.1)) -> void:
	alert_icon.text = text
	alert_icon.modulate = c
	alert_icon.visible = text != ""


func set_disguise(on: bool, dur := 90.0) -> void:
	disguised_until = Game.time() + dur if on else -1.0
	humanoid.set_accessory("disguise", on)


func apply_cosmetics(list: Array) -> void:
	cosmetics.assign(list)
	for c in ["chapeau", "lunettes", "cravate_or"]:
		humanoid.set_accessory(c, c in list)


func _process(_delta: float) -> void:
	if disguised_until > 0.0 and Game.time() > disguised_until:
		set_disguise(false)


# ------------------------------------------------------------------ interaction target (talk etc.)
func interact_point() -> Vector3:
	return global_position + Vector3(0, 1.2, 0)


func ent_id() -> String:
	return id


func get_actions(actor: Node) -> Array:
	if Game.session == null or actor == self:
		return []
	return Game.session.social_actions(actor, self)


func perform(actor: Node, act: String, params: Dictionary) -> Dictionary:
	return Game.session.perform_social(actor, self, act, params)
