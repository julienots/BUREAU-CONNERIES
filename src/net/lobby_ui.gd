class_name LobbyUI
extends Control
## Online hub from the main menu: public room list, create (public/private), join by
## invite code (via the master server), or LAN play (host / join an IP directly).

var status_l: Label
var rooms_box: VBoxContainer
var addr_edit: LineEdit
var link: MasterLink
var _pending := ""        # what we asked the master for
var _create_name := ""
var _public := true
var _join_code := ""


static func open(parent: Control, code := "") -> LobbyUI:
	var ui := LobbyUI.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(ui)
	ui._build(code)
	return ui


func _build(code: String) -> void:
	ChoicePanel.open_count += 1
	theme = UiKit.theme()
	var p := UiKit.panel(Vector2(860, 600))
	UiKit.center_modal(self, p)
	var v := UiKit.vbox(10)
	p.add_child(v)
	v.add_child(UiKit.label("Jouer en ligne", 36, UiKit.YELLOW, true))
	var h := UiKit.hbox(8)
	v.add_child(h)
	h.add_child(UiKit.label("Serveur", 17))
	addr_edit = LineEdit.new()
	addr_edit.text = "%s:%d" % [Settings.get_v("server_address"), int(Settings.get_v("server_port"))]
	addr_edit.custom_minimum_size = Vector2(320, 44)
	h.add_child(addr_edit)
	h.add_child(UiKit.button("Actualiser", _refresh, 180, 18))
	status_l = UiKit.label("", 16, UiKit.MUTED)
	status_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_l.custom_minimum_size = Vector2(820, 0)
	v.add_child(status_l)
	v.add_child(UiKit.label("Salons publics", 20, UiKit.TEXT, true))
	rooms_box = UiKit.vbox(6)
	v.add_child(UiKit.scroll(rooms_box, Vector2(820, 200)))
	var c := UiKit.hbox(8)
	v.add_child(c)
	var name_edit := LineEdit.new()
	name_edit.placeholder_text = "Nom du salon"
	name_edit.text = "Bureau de %s" % Settings.get_v("player_name")
	name_edit.custom_minimum_size = Vector2(300, 44)
	c.add_child(name_edit)
	var pub := CheckBox.new()
	pub.text = "Public"
	pub.button_pressed = true
	c.add_child(pub)
	c.add_child(UiKit.button("Créer un salon", func(): _create(name_edit.text, pub.button_pressed), 240, 18))
	var j := UiKit.hbox(8)
	v.add_child(j)
	var code_edit := LineEdit.new()
	code_edit.placeholder_text = "CODE"
	code_edit.text = code
	code_edit.max_length = 8
	code_edit.custom_minimum_size = Vector2(160, 44)
	j.add_child(code_edit)
	j.add_child(UiKit.button("Rejoindre par code", func(): _find(code_edit.text), 260, 18))
	var lan := UiKit.hbox(8)
	v.add_child(lan)
	lan.add_child(UiKit.button("Héberger en LAN", _host_lan, 260, 18))
	var ip_edit := LineEdit.new()
	ip_edit.placeholder_text = "IP:port (LAN)"
	ip_edit.custom_minimum_size = Vector2(240, 44)
	lan.add_child(ip_edit)
	lan.add_child(UiKit.button("Rejoindre l'IP", func(): _join_direct(ip_edit.text), 220, 18))
	v.add_child(UiKit.button("Retour", close, 200))
	link = MasterLink.ensure()
	link.rooms_received.connect(_on_rooms)
	link.room_resolved.connect(_on_room)
	if code != "":
		_find(code)
	else:
		_refresh()


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
		status_l.text = "Serveur injoignable. Lance un serveur (voir README : --master) ou joue en LAN."
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
	status_l.text = "%d salon(s) public(s)." % list.size()
	if list.is_empty():
		rooms_box.add_child(UiKit.label("Aucun salon public. Crée le tien !", 16, UiKit.MUTED))
	for r in list:
		var b := UiKit.button("%s  —  %d/%d joueurs  —  %s   [%s]" % [r.name, int(r.players), int(r.max), "en partie" if r.phase != "lobby" else "salon", r.code], func(): _find(String(r.code)), 800, 17)
		b.disabled = r.phase != "lobby"
		rooms_box.add_child(b)


func _on_room(info: Dictionary) -> void:
	Net.leave()
	if not info.get("ok", false):
		status_l.text = String(info.get("msg", "Erreur."))
		return
	Net.room_code = String(info.code)
	_join_room(_master_addr()[0], int(info.port))


func _join_room(host: String, port: int) -> void:
	status_l.text = "Connexion au salon %s…" % Net.room_code
	if Net.join(host, port) != OK:
		status_l.text = "Connexion impossible."
		return
	var on_ok := func():
		ChoicePanel.open_count = 0
		Game.goto_scene("res://src/gameplay/game_scene.tscn", {"mode": "online"})
	var on_fail := func(): status_l.text = "Le salon ne répond pas."
	Net.connected.connect(on_ok, CONNECT_ONE_SHOT)
	Net.connection_failed.connect(on_fail, CONNECT_ONE_SHOT)


func _join_direct(addr: String) -> void:
	var parts := addr.strip_edges().split(":")
	if parts.is_empty() or parts[0] == "":
		status_l.text = "Entre une IP (ex : 192.168.1.20:24681)."
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
	if Net.is_active():
		Net.leave()
	ChoicePanel.open_count = maxi(0, ChoicePanel.open_count - 1)
	queue_free()
