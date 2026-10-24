class_name MobileControls
extends CanvasLayer
## Landscape touch controls: virtual joystick (left), camera drag (right half),
## large action buttons. Multi-touch aware.

signal pause_requested

var pc: PlayerController
var root: Control
var _stick_base: Control
var _stick_knob: Control
var _stick_touch := -1
var _look_touch := -1
var _stick_center := Vector2.ZERO
const R := 90.0
var run_btn: Button
var crouch_btn: Button


func setup(controller: PlayerController) -> void:
	pc = controller
	layer = 6
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiKit.theme()
	add_child(root)
	_stick_base = Panel.new()
	_stick_base.add_theme_stylebox_override("panel", UiKit.box(Color(1, 1, 1, 0.12), 100, 3, Color(1, 1, 1, 0.3)))
	_stick_base.size = Vector2(R * 2, R * 2)
	_stick_base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_stick_base)
	_stick_knob = Panel.new()
	_stick_knob.add_theme_stylebox_override("panel", UiKit.box(Color(UiKit.YELLOW, 0.7), 50, 0))
	_stick_knob.size = Vector2(76, 76)
	_stick_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_stick_knob)
	_place_stick(Vector2(170, get_viewport().get_visible_rect().size.y - 170))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	grid.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grid.grow_vertical = Control.GROW_DIRECTION_BEGIN
	grid.offset_right = -24
	grid.offset_bottom = -24
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	root.add_child(grid)
	grid.add_child(_btn("Suivant", func(): pc.cycle(1)))
	grid.add_child(_btn("Alt.", func(): pc.press_alt()))
	grid.add_child(_btn("Lancer", func(): pc.press_throw()))
	crouch_btn = _btn("Accroupi", func():
		pc.mobile_crouch = not pc.mobile_crouch
		crouch_btn.modulate = UiKit.YELLOW if pc.mobile_crouch else Color.WHITE)
	grid.add_child(crouch_btn)
	run_btn = _btn("Courir", func():
		pc.mobile_run = not pc.mobile_run
		run_btn.modulate = UiKit.YELLOW if pc.mobile_run else Color.WHITE)
	grid.add_child(run_btn)
	var act := _btn("AGIR", func(): pc.press_interact())
	act.add_theme_font_size_override("font_size", 28)
	act.add_theme_stylebox_override("normal", UiKit.box(Color(UiKit.YELLOW, 0.85), 20))
	act.add_theme_color_override("font_color", Color.BLACK)
	grid.add_child(act)
	var top := UiKit.hbox(10)
	top.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top.offset_top = 120
	root.add_child(top)
	top.add_child(_btn("Lâcher", func(): pc.press_drop(), Vector2(120, 60)))
	top.add_child(_btn("Pause", func(): pause_requested.emit(), Vector2(120, 60)))


func _btn(text: String, cb: Callable, size := Vector2(120, 96)) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = size
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(cb)
	return b


func _place_stick(c: Vector2) -> void:
	_stick_center = c
	_stick_base.position = c - Vector2(R, R)
	_stick_knob.position = c - _stick_knob.size * 0.5


func _input(event: InputEvent) -> void:
	if pc == null or pc.blocked:
		return
	var vp := get_viewport().get_visible_rect().size
	if event is InputEventScreenTouch:
		if event.pressed:
			if event.position.x < vp.x * 0.4 and event.position.y > vp.y * 0.35 and _stick_touch < 0:
				_stick_touch = event.index
				_place_stick(event.position)
			elif event.position.x >= vp.x * 0.4 and _look_touch < 0 and not _over_button(event.position):
				_look_touch = event.index
		else:
			if event.index == _stick_touch:
				_stick_touch = -1
				pc.mobile_move = Vector2.ZERO
				_place_stick(Vector2(170, vp.y - 170))
			elif event.index == _look_touch:
				_look_touch = -1
	elif event is InputEventScreenDrag:
		if event.index == _stick_touch:
			var d: Vector2 = event.position - _stick_center
			if d.length() > R:
				d = d.normalized() * R
			_stick_knob.position = _stick_center + d - _stick_knob.size * 0.5
			pc.mobile_move = d / R
		elif event.index == _look_touch:
			var s := float(Settings.get_v("touch_sens")) * 0.012
			pc.rig.add_look(event.relative.x * s, event.relative.y * s)


func _over_button(p: Vector2) -> bool:
	for c in root.find_children("*", "Button", true, false):
		if (c as Control).get_global_rect().has_point(p):
			return true
	return false
