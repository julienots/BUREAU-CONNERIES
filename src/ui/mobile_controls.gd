class_name MobileControls
extends CanvasLayer
## Phone controls (landscape, two thumbs):
##  - left half: floating joystick that appears under the thumb; pushing it to the edge runs
##  - right half: drag to look around (the camera also follows automatically when walking)
##  - big contextual ACTION button showing what it will do, with ◀ ▶ to switch action
##  - contextual buttons: Drop / Throw only while holding something, Crouch toggle,
##    objectives and pause in the top corner. Light vibration on actions.

signal pause_requested
signal objectives_requested

var pc: PlayerController
var root: Control
var _stick_base: Panel
var _stick_knob: Panel
var _stick_touch := -1
var _look_touch := -1
var _stick_center := Vector2.ZERO
var _rest := Vector2.ZERO
const R := 110.0
var action_btn: Button
var action_l: Label
var prev_btn: Button
var next_btn: Button
var crouch_btn: Button
var drop_btn: Button
var throw_btn: Button
var stand_btn: Button
var run_hint: Label


func setup(controller: PlayerController) -> void:
	pc = controller
	layer = 6
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiKit.theme()
	add_child(root)
	# joystick
	_stick_base = Panel.new()
	_stick_base.add_theme_stylebox_override("panel", UiKit.box(Color(1, 1, 1, 0.10), int(R), 4, Color(1, 1, 1, 0.35)))
	_stick_base.size = Vector2(R * 2, R * 2)
	_stick_base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_stick_base)
	_stick_knob = Panel.new()
	_stick_knob.add_theme_stylebox_override("panel", UiKit.box(Color(UiKit.YELLOW, 0.85), 48, 0))
	_stick_knob.size = Vector2(96, 96)
	_stick_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_stick_knob)
	run_hint = UiKit.label("COURSE", 18, UiKit.YELLOW, true)
	run_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	run_hint.visible = false
	root.add_child(run_hint)
	# big action button (bottom right) with labels
	action_btn = _btn("", func(): _do(func(): pc.press_interact()), Vector2(210, 210))
	action_btn.add_theme_stylebox_override("normal", UiKit.box(Color(UiKit.YELLOW, 0.92), 105, 4, Color(1, 1, 1, 0.6)))
	action_btn.add_theme_stylebox_override("pressed", UiKit.box(UiKit.YELLOW.darkened(0.25), 105, 4, Color.WHITE))
	action_btn.add_theme_stylebox_override("hover", UiKit.box(Color(UiKit.YELLOW, 0.92), 105, 4, Color(1, 1, 1, 0.6)))
	action_btn.add_theme_stylebox_override("disabled", UiKit.box(Color(0.3, 0.3, 0.35, 0.5), 105, 3, Color(1, 1, 1, 0.2)))
	_br(action_btn, -250, -250)
	action_l = UiKit.label("", 22, Color.BLACK, true)
	action_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	action_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	action_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	action_l.set_anchors_preset(Control.PRESET_FULL_RECT)
	action_l.offset_left = 18
	action_l.offset_right = -18
	action_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	action_l.add_theme_constant_override("outline_size", 0)
	action_btn.add_child(action_l)
	prev_btn = _btn("◀", func(): _do(func(): pc.cycle(-1)), Vector2(84, 84))
	_br(prev_btn, -350, -200)
	next_btn = _btn("▶", func(): _do(func(): pc.cycle(1)), Vector2(84, 84))
	_br(next_btn, -250, -340)
	# secondary buttons (right side, above the action button)
	crouch_btn = _btn("Accroupi", func():
		pc.mobile_crouch = not pc.mobile_crouch
		_refresh_toggles()
		_haptic(), Vector2(150, 84))
	_br(crouch_btn, -180, -440)
	drop_btn = _btn("Lâcher", func(): _do(func(): pc.press_drop()), Vector2(150, 84))
	_br(drop_btn, -520, -120)
	throw_btn = _btn("Lancer !", func(): _do(func(): pc.press_throw()), Vector2(150, 84))
	_br(throw_btn, -520, -220)
	stand_btn = _btn("Se lever", func(): _do(func(): pc.session.request_action(pc.ch, pc.ch.id, "stand")), Vector2(150, 84))
	_br(stand_btn, -520, -120)
	for b in [drop_btn, throw_btn, stand_btn]:
		b.add_to_group("ctx_btn")   # the HUD keeps its action list clear of these
	# (the pause button lives in the HUD top bar, next to BOUTIQUE)
	for b in [action_btn, prev_btn, next_btn, crouch_btn, drop_btn, throw_btn, stand_btn]:
		root.add_child(b)
	pc.focus_changed.connect(_on_focus)
	_on_focus({})
	_rest = Vector2(200, root.get_viewport_rect().size.y - 200)
	_place_stick(_rest)


