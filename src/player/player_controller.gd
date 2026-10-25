class_name PlayerController
extends Node
## Local player input: movement relative to the camera, run/crouch, interaction target
## selection (nearest relevant object in front, no walls in between), action cycling,
## held-object drop/throw, inventory shortcuts. All gameplay effects go through
## Session.request_action() so the authority validates them.

signal focus_changed(focus: Dictionary)
signal ui_open(kind: String, info: Dictionary)

var ch: Character
var rig: CameraRig
var session: Session
var blocked := false          # a modal UI is open
var focus: Dictionary = {}    # {target, name, actions: Array, index}
var selected := 0
var mobile_move := Vector2.ZERO
var mobile_run := false
var mobile_crouch := false
var _scan_t := 0.0
var _last_target := ""


func setup(c: Character, r: CameraRig, s: Session) -> void:
	ch = c
	rig = r
	session = s


func _unhandled_input(event: InputEvent) -> void:
	if ch == null or blocked:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := float(Settings.get_v("mouse_sens")) * 0.01
		rig.add_look(event.relative.x * sens, event.relative.y * sens)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				cycle(-1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				cycle(1)
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			rig.zoom(0.8 if rig.distance < 4.5 else -2.4)
	if Settings.use_touch() and (event is InputEventMouseButton or event is InputEventMouseMotion):
		return  # taps are handled by the touch UI, not as mouse clicks
	if event.is_action_pressed("interact"):
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and event is InputEventMouseButton and not Settings.use_touch():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled()
			return
		press_interact()
	elif event.is_action_pressed("alt_action"):
		press_alt()
	elif event.is_action_pressed("next_action"):
		cycle(1)
	elif event.is_action_pressed("drop"):
		press_drop()
	elif event.is_action_pressed("throw"):
		press_throw()
	elif event.is_action_pressed("jump") and ch.seated_on:
		session.request_action(ch, ch.id, "stand")


func _physics_process(delta: float) -> void:
	if ch == null:
		return
	var input := Vector2.ZERO
	if not blocked and not session.director_interrogating(ch.id):
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		if mobile_move.length() > 0.05:
			input = mobile_move
		# right stick look for gamepads
		var rx := Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
		var ry := Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
		if absf(rx) > 0.15 or absf(ry) > 0.15:
			rig.add_look(rx * delta * 2.6, ry * delta * 2.0)
	var dir := rig.right_flat() * input.x - rig.forward_flat() * input.y
	if dir.length() > 1.0:
		dir = dir.normalized()
	if ch.seated_on and dir.length() > 0.3:
		session.request_action(ch, ch.id, "stand")
	ch.move_dir = dir
	ch.want_run = (Input.is_action_pressed("run") or mobile_run or input.length() > 0.98 and mobile_move.length() > 0.98) and not blocked
	ch.want_crouch = (Input.is_action_pressed("crouch") or mobile_crouch) and not blocked
	if ch.want_crouch and ch.want_run:
		ch.want_run = false
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = 0.1
		_update_focus()


func _update_focus() -> void:
	if blocked:
		return
	var best: Node = null
	var best_score := INF
	var eye := ch.global_position + Vector3(0, 1.2, 0)
	var cam_f := -rig.cam.global_basis.z
	var flat_f := Vector3(cam_f.x, 0, cam_f.z).normalized()
	var cands: Array = session.world.interactables.duplicate()
	for id in session.characters:
		if id != ch.id:
			cands.append(session.characters[id])
	for e in cands:
		if not is_instance_valid(e):
			continue
		if e is Prop and (not (e as Prop).is_available() or (e as Prop).held_by):
			continue
		var p: Vector3 = e.interact_point()
		var to := p - eye
		var flat := Vector3(to.x, 0, to.z)
		var d := flat.length()
		var reach := 2.3 if not e is Character else 2.6
		if d > reach or absf(to.y) > 1.9:
			continue
		var ang := 0.0 if d < 0.4 else acos(clampf(flat_f.dot(flat.normalized()), -1, 1))
		if ang > (1.7 if Settings.use_touch() else 1.1):
			continue
		if session.world.count_walls(eye, p) > 0:
			continue
		var score := d + ang * 1.6
		if e is Character:
			score -= 0.2
		if score < best_score:
			best_score = score
			best = e
	var actions: Array = []
	if best:
		for a in best.get_actions(ch):
			if not a.get("hidden", false):
				actions.append(a)
	if actions.is_empty():
		best = null
	var tid: String = best.ent_id() if best else ""
	# meeting antics need no target: offered first while sitting/standing in the meeting
	var extra: Array = session.self_actions(ch)
	var title: String = best.display_name() if best else ""
	if not extra.is_empty():
		# meeting antics go first, the rest (chair rocket…) after the aimed object's actions
		actions = extra.filter(func(a): return a.get("front", false)) + actions + extra.filter(func(a): return not a.get("front", false))
		if session.in_meeting(ch) and (best == null or ch.seated_on):
			title = "Réunion" + (" — le chef écrit au tableau !" if session.meeting_board else "")
		elif best == null:
			title = "Toi"
		if best == null:
			tid = ch.id
	if tid != _last_target:
		selected = 0
		_last_target = tid
	focus = {"target": tid, "name": title, "actions": actions, "node": best}
	selected = clampi(selected, 0, maxi(0, actions.size() - 1))
	focus["index"] = selected
	focus_changed.emit(focus)


func cycle(dir: int) -> void:
	var n: int = focus.get("actions", []).size()
	if n == 0:
		return
	selected = (selected + dir + n) % n
	focus["index"] = selected
	SoundFx.ui("ui_hover")
	focus_changed.emit(focus)


func press_interact() -> void:
	if blocked:
		return
	var acts: Array = focus.get("actions", [])
	if acts.is_empty():
		if ch.held:
			press_drop()
		return
	trigger(acts[clampi(selected, 0, acts.size() - 1)])


func press_alt() -> void:
	var acts: Array = focus.get("actions", [])
	if acts.size() >= 2:
		trigger(acts[1 if selected == 0 else 0])


func press_drop() -> void:
	if ch.held:
		session.request_action(ch, ch.id, "drop_held")


func press_throw() -> void:
	if ch.held:
		session.request_action(ch, ch.id, "throw_held")
		rig.shake(0.3)


## Runs an action from the prompt. Some actions first need a choice from a UI panel.
func trigger(a: Dictionary) -> void:
	if String(a.get("blocked", "")) != "":
		SoundFx.ui("ui_error")
		session.notified.emit(String(a.blocked), "warn")
		return
	var ui := String(a.get("ui", ""))
	var target: String = ch.id if a.get("self", false) else String(focus.get("target", ""))
	# turn towards what we touch (kept for the whole duration of a timed action)
	var node: Node = focus.get("node")
	if not a.get("self", false) and node and is_instance_valid(node) and node.has_method("interact_point"):
		ch.face_towards(node.interact_point(), maxf(0.8, float(a.get("time", 0.0)) + 0.4))
	if ui in ["denounce", "rumor", "hide", "call", "shop", "objectives", "boss_interrogate", "boss_sanction"]:
		ui_open.emit(ui, {"target": target, "action": a.id})
		return
	var r := session.request_action(ch, target, String(a.id), {})
	if r.get("ok", false) and String(r.get("ui", "")) != "":
		ui_open.emit(String(r.ui), {"target": target})
	elif r.get("ok", false):
		SoundFx.ui("ui_click", -6.0)


func send(target: String, action: String, params: Dictionary) -> Dictionary:
	return session.request_action(ch, target, action, params)
