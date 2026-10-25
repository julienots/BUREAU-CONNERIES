class_name LobbyUI
extends Control
## Online hub from the main menu.
##  1. Internet (no server needed): create a game (you host it from your phone/PC) or join
##     one with its 4-letter code; public games are listed. Traffic goes through a free
##     public relay (RelayPeer).
##  2. Same Wi-Fi / phone hotspot: host directly, the others type your IP.
##  3. Advanced: your own dedicated server (master + rooms, see README).

var status_l: Label
var rooms_box: VBoxContainer
var addr_edit: LineEdit
var code_edit: LineEdit
var name_edit: LineEdit
var pub: CheckBox
var adv_box: VBoxContainer
var link: MasterLink
var lister: MqttWs
var _list_t := -1.0
var _listed: Dictionary = {}
var _waiting := ""          # "host" | "join" while connecting through the relay
var _wait_t := 0.0


static func open(parent: Control, code := "") -> LobbyUI:
	var ui := LobbyUI.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(ui)
	ui._build(code)
	return ui


func _build(code: String) -> void:
	ChoicePanel.open_count += 1
	theme = UiKit.theme()
	var p := UiKit.panel(Vector2(980, 640))
	UiKit.center_modal(self, p)
	var outer := UiKit.vbox(8)
	p.add_child(outer)
	var head := UiKit.hbox(10)
	outer.add_child(head)
	head.add_child(UiKit.label("Jouer en ligne", 32, UiKit.YELLOW, true))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	head.add_child(UiKit.button("Retour", close, 160, 18))
	var v := UiKit.vbox(10)
	outer.add_child(UiKit.scroll(v, Vector2(940, 560)))
	# --- Internet
	v.add_child(UiKit.label("Sur Internet — aucun serveur à installer", 22, UiKit.TEXT, true))
	var c := UiKit.hbox(8)
	v.add_child(c)
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "Nom de la partie"
	name_edit.text = "Bureau de %s" % Settings.get_v("player_name")
	name_edit.custom_minimum_size = Vector2(330, 56)
	c.add_child(name_edit)
	pub = CheckBox.new()
	pub.text = "Publique"
	pub.button_pressed = true
	c.add_child(pub)
	var create := UiKit.accent(UiKit.button("CRÉER UNE PARTIE", _create_relay, 330, 22))
	create.custom_minimum_size.y = 60
	c.add_child(create)
	var j := UiKit.hbox(8)
	v.add_child(j)
	code_edit = LineEdit.new()
	code_edit.placeholder_text = "CODE (ex : K7QZ)"
	code_edit.text = code
	code_edit.max_length = 8
	code_edit.custom_minimum_size = Vector2(330, 56)
	code_edit.add_theme_font_size_override("font_size", 26)
	j.add_child(code_edit)
	var jb := UiKit.button("REJOINDRE AVEC LE CODE", func(): _join_relay(code_edit.text), 470, 20)
	jb.custom_minimum_size.y = 60
	j.add_child(jb)
	status_l = UiKit.label("", 17, UiKit.MUTED)
	status_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_l.custom_minimum_size = Vector2(900, 0)
	v.add_child(status_l)
	var lh := UiKit.hbox(8)
	v.add_child(lh)
	lh.add_child(UiKit.label("Parties publiques", 20, UiKit.TEXT, true))
	lh.add_child(UiKit.button("Actualiser", _list_relay, 180, 17))
	rooms_box = UiKit.vbox(6)
	v.add_child(rooms_box)
	# --- LAN
	v.add_child(UiKit.label("Même Wi-Fi (ou partage de connexion du téléphone)", 22, UiKit.TEXT, true))
	var lan := UiKit.hbox(8)
	v.add_child(lan)
	lan.add_child(UiKit.button("Héberger ici", _host_lan, 220, 18))
	var ip_edit := LineEdit.new()
	ip_edit.placeholder_text = "IP de l'hôte (ex : 192.168.1.20)"
	ip_edit.custom_minimum_size = Vector2(380, 56)
	lan.add_child(ip_edit)
	lan.add_child(UiKit.button("Rejoindre", func(): _join_direct(ip_edit.text), 200, 18))
	var ips := local_ips()
	v.add_child(UiKit.label("Ton IP sur ce réseau : %s" % (", ".join(ips) if not ips.is_empty() else "aucune (pas de Wi-Fi ?)"), 15, UiKit.MUTED))
	# --- advanced: own dedicated server
	var adv_btn := UiKit.button("Avancé : mon propre serveur…", func(): adv_box.visible = not adv_box.visible, 360, 16)
	v.add_child(adv_btn)
	adv_box = UiKit.vbox(8)
	adv_box.visible = false
	v.add_child(adv_box)
	var h := UiKit.hbox(8)
	adv_box.add_child(h)
	h.add_child(UiKit.label("Serveur", 17))
	addr_edit = LineEdit.new()
	addr_edit.text = "%s:%d" % [Settings.get_v("server_address"), int(Settings.get_v("server_port"))]
	addr_edit.custom_minimum_size = Vector2(320, 50)
	h.add_child(addr_edit)
	h.add_child(UiKit.button("Lister", _refresh, 140, 16))
	var hc := UiKit.hbox(8)
	adv_box.add_child(hc)
	hc.add_child(UiKit.button("Créer sur ce serveur", func(): _create(name_edit.text, pub.button_pressed), 280, 16))
	hc.add_child(UiKit.button("Rejoindre ce code", func(): _find(code_edit.text), 260, 16))
	link = MasterLink.ensure()
	link.rooms_received.connect(_on_rooms)
	link.room_resolved.connect(_on_room)
	if code != "":
		_join_relay(code)
	else:
		_list_relay()


