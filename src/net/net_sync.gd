class_name NetSync
extends Node
## Multiplayer glue living at /root/Game/NetSync on the server and on every client.
## Server: lobby (roles, ready, settings), authoritative Session, snapshots (15 Hz),
## private per-player state (money, inventory, missions — and the director's notebook,
## sent ONLY to the director), validated requests, verdicts, scoring, reconnection.
## Client: sends inputs/requests, interpolates snapshots, shows lobby/briefing/results.

const SNAP_HZ := 15.0
const INPUT_HZ := 20.0
const PREP_TIME := 10.0

var gs: Node                         # game scene
var server := false
var phase := "lobby"                 # lobby | prep | play | results
var players: Dictionary = {}         # peer id -> {name, look, role, ready, char_id, token, connected, cosmetics}
var owner_peer := 0                  # room owner (can change settings / start)
var room := {"name": "Salon", "max": 9, "day_minutes": 8.0, "public": true, "code": ""}
var session: Session
var my_char := ""
var private: Dictionary = {}         # client: my private state
var notebook: Array[String] = []     # server: director notes (sent to the director only)
var pending_verdicts: Dictionary = {}
var scores: Dictionary = {"boss_correct": 0, "boss_wrong": 0}
var rematch: Dictionary = {}
var _snap_t := 0.0
var _input_t := 0.0
var _priv_t := 0.0
var _prep_t := 0.0
var _last_props: Dictionary = {}
var _empty_t := 0.0
var lobby_ui: Control
var is_bot := false
var bot: Node
var sus: Suspicion                   # client side placeholder (never filled for employees)


func begin(game_scene: Node) -> void:
	gs = game_scene
	server = Net.is_server()
	is_bot = Net.arg("bot") != ""
	room.code = Net.arg("code", Net.room_code if Net.room_code != "" else Net.make_code())
	room.name = Net.arg("name", "Salon " + room.code)
	room.public = Net.arg("public", "1") == "1"
	room.max = int(Net.arg("max", "9"))
	room.day_minutes = float(Net.arg("day", "8"))
	Net.peer_left.connect(_on_peer_left)
	Net.disconnected.connect(func():
		if not server:
			gs.ui_root.add_child(UiKit.label("Connexion au serveur perdue.", 28, UiKit.BAD, true))
			get_tree().create_timer(2.5).timeout.connect(Game.goto_menu))
	if server:
		print("[server] room %s '%s' ready (public=%s)" % [room.code, room.name, room.public])
		if Net.role == "host":
			players[1] = _player_entry(String(Settings.get_v("player_name")), SaveGame.data.appearance, Net.token, SaveGame.data.equipped_cosmetics)
			owner_peer = 1
			_show_lobby()
	else:
		c2s_hello.rpc_id(1, String(Net.arg("botname", Settings.get_v("player_name"))), SaveGame.data.appearance, Net.token, SaveGame.data.equipped_cosmetics)
		_show_lobby()
	if is_bot:
		bot = load("res://src/net/net_bot.gd").new()
		add_child(bot)
		bot.call("setup", self)
	_write_status()


func _player_entry(n: String, look: Dictionary, token: String, cos: Array) -> Dictionary:
	return {"name": n.substr(0, 16), "look": look, "role": "employee", "ready": false, "char_id": "", "token": token, "connected": true, "cosmetics": cos}


# ------------------------------------------------------------------ lobby (server)
@rpc("any_peer", "reliable")
func c2s_hello(pname: String, look: Dictionary, token: String, cosmetics: Array) -> void:
	if not server:
		return
	var id := multiplayer.get_remote_sender_id()
	# reconnection: same token -> take back the old slot
	for pid in players.keys():
		var p: Dictionary = players[pid]
		if p.token == token and not p.connected:
			players.erase(pid)
			p.connected = true
			players[id] = p
			print("[server] %s reconnected" % p.name)
			if phase in ["prep", "play"] and p.char_id != "":
				_send_start(id)
				if p.char_id == "boss" and session.boss_brain:
					session.boss_brain.observer = true
				session.notify_all("%s est de retour !" % p.name, "event")
			_broadcast_lobby()
			return
	if players.size() >= int(room.max) or phase != "lobby":
		s2c_refused.rpc_id(id, "Salon plein ou partie déjà commencée.")
		return
	players[id] = _player_entry(pname, _safe_look(look), token, cosmetics.filter(func(c): return c in ["chapeau", "lunettes", "cravate_or"]))
	if owner_peer == 0 or not players.has(owner_peer):
		owner_peer = id
	print("[server] %s joined (%d players)" % [pname, players.size()])
	_broadcast_lobby()


func _safe_look(look: Dictionary) -> Dictionary:
	var base: Dictionary = Data.player_default.look.duplicate()
	for k in base:
		if look.has(k) and typeof(look[k]) == typeof(base[k]):
			base[k] = look[k]
	return base


