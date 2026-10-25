class_name SettingsPanel
extends Control
## Settings: graphics, audio (separate buses), controls (sensitivity, invert, key
## remapping), accessibility, gameplay (day length, NPC count, difficulty, director
## memory) and the optional local language model.

signal closed

var _waiting_action := ""
var _rebind_buttons: Dictionary = {}


static func open(parent: Control) -> SettingsPanel:
	var sp := SettingsPanel.new()
	sp.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(sp)
	sp._build()
	return sp


func _build() -> void:
	ChoicePanel.open_count += 1
	theme = UiKit.theme()
	var p := UiKit.panel(Vector2(820, 600))
	UiKit.center_modal(self, p)
	var v := UiKit.vbox(8)
	p.add_child(v)
	v.add_child(UiKit.label("Paramètres", 34, UiKit.YELLOW, true))
	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(780, 470)
	v.add_child(tabs)
	tabs.add_child(_tab_graphics())
	tabs.add_child(_tab_audio())
	tabs.add_child(_tab_controls())
	tabs.add_child(_tab_game())
	v.add_child(UiKit.button("Fermer", close, 220))


func _page(name: String) -> VBoxContainer:
	var v := UiKit.vbox(10)
	v.name = name
	return v


func _wrap(v: VBoxContainer) -> ScrollContainer:
	var sc := UiKit.scroll(v, Vector2(760, 440))
	sc.name = v.name
	return sc


func _slider(parent: Control, label: String, key: String, mn: float, mx: float, step: float) -> void:
	var h := UiKit.hbox(12)
	parent.add_child(h)
	var l := UiKit.label(label, 18)
	l.custom_minimum_size = Vector2(300, 0)
	h.add_child(l)
	var s := HSlider.new()
	s.min_value = mn
	s.max_value = mx
	s.step = step
	s.value = float(Settings.get_v(key))
	s.custom_minimum_size = Vector2(300, 30)
	h.add_child(s)
	var val := UiKit.label(str(snappedf(s.value, step)), 18, UiKit.YELLOW)
	h.add_child(val)
	s.value_changed.connect(func(x):
		val.text = str(snappedf(x, step))
		Settings.set_v(key, x if step < 1.0 else int(x)))


func _check(parent: Control, label: String, key: String) -> void:
	var c := CheckBox.new()
	c.text = label
	c.button_pressed = bool(Settings.get_v(key))
	c.add_theme_font_size_override("font_size", 18)
	c.toggled.connect(func(on): Settings.set_v(key, on))
	parent.add_child(c)


func _option(parent: Control, label: String, key: String, values: Array, labels: Array) -> void:
	var h := UiKit.hbox(12)
	parent.add_child(h)
	var l := UiKit.label(label, 18)
	l.custom_minimum_size = Vector2(300, 0)
	h.add_child(l)
	var ob := OptionButton.new()
	for i in values.size():
		ob.add_item(labels[i], i)
		if values[i] == Settings.get_v(key):
			ob.select(i)
	ob.item_selected.connect(func(i): Settings.set_v(key, values[i]))
	h.add_child(ob)


func _tab_graphics() -> Control:
	var v := _page("Graphismes")
	_option(v, "Qualité", "quality", ["auto", "low", "medium", "high"], ["Automatique", "Basse (mobile)", "Moyenne", "Haute"])
	_slider(v, "Échelle de rendu", "render_scale", 0.5, 1.0, 0.05)
	_check(v, "Ombres", "shadows")
	_check(v, "Occlusion ambiante (SSAO)", "ssao")
	_check(v, "Lueur (glow)", "glow")
	_check(v, "Réduire les effets (tremblements, confettis)", "reduce_effects")
	_slider(v, "Taille des sous-titres", "subtitles_size", 0.7, 1.6, 0.1)
	v.add_child(UiKit.label("Les changements de qualité s'appliquent à la prochaine journée.", 14, UiKit.MUTED))
	return _wrap(v)


func _tab_audio() -> Control:
	var v := _page("Audio")
	_slider(v, "Volume général", "vol_master", 0.0, 1.0, 0.05)
	_slider(v, "Musique", "vol_music", 0.0, 1.0, 0.05)
	_slider(v, "Effets (SFX)", "vol_sfx", 0.0, 1.0, 0.05)
	_slider(v, "Voix", "vol_voices", 0.0, 1.0, 0.05)
	_slider(v, "Ambiance", "vol_ambience", 0.0, 1.0, 0.05)
	return _wrap(v)


