extends Node
## Headless entry point (dispatched by the boot scene):
##   --master [--port=24680]                    room directory (spawns room servers)
##   --server --port=24681 [--code=ABCD] [--name=X] [--public=1] [--max=9] [--autostart=1]
##   --bot --connect=127.0.0.1:24681 [--botrole=director|employee] [--botname=Bob]
##   --server --relay=wss://… --code=ABCD    /   --bot --relay=wss://… --code=ABCD   (Internet relay)


func _ready() -> void:
	if Net.arg("master") != "":
		var port := int(Net.arg("port", str(Net.DEFAULT_PORT)))
		if Net.host(port, 64) != OK:
			push_error("[master] cannot open port %d" % port)
			get_tree().quit(1)
			return
		var link := MasterLink.ensure()
		link.is_master = true
		print("[master] listening on %d" % port)
		return
	if Net.arg("server") != "" and Net.arg("relay") != "":
		# dedicated room on the Internet relay (no open port needed)
		var code := Net.arg("code", Net.make_code())
		if Net.host_relay(code, false) != OK:
			push_error("[server] relay: " + Net.relay_status)
			get_tree().quit(1)
			return
		# wait for the relay before opening the room
		var t := 0.0
		while not Net.relay_ready():
			await get_tree().process_frame
			t += get_process_delta_time()
			if t > 30.0 or Net.peer == null or Net.peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
				push_error("[server] relay unreachable: " + Net.relay_status)
				get_tree().quit(1)
				return
		print("[server] relay room code=%s via %s" % [code, Net.arg("relay")])
		Game.goto_scene("res://src/gameplay/game_scene.tscn", {"mode": "online"})
		return
	if Net.arg("server") != "":
		var port2 := int(Net.arg("port", "24681"))
		if Net.host(port2, Net.MAX_CLIENTS) != OK:
			push_error("[server] cannot open port %d" % port2)
			get_tree().quit(1)
			return
		Net.room_code = Net.arg("code", Net.make_code())
		print("[server] listening on %d code=%s" % [port2, Net.room_code])
		Game.goto_scene("res://src/gameplay/game_scene.tscn", {"mode": "online"})
		return
	if Net.arg("bot") != "":
		if Net.arg("relay") != "":
			Net.join_relay(Net.arg("code", "TEST"))
		else:
			var addr := Net.arg("connect", "127.0.0.1:24681").split(":")
			Net.join(addr[0], int(addr[1]) if addr.size() > 1 else 24681)
		var on_ok := func():
			print("[bot] connected")
			Game.goto_scene("res://src/gameplay/game_scene.tscn", {"mode": "online"})
		Net.connected.connect(on_ok, CONNECT_ONE_SHOT)
		Net.connection_failed.connect(func():
			print("[bot] connection failed")
			get_tree().quit(2))
		return
	# a headless run without a role: nothing to do
	print("Office Mayhem headless: use --master, --server or --bot")
	get_tree().quit()