@rpc("any_peer", "reliable")
func c2s_set_role(r: String) -> void:
	var id := _sender()
	if not server or not players.has(id) or phase != "lobby" or not r in ["employee", "director"]:
		return
	if r == "director":
		for pid in players:
			if players[pid].role == "director" and pid != id:
				_notify_peer(id, "%s est déjà le directeur." % players[pid].name, "warn")
				return
	players[id].role = r
	_broadcast_lobby()


@rpc("any_peer", "reliable")
func c2s_ready(on: bool) -> void:
	var id := _sender()
	if server and players.has(id) and phase == "lobby":
		players[id].ready = on
		_broadcast_lobby()


@rpc("any_peer", "reliable")
func c2s_settings(day_minutes: float, max_players: int) -> void:
	var id := _sender()
	if server and id == owner_peer and phase == "lobby":
		room.day_minutes = clampf(day_minutes, 3.0, 20.0)
		room.max = clampi(max_players, 2, 9)
		_broadcast_lobby()


@rpc("any_peer", "reliable")
func c2s_start() -> void:
	var id := _sender()
	if not server or phase != "lobby" or (id != owner_peer and not is_bot_server()):
		return
	var why := can_start()
	if why != "":
		if id == 1 and Net.role == "host":
			_local_notify(why, "warn")
		else:
			s2c_notify.rpc_id(id, why, "warn")
		return
	_start_game()


func is_bot_server() -> bool:
	return Net.arg("autostart") != ""


func can_start() -> String:
	if players.size() < 2:
		return "Il faut au moins 2 joueurs."
	for pid in players:
		if not players[pid].ready and pid != owner_peer:
			return "Tout le monde n'est pas prêt."
	var employees := 0
	for pid in players:
		if players[pid].role == "employee":
			employees += 1
	if employees == 0:
		return "Il faut au moins un employé."
	return ""


func _sender() -> int:
	var id := multiplayer.get_remote_sender_id()
	return 1 if id == 0 else id


func _broadcast_lobby() -> void:
	var st := lobby_state()
	for pid in players:
		if pid == 1 and Net.role == "host":
			_apply_lobby(st)
		elif players[pid].connected:
			s2c_lobby.rpc_id(pid, st)
	_write_status()


func lobby_state() -> Dictionary:
	var list: Array = []
	for pid in players:
		var p: Dictionary = players[pid]
		list.append({"id": pid, "name": p.name, "role": p.role, "ready": p.ready, "owner": pid == owner_peer, "connected": p.connected})
	return {"players": list, "room": room, "phase": phase}


@rpc("authority", "reliable")
func s2c_lobby(st: Dictionary) -> void:
	_apply_lobby(st)


@rpc("authority", "reliable")
func s2c_refused(msg: String) -> void:
	_local_notify(msg, "danger")
	get_tree().create_timer(2.5).timeout.connect(Game.goto_menu)


func _apply_lobby(st: Dictionary) -> void:
	room = st.room
	if lobby_ui and is_instance_valid(lobby_ui):
		lobby_ui.call("refresh", st, multiplayer.get_unique_id() if Net.role != "host" else 1)
	if bot:
		bot.call("on_lobby", st)


func _show_lobby() -> void:
	var ui: GDScript = load("res://src/net/lobby_room_ui.gd")
	lobby_ui = ui.new()
	gs.ui_root.add_child(lobby_ui)
	lobby_ui.call("setup", self)


## Status file read by the master server to list rooms (same machine).
func _write_status() -> void:
	if not server or Net.role == "host":
		return
	DirAccess.make_dir_recursive_absolute("user://rooms")
	var f := FileAccess.open("user://rooms/%s.json" % room.code, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"code": room.code, "name": room.name, "public": room.public, "players": players.size(), "max": room.max, "phase": phase, "time": Time.get_unix_time_from_system()}))


# ------------------------------------------------------------------ game start
func _humans() -> Dictionary:
	var humans := {}
	var desk := 8
	for pid in players:
		var p: Dictionary = players[pid]
		var cid := "boss" if p.role == "director" else "p%d" % pid
		p.char_id = cid
		humans[cid] = {"name": p.name, "look": p.look, "cosmetics": p.cosmetics, "desk": desk, "peer": pid}
		if cid != "boss":
			desk += 1
	return humans


func _start_game() -> void:
	phase = "prep"
	_prep_t = PREP_TIME
	rematch.clear()
	var seed := randi() % 100000
	var humans := _humans()
	room["seed"] = seed
	room["humans"] = humans
	room["npc"] = 5
	print("[server] starting game seed=%d humans=%s" % [seed, humans.keys()])
	_build_session(true)
	for pid in players:
		if pid == 1 and Net.role == "host":
			continue
		_send_start(pid)
	_write_status()


