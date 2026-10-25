class_name Hud
extends CanvasLayer
## In-game HUD: clock & day progress, productivity, money, own suspicion level,
## objectives, interaction prompt, action progress, notifications, inventory.
## Read-only view of the session: it never decides rewards or detections.

var session: Session
var pc: PlayerController
var ch: Character
var root: Control
var clock_l: Label
var day_bar: ProgressBar
var prod_bar: ProgressBar
var money_l: Label
var sus_l: Label
var sus_dots: Array[ColorRect] = []
var obj_box: VBoxContainer
var obj_panel: PanelContainer
var prompt: PanelContainer
var prompt_v: VBoxContainer
var progress: ProgressBar
var progress_l: Label
var notif_box: VBoxContainer
var banner: Label
var inv_box: HBoxContainer
var crosshair: ColorRect
var hint_l: Label
var meet_banner: PanelContainer
var meet_l: Label
var shop_btn: Button
var pause_btn: Button          # touch only (the keyboard uses Échap)
var mission_chip: Button
var trust_bar: ProgressBar
var trust_l: Label
var _last_trust := -1.0
var _act_t := 0.0
var _act_total := 0.0
var _last_level := 0
var _inv_sig := ""
var _obj_sig := ""


func setup(s: Session, controller: PlayerController) -> void:
	session = s
	pc = controller
	ch = controller.ch
	layer = 5
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiKit.theme()
	add_child(root)
	_build_top()
	_build_objectives()
	_build_prompt()
	_build_notifs()
	_build_inventory()
	crosshair = ColorRect.new()
	crosshair.color = Color(1, 1, 1, 0.7)
	crosshair.size = Vector2(6, 6)
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.position -= Vector2(3, 3)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(crosshair)
	session.notified.connect(notify)
	session.hud_changed.connect(refresh)
	session.action_started.connect(func(label, dur):
		_act_total = dur
		_act_t = 0.0
		progress_l.text = label + "…"
		progress.get_parent().visible = true)
	session.action_ended.connect(func(ok, msg):
		progress.get_parent().visible = false
		if not ok and msg != "":
			notify(msg, "warn"))
	pc.focus_changed.connect(_on_focus)
	refresh()