static func local_ips() -> Array:
	var out: Array = []
	for a in IP.get_local_addresses():
		var s := String(a)
		if s.begins_with("192.168.") or s.begins_with("10.") or (s.begins_with("172.") and int(s.split(".")[1]) >= 16 and int(s.split(".")[1]) <= 31):
			out.append(s)
	return out


func _process(delta: float) -> void:
	if lister:
		lister.poll(delta)
		if _list_t >= 0.0:
			_list_t += delta
			if _list_t > 3.5:
				_show_relay_rooms()
	if _waiting != "":
		_wait_t += delta
		if Net.relay_status != "":
			status_l.text = Net.relay_status
		if _waiting == "host" and Net.relay_ready():
			_waiting = ""
			ChoicePanel.open_count = 0
			Game.goto_scene("res://src/gameplay/game_scene.tscn", {"mode": "online"})
		elif _waiting == "host" and Net.peer and Net.peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
			_waiting = ""
			status_l.text = Net.relay_status if Net.relay_status != "" else "Impossible d'ouvrir la partie."


# ------------------------------------------------------------------ Internet (relay)
func _create_relay() -> void:
	var code := Net.arg("code", Net.make_code())   # --code only used by automated tests
	Net.args["name"] = name_edit.text.strip_edges().substr(0, 24) if name_edit.text.strip_edges() != "" else "Salon " + code
	Net.args["public"] = "1" if pub.button_pressed else "0"
	status_l.text = "Ouverture de la partie %s…" % code
	if Net.host_relay(code, true) != OK:
		status_l.text = Net.relay_status
		return
	_waiting = "host"
	_wait_t = 0.0


func _join_relay(code: String) -> void:
	code = code.strip_edges().to_upper()
	if code.length() < 3:
		status_l.text = "Entre le code donné par l'hôte (4 lettres)."
		return
	status_l.text = "Recherche de la partie %s…" % code
	if Net.join_relay(code) != OK:
		status_l.text = Net.relay_status
		return
	_waiting = "join"
	var on_ok := func():
		_waiting = ""
		ChoicePanel.open_count = 0
		Game.goto_scene("res://src/gameplay/game_scene.tscn", {"mode": "online"})
	var on_fail := func():
		_waiting = ""
		if Net.connected.is_connected(on_ok):
			Net.connected.disconnect(on_ok)
		status_l.text = Net.relay_status if Net.relay_status != "" else "Partie introuvable."
	Net.connected.connect(on_ok, CONNECT_ONE_SHOT)
	Net.connection_failed.connect(on_fail, CONNECT_ONE_SHOT)


func _list_relay() -> void:
	for ch in rooms_box.get_children():
		ch.queue_free()
	rooms_box.add_child(UiKit.label("Recherche des parties publiques…", 16, UiKit.MUTED))
	_listed.clear()
	if lister:
		lister.close()
	lister = MqttWs.new()
	lister.connected.connect(func(): lister.subscribe([RelayPeer.PREFIX + "rooms/+"]))
	lister.message.connect(func(topic: String, payload: PackedByteArray):
		var code := topic.get_slice("/", topic.get_slice_count("/") - 1)
		if payload.is_empty():
			_listed.erase(code)
			return
		var d = JSON.parse_string(payload.get_string_from_utf8())
		if typeof(d) == TYPE_DICTIONARY:
			_listed[code] = d)
	lister.disconnected.connect(func(reason: String):
		if _list_t >= 0.0 and _list_t < 3.5:
			_list_t = -1.0
			for ch in rooms_box.get_children():
				ch.queue_free()
			rooms_box.add_child(UiKit.label("Relais Internet injoignable (%s). Vérifie ta connexion." % reason, 16, UiKit.WARN)))
	var urls := RelayPeer.broker_list()
	lister.open(String(urls[0]), "om-list-%d" % (randi() % 1000000))
	_list_t = 0.0