func _build_session(is_srv: bool) -> void:
	if session:
		session.queue_free()
		await get_tree().process_frame
	session = Session.new()
	session.name = "Session"
	session.net = self
	gs.session = session
	gs.add_child(session)
	session.setup("server" if is_srv else "client", {"seed": int(room.seed), "day_minutes": float(room.day_minutes), "day": 1, "profile": room.get("profile", "methodical")})
	session.spawn_cast(room.humans, int(room.npc))
	session.events.enabled = is_srv
	if is_srv:
		var rng := RandomNumberGenerator.new()
		rng.seed = int(room.seed)
		var side_ids: Array = []
		for sc in Data.side_challenges:
			side_ids.append(sc.id)
		for cid in room.humans:
			if cid == "boss":
				continue
			session._setup_missions(cid, MissionSystem.pick_for_day(2, rng, [], 3), side_ids.slice(0, 2))
			session.economy.setup_peer(cid, 120, 3)
		session.economy.setup_peer("boss", 0, 1)
	# local player (host or client)
	var mine := ""
	for cid in room.humans:
		if int(room.humans[cid].peer) == (1 if Net.role == "host" else multiplayer.get_unique_id()):
			mine = cid
	if not is_srv:
		mine = my_char
	if mine != "" and session.characters.has(mine) and not (is_srv and Net.role != "host"):
		my_char = mine
		var ch: Character = session.characters[mine]
		ch.is_remote = false
		ch.is_player = true
		session.player = ch
		gs._setup_local_player(ch)
		if not is_srv:
			session.missions[mine] = MissionSystem.new()
			session.missions[mine].owner = mine
	session.running = phase == "play"
	if lobby_ui and is_instance_valid(lobby_ui):
		lobby_ui.call("show_briefing", _briefing(mine))


func _send_start(pid: int) -> void:
	var info := {"room": room, "char": players[pid].char_id, "phase": phase}
	s2c_start.rpc_id(pid, info)


@rpc("authority", "reliable")
func s2c_start(info: Dictionary) -> void:
	room = info.room
	my_char = String(info.char)
	phase = String(info.phase)
	print("[client] game starting as %s" % my_char)
	_build_session(false)
	if bot:
		bot.call("on_start")


func _briefing(cid: String) -> String:
	if cid == "boss":
		return "Tu es LE DIRECTEUR. Observe, écoute, enquête. Interroge les suspects (vise-les) puis sanctionne les coupables. " + \
			"Chaque sanction juste te rapporte des points, chaque erreur t'en coûte. Ton carnet (touche N) liste ce que tu as vu et ce qu'on t'a dit."
	return "Tu es EMPLOYÉ. Accomplis tes objectifs secrets sans te faire prendre par le directeur. Coopère avec les autres employés… ou dénonce-les !"


# ------------------------------------------------------------------ main loop
func _process(delta: float) -> void:
	if server:
		_server_tick(delta)
	elif session and session.player and phase in ["prep", "play"]:
		_input_t -= delta
		if _input_t <= 0.0:
			_input_t = 1.0 / INPUT_HZ
			var p := session.player
			c2s_input.rpc_id(1, p.global_position, p.rotation.y, {"r": p.want_run, "c": p.want_crouch})


func _server_tick(delta: float) -> void:
	if players.is_empty() and Net.role != "host":
		_empty_t += delta
		if _empty_t > 120.0:
			print("[server] room empty, shutting down")
			DirAccess.remove_absolute("user://rooms/%s.json" % room.code)
			get_tree().quit()
	else:
		_empty_t = 0.0
	if session == null:
		return
	if phase == "prep":
		_prep_t -= delta
		if _prep_t <= 0.0:
			phase = "play"
			session.running = true
			session.notify_all("La journée commence !", "event")
			_send_phase()
	if phase != "play":
		return
	_snap_t -= delta
	if _snap_t <= 0.0:
		_snap_t = 1.0 / SNAP_HZ
		_send_snapshot()
	_priv_t -= delta
	if _priv_t <= 0.0:
		_priv_t = 0.5
		_send_private()


func _send_phase() -> void:
	for pid in players:
		if pid != 1 and players[pid].connected:
			s2c_phase.rpc_id(pid, phase)
	if lobby_ui and is_instance_valid(lobby_ui) and phase == "play":
		lobby_ui.call("hide_all")


@rpc("authority", "reliable")
func s2c_phase(ph: String) -> void:
	phase = ph
	if session:
		session.running = ph == "play"
	if lobby_ui and is_instance_valid(lobby_ui) and ph == "play":
		lobby_ui.call("hide_all")


