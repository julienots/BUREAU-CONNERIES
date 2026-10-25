class_name MasterLink
extends Node
## Room directory. Lives at /root/MasterLink both in the master server process and in
## clients browsing rooms (same node path so RPCs match).
## Master: lists public rooms, creates rooms (spawns a dedicated room server process on
## a free port), resolves invite codes. Room servers report their status in
## user://rooms/<code>.json (same machine).

signal rooms_received(rooms: Array)
signal room_resolved(info: Dictionary)

const FIRST_ROOM_PORT := 24681
const MAX_ROOMS := 16

var is_master := false
var rooms: Dictionary = {}       # code -> {name, public, max, port, pid}


static func ensure() -> MasterLink:
	var tree := Engine.get_main_loop() as SceneTree
	var existing := tree.root.get_node_or_null("MasterLink")
	if existing:
		return existing
	var m := MasterLink.new()
	m.name = "MasterLink"
	tree.root.add_child(m)
	return m


func _process(_d: float) -> void:
	if not is_master:
		return
	for code in rooms.keys():
		if not OS.is_process_running(int(rooms[code].pid)):
			print("[master] room %s closed" % code)
			rooms.erase(code)
			DirAccess.remove_absolute("user://rooms/%s.json" % code)


func _status(code: String) -> Dictionary:
	var p := "user://rooms/%s.json" % code
	if not FileAccess.file_exists(p):
		return {}
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
	return d if typeof(d) == TYPE_DICTIONARY else {}


# ------------------------------------------------------------------ client -> master
@rpc("any_peer", "reliable")
func c2m_list() -> void:
	if not is_master:
		return
	var out: Array = []
	for code in rooms:
		var r: Dictionary = rooms[code]
		if not r.public:
			continue
		var st := _status(code)
		out.append({"code": code, "name": r.name, "players": int(st.get("players", 0)), "max": r.max, "phase": st.get("phase", "lobby")})
	m2c_rooms.rpc_id(multiplayer.get_remote_sender_id(), out)


@rpc("any_peer", "reliable")
func c2m_create(room_name: String, public: bool, max_players: int) -> void:
	if not is_master:
		return
	var sender := multiplayer.get_remote_sender_id()
	if rooms.size() >= MAX_ROOMS:
		m2c_room.rpc_id(sender, {"ok": false, "msg": "Serveur plein, réessaie plus tard."})
		return
	var code := Net.make_code()
	while rooms.has(code):
		code = Net.make_code()
	var port := FIRST_ROOM_PORT
	var used := rooms.values().map(func(r): return int(r.port))
	while port in used:
		port += 1
	var args := PackedStringArray()
	if FileAccess.file_exists("res://project.godot"):
		args.append_array(["--path", ProjectSettings.globalize_path("res://")])
	args.append_array(["--headless", "--", "--server", "--port=%d" % port, "--code=%s" % code,
		"--name=%s" % room_name.substr(0, 24).replace(" ", "_"), "--public=%d" % int(public), "--max=%d" % clampi(max_players, 2, 9)])
	var pid := OS.create_process(OS.get_executable_path(), args)
	if pid <= 0:
		m2c_room.rpc_id(sender, {"ok": false, "msg": "Impossible de créer le salon."})
		return
	rooms[code] = {"name": room_name, "public": public, "max": max_players, "port": port, "pid": pid}
	print("[master] room %s on port %d (pid %d)" % [code, port, pid])
	# give the room process a moment to open its port
	await get_tree().create_timer(2.5).timeout
	m2c_room.rpc_id(sender, {"ok": true, "code": code, "port": port})


@rpc("any_peer", "reliable")
func c2m_find(code: String) -> void:
	if not is_master:
		return
	var sender := multiplayer.get_remote_sender_id()
	code = code.strip_edges().to_upper()
	if rooms.has(code):
		m2c_room.rpc_id(sender, {"ok": true, "code": code, "port": int(rooms[code].port)})
	else:
		m2c_room.rpc_id(sender, {"ok": false, "msg": "Aucun salon avec ce code."})


# ------------------------------------------------------------------ master -> client
@rpc("authority", "reliable")
func m2c_rooms(list: Array) -> void:
	rooms_received.emit(list)


@rpc("authority", "reliable")
func m2c_room(info: Dictionary) -> void:
	room_resolved.emit(info)
