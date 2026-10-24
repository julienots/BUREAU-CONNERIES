class_name UiKit
## Shared visual identity for menus and HUD (SuperEssence black & yellow, rounded
## panels, Lilita One titles, Fredoka body) + small widget helpers.

const YELLOW := Color("#ffcc22")
const DARK := Color(0.07, 0.08, 0.12, 0.93)
const DARK2 := Color(0.13, 0.14, 0.2, 0.96)
const TEXT := Color(0.96, 0.96, 0.98)
const MUTED := Color(0.7, 0.72, 0.8)
const GOOD := Color("#4cd97b")
const BAD := Color("#ff4d4d")
const WARN := Color("#ffa53a")

static var _theme: Theme
static var title_font: Font
static var body_font: Font


static func theme() -> Theme:
	if _theme:
		return _theme
	title_font = load("res://assets/fonts/LilitaOne-Regular.ttf")
	body_font = load("res://assets/fonts/Fredoka.ttf")
	var t := Theme.new()
	t.default_font = body_font
	t.default_font_size = 20
	var panel := _box(DARK, 18, 2, Color(1, 1, 1, 0.06))
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)
	var bn := _box(Color(0.18, 0.19, 0.27), 14, 0, Color.TRANSPARENT)
	var bh := _box(Color(0.26, 0.27, 0.38), 14, 2, YELLOW)
	var bp := _box(YELLOW.darkened(0.15), 14, 0, Color.TRANSPARENT)
	var bd := _box(Color(0.14, 0.14, 0.18, 0.7), 14, 0, Color.TRANSPARENT)
	var bf := _box(Color(0.26, 0.27, 0.38), 14, 3, YELLOW)
	for st in [["normal", bn], ["hover", bh], ["pressed", bp], ["disabled", bd], ["focus", bf]]:
		t.set_stylebox(st[0], "Button", st[1])
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", YELLOW)
	t.set_color("font_pressed_color", "Button", Color.BLACK)
	t.set_color("font_disabled_color", "Button", Color(0.5, 0.5, 0.55))
	t.set_color("font_focus_color", "Button", YELLOW)
	t.set_font_size("font_size", "Button", 22)
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("background", "ProgressBar", _box(Color(0, 0, 0, 0.45), 8, 0, Color.TRANSPARENT))
	t.set_stylebox("fill", "ProgressBar", _box(YELLOW, 8, 0, Color.TRANSPARENT))
	t.set_stylebox("slider", "HSlider", _box(Color(0.25, 0.26, 0.34), 6, 0, Color.TRANSPARENT))
	t.set_stylebox("grabber_area", "HSlider", _box(YELLOW.darkened(0.2), 6, 0, Color.TRANSPARENT))
	t.set_stylebox("grabber_area_highlight", "HSlider", _box(YELLOW, 6, 0, Color.TRANSPARENT))
	t.set_stylebox("normal", "LineEdit", _box(Color(0.12, 0.13, 0.18), 10, 2, Color(1, 1, 1, 0.1)))
	t.set_stylebox("focus", "LineEdit", _box(Color(0.12, 0.13, 0.18), 10, 2, YELLOW))
	t.set_stylebox("panel", "TooltipPanel", _box(DARK2, 10, 1, YELLOW))
	t.set_stylebox("normal", "OptionButton", bn)
	t.set_stylebox("hover", "OptionButton", bh)
	t.set_stylebox("pressed", "OptionButton", bp)
	t.set_stylebox("focus", "OptionButton", bf)
	t.set_stylebox("panel", "PopupMenu", _box(DARK2, 10, 1, YELLOW))
	t.set_constant("separation", "VBoxContainer", 10)
	t.set_constant("separation", "HBoxContainer", 10)
	t.set_stylebox("tab_selected", "TabContainer", _box(Color(0.26, 0.27, 0.38), 10, 0, Color.TRANSPARENT))
	t.set_stylebox("tab_unselected", "TabContainer", _box(Color(0.14, 0.15, 0.2), 10, 0, Color.TRANSPARENT))
	t.set_stylebox("panel", "TabContainer", _box(Color(0, 0, 0, 0), 0, 0, Color.TRANSPARENT))
	t.set_stylebox("normal", "CheckBox", _box(Color(0, 0, 0, 0), 6, 0, Color.TRANSPARENT))
	t.set_stylebox("hover", "CheckBox", _box(Color(1, 1, 1, 0.05), 6, 0, Color.TRANSPARENT))
	t.set_stylebox("pressed", "CheckBox", _box(Color(0, 0, 0, 0), 6, 0, Color.TRANSPARENT))
	_theme = t
	return t


static func _box(c: Color, r: int, border: int, bc: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(r)
	s.set_border_width_all(border)
	s.border_color = bc
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	s.anti_aliasing = true
	return s


static func box(c: Color, r := 14, border := 0, bc := Color.TRANSPARENT) -> StyleBoxFlat:
	return _box(c, r, border, bc)


static func label(text: String, size := 20, color := TEXT, title := false) -> Label:
	theme()
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if title:
		l.add_theme_font_override("font", title_font)
	l.add_theme_constant_override("outline_size", 6 if title else 0)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	return l


static func button(text: String, cb: Callable, min_w := 260.0, size := 22) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, 54)
	b.add_theme_font_size_override("font_size", size)
	b.pressed.connect(func():
		SoundFx.ui("ui_click")
		cb.call())
	b.mouse_entered.connect(func(): SoundFx.ui("ui_hover", -10.0))
	b.focus_mode = Control.FOCUS_ALL
	return b


static func panel(min_size := Vector2.ZERO) -> PanelContainer:
	var p := PanelContainer.new()
	p.theme = theme()
	p.custom_minimum_size = min_size
	return p


static func vbox(sep := 10) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep := 10) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func icon(item_id: String, size := 56) -> TextureRect:
	var tr := TextureRect.new()
	var info := Data.item_info(item_id)
	var p := "res://assets/textures/icons/%s.png" % info.get("icon", item_id)
	if ResourceLoader.exists(p):
		tr.texture = load(p)
	tr.custom_minimum_size = Vector2(size, size)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return tr


static func center_modal(parent: Control, content: Control) -> Control:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(cc)
	cc.add_child(content)
	return dim


static func scroll(child: Control, min_size: Vector2) -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = min_size
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.add_child(child)
	child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return sc
