extends Node3D
## Main menu over a live 3D view of the office (slow orbiting camera, idle characters).

var ui: Control
var cam: Camera3D
var _t := 0.0
var world: OfficeWorld
var main_box: VBoxContainer
var money_l: Label


func _ready() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	ChoicePanel.open_count = 0
	world = OfficeWorld.new()
	add_child(world)
	OfficeBuilder.build(world, 77, "low" if Settings.is_mobile() else "medium", false)
	_pose_cast()
	cam = Camera3D.new()
	cam.fov = 55
	add_child(cam)
	SoundFx.music("menu_loop", 1.5)
	SoundFx.ambience(["ambience_vent"])
	var layer := CanvasLayer.new()
	add_child(layer)
	ui = Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.theme = UiKit.theme()
	layer.add_child(ui)
	var grad := TextureRect.new()
	var gt := GradientTexture2D.new()
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(0, 0, 0, 0.85), Color(0, 0, 0, 0.0)])
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 0)
	grad.texture = gt
	grad.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	grad.offset_right = 760
	grad.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ui.add_child(grad)
	var v := UiKit.vbox(12)
	v.position = Vector2(70, 60)
	ui.add_child(v)
	var title := UiKit.label("OFFICE", 92, Color.WHITE, true)
	v.add_child(title)
	var title2 := UiKit.label("MAYHEM", 92, UiKit.YELLOW, true)
	title2.position.y -= 30
	v.add_child(title2)
	v.add_child(UiKit.label("Bêtises, mensonges et chaises qui roulent.", 20, UiKit.MUTED))
	main_box = UiKit.vbox(10)
	v.add_child(main_box)
	main_box.add_child(UiKit.button("Jouer en solo", _solo, 340))
	main_box.add_child(UiKit.button("Jouer en ligne", func(): _online(""), 340))
	main_box.add_child(UiKit.button("Rejoindre une partie", _join_code, 340))
	main_box.add_child(UiKit.button("Personnalisation", func(): CustomizePanel.open(ui), 340))
	main_box.add_child(UiKit.button("Paramètres", func(): SettingsPanel.open(ui), 340))
	main_box.add_child(UiKit.button("Crédits", _credits, 340))
	if not Settings.is_mobile():
		main_box.add_child(UiKit.button("Quitter", func(): get_tree().quit(), 340))
	(main_box.get_child(0) as Control).grab_focus()
	var info := UiKit.panel()
	info.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	info.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	info.grow_vertical = Control.GROW_DIRECTION_BEGIN
	info.offset_right = -24
	info.offset_bottom = -24
	ui.add_child(info)
	var iv := UiKit.vbox(2)
	info.add_child(iv)
	money_l = UiKit.label("", 22, UiKit.YELLOW, true)
	iv.add_child(money_l)
	var d := SaveGame.data
	iv.add_child(UiKit.label("Jour %d · %d journées réussies · niveau boutique %d" % [d.day, d.stats.days_won, d.tier_unlocked], 15, UiKit.MUTED))
	iv.add_child(UiKit.label("SuperEssence Studio · v%s" % ProjectSettings.get_setting("application/config/version"), 13, UiKit.MUTED))
	_refresh_money()


func _refresh_money() -> void:
	money_l.text = "%d €" % SaveGame.money()


func _pose_cast() -> void:
	var spots := [[Vector3(-15.2, 0, 3.9), 160.0, Data.coworkers[1]], [Vector3(-16.6, 0, 3.6), 200.0, Data.coworkers[4]],
		[Vector3(-12.5, 0, 4.4), -100.0, Data.director], [Vector3(-7.5, 0, 3.6), 180.0, Data.coworkers[0]]]
	for s in spots:
		var h := Humanoid.new()
		add_child(h)
		h.build(s[2].look)
		h.position = s[0]
		h.rotation_degrees.y = s[1]
		h.posture = 0.8 if s[2].get("id", "") == "boss" else 0.0
	var hs: Array = get_children().filter(func(c): return c is Humanoid)
	if hs.size() >= 4:
		(hs[0] as Humanoid).emote = "laugh"
		(hs[1] as Humanoid).emote = "panic"
		(hs[2] as Humanoid).emote = "suspicious"
		(hs[2] as Humanoid).look_target = Vector3(-15.8, 1.5, 3.6)
		(hs[3] as Humanoid).typing = true


func _process(delta: float) -> void:
	_t += delta * 0.05
	var center := Vector3(-13.0, 0.8, 3.6)
	cam.global_position = center + Vector3(cos(_t) * 7.5, 2.6 + sin(_t * 0.7) * 0.4, sin(_t) * 7.5)
	cam.look_at(center + Vector3(0, 0.3, 0), Vector3.UP)


func _solo() -> void:
	Game.start_solo()


func _online(code: String) -> void:
	LobbyUI.open(ui, code)


func _join_code() -> void:
	var p := UiKit.panel(Vector2(460, 0))
	var dim := UiKit.center_modal(ui, p)
	ChoicePanel.open_count += 1
	var v := UiKit.vbox(10)
	p.add_child(v)
	v.add_child(UiKit.label("Rejoindre une partie", 28, UiKit.YELLOW, true))
	v.add_child(UiKit.label("Code d'invitation (ex : KXQ4) :", 16, UiKit.MUTED))
	var le := LineEdit.new()
	le.max_length = 8
	le.custom_minimum_size = Vector2(420, 50)
	le.placeholder_text = "CODE"
	v.add_child(le)
	var h := UiKit.hbox(10)
	v.add_child(h)
	var close := func():
		ChoicePanel.open_count = maxi(0, ChoicePanel.open_count - 1)
		dim.queue_free()
	h.add_child(UiKit.button("Rejoindre", func():
		close.call()
		_online(le.text.strip_edges().to_upper()), 200))
	h.add_child(UiKit.button("Annuler", close, 200))
	le.grab_focus()


func _credits() -> void:
	var txt := "OFFICE MAYHEM\nun jeu SuperEssence Studio\n\nConception, programmation, modèles 3D procéduraux, IA, sons et voix générés par l'équipe SuperEssence " + \
		"(avec l'aide de Claude, assistant IA d'Anthropic).\n\nMoteur : Godot Engine 4.5 (MIT) · Physique : Jolt\nPolices : Lilita One & Fredoka (SIL Open Font License)\n" + \
		"Voix : synthèse espeak-ng retravaillée (charabia garanti 100 % sans sens)\n\nMerci à tous les collègues qui ont perdu leur chaise pendant les tests."
	var cp := ChoicePanel.open(ui, "Crédits", txt, [], "Fermer")
	cp.custom_minimum_size = Vector2(600, 0)
