extends Node
## Headless test client ("--bot"). Joins a room, picks a role, gets ready, then plays:
## employees walk to colleagues' PCs and try pranks; the director walks to employees,
## interrogates them and sanctions. Everything goes through the normal network path.

var ns: Node
var role := "employee"
var bname := "Bot"
var _did_role := false
var _t := 0.0
var _path: PackedVector3Array = []
var _pi := 0
var _target := ""
var _cool := 0.0
var _results := 0
var started := false


func setup(net_sync: Node) -> void:
	ns = net_sync
	role = Net.arg("botrole", "employee")
	bname = Net.arg("botname", "Bot")
	print("[bot:%s] ready as %s" % [bname, role])


func on_lobby(st: Dictionary) -> void:
	if not _did_role:
		_did_role = true
		ns.rpc_id(1, "c2s_set_role", "director" if role == "director" else "employee")
		ns.rpc_id(1, "c2s_ready", true)
	var n: int = st.players.size()
	var all_ready := true
	for p in st.players:
		if not p.ready:
			all_ready = false
	var me := multiplayer.get_unique_id()
	for p in st.players:
		if int(p.id) == me and p.owner and n >= int(Net.arg("botwait", "3")) and all_ready and st.phase == "lobby":
			ns.rpc_id(1, "c2s_start")


func on_lobby_again() -> void:
	_did_role = false
	started = false
	_t = 0.0


func on_start() -> void:
	started = true
	await get_tree().process_frame
	await get_tree().process_frame
	if ns.gs.pc:
		ns.gs.pc.set_physics_process(false)
	print("[bot:%s] game started, my char = %s" % [bname, ns.my_char])


func on_notify(text: String) -> void:
	print("[bot:%s] notif: %s" % [bname, text])


func on_interrogated(info: Dictionary) -> void:
	print("[bot:%s] interrogated about: %s" % [bname, info.get("act_text", "")])
	await get_tree().create_timer(1.0).timeout
	ns.send_request("boss", "answer_deny", {})


func on_verdict(p: Dictionary) -> void:
	print("[bot:%s] verdict for %s (answer: %s, strength %.2f) -> sanction" % [bname, p.name, p.answer, float(p.strength)])
	ns.send_request(String(p.who), "verdict", {"sanction": true})


func on_results(res: Dictionary) -> void:
	_results += 1
	print("[bot:%s] RESULTS #%d winner=%s rows=%s" % [bname, _results, res.winner, res.rows])
	if _results == 1 and Net.arg("rematch") != "":
		ns.rpc_id(1, "c2s_rematch")
	elif _results >= 1:
		await get_tree().create_timer(1.0).timeout
		get_tree().quit()


func _process(delta: float) -> void:
	var s: Session = ns.session
	if not started or s == null or s.player == null or ns.phase != "play":
		return
	_t += delta
	_cool -= delta
	var me := s.player
	_follow_path(me)
	if _cool > 0.0:
		return
	_cool = 1.0
	if role == "director":
		_director_logic(s, me)
	else:
		_employee_logic(s, me)


func _go(s: Session, me: Character, to: Vector3) -> void:
	var map := s.world.get_world_3d().navigation_map
	_path = NavigationServer3D.map_get_path(map, me.global_position, s.world.nav_closest(to), true)
	_pi = 0


func _follow_path(me: Character) -> void:
	if _pi >= _path.size():
		me.move_dir = Vector3.ZERO
		return
	var d := _path[_pi] - me.global_position
	d.y = 0
	if d.length() < 0.4:
		_pi += 1
		return
	me.move_dir = d.normalized()


func _employee_logic(s: Session, me: Character) -> void:
	if _target == "":
		for d in s.world.desks:
			if d.owner != "" and d.owner != me.id and d.owner != "boss" and randf() < 0.3:
				_target = d.pc_id
				_go(s, me, d.seat + d.facing * -0.4)
				print("[bot:%s] heading to %s" % [bname, d.pc_id])
				break
		return
	var pc: Node = s.world.ent(_target)
	if pc and me.global_position.distance_to(pc.interact_point()) < 2.3:
		print("[bot:%s] trying change_wallpaper on %s" % [bname, _target])
		ns.send_request(_target, "change_wallpaper", {})
		_target = ""
		_cool = 8.0
	elif _pi >= _path.size():
		_target = ""


func _director_logic(s: Session, me: Character) -> void:
	var best: Character = null
	var bd := INF
	for id in s.characters:
		var c: Character = s.characters[id]
		if c == me or not id.begins_with("p"):
			continue
		var d := c.global_position.distance_to(me.global_position)
		if d < bd:
			bd = d
			best = c
	if best == null:
		return
	if bd < 2.6 and _t > 12.0:
		print("[bot:%s] interrogating %s" % [bname, best.id])
		ns.send_request(best.id, "interrogate", {"act_id": -1})
		_cool = 20.0
	else:
		_go(s, me, best.global_position)