func _build_top() -> void:
	var top := UiKit.hbox(14)
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 16
	top.offset_right = -16
	top.offset_top = 12
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)
	var left := UiKit.panel()
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(left)
	var lv := UiKit.vbox(4)
	left.add_child(lv)
	var row := UiKit.hbox(8)
	lv.add_child(row)
	clock_l = UiKit.label("09:00", 30, UiKit.YELLOW, true)
	row.add_child(clock_l)
	row.add_child(UiKit.label("Jour %d" % session.day_number, 18, UiKit.MUTED))
	day_bar = ProgressBar.new()
	day_bar.custom_minimum_size = Vector2(210, 8)
	day_bar.show_percentage = false
	lv.add_child(day_bar)
	var prow := UiKit.hbox(6)
	lv.add_child(prow)
	prow.add_child(UiKit.label("Productivité", 15, UiKit.MUTED))
	prod_bar = ProgressBar.new()
	prod_bar.custom_minimum_size = Vector2(110, 14)
	prod_bar.show_percentage = false
	prod_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fill := UiKit.box(UiKit.GOOD, 7)
	prod_bar.add_theme_stylebox_override("fill", fill)
	prow.add_child(prod_bar)
	# current secret mission, always visible; tap/click to see them all
	mission_chip = Button.new()
	mission_chip.focus_mode = Control.FOCUS_NONE
	mission_chip.alignment = HORIZONTAL_ALIGNMENT_LEFT
	mission_chip.clip_text = true
	mission_chip.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	mission_chip.custom_minimum_size = Vector2(250, 44)
	mission_chip.add_theme_font_override("font", UiKit.hand_font)
	mission_chip.add_theme_font_size_override("font_size", 21)
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		mission_chip.add_theme_color_override(k, UiKit.INK)
	var chip_st := UiKit.postit_box()
	chip_st.border_width_top = 6
	chip_st.content_margin_top = 4
	chip_st.content_margin_bottom = 4
	chip_st.content_margin_left = 12
	mission_chip.add_theme_stylebox_override("normal", chip_st)
	mission_chip.add_theme_stylebox_override("hover", chip_st)
	mission_chip.add_theme_stylebox_override("pressed", chip_st)
	mission_chip.add_theme_stylebox_override("focus", chip_st)
	mission_chip.pressed.connect(toggle_objectives)
	lv.add_child(mission_chip)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(sp)
	shop_btn = Button.new()
	shop_btn.text = "BOUTIQUE"
	shop_btn.focus_mode = Control.FOCUS_NONE
	shop_btn.custom_minimum_size = Vector2(150, 64)
	shop_btn.add_theme_font_override("font", UiKit.title_font)
	shop_btn.add_theme_font_size_override("font_size", 22)
	shop_btn.add_theme_color_override("font_color", Color.BLACK)
	shop_btn.add_theme_color_override("font_hover_color", Color.BLACK)
	shop_btn.add_theme_color_override("font_pressed_color", Color.BLACK)
	shop_btn.add_theme_stylebox_override("normal", UiKit.box(UiKit.YELLOW, 16))
	shop_btn.add_theme_stylebox_override("hover", UiKit.box(UiKit.YELLOW.lightened(0.15), 16))
	shop_btn.add_theme_stylebox_override("pressed", UiKit.box(UiKit.YELLOW.darkened(0.2), 16))
	shop_btn.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	shop_btn.pressed.connect(func(): pc.ui_open.emit("shop", {"target": ""}))
	pause_btn = UiKit.button("II", func(): pass, 64, 24)
	pause_btn.focus_mode = Control.FOCUS_NONE
	pause_btn.custom_minimum_size = Vector2(64, 64)
	pause_btn.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	pause_btn.visible = Settings.use_touch()
	pause_btn.tooltip_text = "Pause"
	top.add_child(pause_btn)
	top.add_child(shop_btn)
	var right := UiKit.panel()
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(right)
	var rv := UiKit.vbox(4)
	right.add_child(rv)
	money_l = UiKit.label("0 €", 28, UiKit.YELLOW, true)
	money_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rv.add_child(money_l)
	# the director's opinion of you
	var trow := UiKit.hbox(6)
	trow.alignment = BoxContainer.ALIGNMENT_END
	rv.add_child(trow)
	trow.add_child(UiKit.label("Le chef", 15, UiKit.MUTED))
	trust_bar = ProgressBar.new()
	trust_bar.custom_minimum_size = Vector2(120, 14)
	trust_bar.show_percentage = false
	trust_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	trow.add_child(trust_bar)
	trust_l = UiKit.label("Neutre", 15, UiKit.TEXT)
	trust_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rv.add_child(trust_l)
	var srow := UiKit.hbox(4)
	srow.alignment = BoxContainer.ALIGNMENT_END
	rv.add_child(srow)
	srow.add_child(UiKit.label("Soupçons", 15, UiKit.MUTED))
	for i in 5:
		var d := ColorRect.new()
		d.custom_minimum_size = Vector2(16, 12)
		d.color = Color(1, 1, 1, 0.15)
		d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		srow.add_child(d)
		sus_dots.append(d)
	sus_l = UiKit.label("Aucun soupçon", 15, UiKit.MUTED)
	sus_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rv.add_child(sus_l)


func toggle_objectives() -> void:
	obj_panel.visible = not obj_panel.visible
	SoundFx.ui("ui_click")


## Day start briefing: show the secret objectives for a few seconds so nobody misses them.
func brief_objectives(dur := 12.0) -> void:
	obj_panel.visible = true
	notify("Tes missions du jour sont sur le post-it à gauche. Touche le petit post-it en haut (ou %s) pour le revoir." % ("ton PC" if Settings.use_touch() else Settings.key_label("objectives")), "event")
	get_tree().create_timer(dur).timeout.connect(func():
		if is_instance_valid(obj_panel):
			obj_panel.visible = false)


func _build_objectives() -> void:
	obj_panel = PanelContainer.new()
	obj_panel.add_theme_stylebox_override("panel", UiKit.postit_box())
	obj_panel.custom_minimum_size = Vector2(340, 0)
	obj_panel.rotation_degrees = -1.5
	obj_panel.position = Vector2(20, 190)
	obj_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	obj_panel.visible = false
	root.add_child(obj_panel)
	obj_box = UiKit.vbox(6)
	# phones: keep the list above the joystick; both scroll when the list is long
	var sc := UiKit.scroll(obj_box, Vector2(320, 230 if Settings.use_touch() else 470))
	obj_panel.add_child(sc)
	if Settings.use_touch():
		obj_panel.position = Vector2(20, 178)