func _send_snapshot() -> void:
	var chars: Array = []
	for id in session.characters:
		var c: Character = session.characters[id]
		chars.append([id, c.global_position, c.rotation.y, c.net_state()])
	var props: Array = []
	for p in session.world.props:
		var pr := p as Prop
		if not is_instance_valid(pr):
			continue
		var key := pr.ent_id()
		var vis := pr.visible
		var last: Array = _last_props.get(key, [])
		var t := pr.global_transform
		if last.is_empty() or last[1] != vis or (last[0] as Transform3D).origin.distance_to(t.origin) > 0.01 or not (last[0] as Transform3D).basis.is_equal_approx(t.basis):
			props.append([key, t, vis])
			_last_props[key] = [t, vis]
			if props.size() >= 12:
				break   # stay under the MTU; the rest goes in the next snapshots
	var doors: Array = []
	for d in session.world.doors:
		doors.append(snappedf((d as Door).amount, 0.01))
	var snap := {"m": session.day.minutes, "c": chars, "p": props, "d": doors}
	for pid in players:
		if pid != 1 and players[pid].connected:
			s2c_snap.rpc_id(pid, snap)


@rpc("authority", "unreliable_ordered")
func s2c_snap(snap: Dictionary) -> void:
	if session == null:
		return
	session.day.minutes = float(snap.m)
	for row in snap.c:
		var c: Character = session.characters.get(row[0])
		if c == null:
			continue
		if c == session.player:
			_reconcile_local(c, row[1], row[3])
		else:
			c.apply_net(row[1], row[2], row[3])
	for row in snap.p:
		var p: Prop = session.world.ent(row[0])
		if p:
			p.apply_net(row[1])
			p.visible = row[2]
	var dl: Array = snap.get("d", [])
	for i in mini(dl.size(), session.world.doors.size()):
		(session.world.doors[i] as Door).net_amount = float(dl[i])


## Own character: movement is predicted locally; seat/hold/fall come from the server.
func _reconcile_local(c: Character, pos: Vector3, f: Dictionary) -> void:
	if c.global_position.distance_to(pos) > 2.5:
		c.global_position = pos
	var seat: String = f.get("s", "")
	if seat != "" and c.seated_on == null:
		var chair: Prop = session.world.ent(seat)
		if chair:
			c.seated_on = chair
			c.add_collision_exception_with(chair)
	elif seat == "" and c.seated_on != null:
		c.seated_on = null
		c.global_position = pos
	var held: String = f.get("h", "")
	c.held = session.world.ent(held) as Prop if held != "" else null
	if float(f.get("f", 0.0)) > 0.3 and not c.is_down():
		c.knock_down("net", "", float(f.get("fd", 1.0)))
	c.humanoid.typing = f.has("t")
	c.humanoid.emote = f.get("e", "")


@rpc("any_peer", "unreliable_ordered")
func c2s_input(pos: Vector3, yaw: float, flags: Dictionary) -> void:
	if not server or session == null:
		return
	var id := _sender()
	if not players.has(id):
		return
	var c: Character = session.characters.get(players[id].char_id)
	if c == null or c.seated_on:
		return
	# validation: far-away positions are ignored (the snapshot will correct the client)
	if pos.distance_to(c.global_position) > 4.0 or not is_finite(pos.x) or not is_finite(pos.z):
		return
	c.net_drive = Vector3(pos.x, c.global_position.y, pos.z)
	c.net_drive_yaw = yaw
	c.want_run = bool(flags.get("r", false))
	c.want_crouch = bool(flags.get("c", false))


# ------------------------------------------------------------------ requests
func send_request(target: String, action: String, params: Dictionary) -> void:
	c2s_request.rpc_id(1, target, action, params)


@rpc("any_peer", "reliable")
func c2s_request(target: String, action: String, params: Dictionary) -> void:
	if not server or session == null or phase != "play":
		return
	var id := _sender()
	if not players.has(id):
		return
	var c: Character = session.characters.get(players[id].char_id)
	if c == null:
		return
	if c.is_director() and action in ["interrogate", "verdict", "sanction"]:
		_director_action(id, c, target, action, params)
		return
	if target == "" and action == "take_stock":
		target = c.id
	var r := session.request_action(c, target, action, params)
	if r.get("ok", false) and String(r.get("ui", "")) != "":
		s2c_ui.rpc_id(id, String(r.ui), target)


@rpc("authority", "reliable")
func s2c_ui(kind: String, target: String) -> void:
	if gs and gs.pc:
		gs._on_ui_open(kind, {"target": target})


