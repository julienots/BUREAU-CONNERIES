extends Node
## Two real game processes go online through the Internet relay via the actual menu:
##   --as=host : "CRÉER UNE PARTIE", then waits until a second player is in its lobby
##   --as=join : lists public games (must see the host's), joins with the code
## Run with RELAY set (see tools/relay_ui_test.sh). Exit code 0 = success.
## Lives directly under /root so it survives the menu -> game scene change.

var role := "host"
var code := ""
var _t := 0.0
var _phase := 0
var ui: LobbyUI


func _ready() -> void:
	SaveGame.use_test_file()
	Settings.values.tutorial_done = true
	role = Net.arg("as", "host")
	code = Net.arg("code", "ZZZZ")
	Settings.values.player_name = "Hote" if role == "host" else "Invite"
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	get_tree().root.add_child.call_deferred(root)
	await get_tree().process_frame
	await get_tree().process_frame
	ui = LobbyUI.open(root)
	if role == "host":
		ui._create_relay()
		print("[ui-test] host: creating ", code)
	else:
		print("[ui-test] join: listing public games")


func _process(delta: float) -> void:
	_t += delta
	if _t > 60.0:
		print("[ui-test] TIMEOUT phase=%d status=%s" % [_phase, Net.relay_status])
		get_tree().quit(1)
		return
	var ns: Node = get_tree().current_scene.get_node_or_null("NetSync") if get_tree().current_scene else null
	if role == "host":
		if ns and ns.players.size() >= 2:
			print("[ui-test] host: second player joined: ", ns.players.values().map(func(p): return p.name))
			get_tree().quit(0)
		return
	# joiner
	if _phase == 0 and _t > 5.0 and is_instance_valid(ui):
		var found := false
		for b in ui.rooms_box.get_children():
			if b is Button and (b as Button).text.contains("[%s]" % code):
				found = true
		print("[ui-test] join: public list shows the game: ", found)
		if not found:
			get_tree().quit(3)
			return
		_phase = 1
		ui._join_relay(code)
	elif _phase == 1 and ns and ns.lobby_ui and is_instance_valid(ns.lobby_ui):
		_phase = 2
		print("[ui-test] join: in the game lobby")
	elif _phase == 2 and ns and ns.lobby_ui and ns.lobby_ui.list.get_child_count() >= 2:
		print("[ui-test] join: lobby shows %d players" % ns.lobby_ui.list.get_child_count())
		get_tree().quit(0)