func _build_prompt() -> void:
	prompt = UiKit.panel()
	prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	prompt.grow_vertical = Control.GROW_DIRECTION_BEGIN
	prompt.offset_bottom = -110 if not Settings.use_touch() else -24
	prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE if not Settings.use_touch() else Control.MOUSE_FILTER_PASS
	if Settings.use_touch():
		prompt.add_to_group("touch_blocker")
		# phones: list sits left of the big action button, centre of the screen stays clear
		prompt.anchor_left = 1.0
		prompt.anchor_right = 1.0
		prompt.anchor_top = 1.0
		prompt.anchor_bottom = 1.0
		prompt.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		prompt.offset_right = -370
		prompt.offset_left = -370
		prompt.offset_bottom = -24
		prompt.offset_top = -24
	prompt.visible = false
	root.add_child(prompt)
	prompt_v = UiKit.vbox(2)
	prompt.add_child(prompt_v)
	# re-place whenever the content or the screen changes size
	prompt.minimum_size_changed.connect(func(): _place_prompt.call_deferred())
	prompt.visibility_changed.connect(func(): _place_prompt.call_deferred())
	root.resized.connect(func(): _place_prompt.call_deferred())
	var pp := UiKit.panel(Vector2(320, 0))
	pp.set_anchors_preset(Control.PRESET_CENTER)
	pp.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pp.offset_top = 70
	pp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pp.visible = false
	root.add_child(pp)
	var pv := UiKit.vbox(4)
	pp.add_child(pv)
	progress_l = UiKit.label("", 18)
	progress_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pv.add_child(progress_l)
	progress = ProgressBar.new()
	progress.custom_minimum_size = Vector2(290, 14)
	progress.show_percentage = false
	pv.add_child(progress)


func _build_notifs() -> void:
	notif_box = UiKit.vbox(6)
	notif_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	notif_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	notif_box.offset_top = 14
	notif_box.custom_minimum_size = Vector2(560, 0)
	notif_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(notif_box)
	meet_banner = PanelContainer.new()
	meet_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	meet_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	meet_banner.offset_top = 12
	meet_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meet_banner.visible = false
	root.add_child(meet_banner)
	meet_l = UiKit.label("", 20, Color.BLACK, true)
	meet_l.add_theme_constant_override("outline_size", 0)
	meet_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	meet_banner.add_child(meet_l)
	hint_l = UiKit.label("", 15, UiKit.MUTED)
	hint_l.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hint_l.offset_left = 18
	hint_l.offset_top = -34
	hint_l.text = "%s/%s/%s/%s bouger · %s courir · %s s'accroupir · %s agir · %s action suivante · %s lâcher · Échap pause" % [
		Settings.key_label("move_forward"), Settings.key_label("move_left"), Settings.key_label("move_back"), Settings.key_label("move_right"),
		Settings.key_label("run"), Settings.key_label("crouch"), Settings.key_label("interact"), Settings.key_label("next_action"), Settings.key_label("drop")]
	hint_l.visible = not Settings.use_touch()
	root.add_child(hint_l)


func _build_inventory() -> void:
	var p := UiKit.panel()
	if Settings.use_touch():
		# phones: inventory under the money panel, out of the thumbs' way
		p.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		p.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		p.offset_right = -16
		p.offset_top = 132
		p.add_to_group("touch_blocker")
	else:
		p.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		p.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		p.grow_vertical = Control.GROW_DIRECTION_BEGIN
		p.offset_right = -16
		p.offset_bottom = -16
	root.add_child(p)
	inv_box = UiKit.hbox(8)
	p.add_child(inv_box)


# ------------------------------------------------------------------ updates
func _process(delta: float) -> void:
	if session == null:
		return
	clock_l.text = session.day.clock_text()
	day_bar.value = session.day.progress() * 100.0
	if progress.get_parent().visible and _act_total > 0.0:
		_act_t += delta
		progress.value = clampf(_act_t / _act_total, 0, 1) * 100.0
	crosshair.visible = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	_update_meeting_banner()
	if Settings.use_touch() and prompt.visible and _ctx_visible() != _ctx_shown:
		_place_prompt()
	# objectives toggle
	if Input.is_action_just_pressed("objectives"):
		toggle_objectives()
	if Input.is_action_just_pressed("shop") and not pc.blocked:
		pc.ui_open.emit("shop", {"target": ""})


