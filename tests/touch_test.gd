extends Node
## Simulates real fingers (InputEventScreenTouch, multi-touch) on the phone controls.
## Run: godot --headless --path . res://tests/touch_test.tscn   (exit code = failures)
var game: Node
var s: Session
var fails := 0
var actions: Array = []

func check(n: String, ok: bool, extra := "") -> void:
	print(("PASS " if ok else "FAIL ") + n + " " + extra)
	if not ok:
		fails += 1

## Positions are given in viewport (UI) coordinates; input events expect window coordinates.
func win(pos: Vector2) -> Vector2:
	return get_viewport().get_final_transform() * pos

func touch(idx: int, pos: Vector2, down: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = idx
	e.position = win(pos)
	e.pressed = down
	Input.parse_input_event(e)

func drag(idx: int, pos: Vector2, rel: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = idx
	e.position = win(pos)
	e.relative = rel
	Input.parse_input_event(e)

func tap(idx: int, pos: Vector2, hold := 0.2) -> void:
	touch(idx, pos, true)
	await get_tree().create_timer(hold).timeout
	touch(idx, pos, false)
	await get_tree().create_timer(0.15).timeout

func center(c: Control) -> Vector2:
	return c.get_global_rect().get_center()

func _ready() -> void:
	SaveGame.use_test_file()
	SaveGame.data.money = 300
	Settings.values.tutorial_done = true
	Settings.values.touch_controls = "on"
	Game.start_args = {"mode": "solo", "seed": 5}
	game = load("res://src/gameplay/game_scene.tscn").instantiate()
	add_child(game)
	s = game.session
	s.events.enabled = false
	s.game_event_emitted.connect(func(t, d): if t == "action" and d.get("actor", "") == "player": actions.append(d.action))
	await get_tree().create_timer(4.0).timeout
	_close_modals()
	var m: MobileControls = game.mobile
	var p := s.player
	# stand next to the player's own chair
	var desk := s.world.desk_of("player")
	var chair: Prop = s.world.ent(desk.chair_id)
	p.global_position = s.world.nav_closest(chair.global_position + desk.facing * -1.0)
	p.rotation.y = atan2(-desk.facing.x, -desk.facing.z)
	game.rig.yaw = p.rotation.y
	await get_tree().create_timer(0.6).timeout
	check("chair is focused", String(game.pc.focus.get("target", "")) == desk.chair_id, str(game.pc.focus.get("name", "")))
	# 1) thumb on the joystick (finger 0) + tap the big action button with finger 1
	touch(0, Vector2(200, 560), true)
	drag(0, Vector2(205, 560), Vector2(5, 0))
	await get_tree().create_timer(0.2).timeout
	await tap(1, center(m.action_btn))
	touch(0, Vector2(205, 560), false)
	await get_tree().create_timer(0.5).timeout
	check("action button works while holding the joystick", p.seated_on != null, "actions=%s" % [actions])
	s.request_action(p, p.id, "stand")
	await get_tree().create_timer(0.8).timeout
	var np := s.world.nav_closest(p.global_position)
	check("standing up does not put you inside the desk", Vector2(np.x - p.global_position.x, np.z - p.global_position.z).length() < 0.3, str(p.global_position))
	# action list must stay fully on screen when it changes size (chair -> PC -> chair)
	var pc_dev: Node3D = s.world.ent(desk.pc_id)
	for tgt in [pc_dev, chair, pc_dev]:
		p.global_position = s.world.nav_closest(tgt.global_position + desk.facing * -0.9)
		var to: Vector3 = tgt.global_position - p.global_position
		p.rotation.y = atan2(-to.x, -to.z)
		game.rig.yaw = p.rotation.y
		await get_tree().create_timer(0.5).timeout
		var r: Rect2 = game.hud.prompt.get_global_rect()
		var area: Vector2 = game.ui_root.size
		check("action list on screen (%s, %d rows)" % [game.pc.focus.get("name", ""), game.pc.focus.get("actions", []).size()],
			game.hud.prompt.visible and r.position.y >= 0.0 and r.end.y <= area.y + 1.0 and r.end.x <= area.x + 1.0, str(r))
	p.global_position = s.world.nav_closest(chair.global_position + desk.facing * -1.0)
	p.rotation.y = atan2(-desk.facing.x, -desk.facing.z)
	game.rig.yaw = p.rotation.y
	await get_tree().create_timer(0.6).timeout
	# 2) tap a row of the action list (single finger, normal tap duration)
	var rows: Array = game.hud.prompt_v.get_children().filter(func(c): return c is Button)
	check("action list has tappable rows", rows.size() >= 2, str(rows.size()))
	if rows.size() >= 2:
		var before := actions.size()
		await tap(0, center(rows[1]), 0.3)
		await get_tree().create_timer(0.5).timeout
		check("tapping a list row runs that action", actions.size() > before, "actions=%s" % [actions])
	# 3) shop button reachable from anywhere
	var shop_btn: Button = game.hud.get("shop_btn")
	check("shop button exists in HUD", shop_btn != null and shop_btn.is_visible_in_tree())
	if shop_btn:
		touch(0, Vector2(200, 560), true)
		await tap(1, center(shop_btn))
		touch(0, Vector2(200, 560), false)
		await get_tree().create_timer(0.4).timeout
		var shops: Array = game.ui_root.find_children("*", "ShopPanel", true, false)
		check("shop opens with a second finger", not shops.is_empty())
	# 4) missions are visible on the phone HUD
	var chip: Button = game.hud.get("mission_chip")
	check("mission tracker visible", chip != null and chip.is_visible_in_tree() and chip.text != "", chip.text if chip else "")
	print("TOUCH RESULT fails=%d" % fails)
	get_tree().quit(fails)

func _close_modals() -> void:
	for c in game.ui_root.get_children():
		if c.has_method("close"):
			c.close()