# ------------------------------------------------------------------ human director
func _director_action(pid: int, boss: Character, target: String, action: String, params: Dictionary) -> void:
	var who: Character = session.characters.get(target)
	if who == null or who.is_director():
		return
	if boss.global_position.distance_to(who.global_position) > 3.5:
		_notify_peer(pid, "Trop loin.", "warn")
		return
	var sus2 := session.boss_brain.sus
	match action:
		"interrogate":
			if session.interrogation.size() > 0:
				_notify_peer(pid, "Un interrogatoire est déjà en cours.", "warn")
				return
			var act_id := int(params.get("act_id", -1))
			if act_id < 0:
				act_id = sus2.best_act(who.id)
			if act_id < 0 and not session.acts.is_empty():
				act_id = int(session.acts[-1].id)
			if act_id < 0:
				_notify_peer(pid, "Aucun incident à reprocher.", "warn")
				return
			session.start_interrogation(boss, who, act_id, sus2.strength(who.id, act_id))
		"verdict":
			var pv: Dictionary = pending_verdicts.get(who.id, {})
			if pv.is_empty():
				return
			pending_verdicts.erase(who.id)
			_apply_verdict(pid, who, pv, bool(params.get("sanction", false)))
		"sanction":
			if sus2.level(who.id) < 3:
				_notify_peer(pid, "Pas assez de preuves : interroge-le d'abord (soupçon ≥ 3).", "warn")
				return
			var act_id2 := sus2.best_act(who.id)
			var act := session.act_by_id(act_id2)
			_apply_verdict(pid, who, {"act_id": act_id2, "guilty": act.get("actor", "") == who.id}, true)


func _apply_verdict(pid: int, who: Character, pv: Dictionary, sanction: bool) -> void:
	var act := session.act_by_id(int(pv.act_id))
	if sanction:
		var res: Dictionary = session._sanction(who, act, bool(pv.guilty))
		if bool(pv.guilty):
			scores.boss_correct += 1
			_notify_peer(pid, "Sanction juste ! (+1)", "good")
		else:
			scores.boss_wrong += 1
			session.economy.add(who.id, 30)
			_notify_peer(pid, "%s était innocent… (-1)" % who.nick, "danger")
		var info := {"who": who.id, "outcome": "sanctioned", "guilty": pv.guilty}
		info.merge(res)
		_send_inter_result(who, info)
		session.notify_all("%s a été sanctionné par le directeur !" % who.nick, "event")
	else:
		_send_inter_result(who, {"who": who.id, "outcome": "cleared"})
	session.boss_brain.on_interrogation_done(who.id, int(pv.act_id), "sanctioned" if sanction else "cleared")


## Called by Session when an interrogation answer arrives and the director is human.
func on_interrogation_resolved(info: Dictionary) -> void:
	pass


## Director UI flows (aim at an employee/coworker, then choose).
func open_boss_ui(kind: String, target: String) -> void:
	if kind == "boss_interrogate":
		var opts: Array = [{"label": "Son incident le plus suspect", "value": -1}]
		for inc in private.get("incidents", []):
			opts.append({"label": "%s — %s" % [inc.who, inc.zone], "value": int(inc.act_id)})
		var cp := ChoicePanel.open(gs.ui_root, "Interroger %s" % session.char_name(target), "À propos de quel incident ?", opts)
		cp.chosen.connect(func(v): _boss_send(target, "interrogate", {"act_id": v}))
	else:
		var cp2 := ChoicePanel.open(gs.ui_root, "Sanctionner %s ?" % session.char_name(target), "Possible seulement avec un soupçon ≥ 3. Une erreur te coûte un point.", [{"label": "Sanctionner", "value": true}])
		cp2.chosen.connect(func(_v): _boss_send(target, "sanction", {}))


func _boss_send(target: String, action: String, params: Dictionary) -> void:
	if server:
		_director_action(1, session.director, target, action, params)
	else:
		send_request(target, action, params)


func human_director() -> bool:
	return session != null and "boss" in session.human_ids


# ------------------------------------------------------------------ Session -> network hooks
func _peer_of(char_id: String) -> int:
	for pid in players:
		if players[pid].char_id == char_id:
			return pid
	return 0


func _notify_peer(pid: int, text: String, kind: String) -> void:
	if pid == 1 and Net.role == "host":
		_local_notify(text, kind)
	elif pid != 0 and players.has(pid) and players[pid].connected:
		s2c_notify.rpc_id(pid, text, kind)


func _local_notify(text: String, kind: String) -> void:
	if session:
		session.notified.emit(text, kind)
	else:
		print("[notify] ", text)


func send_notify(char_id: String, text: String, kind: String) -> void:
	_notify_peer(_peer_of(char_id), text, kind)


func broadcast_notify(text: String, kind: String) -> void:
	for pid in players:
		if pid != 1 and players[pid].connected:
			s2c_notify.rpc_id(pid, text, kind)


@rpc("authority", "reliable")
func s2c_notify(text: String, kind: String) -> void:
	_local_notify(text, kind)
	if bot:
		bot.call("on_notify", text)


func broadcast_say(id: String, text: String, emotion: String) -> void:
	_rpc_all("s2c_say", [id, text, emotion])


@rpc("authority", "reliable")
func s2c_say(id: String, text: String, emotion: String) -> void:
	if session and session.characters.has(id):
		(session.characters[id] as Character).say(text, emotion)