## Anchors a control to the bottom-right corner with its top-left at (x, y) from that corner.
func _br(c: Control, x: float, y: float) -> void:
	c.anchor_left = 1.0
	c.anchor_top = 1.0
	c.anchor_right = 1.0
	c.anchor_bottom = 1.0
	c.offset_left = x
	c.offset_top = y
	c.offset_right = x + c.custom_minimum_size.x
	c.offset_bottom = y + c.custom_minimum_size.y


func _btn(text: String, cb: Callable, size: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = size
	b.size = size
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 22)
	b.add_theme_stylebox_override("normal", UiKit.box(Color(0.08, 0.09, 0.13, 0.72), 22, 2, Color(1, 1, 1, 0.25)))
	b.add_theme_stylebox_override("hover", UiKit.box(Color(0.08, 0.09, 0.13, 0.72), 22, 2, Color(1, 1, 1, 0.25)))
	b.add_theme_stylebox_override("pressed", UiKit.box(Color(0.25, 0.26, 0.35, 0.9), 22, 3, UiKit.YELLOW))
	b.pressed.connect(cb)
	return b


func _do(f: Callable) -> void:
	f.call()
	_haptic()


func _haptic() -> void:
	if Settings.is_mobile() and not Settings.get_v("reduce_effects"):
		Input.vibrate_handheld(25)


func _refresh_toggles() -> void:
	crouch_btn.modulate = UiKit.YELLOW if pc.mobile_crouch else Color.WHITE


func _on_focus(f: Dictionary) -> void:
	var acts: Array = f.get("actions", [])
	if acts.is_empty():
		action_l.text = "Lâcher" if pc.ch and pc.ch.held else "—"
		action_btn.disabled = not (pc.ch and pc.ch.held)
	else:
		var a: Dictionary = acts[clampi(int(f.get("index", 0)), 0, acts.size() - 1)]
		action_l.text = String(a.label)
		action_btn.disabled = false
		action_btn.modulate = Color(1, 1, 1, 0.55) if String(a.get("blocked", "")) != "" else Color.WHITE
	prev_btn.visible = acts.size() > 1
	next_btn.visible = acts.size() > 1


func _process(_d: float) -> void:
	if pc == null or pc.ch == null:
		return
	var holding := pc.ch.held != null
	drop_btn.visible = holding
	throw_btn.visible = holding
	stand_btn.visible = pc.ch.seated_on != null and not holding
	run_hint.visible = pc.mobile_run and _stick_touch >= 0
	run_hint.position = _stick_center + Vector2(-38, -R - 34)


func _place_stick(c: Vector2) -> void:
	_stick_center = c
	_stick_base.position = c - Vector2(R, R)
	_stick_knob.position = c - _stick_knob.size * 0.5


## Godot only turns the FIRST finger into mouse clicks, so buttons pressed with a second
## finger (thumb already on the joystick) would be ignored. Any extra finger is routed
## to the button under it here, whatever the screen (HUD, action list, shop, menus).
var _consumed: Dictionary = {}


