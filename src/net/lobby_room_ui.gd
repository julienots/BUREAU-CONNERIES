extends Control
## In-room lobby (inside the game scene): players, roles, ready flags, room settings,
## invite code, start button for the room owner; then the role briefing during "prep".

var ns: Node
var list: VBoxContainer
var code_l: Label
var info_l: Label
var start_b: Button
var ready_b: Button
var settings_box: HBoxContainer
var _ready_on := false
var _panel: Control
var _brief: Control


func setup(net_sync: Node) -> void:
	ns = net_sync
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UiKit.theme()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	ChoicePanel.open_count += 1
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.08, 1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var p := UiKit.panel(Vector2(760, 560))
	_panel = UiKit.center_modal(self, p)
	var v := UiKit.vbox(10)
	p.add_child(v)
	var head := UiKit.hbox(12)
	v.add_child(head)
	head.add_child(UiKit.label("Salon en ligne", 34, UiKit.YELLOW, true))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	code_l = UiKit.label("", 30, Color.WHITE, true)
	head.add_child(code_l)
	info_l = UiKit.label("", 16, UiKit.MUTED)
	v.add_child(info_l)
	list = UiKit.vbox(6)
	v.add_child(UiKit.scroll(list, Vector2(720, 260)))
	var roles := UiKit.hbox(10)
	v.add_child(roles)
	roles.add_child(UiKit.button("Je veux être le DIRECTEUR", func(): _role("director"), 330, 18))
	roles.add_child(UiKit.button("Je serai EMPLOYÉ", func(): _role("employee"), 330, 18))
	settings_box = UiKit.hbox(10)
	v.add_child(settings_box)
	settings_box.add_child(UiKit.label("Durée (min)", 16))
	var dur := SpinBox.new()
	dur.min_value = 3
	dur.max_value = 20
	dur.value = 8
	dur.value_changed.connect(func(x): _settings(x, -1))
	settings_box.add_child(dur)
	settings_box.add_child(UiKit.label("Joueurs max", 16))
	var mx := SpinBox.new()
	mx.min_value = 2
	mx.max_value = 9
	mx.value = 9
	mx.value_changed.connect(func(x): _settings(-1, x))
	settings_box.add_child(mx)
	var bottom := UiKit.hbox(10)
	v.add_child(bottom)
	ready_b = UiKit.button("Prêt !", _toggle_ready, 220)
	bottom.add_child(ready_b)
	start_b = UiKit.button("Lancer la partie", _start, 260)
	bottom.add_child(start_b)
	bottom.add_child(UiKit.button("Quitter", Game.goto_menu, 160))


var _dur := 8.0
var _max := 9


func _settings(d: float, m: float) -> void:
	if d > 0:
		_dur = d
	if m > 0:
		_max = int(m)
	_send("c2s_settings", [_dur, _max])


func _send(method: String, args: Array) -> void:
	if Net.role == "host":
		# local owner: call the server function directly (sender id = 1)
		ns.callv(method, args)
	else:
		ns.callv("rpc_id", [1, method] + args)


func _role(r: String) -> void:
	_send("c2s_set_role", [r])


func _toggle_ready() -> void:
	_ready_on = not _ready_on
	_send("c2s_ready", [_ready_on])


func _start() -> void:
	_send("c2s_start", [])


func refresh(st: Dictionary, me: int) -> void:
	var room: Dictionary = st.room
	code_l.text = "Code : %s" % room.code
	info_l.text = "%s · %s · %d min · max %d joueurs" % [room.name, "public" if room.public else "privé", int(room.day_minutes), int(room.max)]
	for c in list.get_children():
		c.queue_free()
	var am_owner := false
	for p in st.players:
		var row := UiKit.hbox(10)
		list.add_child(row)
		var role_txt := "👔 DIRECTEUR" if p.role == "director" else "💼 Employé"
		var name_l := UiKit.label(String(p.name) + ("  (toi)" if int(p.id) == me else "") + ("  ★" if p.owner else ""), 20, UiKit.YELLOW if int(p.id) == me else UiKit.TEXT)
		name_l.custom_minimum_size = Vector2(320, 0)
		row.add_child(name_l)
		row.add_child(UiKit.label(role_txt, 18, UiKit.WARN if p.role == "director" else UiKit.MUTED))
		row.add_child(UiKit.label("✔ prêt" if p.ready else ("…" if p.connected else "déconnecté"), 18, UiKit.GOOD if p.ready else UiKit.MUTED))
		if p.owner and int(p.id) == me:
			am_owner = true
	start_b.visible = am_owner
	settings_box.visible = am_owner
	ready_b.text = "Pas prêt" if _ready_on else "Prêt !"
	if st.players.size() < 2:
		info_l.text += "  —  En attente d'autres joueurs (partage le code !)"


func show_briefing(text: String) -> void:
	if _panel:
		_panel.queue_free()
		_panel = null
	for c in get_children():
		c.queue_free()
	var p := UiKit.panel(Vector2(700, 0))
	_brief = UiKit.center_modal(self, p)
	(_brief as ColorRect).color = Color(0, 0, 0, 0.6)
	var v := UiKit.vbox(10)
	p.add_child(v)
	v.add_child(UiKit.label("Briefing", 34, UiKit.YELLOW, true))
	var l := UiKit.label(text, 19)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(660, 0)
	v.add_child(l)
	v.add_child(UiKit.label("La journée commence dans quelques secondes…", 16, UiKit.MUTED))


func hide_all() -> void:
	ChoicePanel.open_count = maxi(0, ChoicePanel.open_count - 1)
	if not Settings.use_touch():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	queue_free()