## Meeting: where to go, and whether the director is looking (the risk indicator).
func _update_meeting_banner() -> void:
	var show := session.day.meeting_active and not ch.is_director()
	meet_banner.visible = show
	notif_box.offset_top = 70 if show else 14
	if not show:
		return
	var col := UiKit.YELLOW
	if session.world.zone_at(ch.global_position) != "meeting":
		meet_l.text = "RÉUNION EN COURS → salle Synergie (le chef note les absents)"
		col = UiKit.WARN
	elif session.boss_back_turned():
		meet_l.text = "Le chef écrit au tableau : c'est le moment de faire le con !"
		col = UiKit.GOOD
	else:
		meet_l.text = "Le chef vous regarde… tiens-toi bien."
		col = UiKit.YELLOW
	meet_banner.add_theme_stylebox_override("panel", UiKit.box(col, 12))


func refresh() -> void:
	if session == null or ch == null:
		return
	money_l.text = "%d €" % session.economy.money(ch.id)
	prod_bar.value = ch.productivity
	var lvl := session.suspicion_level(ch.id)
	sus_l.text = Suspicion.LEVELS[lvl]
	var cols := [UiKit.GOOD, Color("#c8e04c"), UiKit.YELLOW, UiKit.WARN, UiKit.BAD]
	for i in 5:
		sus_dots[i].color = cols[i] if i < lvl else Color(1, 1, 1, 0.15)
	sus_l.add_theme_color_override("font_color", UiKit.MUTED if lvl == 0 else cols[mini(lvl - 1, 4)])
	if lvl > _last_level:
		SoundFx.ui("suspicion_up")
	_last_level = lvl
	_refresh_objectives()
	_refresh_inventory()
	_refresh_trust()


func _refresh_trust() -> void:
	var hidden := session.mode != "solo" and not ch.is_director()
	trust_bar.get_parent().visible = not hidden and not ch.is_director()
	trust_l.visible = trust_bar.get_parent().visible
	if hidden or ch.is_director():
		return
	var v := session.trust_of(ch.id)
	trust_bar.value = v
	var col := UiKit.BAD.lerp(UiKit.YELLOW, clampf(v / 50.0, 0, 1)) if v < 50.0 else UiKit.YELLOW.lerp(UiKit.GOOD, clampf((v - 50.0) / 50.0, 0, 1))
	trust_bar.add_theme_stylebox_override("fill", UiKit.box(col, 7))
	trust_l.text = Session.trust_mood(v)
	trust_l.add_theme_color_override("font_color", col)
	if _last_trust >= 0.0 and absf(v - _last_trust) >= 1.0:
		var tw := trust_bar.create_tween()
		trust_bar.modulate = Color(1.6, 1.6, 1.6) if v > _last_trust else Color(1.6, 0.6, 0.6)
		tw.tween_property(trust_bar, "modulate", Color.WHITE, 0.6)
	_last_trust = v


func _refresh_objectives() -> void:
	var ms: MissionSystem = session.missions.get(ch.id)
	if ms == null:
		mission_chip.visible = false
		return
	var cur := ""
	var n_done := 0
	for id in ms.active:
		if ms.is_done(id):
			n_done += 1
		elif cur == "":
			cur = id
	mission_chip.visible = true
	mission_chip.text = ("%d/%d  %s  +%d €" % [n_done, ms.active.size(), ms.title(cur), ms.reward_of(cur)] if cur != "" else "Tout est fait ! %d/%d" % [n_done, ms.active.size()])
	var sig := ""
	for id in ms.all_ids():
		sig += id + str(ms.is_done(id)) + str(ms.progress.get(id, "")) + str(ms._hold.get(id, 0))
	if sig == _obj_sig:
		return
	_obj_sig = sig
	for c in obj_box.get_children():
		c.queue_free()
	obj_box.add_child(UiKit.hand("À faire (en douce !)" + ("" if Settings.use_touch() else "  [%s]" % Settings.key_label("objectives")), 22, UiKit.RED_INK, true))
	for id in ms.active:
		_obj_row(ms, id, true)
	obj_box.add_child(UiKit.hand("Bonus :", 20, UiKit.INK, true))
	for id in ms.side:
		_obj_row(ms, id, false)


