class_name CustomizePanel
extends Control
## Character customisation with a live 3D preview: name, skin, hair style & colour,
## clothes, accessories, owned cosmetics. Saved locally.

signal closed

var look: Dictionary
var preview: Humanoid
var vp: SubViewport
var _rot := 0.0
var name_edit: LineEdit
var cos_box: VBoxContainer

const SKINS := ["#f5d2b8", "#e9bb98", "#d9a582", "#c98e6b", "#a8704e", "#7a4e33", "#5a3825"]
const HAIRS := ["short", "messy", "slick", "bun", "ponytail", "long", "curly", "bald"]
const HAIR_COLORS := ["#1c1714", "#3b2a1e", "#6b4a2b", "#b5441f", "#d1a35a", "#e3c36b", "#9a9a9a", "#3f6fd6", "#d63fa0"]
const SHIRTS := ["#3fa7d6", "#e07a2e", "#4f9a6a", "#7d3f8c", "#f2f2f2", "#d8c9a3", "#b81f2c", "#2f4f8f", "#ffcc22", "#222222"]
const PANTS := ["#2b2f3a", "#4b4136", "#3d4f6e", "#1f1f24", "#6b6b6b", "#7a5a3f"]


static func open(parent: Control) -> CustomizePanel:
	var c := CustomizePanel.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(c)
	c._build()
	return c


func _build() -> void:
	ChoicePanel.open_count += 1
	theme = UiKit.theme()
	look = SaveGame.data.appearance.duplicate(true)
	var p := UiKit.panel(Vector2(980, 600))
	UiKit.center_modal(self, p)
	var h := UiKit.hbox(16)
	p.add_child(h)
	var svc := SubViewportContainer.new()
	svc.custom_minimum_size = Vector2(360, 560)
	svc.stretch = true
	h.add_child(svc)
	vp = SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	svc.add_child(vp)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.05, 3.0)
	cam.fov = 40
	vp.add_child(cam)
	cam.look_at(Vector3(0, 0.95, 0))
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, 30, 0)
	vp.add_child(light)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.7)
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	vp.add_child(env)
	_rebuild_preview()
	var right := UiKit.vbox(8)
	h.add_child(UiKit.scroll(right, Vector2(560, 560)))
	right.add_child(UiKit.label("Personnalisation", 32, UiKit.YELLOW, true))
	var nh := UiKit.hbox(8)
	right.add_child(nh)
	nh.add_child(UiKit.label("Nom", 18))
	name_edit = LineEdit.new()
	name_edit.text = String(Settings.get_v("player_name"))
	name_edit.max_length = 16
	name_edit.custom_minimum_size = Vector2(300, 44)
	nh.add_child(name_edit)
	_swatches(right, "Peau", "skin", SKINS)
	_choices(right, "Coiffure", "hair", HAIRS, ["Courte", "Ébouriffée", "Gominée", "Chignon", "Queue", "Longue", "Bouclée", "Chauve"])
	_swatches(right, "Cheveux", "hair_color", HAIR_COLORS)
	_swatches(right, "Haut", "shirt", SHIRTS)
	_swatches(right, "Bas", "pants", PANTS)
	_choices(right, "Barbe", "beard", ["", "mustache", "beard"], ["Aucune", "Moustache", "Barbe"])
	var toggles := UiKit.hbox(14)
	right.add_child(toggles)
	for spec in [["Lunettes", "glasses"], ["Jupe", "skirt"]]:
		var cb := CheckBox.new()
		cb.text = spec[0]
		cb.button_pressed = bool(look.get(spec[1], false))
		cb.toggled.connect(func(on):
			look[spec[1]] = on
			_rebuild_preview())
		toggles.add_child(cb)
	right.add_child(UiKit.label("Cosmétiques achetés", 18, UiKit.YELLOW, true))
	cos_box = UiKit.vbox(4)
	right.add_child(cos_box)
	var any := false
	for id in ["chapeau", "lunettes", "cravate_or"]:
		if SaveGame.owned_count(id) > 0:
			any = true
			var cb2 := CheckBox.new()
			cb2.text = Data.item_name(id)
			cb2.button_pressed = id in SaveGame.data.equipped_cosmetics
			cb2.toggled.connect(func(on):
				var eq: Array = SaveGame.data.equipped_cosmetics
				if on and not id in eq:
					eq.append(id)
				elif not on:
					eq.erase(id)
				_rebuild_preview())
			cos_box.add_child(cb2)
	if not any:
		cos_box.add_child(UiKit.label("Achète-les dans la boutique (ton PC au bureau).", 14, UiKit.MUTED))
	var bh := UiKit.hbox(10)
	right.add_child(bh)
	bh.add_child(UiKit.button("Enregistrer", _save, 220))
	bh.add_child(UiKit.button("Annuler", close, 200))


func _swatches(parent: Control, label: String, key: String, colors: Array) -> void:
	parent.add_child(UiKit.label(label, 17))
	var h := UiKit.hbox(6)
	parent.add_child(h)
	for c in colors:
		var b := Button.new()
		b.custom_minimum_size = Vector2(40, 40)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_stylebox_override("normal", UiKit.box(Color(c), 20, 2, Color(1, 1, 1, 0.3)))
		b.add_theme_stylebox_override("hover", UiKit.box(Color(c), 20, 3, UiKit.YELLOW))
		b.add_theme_stylebox_override("pressed", UiKit.box(Color(c), 20, 3, UiKit.YELLOW))
		b.pressed.connect(func():
			look[key] = c
			SoundFx.ui("ui_click", -8)
			_rebuild_preview())
		h.add_child(b)


func _choices(parent: Control, label: String, key: String, values: Array, labels: Array) -> void:
	var h := UiKit.hbox(8)
	parent.add_child(h)
	h.add_child(UiKit.label(label, 17))
	var ob := OptionButton.new()
	for i in values.size():
		ob.add_item(labels[i], i)
		if values[i] == look.get(key, ""):
			ob.select(i)
	ob.item_selected.connect(func(i):
		look[key] = values[i]
		_rebuild_preview())
	h.add_child(ob)


func _rebuild_preview() -> void:
	if preview:
		preview.queue_free()
	preview = Humanoid.new()
	vp.add_child(preview)
	preview.build(look)
	for c in ["chapeau", "lunettes", "cravate_or"]:
		preview.set_accessory(c, c in SaveGame.data.equipped_cosmetics)
	preview.rotation.y = _rot


func _process(delta: float) -> void:
	_rot += delta * 0.6
	if preview:
		preview.rotation.y = _rot


func _save() -> void:
	SaveGame.data.appearance = look
	Settings.set_v("player_name", name_edit.text.strip_edges() if name_edit.text.strip_edges() != "" else "Joueur")
	SaveGame.save_game()
	SoundFx.ui("ui_confirm")
	close()


func close() -> void:
	if is_queued_for_deletion():
		return
	ChoicePanel.open_count = maxi(0, ChoicePanel.open_count - 1)
	closed.emit()
	queue_free()
