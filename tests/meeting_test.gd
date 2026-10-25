extends Node
## Meeting antics: the director alternates talking / writing on the board, antics only pay
## when he does not see you, meeting missions complete. Run:
## godot --headless --path . res://tests/meeting_test.tscn   (exit code = failures)

var game: Node
var s: Session
var p: Character
var fails := 0
var passes := 0


func _ready() -> void:
	SaveGame.use_test_file()
	Settings.values.tutorial_done = true
	SaveGame.data = SaveGame.default_data()
	SaveGame.data.money = 200
	Game.start_args = {"mode": "solo", "seed": 11}
	game = load("res://src/gameplay/game_scene.tscn").instantiate()
	add_child(game)
	s = game.session
	p = s.player
	s.events.enabled = false
	game.pc.set_physics_process(false)
	s.missions.player.active.assign(["imitateur", "sieste_reunion", "clown_reunion", "boulette_chef"])
	_run()


func check(name: String, ok: bool, extra := "") -> void:
	if ok:
		passes += 1
		print("PASS ", name, " ", extra)
	else:
		fails += 1
		print("FAIL ", name, " ", extra)


func wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


func act(action: String) -> Dictionary:
	await wait(0.6)
	return s.request_action(p, p.id, action, {})


func _run() -> void:
	await wait(3.0)
	check("coworkers spawned (setting npc_count)", s.brains.size() == mini(14, int(Settings.get_v("npc_count"))), str(s.brains.size()))
	check("12 meeting seats", s.world.poi.get("meeting_seat", []).size() == 12)
	check("no antics outside meetings", s.self_actions(p).is_empty())
	s.day.start_meeting_now(40.0)
	await wait(1.0)
	check("meeting started", s.day.meeting_active)
	# everyone heads to the meeting room; put the boss at his spot right away
	var bp: Dictionary = s.world.poi.get("meeting_boss", [{}])[0]
	s.director.global_position = bp.pos
	s.boss_brain._switch("meeting")
	s.boss_brain.step = 1
	s.boss_brain.timer = 0.0
	# player sits at the table, near the boss end
	var seat: Dictionary = s.world.poi.meeting_seat[0]
	var chair: Prop = s.world.ent(seat.chair_id)
	p.global_position = s.world.nav_closest(seat.pos)
	await wait(1.0)
	if chair.occupant == "":
		p.sit_on(chair)
	await wait(1.5)
	var acts := s.self_actions(p).filter(func(a): return a.id.begins_with("meet_"))
	check("6 antics offered when seated in the meeting", acts.size() == 6, str(acts.map(func(a): return a.id)))
	game.pc._update_focus()
	check("antics in the player's action list", game.pc.focus.get("actions", []).any(func(a): return a.get("self", false)))
	await wait(4.0)
	var npcs_in := 0
	for id in s.brains:
		if s.world.zone_at(s.characters[id].global_position) == "meeting":
			npcs_in += 1
	print("    coworkers in the meeting room: %d" % npcs_in)
	# boss facing the table: he sees us -> antic is caught, no money
	s.boss_brain._set_board(false)
	await wait(1.0)
	check("boss looks at the table", not s.boss_back_turned() and s.director_sees(p))
	var m := s.economy.money("player")
	var tr := s.trust_of("player")
	var r := await act("meet_snore")
	check("snore while watched: caught, no prime", r.get("ok", false) and s.economy.money("player") == m and s.trust_of("player") < tr, "%d -> %d" % [m, s.economy.money("player")])
	check("watched snore does not complete the mission", not s.missions.player.is_done("sieste_reunion"))
	# boss writes on the board: back turned
	s.boss_brain._set_board(true)
	await wait(1.2)
	check("boss back turned", s.boss_back_turned(), str(s.director.forward()))
	check("boss does not see us", not s.director_sees(p))
	m = s.economy.money("player")
	r = await act("meet_imitate")
	check("imitate while his back is turned pays", r.get("ok", false) and s.economy.money("player") >= m + 25, "%d -> %d" % [m, s.economy.money("player")])
	check("mission L'imitateur done", s.missions.player.is_done("imitateur"))
	s.boss_brain._set_board(true)
	await wait(1.0)
	r = await act("meet_snore")
	check("mission Sieste stratégique done", s.missions.player.is_done("sieste_reunion"))
	# paper ball at the boss
	p.stand_up()
	await wait(0.5)
	s.boss_brain._set_board(false)
	p.global_position = s.world.nav_closest(Vector3(3.0, 0, -11.9))
	var to: Vector3 = s.director.global_position - p.global_position
	p.rotation.y = atan2(-to.x, -to.z)
	await wait(0.6)
	var hit := false
	for i in 4:
		r = await act("meet_paperball")
		await wait(1.2)
		if s.missions.player.is_done("boulette_chef"):
			hit = true
			break
	check("paper ball hits the boss (mission done)", hit)
	print("\nMEETING TEST: %d passed, %d failed" % [passes, fails])
	get_tree().quit(fails)
