extends Node
## In-game scene: builds the session for the requested mode, the local player's camera,
## controller, HUD, touch controls, tutorial, and routes UI flows (shop, work, social
## choices, interrogation, pause, end of day).

var session: Session
var rig: CameraRig
var pc: PlayerController
var hud: Hud
var mobile: MobileControls
var ui_layer: CanvasLayer
var ui_root: Control
var paused_panel: Control
var mode := "solo"


func _ready() -> void:
	var args: Dictionary = Game.start_args
	mode = String(args.get("mode", "solo"))
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 10
	ui_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(ui_layer)
	ui_root = Control.new()
	ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.theme = UiKit.theme()
	ui_layer.add_child(ui_root)
	ChoicePanel.open_count = 0
	_apply_render_scale()
	if mode == "solo":
		_start_solo(args)
	else:
		_start_network(args)


func _apply_render_scale() -> void:
	var s := float(Settings.get_v("render_scale"))
	if Settings.is_mobile() and Settings.get_v("quality") == "auto":
		s = minf(s, 0.75)
	get_viewport().scaling_3d_scale = s


func _start_solo(args: Dictionary) -> void:
	session = Session.new()
	session.name = "Session"
	add_child(session)
	session.setup("solo", {"day": SaveGame.data.day, "seed": int(args.get("seed", randi() % 99999))})
	var look: Dictionary = SaveGame.data.appearance
	session.spawn_cast({"player": {"name": Settings.get_v("player_name"), "look": look, "cosmetics": SaveGame.data.equipped_cosmetics}}, int(Settings.get_v("npc_count")))
	session.player = session.characters["player"]
	_setup_local_player(session.player)
	session.start_day_solo()
	session.day_over.connect(_on_day_over)
	if not Settings.get_v("tutorial_done"):
		var t := Tutorial.new()
		add_child(t)
		t.setup(session, hud, session.player)


## Multiplayer: the session is created by NetSync once the server sends the game start.
func _start_network(_args: Dictionary) -> void:
	var ns: Node = load("res://src/net/net_sync.gd").new()
	ns.name = "NetSync"
	add_child(ns)
	ns.call("begin", self)


func _setup_local_player(ch: Character) -> void:
	rig = CameraRig.new()
	add_child(rig)
	rig.attach(ch)
	pc = PlayerController.new()
	pc.name = "PlayerController"
	add_child(pc)
	pc.setup(ch, rig, session)
	pc.ui_open.connect(_on_ui_open)
	hud = Hud.new()
	add_child(hud)
	hud.setup(session, pc)
	if Settings.use_touch():
		mobile = MobileControls.new()
		add_child(mobile)
		mobile.setup(pc)
		mobile.pause_requested.connect(_toggle_pause)
		mobile.objectives_requested.connect(func(): hud.obj_panel.visible = not hud.obj_panel.visible)
		rig.auto_follow = true
		hud.obj_panel.visible = false
	session.interrogation_started.connect(func(info): InterrogationPanel.open(ui_root, session, ch, info))
	session.interrogation_finished.connect(_on_interrogation_done)
	ch.fell.connect(func(_c): rig.shake(0.6))
	SoundFx.music("day_loop", 2.0)
	SoundFx.ambience(["ambience_vent", "ambience_office"])
	if not Settings.use_touch():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(_delta: float) -> void:
	if pc == null:
		return
	var modal := ChoicePanel.open_count > 0 or paused_panel != null
	pc.blocked = modal
	if modal:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if mobile:
		mobile.visible = not modal


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and ChoicePanel.open_count == 0:
		_toggle_pause()
		get_viewport().set_input_as_handled()


func _toggle_pause() -> void:
	if paused_panel:
		paused_panel.queue_free()
		paused_panel = null
		if mode == "solo":
			get_tree().paused = false
		if not Settings.use_touch():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	if mode == "solo":
		get_tree().paused = true
	var p := UiKit.panel(Vector2(420, 0))
	paused_panel = UiKit.center_modal(ui_root, p)
	var v := UiKit.vbox(10)
	p.add_child(v)
	v.add_child(UiKit.label("PAUSE", 40, UiKit.YELLOW, true))
	v.add_child(UiKit.button("Reprendre", _toggle_pause))
	v.add_child(UiKit.button("Objectifs", func():
		hud.obj_panel.visible = true
		_toggle_pause()))
	v.add_child(UiKit.button("Paramètres", func(): SettingsPanel.open(ui_root)))
	v.add_child(UiKit.button("Revoir le tutoriel", func():
		Settings.set_v("tutorial_done", false)
		var t := Tutorial.new()
		add_child(t)
		t.setup(session, hud, pc.ch)
		_toggle_pause()))
	v.add_child(UiKit.button("Quitter la journée", func():
		get_tree().paused = false
		if session and mode == "solo":
			session.economy.return_pocket("player", session.player)
			SaveGame.save_game()
		Game.goto_menu()))


