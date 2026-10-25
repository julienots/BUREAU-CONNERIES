extends Node
## Headless test of the "Farces & Attrapes" shop items: each one must work in game and pay
## the prankster. Run: godot --headless --path . res://tests/farce_test.tscn

var game: Node
var s: Session
var p: Character
var fails := 0
var passes := 0


func _ready() -> void:
	SaveGame.use_test_file()
	Settings.values.tutorial_done = true
	SaveGame.data = SaveGame.default_data()
	SaveGame.data.money = 1000
	Game.start_args = {"mode": "solo", "seed": 7}
	game = load("res://src/gameplay/game_scene.tscn").instantiate()
	add_child(game)
	s = game.session
	p = s.player
	s.events.enabled = false
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


func act(target: String, action: String, params := {}) -> Dictionary:
	await wait(0.6)   # stay under the action rate limit
	var r := s.request_action(p, target, action, params)
	if r.get("timed", false):
		await wait(float(p.action.get("t_total", 0.0)) + 0.4)
	return r


func face(c: Character, pos: Vector3) -> void:
	var d := pos - c.global_position
	c.rotation.y = atan2(-d.x, -d.z)


## Park an NPC (brain paused) at pos, facing `look`.
func park(npc: Character, pos: Vector3, look: Vector3) -> void:
	if npc.seated_on:
		npc.stand_up()
	s.brains[npc.id].set_physics_process(false)
	npc.stop()
	npc.global_position = pos
	npc.velocity = Vector3.ZERO
	face(npc, look)


func release(npc: Character) -> void:
	s.brains[npc.id].set_physics_process(true)


func _run() -> void:
	await wait(4.0)
	s.director.global_position = Vector3(20.5, 0, 9.5)
	s.boss_brain._switch("phone")
	for it in ["klaxon", "pistolet_eau", "boule_puante", "poil_gratter", "serpent", "cafard"]:
		var r := await act("player", "buy", {"item": it})
		check("buy " + it, r.get("ok", false) and (p.has_item(it) or int(s.economy.stock.player.get(it, 0)) > 0), str(r))
	check("full pockets go to stock", p.items.size() == 4 and int(s.economy.stock.player.get("cafard", 0)) == 1)
	var npcs: Array = s.npc_ids()
	var a: Character = s.characters[npcs[0]]
	var b: Character = s.characters[npcs[1]]
	var base := s.world.nav_closest(Vector3(4, 0, 4))
	p.global_position = base
	face(p, base + Vector3(0, 0, -3))
	# --- klaxon
	park(a, base + Vector3(0, 0, -2), base)
	park(b, base + Vector3(2, 0, 0), base)
	await wait(0.5)
	var m := s.economy.money("player")
	var r := await act("player", "use_klaxon", {"item": "klaxon"})
	check("klaxon used", r.get("ok", false) and s.charges(p, "klaxon") == 4, str(r))
	check("klaxon pays", s.economy.money("player") == m + 12, "%d -> %d" % [m, s.economy.money("player")])
	# --- water pistol
	await wait(2.5)
	m = s.economy.money("player")
	face(p, a.global_position)
	r = await act("player", "use_water", {"item": "pistolet_eau"})
	check("water hits", r.get("ok", false) and s.economy.money("player") == m + 7, str(r))
	face(p, base + Vector3(-5, 0, 3))
	park(b, base + Vector3(9, 0, 0), base)
	r = await act("player", "use_water", {"item": "pistolet_eau"})
	check("water needs a target", not r.get("ok", true) and s.charges(p, "pistolet_eau") == 7, str(r))
	# --- stink bomb
	m = s.economy.money("player")
	r = await act("player", "use_stink", {"item": "boule_puante"})
	check("stink used", r.get("ok", false) and not p.has_item("boule_puante") and not s.smell.is_empty(), str(r))
	check("stink pays", s.economy.money("player") >= m + 5, "%d -> %d" % [m, s.economy.money("player")])
	release(a)
	release(b)
	await wait(3.0)
	# --- itching powder on a chair
	var chair: Prop = null
	for c in s.world.props_with_tag("chair"):
		var pr := c as Prop
		if pr.occupant == "" and pr.is_available():
			chair = pr
			break
	p.global_position = s.world.nav_closest(chair.global_position + Vector3(0.8, 0, 0))
	await wait(0.3)
	r = await act(chair.ent_id(), "itch_powder")
	check("itch powder applied", r.get("ok", false) and chair.has_meta("itch_by") and not p.has_item("poil_gratter"), str(r))
	m = s.economy.money("player")
	park(a, chair.global_position + Vector3(0, 0, 0.6), chair.global_position)
	a.sit_on(chair)
	await wait(0.5)
	check("itch triggers & pays", s.economy.money("player") == m + 18 and not chair.has_meta("itch_by"), "%d -> %d" % [m, s.economy.money("player")])
	release(a)
	await wait(3.5)
	check("itched NPC stands up", a.seated_on == null)
	# --- snake in a drawer
	r = await act("player", "take_stock", {"item": "serpent"})
	check("stock -> pocket", r.get("ok", false) and p.has_item("serpent"), str(r))
	var drawer: Device = null
	for e in s.world.interactables:
		if e is Device and (e as Device).kind == "drawer":
			drawer = e
			break
	p.global_position = s.world.nav_closest(drawer.interact_point())
	await wait(0.3)
	r = await act(drawer.ent_id(), "snake")
	check("snake hidden", r.get("ok", false) and drawer.state.get("snake", false), str(r))
	m = s.economy.money("player")
	s.npc_searches_container(b, drawer)
	check("snake pops & pays", not drawer.state.get("snake", false) and s.economy.money("player") == m + 20, "%d -> %d" % [m, s.economy.money("player")])
	# --- fake cockroach
	await act("player", "take_stock", {"item": "cafard"})
	p.global_position = base
	face(p, base + Vector3(0, 0, -3))
	r = await act("player", "drop_item", {"item": "cafard"})
	check("cafard dropped", r.get("ok", false) and not p.has_item("cafard"), str(r))
	await wait(0.5)
	var roach: Prop = s.world.props_with_tag("cafard")[0]
	p.global_position = base + Vector3(-6, 0, 0)
	m = s.economy.money("player")
	park(a, roach.global_position + Vector3(0, 0, -2.0), roach.global_position)
	await wait(1.5)
	check("cafard scares & pays", s.economy.money("player") == m + 12, "%d -> %d" % [m, s.economy.money("player")])
	await wait(1.5)
	check("cafard pays once per victim", s.economy.money("player") == m + 12)
	release(a)
	print("\nFARCE TEST: %d passed, %d failed" % [passes, fails])
	get_tree().quit(fails)