func _tab_controls() -> Control:
	var v := _page("Commandes")
	_slider(v, "Sensibilité souris", "mouse_sens", 0.05, 1.0, 0.05)
	_slider(v, "Sensibilité tactile", "touch_sens", 0.1, 1.0, 0.05)
	_check(v, "Inverser l'axe vertical", "invert_y")
	_option(v, "Contrôles tactiles", "touch_controls", ["auto", "on", "off"], ["Automatique", "Toujours", "Jamais"])
	v.add_child(UiKit.label("Touches (clic puis appuie sur une touche)", 18, UiKit.YELLOW, true))
	var names := {"move_forward": "Avancer", "move_back": "Reculer", "move_left": "Gauche", "move_right": "Droite", "run": "Courir",
		"crouch": "S'accroupir", "interact": "Interagir", "alt_action": "Action secondaire", "next_action": "Action suivante",
		"drop": "Lâcher", "use_item": "Déclencher gadget", "objectives": "Objectifs"}
	for a in names:
		var h := UiKit.hbox(12)
		v.add_child(h)
		var l := UiKit.label(names[a], 17)
		l.custom_minimum_size = Vector2(300, 0)
		h.add_child(l)
		var b := Button.new()
		b.text = Settings.key_label(a)
		b.custom_minimum_size = Vector2(200, 40)
		b.pressed.connect(func():
			_waiting_action = a
			b.text = "…")
		h.add_child(b)
		_rebind_buttons[a] = b
	v.add_child(UiKit.button("Réinitialiser les touches", func():
		Settings.reset_keys()
		for a in _rebind_buttons:
			_rebind_buttons[a].text = Settings.key_label(a), 300))
	return _wrap(v)


func _tab_game() -> Control:
	var v := _page("Jeu")
	_slider(v, "Durée d'une journée (minutes réelles)", "day_minutes", 4.0, 20.0, 1.0)
	_slider(v, "Nombre de collègues (PNJ)", "npc_count", 3.0, 14.0, 1.0)
	_slider(v, "Difficulté (soupçons)", "difficulty", 0.5, 1.5, 0.1)
	_slider(v, "Mémoire du directeur", "boss_memory", 0.5, 1.5, 0.1)
	v.add_child(UiKit.label("IA générative locale (facultatif)", 18, UiKit.YELLOW, true))
	var info := UiKit.label("Le jeu fonctionne entièrement sans. Si tu as un serveur local compatible Ollama, " +
		"un petit modèle (0,5–1,5 Go de RAM) peut enrichir certaines répliques. Rien n'est téléchargé automatiquement.", 14, UiKit.MUTED)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(720, 0)
	v.add_child(info)
	_check(v, "Activer le modèle local", "llm_enabled")
	var le := LineEdit.new()
	le.text = String(Settings.get_v("llm_endpoint"))
	le.custom_minimum_size = Vector2(600, 44)
	le.text_changed.connect(func(t): Settings.set_v("llm_endpoint", t))
	v.add_child(le)
	var lm := LineEdit.new()
	lm.text = String(Settings.get_v("llm_model"))
	lm.custom_minimum_size = Vector2(300, 44)
	lm.text_changed.connect(func(t): Settings.set_v("llm_model", t))
	v.add_child(lm)
	v.add_child(UiKit.button("Effacer la progression", func():
		var cp := ChoicePanel.open(self, "Effacer la progression ?", "Argent, objets et statistiques seront perdus.", [{"label": "Oui, tout effacer", "value": true}])
		cp.chosen.connect(func(_v): SaveGame.reset()), 320))
	return _wrap(v)


func _input(event: InputEvent) -> void:
	if _waiting_action != "" and event is InputEventKey and event.pressed:
		if event.physical_keycode != KEY_ESCAPE:
			Settings.rebind(_waiting_action, event.physical_keycode)
		_rebind_buttons[_waiting_action].text = Settings.key_label(_waiting_action)
		_waiting_action = ""
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if _waiting_action == "" and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause")):
		get_viewport().set_input_as_handled()
		close()


func close() -> void:
	if is_queued_for_deletion():
		return
	ChoicePanel.open_count = maxi(0, ChoicePanel.open_count - 1)
	closed.emit()
	queue_free()