func broadcast_sound(sfx: String, pos: Vector3, loud: float) -> void:
	_rpc_all("s2c_sound", [sfx, pos, loud], false)


@rpc("authority", "unreliable")
func s2c_sound(sfx: String, pos: Vector3, loud: float) -> void:
	SoundFx.play_at(sfx, pos, loud)


func broadcast_device(d: Device) -> void:
	_rpc_all("s2c_device", [d.ent_id(), d.state])


@rpc("authority", "reliable")
func s2c_device(id: String, st: Dictionary) -> void:
	if session:
		var d: Device = session.world.ent(id) as Device
		if d:
			d.state = st
			d.apply_state()


func broadcast_lights(zone: String, on: bool) -> void:
	_rpc_all("s2c_lights", [zone, on])


@rpc("authority", "reliable")
func s2c_lights(zone: String, on: bool) -> void:
	if session:
		session.world.set_zone_lights(zone, on)


func broadcast_fx(kind: String, pos: Vector3) -> void:
	_rpc_all("s2c_fx", [kind, pos])


@rpc("authority", "reliable")
func s2c_fx(kind: String, pos: Vector3) -> void:
	if session and kind == "confetti":
		session._spawn_confetti_fx(pos)


func broadcast_disguise(id: String, on: bool) -> void:
	pass  # carried by the snapshot flags


func broadcast_prop_state(_p: Prop) -> void:
	pass  # visibility/transform are carried by snapshots


func on_prop_spawned(p: Prop) -> void:
	if server:
		_rpc_all("s2c_prop_spawn", [p.ent_id(), p.kind, p.global_transform, p.placed_by])


@rpc("authority", "reliable")
func s2c_prop_spawn(id: String, kind: String, t: Transform3D, placed_by: String) -> void:
	if session == null or session.world.ent(id) != null:
		return
	var p := PropFactory.make(kind)
	p.remote = true
	p.freeze = true
	p.placed_by = placed_by
	session.world.props_root.add_child(p)
	p.global_transform = t
	session.world.register(p, id)


func on_prop_despawned(id: String) -> void:
	if server:
		_rpc_all("s2c_prop_despawn", [id])


@rpc("authority", "reliable")
func s2c_prop_despawn(id: String) -> void:
	if session:
		var p: Node = session.world.ent(id)
		if p:
			session.world.unregister(id)
			p.queue_free()


func send_action_started(char_id: String, label: String, dur: float) -> void:
	var pid := _peer_of(char_id)
	if pid > 1:
		s2c_action.rpc_id(pid, true, label, dur, true, "")


func send_action_ended(char_id: String, ok: bool, msg: String) -> void:
	var pid := _peer_of(char_id)
	if pid > 1:
		s2c_action.rpc_id(pid, false, "", 0.0, ok, msg)


@rpc("authority", "reliable")
func s2c_action(started: bool, label: String, dur: float, ok: bool, msg: String) -> void:
	if session == null:
		return
	if started:
		session.action_started.emit(label, dur)
	else:
		session.action_ended.emit(ok, msg)


func send_interrogation(char_id: String, info: Dictionary) -> void:
	var pid := _peer_of(char_id)
	if pid > 1:
		s2c_interrogation.rpc_id(pid, info)


@rpc("authority", "reliable")
func s2c_interrogation(info: Dictionary) -> void:
	if session:
		session.interrogation = {"who": my_char}
		session.interrogation_started.emit(info)
	if bot:
		bot.call("on_interrogated", info)


func send_interrogation_result(char_id: String, info: Dictionary) -> void:
	var pid := _peer_of(char_id)
	if pid > 1:
		s2c_inter_result.rpc_id(pid, info)


func _send_inter_result(who: Character, info: Dictionary) -> void:
	var pid := _peer_of(who.id)
	if who == session.player:
		session.interrogation_finished.emit(info)
	elif pid > 1:
		s2c_inter_result.rpc_id(pid, info)


@rpc("authority", "reliable")
func s2c_inter_result(info: Dictionary) -> void:
	if session:
		session.interrogation = {}
		session.interrogation_finished.emit(info)


## The answer is in; the human director decides (server keeps the truth for scoring).
func _ask_verdict(info: Dictionary) -> void:
	var who: String = info.get("who", "")
	var act := session.act_by_id(int(info.get("act_id", -1)))
	pending_verdicts[who] = {"act_id": int(info.get("act_id", -1)), "guilty": act.get("actor", "") == who}
	var choice: String = {"deny": "nie tout", "excuse": "invoque une excuse", "confess": "AVOUE", "accuse": "accuse quelqu'un d'autre"}.get(String(info.get("choice", "")), "se tait")
	var payload := {"who": who, "name": session.char_name(who), "answer": choice, "strength": session.boss_brain.sus.strength(who, int(info.get("act_id", -1))),
		"act": session.act_description(act).replace("On vous soupçonne de : ", "")}
	var pid := _peer_of("boss")
	if pid == 1 and Net.role == "host":
		_open_verdict(payload)
	elif pid > 1:
		s2c_verdict.rpc_id(pid, payload)