func _show_relay_rooms() -> void:
	_list_t = -1.0
	if lister:
		lister.close()
	for ch in rooms_box.get_children():
		ch.queue_free()
	var now := Time.get_unix_time_from_system()
	var n := 0
	for code in _listed:
		var r: Dictionary = _listed[code]
		if now - float(r.get("t", 0.0)) > 120.0 or not r.get("public", true):
			continue   # stale announcement (the host left without cleaning up)
		n += 1
		var in_game: bool = String(r.get("phase", "lobby")) != "lobby"
		var b := UiKit.button("%s  —  %d/%d joueurs  —  %s   [%s]" % [r.get("name", code), int(r.get("players", 0)), int(r.get("max", 9)), "en partie" if in_game else "rejoindre", code], func(): _join_relay(code), 880, 18)
		b.custom_minimum_size.y = 56
		b.disabled = in_game
		rooms_box.add_child(b)
	if n == 0:
		rooms_box.add_child(UiKit.label("Aucune partie publique pour l'instant : crée la tienne et donne le code à tes amis !", 16, UiKit.MUTED))


# ------------------------------------------------------------------ dedicated server (advanced)
func _master_addr() -> Array:
	var parts := addr_edit.text.strip_edges().split(":")
	var host := parts[0] if parts.size() > 0 and parts[0] != "" else "127.0.0.1"
	var port := int(parts[1]) if parts.size() > 1 else Net.DEFAULT_PORT
	Settings.set_v("server_address", host)
	Settings.set_v("server_port", port)
	return [host, port]


## Connects to the master then runs `then`.
func _with_master(then: Callable) -> void:
	var a := _master_addr()
	status_l.text = "Connexion au serveur %s:%d…" % [a[0], a[1]]
	if Net.join(a[0], a[1]) != OK:
		status_l.text = "Adresse invalide."
		return
	var on_ok := func(): then.call()
	var on_fail := func():
		if Net.connected.is_connected(on_ok):
			Net.connected.disconnect(on_ok)
		status_l.text = "Serveur injoignable. Utilise plutôt « Créer une partie » (Internet) ou le même Wi-Fi."
	Net.connected.connect(on_ok, CONNECT_ONE_SHOT)
	Net.connection_failed.connect(on_fail, CONNECT_ONE_SHOT)


func _refresh() -> void:
	_with_master(func(): link.c2m_list.rpc_id(1))


func _create(n: String, public: bool) -> void:
	_with_master(func():
		status_l.text = "Création du salon…"
		link.c2m_create.rpc_id(1, n, public, 9))


func _find(code: String) -> void:
	if code.strip_edges() == "":
		return
	_with_master(func(): link.c2m_find.rpc_id(1, code.strip_edges().to_upper()))


func _on_rooms(list: Array) -> void:
	Net.leave()
	for ch in rooms_box.get_children():
		ch.queue_free()
	status_l.text = "%d salon(s) sur ce serveur." % list.size()
	for r in list:
		var b := UiKit.button("%s  —  %d/%d joueurs  —  %s   [%s]" % [r.name, int(r.players), int(r.max), "en partie" if r.phase != "lobby" else "salon", r.code], func(): _find(String(r.code)), 880, 17)
		b.disabled = r.phase != "lobby"
		rooms_box.add_child(b)


func _on_room(info: Dictionary) -> void:
	Net.leave()
	if not info.get("ok", false):
		status_l.text = String(info.get("msg", "Erreur."))
		return
	Net.room_code = String(info.code)
	_join_room(_master_addr()[0], int(info.port))


# ------------------------------------------------------------------ LAN
func _join_room(host: String, port: int) -> void:
	status_l.text = "Connexion au salon %s…" % Net.room_code
	if Net.join(host, port) != OK:
		status_l.text = "Connexion impossible."
		return
	var on_ok := func():
		ChoicePanel.open_count = 0
		Game.goto_scene("res://src/gameplay/game_scene.tscn", {"mode": "online"})
	var on_fail := func(): status_l.text = "L'hôte ne répond pas (même Wi-Fi ? bonne IP ?)."
	Net.connected.connect(on_ok, CONNECT_ONE_SHOT)
	Net.connection_failed.connect(on_fail, CONNECT_ONE_SHOT)


func _join_direct(addr: String) -> void:
	var parts := addr.strip_edges().split(":")
	if parts.is_empty() or parts[0] == "":
		status_l.text = "Entre l'IP affichée chez l'hôte (ex : 192.168.1.20)."
		return
	Net.room_code = "LAN"
	_join_room(parts[0], int(parts[1]) if parts.size() > 1 else 24681)


func _host_lan() -> void:
	var err := Net.host(24681, Net.MAX_CLIENTS, true)
	if err != OK:
		status_l.text = "Impossible d'ouvrir le port 24681 (déjà utilisé ?)."
		return
	Net.room_code = "LAN"
	ChoicePanel.open_count = 0
	Game.goto_scene("res://src/gameplay/game_scene.tscn", {"mode": "online"})


func close() -> void:
	if lister:
		lister.close()
	if Net.is_active():
		Net.leave()
	_waiting = ""
	ChoicePanel.open_count = maxi(0, ChoicePanel.open_count - 1)
	queue_free()
