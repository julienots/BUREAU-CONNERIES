extends Node
## CEO visit: arrival, director escort, pranks on the CEO pay big, 3 pranks make him leave.
## Run: godot --headless --path . res://tests/pdg_test.tscn   (exit code = failures)

var game: Node
var s: Session
var p: Character
var fails := 0
var passes := 0


func _ready() -> void:
	SaveGame.use_test_file()
	Settings.values.tutorial_done = true
	SaveGame.data = SaveGame.default_data()
	SaveGame.data.money = 500
	Game.start_args = {"mode": "solo", "seed": 21}
	game = load("res://src/gameplay/game_scene.tscn").instantiate()
	add_child(game)
	s = game.session
	p = s.player
	s.events.enabled = false
	s.pdg_at_min = -1.0
	game.pc.set_physics_process(false)
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


func act(action: String, params := {}) -> Dictionary:
	await wait(0.6)
	return s.request_action(p, p.id, action, params)


func near_pdg() -> void:
	var pd: Character = s.pdg
	var spot := s.world.nav_closest(pd.global_position + pd.forward() * 2.0)
	p.global_position = spot
	var to := pd.global_position - p.global_position
	p.rotation.y = atan2(-to.x, -to.z)
	# keep the director looking elsewhere for these checks
	s.director.global_position = s.world.nav_closest(Vector3(-18, 0, 10))


func _run() -> void:
	await wait(3.0)
	s.events.start("pdg_visit", s.now(), {})
	await wait(0.5)
	check("CEO arrived", s.pdg_active() and s.characters.has("pdg"))
	check("CEO is not an employee", not s.is_employee("pdg") and not s.employees().has(s.pdg))
	check("bonus CEO missions on the post-it", "pdg_farce" in s.missions.player.active and "pdg_fuite" in s.missions.player.active)
	await wait(1.5)
	check("director escorts the CEO", s.boss_brain.state == "escort", s.boss_brain.state)
	var start: Vector3 = s.pdg.global_position
	await wait(11.0)
	check("CEO walks his tour", s.pdg.global_position.distance_to(start) > 1.5 or s.pdg_brain.i > 0, str(s.pdg.global_position))
	s.pdg_brain.set_physics_process(false)   # freeze him for the prank checks
	s.pdg.stop()
	for it in ["klaxon", "pistolet_eau", "boule_puante"]:
		p.add_item(it)
	near_pdg()
	await wait(0.3)
	var m := s.economy.money("player")
	var r := await act("use_klaxon", {"item": "klaxon"})
	check("klaxon on the CEO pays the CEO bonus", r.get("ok", false) and s.economy.money("player") >= m + 50, "%d -> %d" % [m, s.economy.money("player")])
	check("mission Bizutage du PDG done", s.missions.player.is_done("pdg_farce"))
	near_pdg()
	await wait(0.3)
	r = await act("use_water", {"item": "pistolet_eau"})
	check("water pistol on the CEO", r.get("ok", false), str(r))
	near_pdg()
	r = await act("use_stink", {"item": "boule_puante"})
	check("3rd prank: the CEO flees", s.pdg_brain.leaving and s.missions.player.is_done("pdg_fuite"))
	# fast-forward: put him at the lift
	s.pdg_brain.set_physics_process(true)
	s.pdg.global_position = s.pdg_brain.route[-1]
	await wait(2.0)
	check("CEO left the building", not s.pdg_active() and not s.characters.has("pdg"))
	check("unfinished CEO missions removed", not "pdg_glissade" in s.missions.player.active)
	await wait(1.0)
	check("director back to normal", s.boss_brain.state != "escort", s.boss_brain.state)
	# a full, undisturbed tour (time x4): he must sit in the boss chair and leave on his own
	s.economy.add("player", 0)
	s.events._last_time.erase("pdg_visit")
	p.global_position = s.world.nav_closest(Vector3(-18, 0, 10))
	s.events.start("pdg_visit", s.now(), {})
	await wait(0.3)
	var sat := false
	Engine.time_scale = 4.0
	for k in 200:
		await wait(1.0)
		if s.pdg_active() and s.pdg.seated_on and "boss_chair" in s.pdg.seated_on.tags:
			sat = true
		if not s.pdg_active():
			break
	Engine.time_scale = 1.0
	check("full tour: sat in the boss chair", sat)
	check("full tour: left on his own", not s.pdg_active())
	print("\nPDG TEST: %d passed, %d failed" % [passes, fails])
	get_tree().quit(fails)