func _obj_row(ms: MissionSystem, id: String, main: bool) -> void:
	var done := ms.is_done(id)
	var v := UiKit.vbox(0)
	obj_box.add_child(v)
	# handwritten line, crossed out once done
	var t := RichTextLabel.new()
	t.bbcode_enabled = true
	t.fit_content = true
	t.scroll_active = false
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size = Vector2(300, 0)
	t.add_theme_font_override("normal_font", UiKit.hand_font)
	t.add_theme_font_size_override("normal_font_size", 22 if main else 19)
	t.add_theme_color_override("default_color", UiKit.INK)
	var line := "- " + ms.title(id) + ("  [color=#b3181f]+%d €[/color]" % ms.reward_of(id) if main else "")
	t.text = "[s]%s[/s]  [color=#1f7a33]Fait ![/color]" % line if done else line
	v.add_child(t)
	if main and not done:
		var d := UiKit.hand(ms.desc(id), 17, UiKit.INK.lightened(0.25))
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(300, 0)
		v.add_child(d)
		var need: Array = Data.missions[id].get("items", [])
		for it in need:
			if not ch.has_item(it):
				v.add_child(UiKit.hand("   il me faut : %s (boutique)" % Data.item_name(it), 17, UiKit.RED_INK))


func _refresh_inventory() -> void:
	var sig := ",".join(ch.items) + "|" + ",".join(ch.passive) + "|" + str(session.item_actions(ch).size())
	if sig == _inv_sig:
		return
	_inv_sig = sig
	for c in inv_box.get_children():
		c.queue_free()
	var cap := Character.MAX_POCKET + (2 if "sac_sport" in ch.passive else 0)
	for i in cap:
		var b := Button.new()
		b.custom_minimum_size = Vector2(64, 64)
		b.focus_mode = Control.FOCUS_NONE
		if i < ch.items.size():
			var it: String = ch.items[i]
			var ic := UiKit.icon(it, 46)
			ic.position = Vector2(9, 9)   # top-left anchors: the slot is still 0x0 when built
			ic.size = Vector2(46, 46)
			ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.add_child(ic)
			b.tooltip_text = Data.item_name(it)
			b.pressed.connect(func(): open_item_menu(it))
		else:
			b.disabled = true
		var k := UiKit.label(str(i + 1), 12, UiKit.MUTED)
		k.position = Vector2(4, 0)
		k.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(k)
		inv_box.add_child(b)
	var extra := session.item_actions(ch).filter(func(a): return a.id in ["trigger_buzzer"])
	for a in extra:
		var tb := UiKit.button("BUZZ", func(): pc.send(ch.id, a.id, {"item": a.item, "target": a.get("target", "")}), 80, 18)
		tb.tooltip_text = a.label
		inv_box.add_child(tb)


func _unhandled_input(event: InputEvent) -> void:
	for i in 4:
		if event.is_action_pressed("slot_%d" % (i + 1)) and i < ch.items.size():
			open_item_menu(ch.items[i])
	if event.is_action_pressed("use_item"):
		var acts := session.item_actions(ch).filter(func(a): return a.id == "trigger_buzzer")
		if not acts.is_empty():
			pc.send(ch.id, "trigger_buzzer", {"item": "buzzer", "target": acts[0].target})


func open_item_menu(item: String) -> void:
	var opts: Array = []
	for a in session.item_actions(ch):
		if a.item == item:
			opts.append({"label": a.label, "value": a})
	if opts.is_empty():
		var why := "Utilise-le sur un objet du décor (vise-le puis %s)." % Settings.key_label("interact")
		if item in ["confettis", "serpent"]:
			why = "À cacher dans un tiroir : approche-toi d'un tiroir de bureau et choisis l'action."
		elif item == "poil_gratter":
			why = "Approche-toi d'une chaise (celle d'un collègue !) et choisis « Saupoudrer »."
		elif item == "post_its":
			why = "Vise l'ordinateur d'un collègue absent."
		notify(Data.item_name(item) + " — " + why, "info")
		return
	var cp := ChoicePanel.open(root, Data.item_name(item), Data.item_info(item).get("desc", ""), opts)
	cp.chosen.connect(func(v): pc.send(ch.id, String(v.id), {"item": item, "target": v.get("target", "")}))


var _prompt_sig := ""


