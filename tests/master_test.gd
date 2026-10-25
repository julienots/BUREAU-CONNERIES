extends Node
## Connects to a running master (--master --port=24800), creates a public room, lists
## rooms, resolves the code, then joins the spawned room server. Exit code = failures.
var fails := 0
var link: MasterLink

func _ready() -> void:
	await get_tree().process_frame
	link = MasterLink.ensure()
	Net.join("127.0.0.1", 24800)
	await Net.connected
	link.c2m_create.rpc_id(1, "Salon test", true, 4)
	var info: Dictionary = await link.room_resolved
	print("created: ", info)
	if not info.get("ok", false): fails += 1
	link.c2m_list.rpc_id(1)
	var rooms: Array = await link.rooms_received
	print("rooms: ", rooms)
	if rooms.is_empty(): fails += 1
	link.c2m_find.rpc_id(1, String(info.get("code", "")))
	var found: Dictionary = await link.room_resolved
	print("found: ", found)
	if int(found.get("port", 0)) != int(info.get("port", -1)): fails += 1
	link.c2m_find.rpc_id(1, "ZZZZ")
	var nf: Dictionary = await link.room_resolved
	print("unknown code: ", nf)
	if nf.get("ok", true): fails += 1
	Net.leave()
	Net.join("127.0.0.1", int(info.port))
	var ok := false
	Net.connected.connect(func(): ok = true)
	await get_tree().create_timer(3.0).timeout
	print("joined spawned room server: ", Net.is_active() and multiplayer.get_unique_id() != 1)
	if not (Net.is_active() and multiplayer.get_unique_id() != 1): fails += 1
	print("MASTER RESULT fails=%d" % fails)
	get_tree().quit(fails)