@rpc("authority", "reliable")
func s2c_verdict(payload: Dictionary) -> void:
	_open_verdict(payload)


func _open_verdict(payload: Dictionary) -> void:
	if bot:
		bot.call("on_verdict", payload)
		return
	var opts := [{"label": "Sanctionner %s" % payload.name, "value": true}, {"label": "Relâcher", "value": false}]
	var desc := "%s %s.\nIncident : %s\nForce de tes preuves : %d %%" % [payload.name, payload.answer, payload.act, int(float(payload.strength) * 100)]
	var cp := ChoicePanel.open(gs.ui_root, "Verdict", desc, opts, "Plus tard")
	cp.chosen.connect(func(v): send_request(String(payload.who), "verdict", {"sanction": v}) if not server else _director_action(1, session.director, String(payload.who), "verdict", {"sanction": v}))


func on_mission_completed(owner: String, id: String, reward: int) -> void:
	pass  # notification already routed through send_notify


func send_director_note(act: Dictionary, info: Dictionary) -> void:
	pass


func send_director_note_text(text: String) -> void:
	notebook.append("[%s] %s" % [session.day.clock_text(), text])
	while notebook.size() > 30:
		notebook.pop_front()
	var pid := _peer_of("boss")
	if pid == 1 and Net.role == "host":
		_local_notify(text, "event")
	elif pid > 1:
		s2c_notify.rpc_id(pid, "Carnet : " + text, "event")


func send_director_testimony(witness: String, accused: String, act_id: int, kind: String) -> void:
	if session.boss_brain:
		session.boss_brain.on_testimony(witness, accused, act_id, kind, session.now())


func suspicion_level(id: String) -> int:
	if server and session and session.boss_brain:
		return session.boss_brain.sus.level(id)
	return int(private.get("level", 0))


func my_witnessed() -> Array:
	return private.get("witnessed", [])


# ------------------------------------------------------------------ private state
func _send_private() -> void:
	for pid in players:
		var p: Dictionary = players[pid]
		if not p.connected or p.char_id == "":
			continue
		var st := _private_for(p.char_id)
		if pid == 1 and Net.role == "host":
			_apply_private(st)
		else:
			s2c_private.rpc_id(pid, st)


func _private_for(cid: String) -> Dictionary:
	var c: Character = session.characters.get(cid)
	var st := {"money": session.economy.money(cid), "items": c.items if c else [], "passive": c.passive if c else [],
		"prod": c.productivity if c else 0.0, "warnings": int(session.warnings.get(cid, 0)), "stock": session.economy.stock.get(cid, {}),
		"tier": int(session.economy.tier.get(cid, 1))}
	var ms: MissionSystem = session.missions.get(cid)
	if ms:
		var prog := {}
		for id in ms.all_ids():
			prog[id] = str(ms.progress.get(id, ""))
		st["missions"] = {"active": ms.active, "side": ms.side, "done": ms.done.keys(), "progress": prog}
	var mem: Memory = session.human_memory.get(cid)
	if mem:
		st["witnessed"] = mem.witnessed
	if cid == "boss":
		# confidential: only the director receives the ledger
		var levels := {}
		for e in session.employees():
			levels[e.id] = {"name": e.nick, "level": session.boss_brain.sus.level(e.id), "score": int(session.boss_brain.sus.score(e.id))}
		st["notebook"] = notebook
		st["levels"] = levels
		st["incidents"] = session.boss_brain.mem.witnessed.map(func(w): return {"act_id": w.act_id, "who": session.char_name(w.actor) if w.actor != "" else w.desc, "zone": session.world.zone_name(w.zone)})
		st["score"] = scores
	return st


@rpc("authority", "reliable")
func s2c_private(st: Dictionary) -> void:
	_apply_private(st)


func _apply_private(st: Dictionary) -> void:
	private = st
	if session == null or session.player == null:
		return
	var c := session.player
	var cid := c.id
	session.economy.wallets[cid] = int(st.money)
	session.economy.stock[cid] = st.get("stock", {})
	session.economy.tier[cid] = int(st.get("tier", 1))
	if not server:
		c.items.assign(st.items)
		c.passive.assign(st.passive)
		c.productivity = float(st.prod)
		session.warnings[cid] = int(st.warnings)
		var ms: MissionSystem = session.missions.get(cid)
		if ms and st.has("missions"):
			ms.active.assign(st.missions.active)
			ms.side.assign(st.missions.side)
			ms.done.clear()
			for id in st.missions.done:
				ms.done[id] = {}
			ms.progress = st.missions.progress
	session.hud_changed.emit()


