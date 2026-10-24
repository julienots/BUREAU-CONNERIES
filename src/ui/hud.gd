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
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(sp)
	var right := UiKit.panel()
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(right)
	var rv := UiKit.vbox(4)
	right.add_child(rv)
	money_l = UiKit.label("0 €", 28, UiKit.YELLOW, true)
	money_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rv.add_child(money_l)
	var srow := UiKit.hbox(4)
	srow.alignment = BoxContainer.ALIGNMENT_END
	rv.add_child(srow)
	srow.add_child(UiKit.label("👁", 18))
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


func _build_objectives() -> void:
	obj_panel = UiKit.panel(Vector2(330, 0))
	obj_panel.position = Vector2(16, 150)
	obj_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(obj_panel)
	obj_box = UiKit.vbox(6)
	obj_panel.add_child(obj_box)


func _build_prompt() -> void:
	prompt = UiKit.panel()
	prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	prompt.grow_vertical = Control.GROW_DIRECTION_BEGIN
	prompt.offset_bottom = -110
	prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prompt.visible = false
	root.add_child(prompt)
	prompt_v = UiKit.vbox(2)
	prompt.add_child(prompt_v)
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
	p.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	p.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	p.grow_vertical = Control.GROW_DIRECTION_BEGIN
	p.offset_right = -16
	p.offset_bottom = -16 if not Settings.use_touch() else -260
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
	# objectives toggle
	if Input.is_action_just_pressed("objectives"):
		obj_panel.visible = not obj_panel.visible


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


func _refresh_objectives() -> void:
	var ms: MissionSystem = session.missions.get(ch.id)
	if ms == null:
		return
	var sig := ""
	for id in ms.all_ids():
		sig += id + str(ms.is_done(id)) + str(ms.progress.get(id, "")) + str(ms._hold.get(id, 0))
	if sig == _obj_sig:
		return
	_obj_sig = sig
	for c in obj_box.get_children():
		c.queue_free()
	obj_box.add_child(UiKit.label("OBJECTIFS SECRETS  [%s]" % Settings.key_label("objectives"), 18, UiKit.YELLOW, true))
	for id in ms.active:
		_obj_row(ms, id, true)
	obj_box.add_child(UiKit.label("Défis", 15, UiKit.MUTED))
	for id in ms.side:
		_obj_row(ms, id, false)


func _obj_row(ms: MissionSystem, id: String, main: bool) -> void:
	var done := ms.is_done(id)
	var v := UiKit.vbox(0)
	obj_box.add_child(v)
	var t := UiKit.label(("✔ " if done else "• ") + ms.title(id) + ("  +%d €" % ms.reward_of(id) if main else ""), 17 if main else 15, UiKit.GOOD if done else UiKit.TEXT)
	v.add_child(t)
	if main and not done:
		var d := UiKit.label(ms.desc(id), 13, UiKit.MUTED)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(300, 0)
		v.add_child(d)
		var need: Array = Data.missions[id].get("items", [])
		for it in need:
			if not ch.has_item(it):
				v.add_child(UiKit.label("   Requiert : %s (boutique)" % Data.item_name(it), 13, UiKit.WARN))
		var p = ms.progress.get(id, null)
		if typeof(p) == TYPE_INT or typeof(p) == TYPE_ARRAY:
			pass


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
			ic.set_anchors_preset(Control.PRESET_CENTER)
			ic.position = Vector2(9, 9)
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
		var tb := UiKit.button("📡", func(): pc.send(ch.id, a.id, {"item": a.item, "target": a.get("target", "")}), 64, 26)
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
		if item == "confettis":
			why = "À cacher dans un tiroir (vise un tiroir)."
		elif item == "post_its":
			why = "Vise l'ordinateur d'un collègue absent."
		notify(Data.item_name(item) + " — " + why, "info")
		return
	var cp := ChoicePanel.open(root, Data.item_name(item), Data.item_info(item).get("desc", ""), opts)
	cp.chosen.connect(func(v): pc.send(ch.id, String(v.id), {"item": item, "target": v.get("target", "")}))


func _on_focus(f: Dictionary) -> void:
	for c in prompt_v.get_children():
		c.queue_free()
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
		var l := UiKit.label(txt, 18 if i == idx else 16, col)
		prompt_v.add_child(l)
		if blocked and i == idx:
			prompt_v.add_child(UiKit.label("   " + String(a.blocked), 14, UiKit.WARN))


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
	while notif_box.get_child_count() > 4:
		notif_box.get_child(0).queue_free()
		notif_box.remove_child(notif_box.get_child(0))
	var tw := p.create_tween()
	tw.tween_interval(4.5 if kind != "event" else 6.0)
	tw.tween_property(p, "modulate:a", 0.0, 0.6)
	tw.tween_callback(p.queue_free)
