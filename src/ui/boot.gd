extends Control
## Studio splash: "SuperEssence Studio" logo with jingle, then the main menu.
## Tap / click / any key skips.

var _done := false


func _ready() -> void:
	theme = UiKit.theme()
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var logo := TextureRect.new()
	logo.texture = load("res://assets/branding/superessence_logo.png")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.set_anchors_preset(Control.PRESET_FULL_RECT)
	logo.offset_left = 80
	logo.offset_right = -80
	logo.offset_top = 40
	logo.offset_bottom = -120
	logo.modulate.a = 0.0
	logo.pivot_offset = get_viewport_rect().size * 0.5
	add_child(logo)
	var studio := UiKit.label("S T U D I O", 34, Color(1, 1, 1, 0.9), true)
	studio.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	studio.grow_horizontal = Control.GROW_DIRECTION_BOTH
	studio.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	studio.offset_bottom = -150
	studio.offset_top = -200
	studio.modulate.a = 0.0
	add_child(studio)
	var presents := UiKit.label("présente", 22, UiKit.MUTED)
	presents.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	presents.grow_horizontal = Control.GROW_DIRECTION_BOTH
	presents.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	presents.offset_bottom = -100
	presents.offset_top = -140
	presents.modulate.a = 0.0
	add_child(presents)
	SoundFx.music("studio_jingle", 0.05)
	var tw := create_tween()
	tw.tween_property(logo, "modulate:a", 1.0, 0.8)
	tw.parallel().tween_property(logo, "scale", Vector2(1.03, 1.03), 3.2).from(Vector2(0.97, 0.97))
	tw.parallel().tween_property(studio, "modulate:a", 1.0, 1.0).set_delay(0.6)
	tw.parallel().tween_property(presents, "modulate:a", 1.0, 0.8).set_delay(1.4)
	tw.tween_interval(0.8)
	tw.tween_property(self, "modulate:a", 0.0, 0.6)
	tw.tween_callback(_go)


func _go() -> void:
	if _done:
		return
	_done = true
	if OS.get_cmdline_user_args().has("--server") or OS.get_cmdline_user_args().has("--master") or DisplayServer.get_name() == "headless":
		get_tree().change_scene_to_file("res://src/net/server_main.tscn")
		return
	get_tree().change_scene_to_file("res://src/ui/main_menu.tscn")


func _input(event: InputEvent) -> void:
	if (event is InputEventKey or event is InputEventMouseButton or event is InputEventScreenTouch) and event.is_pressed():
		_go()