# ------------------------------------------------------------------ end of day
func on_day_over() -> void:
	phase = "results"
	var res := results()
	print("[server] day over: ", res)
	for pid in players:
		if pid == 1 and Net.role == "host":
			_show_results(res)
		elif players[pid].connected:
			s2c_results.rpc_id(pid, res)
	_write_status()


func results() -> Dictionary:
	var rows: Array = []
	var total_missions := 0
	var employees := 0
	for pid in players:
		var cid: String = players[pid].char_id
		if cid == "" or cid == "boss":
			continue
		employees += 1
		var ms: MissionSystem = session.missions.get(cid)
		var done := ms.done.size() if ms else 0
		total_missions += done
		rows.append({"name": players[pid].name, "role": "Employé", "missions": done, "money": session.economy.money(cid), "warnings": int(session.warnings.get(cid, 0))})
	var boss_name := "IA"
	for pid in players:
		if players[pid].char_id == "boss":
			boss_name = players[pid].name
	rows.append({"name": boss_name, "role": "Directeur", "correct": scores.boss_correct, "wrong": scores.boss_wrong})
	var boss_wins: bool = int(scores.boss_correct) - int(scores.boss_wrong) >= maxi(1, employees) or total_missions < employees
	return {"rows": rows, "winner": "Directeur" if boss_wins else "Employés", "missions": total_missions}


@rpc("authority", "reliable")
func s2c_results(res: Dictionary) -> void:
	phase = "results"
	_show_results(res)


func _show_results(res: Dictionary) -> void:
	if bot:
		bot.call("on_results", res)
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var lines := ""
	for r in res.rows:
		if r.role == "Directeur":
			lines += "%s (Directeur) — sanctions justes : %d, erreurs : %d\n" % [r.name, int(r.correct), int(r.wrong)]
		else:
			lines += "%s — missions : %d, argent : %d €, avertissements : %d\n" % [r.name, int(r.missions), int(r.money), int(r.warnings)]
	var cp := ChoicePanel.open(gs.ui_root, "Victoire : %s !" % res.winner, lines, [{"label": "Revanche !", "value": "rematch"}, {"label": "Quitter", "value": "quit"}], "Fermer")
	cp.chosen.connect(func(v):
		if v == "rematch":
			if server:
				_vote_rematch(1)
			else:
				c2s_rematch.rpc_id(1)
		else:
			Game.goto_menu())


@rpc("any_peer", "reliable")
func c2s_rematch() -> void:
	if server:
		_vote_rematch(_sender())


func _vote_rematch(pid: int) -> void:
	if phase != "results":
		return
	rematch[pid] = true
	var connected := players.keys().filter(func(p): return players[p].connected)
	session.notify_all("Revanche : %d/%d" % [rematch.size(), connected.size()], "event")
	if rematch.size() >= connected.size():
		print("[server] rematch!")
		for p in players:
			players[p].ready = false
		phase = "lobby"
		if session:
			session.queue_free()
			session = null
		for pid2 in players:
			if pid2 != 1 and players[pid2].connected:
				s2c_back_to_lobby.rpc_id(pid2)
		if Net.role == "host":
			_back_to_lobby_local()
		_broadcast_lobby()


@rpc("authority", "reliable")
func s2c_back_to_lobby() -> void:
	_back_to_lobby_local()


func _back_to_lobby_local() -> void:
	phase = "lobby"
	Game.start_args = {"mode": "online"}
	if bot:
		bot.call("on_lobby_again")
	var scene_tree := get_tree()
	for c in gs.get_children():
		if c != self and c != gs.ui_layer:
			c.queue_free()
	gs.pc = null
	gs.session = null
	session = null
	ChoicePanel.open_count = 0
	for c in gs.ui_root.get_children():
		c.queue_free()
	_show_lobby()


# ------------------------------------------------------------------ disconnection
func _on_peer_left(id: int) -> void:
	if not server or not players.has(id):
		return
	var p: Dictionary = players[id]
	print("[server] %s left" % p.name)
	if phase == "lobby":
		players.erase(id)
		if owner_peer == id:
			owner_peer = players.keys()[0] if not players.is_empty() else 0
	else:
		p.connected = false
		if session and p.char_id != "":
			var c: Character = session.characters.get(p.char_id)
			if c:
				c.net_drive = Vector3.INF
				c.stop()
			if p.char_id == "boss" and session.boss_brain:
				session.boss_brain.observer = false   # the AI takes over the director
				session.notify_all("Le directeur s'est déconnecté : l'IA prend le relais.", "event")
			else:
				session.notify_all("%s s'est déconnecté (60 s pour revenir)." % p.name, "warn")
	_broadcast_lobby()


func _rpc_all(method: String, args: Array, reliable := true) -> void:
	for pid in players:
		if pid != 1 and players[pid].connected:
			callv("rpc_id", [pid, method] + args)