static func button_at(tree: SceneTree, p: Vector2) -> Button:
	var best: Button = null
	var best_layer := -1000
	for c in tree.root.find_children("*", "Button", true, false):
		var b := c as Button
		if not b.is_visible_in_tree() or b.disabled or not b.get_global_rect().grow(6).has_point(p):
			continue
		var layer := 0
		var n: Node = b
		while n:
			if n is CanvasLayer:
				layer = (n as CanvasLayer).layer
				break
			n = n.get_parent()
		if layer >= best_layer:
			best_layer = layer
			best = b
	return best


func _dispatch_extra_finger(event: InputEventScreenTouch) -> bool:
	if event.pressed:
		if event.index == 0:
			return false
		var b := button_at(get_tree(), event.position)
		if b == null:
			return false
		_consumed[event.index] = true
		b.modulate = Color(1.3, 1.3, 1.0)
		var tw := b.create_tween()
		tw.tween_property(b, "modulate", Color.WHITE, 0.15)
		if b.toggle_mode:
			b.button_pressed = not b.button_pressed
		b.pressed.emit()
		_haptic()
		get_viewport().set_input_as_handled()
		return true
	if _consumed.has(event.index):
		_consumed.erase(event.index)
		get_viewport().set_input_as_handled()
		return true
	return false


func _input(event: InputEvent) -> void:
	if pc == null:
		return
	if event is InputEventScreenTouch and _dispatch_extra_finger(event):
		return
	if pc.blocked:
		if _stick_touch >= 0:
			_stick_touch = -1
			pc.mobile_move = Vector2.ZERO
			pc.mobile_run = false
			_place_stick(_rest)
		_look_touch = -1
		return
	var vp := root.get_viewport_rect().size
	if event is InputEventScreenTouch:
		if event.pressed:
			if event.position.x < vp.x * 0.45 and event.position.y > vp.y * 0.25 and _stick_touch < 0 and not _over_button(event.position):
				_stick_touch = event.index
				_place_stick(event.position)
				_stick_base.modulate.a = 1.0
			elif event.position.x >= vp.x * 0.45 and _look_touch < 0 and not _over_button(event.position):
				_look_touch = event.index
		else:
			if event.index == _stick_touch:
				_stick_touch = -1
				pc.mobile_move = Vector2.ZERO
				pc.mobile_run = false
				_place_stick(_rest)
				_stick_base.modulate.a = 0.6
			elif event.index == _look_touch:
				_look_touch = -1
	elif event is InputEventScreenDrag:
		if event.index == _stick_touch:
			var d: Vector2 = event.position - _stick_center
			var l := d.length()
			# the base follows the thumb when it goes too far, like most mobile games
			if l > R * 1.35:
				_stick_center += d.normalized() * (l - R * 1.35)
				_stick_base.position = _stick_center - Vector2(R, R)
				d = event.position - _stick_center
				l = d.length()
			var clamped := d.normalized() * minf(l, R)
			_stick_knob.position = _stick_center + clamped - _stick_knob.size * 0.5
			var v := clamped / R
			pc.mobile_move = v if v.length() > 0.12 else Vector2.ZERO
			pc.mobile_run = v.length() > 0.92 and not pc.mobile_crouch
		elif event.index == _look_touch:
			var s := float(Settings.get_v("touch_sens")) * 0.012
			pc.rig.add_look(event.relative.x * s, event.relative.y * s)
			pc.rig.note_manual_look()


func _over_button(p: Vector2) -> bool:
	for c in root.find_children("*", "Button", true, false):
		var b := c as Control
		if b.is_visible_in_tree() and b.get_global_rect().grow(12).has_point(p):
			return true
	var hud_buttons := get_tree().get_nodes_in_group("touch_blocker")
	for c in hud_buttons:
		if (c as Control).is_visible_in_tree() and (c as Control).get_global_rect().has_point(p):
			return true
	return false