# ------------------------------------------------------------------ UI flows
func _on_ui_open(kind: String, info: Dictionary) -> void:
	var ch := pc.ch
	var target: String = info.get("target", "")
	match kind:
		"shop":
			ShopPanel.open(ui_root, session, ch)
		"work":
			WorkPanel.open(ui_root, session, ch, target)
		"denounce":
			_denounce_flow(target)
		"rumor":
			_rumor_flow(target)
		"hide":
			var opts: Array = []
			for it in ch.items:
				opts.append({"label": Data.item_name(it), "value": it, "icon": it})
			var cp := ChoicePanel.open(ui_root, "Cacher quel objet ?", "Les objets cachés peuvent être découverts lors d'une fouille.", opts)
			cp.chosen.connect(func(v): pc.send(target, "hide", {"item": v}))
		"call":
			var opts2: Array = []
			for c in session.employees():
				if c.id != ch.id:
					opts2.append({"label": "Poste de " + c.nick, "value": c.id})
			var cp2 := ChoicePanel.open(ui_root, "Appeler un poste", "Le téléphone sonnera et fera du bruit.", opts2)
			cp2.chosen.connect(func(v): pc.send(target, "call_phone", {"target": v}))
		"boss_interrogate", "boss_sanction":
			if session.net:
				session.net.call("open_boss_ui", kind, target)


func _denounce_flow(boss_id: String) -> void:
	var ch := pc.ch
	var opts: Array = []
	for c in session.employees():
		if c.id != ch.id:
			opts.append({"label": c.nick, "value": c.id})
	var cp := ChoicePanel.open(ui_root, "Dénoncer qui ?", "Un faux témoignage peut se retourner contre toi si le directeur a vu la personne ailleurs.", opts)
	cp.chosen.connect(func(accused):
		var claims: Array = []
		var mem: Memory = session.human_memory.get(ch.id)
		var witnessed: Array = mem.witnessed if mem else (session.net.call("my_witnessed") if session.net else [])
		for w in witnessed:
			if w.actor == accused:
				var a := session.act_by_id(int(w.act_id))
				var txt := session.act_description(a).replace("On vous soupçonne de : ", "") if not a.is_empty() else String(w.kind)
				claims.append({"label": "Je l'ai vu " + txt, "value": int(w.act_id), "sub": "Témoignage sincère"})
		claims.append({"label": "L'accuser sans preuve (dernier incident)", "value": -1, "sub": "Mensonge possible : risqué"})
		var cp2 := ChoicePanel.open(ui_root, "Que dis-tu au directeur ?", "", claims)
		cp2.chosen.connect(func(act_id): pc.send(boss_id, "denounce", {"accused": accused, "act_id": act_id})))


func _rumor_flow(target: String) -> void:
	var opts: Array = []
	for id in Data.rumors:
		var r: Dictionary = Data.rumors[id]
		opts.append({"label": String(r.text).replace("{about}", "…quelqu'un"), "value": id})
	var cp := ChoicePanel.open(ui_root, "Quelle rumeur ?", "Les bavards la répéteront. Les naïfs la croiront.", opts)
	cp.chosen.connect(func(rid):
		if Data.rumors[rid].get("about", "") == "target":
			var who: Array = []
			for c in session.employees():
				if c.id != pc.ch.id and c.id != target:
					who.append({"label": c.nick, "value": c.id})
			var cp2 := ChoicePanel.open(ui_root, "À propos de qui ?", "", who)
			cp2.chosen.connect(func(about): pc.send(target, "rumor", {"rumor": rid, "about": about}))
		else:
			pc.send(target, "rumor", {"rumor": rid, "about": ""}))


func _on_interrogation_done(info: Dictionary) -> void:
	match String(info.outcome):
		"sanctioned":
			var txt := "Sanction : avertissement %d/3, amende %d €." % [int(info.get("warning", 0)), int(info.get("fine", 0))]
			if String(info.get("confiscated", "")) != "":
				txt += " Confisqué : " + String(info.confiscated) + "."
			hud.notify(txt, "danger")
		"cleared":
			hud.notify("Ouf ! Le directeur te laisse partir.", "good")
		"redirected":
			hud.notify("Le directeur se tourne vers quelqu'un d'autre…", "good")


func _on_day_over(results: Dictionary) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	SoundFx.stop_music(1.5)
	var rp := ResultsPanel.open(ui_root, results)
	rp.next_day.connect(func():
		ChoicePanel.open_count = 0
		Game.start_solo())
	rp.to_menu.connect(func():
		ChoicePanel.open_count = 0
		Game.goto_menu())