func _on_focus(f: Dictionary) -> void:
	var sig := "%s|%d|%s" % [f.get("target", ""), int(f.get("index", 0)), str(pc.blocked)]
	for a in f.get("actions", []):
		sig += "|" + String(a.get("label", "")) + String(a.get("blocked", ""))
	if sig == _prompt_sig:
		return   # rebuilding every frame would swallow taps
	_prompt_sig = sig
	for c in prompt_v.get_children():
		prompt_v.remove_child(c)   # now, so the panel is not sized for old + new rows
		c.queue_free()
	_place_prompt.call_deferred()
	var acts: Array = f.get("actions", [])
	if acts.is_empty() or pc.blocked:
		prompt.visible = false
		return
	prompt.visible = true
	prompt_v.add_child(UiKit.label(String(f.name), 20, UiKit.YELLOW, true))
	var idx: int = f.get("index", 0)
	for i in acts.size():
		var a: Dictionary = acts[i]
		var blocked := String(a.get("blocked", "")) != ""
		var key := ""
		if i == idx:
			key = "[%s] " % Settings.key_label("interact")
		elif (i == 1 and idx == 0) or (i == 0 and idx != 0):
			key = "[%s] " % Settings.key_label("alt_action")
		var txt := key + String(a.label)
		if float(a.get("time", 0.0)) > 0.0:
			txt += "  (%ds)" % ceili(float(a.time))
		if float(a.get("sus", 0.0)) >= 0.6:
			txt += "  ⚠"
		var col := UiKit.TEXT if i == idx else UiKit.MUTED
		if blocked:
			col = Color(0.55, 0.55, 0.6)
		if Settings.use_touch():
			# phones: every action is a big tappable row
			var b := Button.new()
			b.text = String(a.label) + ("  (%ds)" % ceili(float(a.time)) if float(a.get("time", 0.0)) > 0.0 else "") + ("  ⚠" if float(a.get("sus", 0.0)) >= 0.6 else "")
			b.custom_minimum_size = Vector2(330, 56 if acts.size() <= 6 else 48)
			b.focus_mode = Control.FOCUS_NONE
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.add_theme_font_size_override("font_size", 21)
			if i == idx:
				b.add_theme_stylebox_override("normal", UiKit.box(Color(0.3, 0.28, 0.12, 0.95), 14, 2, UiKit.YELLOW))
			b.modulate = Color(1, 1, 1, 0.55) if blocked else Color.WHITE
			var ii := i
			b.pressed.connect(func():
				pc.selected = ii
				pc.press_interact())
			prompt_v.add_child(b)
			continue
		var l := UiKit.label(txt, 18 if i == idx else 16, col)
		prompt_v.add_child(l)
		if blocked and i == idx:
			prompt_v.add_child(UiKit.label("   " + String(a.blocked), 14, UiKit.WARN))


var _ctx_shown := false


func _ctx_visible() -> bool:
	for b in get_tree().get_nodes_in_group("ctx_btn"):
		if (b as Control).is_visible_in_tree():
			return true
	return false


## Keeps the action list fully on screen whatever its length (anchored bottom-right on
## phones, bottom-centre on PC). Containers never shrink by themselves, so size it explicitly.
func _place_prompt() -> void:
	if not is_instance_valid(prompt) or not prompt.visible:
		return
	prompt.reset_size()
	var area := root.size
	var sz := prompt.size
	if Settings.use_touch():
		# leave room for the contextual Lâcher / Lancer / Se lever buttons when they show
		_ctx_shown = _ctx_visible()
		var right := 530.0 if _ctx_shown else 370.0
		prompt.position = Vector2(area.x - right - sz.x, maxf(8.0, area.y - 24.0 - sz.y))
	else:
		prompt.position = Vector2((area.x - sz.x) * 0.5, maxf(8.0, area.y - 110.0 - sz.y))


func notify(text: String, kind := "info") -> void:
	var col := UiKit.TEXT
	match kind:
		"good":
			col = UiKit.GOOD
		"warn":
			col = UiKit.WARN
		"danger":
			col = UiKit.BAD
		"event":
			col = UiKit.YELLOW
	var p := UiKit.panel()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UiKit.label(text, 18, col, kind == "event")
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(520, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	notif_box.add_child(p)
	# autowrapped labels report a one-line minimum height on their first frame: fix it once laid out
	l.resized.connect(func():
		var h := l.get_line_count() * l.get_line_height() + 2
		if absf(l.custom_minimum_size.y - h) > 1.0:
			l.custom_minimum_size.y = h)
	while notif_box.get_child_count() > 4:
		notif_box.get_child(0).queue_free()
		notif_box.remove_child(notif_box.get_child(0))
	var tw := p.create_tween()
	tw.tween_interval(4.5 if kind != "event" else 6.0)
	tw.tween_property(p, "modulate:a", 0.0, 0.6)
	tw.tween_callback(p.queue_free)
