extends Node
## Cartoon physics: banana somersaults, stars, chair rides with someone on it, ejection on
## impact, chair rocket, bouncy duck. Run: godot --headless --path . res://tests/physics_test.tscn

var game: Node
var s: Session
var p: Character
var fails := 0
var passes := 0


func _ready() -> void:
	SaveGame.use_test_file()
	Settings.values.tutorial_done = true
	SaveGame.data = SaveGame.default_data()
	Game.start_args = {"mode": "solo", "seed": 31}
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


func park(c: Character, pos: Vector3) -> void:
	if c.seated_on:
		c.stand_up()
	if s.brains.has(c.id):
		s.brains[c.id].set_physics_process(false)
	c.stop()
	c.global_position = s.world.nav_closest(pos)
	c.velocity = Vector3.ZERO


func _run() -> void:
	await wait(3.0)
	s.director.global_position = s.world.nav_closest(Vector3(20, 0, 9))
	s.boss_brain.set_physics_process(false)
	var npcs: Array = s.npc_ids()
	var a: Character = s.characters[npcs[0]]
	var b: Character = s.characters[npcs[1]]
	# --- banana: flight + somersault + stars
	park(a, Vector3(5, 0, 4.9))
	await wait(0.3)
	var start := a.global_position
	a.velocity = Vector3(2.5, 0, 0)
	a.slip("banana", "player")
	var max_y := 0.0
	var max_spin := 0.0
	var stars := false
	for k in 40:
		await wait(0.05)
		max_y = maxf(max_y, a.global_position.y)
		max_spin = maxf(max_spin, absf(a.humanoid.spin))
		if a._stars:
			stars = true
	check("banana launches the victim in the air", max_y > 0.4, "max y %.2f" % max_y)
	check("banana somersault", max_spin > PI, "spin %.2f" % max_spin)
	check("banana victim slides away", a.global_position.distance_to(start) > 1.0, "%.2f m" % a.global_position.distance_to(start))
	check("stars around the head when knocked out", stars)
	await wait(3.5)
	check("gets up, stars gone", not a.is_down() and a._stars == null)
	# --- push a chair with someone on it
	var chair: Prop = null
	for c in s.world.props_with_tag("chair"):
		var pr := c as Prop
		if pr.occupant == "" and pr.global_position.distance_to(Vector3(-2.4, 0, 4.9)) < 6.0 and not "boss_chair" in pr.tags:
			chair = pr
			break
	chair.freeze = false
	chair.global_position = s.world.nav_closest(Vector3(-2.4, 0, 4.9)) + Vector3(0, 0.05, 0)
	chair.rotation = Vector3(0, PI * 0.5, 0)
	await wait(0.6)
	park(b, chair.global_position + Vector3(0.6, 0, 0))
	b.sit_on(chair)
	await wait(0.6)
	p.global_position = chair.global_position + Vector3(0.9, 0, 0)
	var c0 := chair.global_position
	var m := s.economy.money("player")
	var acts: Array = chair.get_actions(p).map(func(x): return x.id)
	check("chair with someone on it offers a ride", "chair_ride" in acts, str(acts))
	var r := s.request_action(p, chair.ent_id(), "chair_ride", {})
	await wait(1.2)
	check("the chair rolls away with its occupant", chair.global_position.distance_to(c0) > 1.0 and (b.seated_on == chair or b.is_down()), "%.2f m" % chair.global_position.distance_to(c0))
	check("ride pays a prank bonus", s.economy.money("player") >= m + 10, "%d -> %d" % [m, s.economy.money("player")])
	await wait(4.0)
	# --- crash: launch towards a wall hard -> ejected
	if b.is_down():
		await wait(4.0)
	park(b, Vector3(-11.5, 0, 4.9))
	chair.freeze = false
	chair.global_position = s.world.nav_closest(Vector3(-19.5, 0, 4.9)) + Vector3(0, 0.05, 0)
	chair.rotation = Vector3(0, PI * 0.5, 0)
	chair.linear_velocity = Vector3.ZERO
	await wait(0.6)
	b.global_position = chair.global_position
	b.sit_on(chair)
	await wait(0.4)
	s.launch_chair(chair, "player", Vector3(-1, 0, 0), 14.0)
	var ejected := false
	for k in 40:
		await wait(0.1)
		if b.is_down():
			ejected = true
			break
	check("crashing into the wall ejects the rider", ejected, str(chair.global_position))
	await wait(4.0)
	# --- chair rocket (self)
	park(p, Vector3(-2.4, 0, 4.9))
	chair.freeze = false
	chair.global_position = s.world.nav_closest(Vector3(-2.4, 0, 4.9)) + Vector3(0, 0.05, 0)
	chair.rotation = Vector3.ZERO
	await wait(0.6)
	if b.seated_on:
		b.stand_up()
	p.sit_on(chair)
	await wait(0.4)
	var acts2: Array = s.self_actions(p).map(func(x): return x.id)
	check("chair rocket offered when seated", "chair_rocket" in acts2, str(acts2))
	c0 = chair.global_position
	s.request_action(p, p.id, "chair_rocket", {})
	await wait(1.0)
	check("chair rocket rolls the player", chair.global_position.distance_to(c0) > 1.0, "%.2f m" % chair.global_position.distance_to(c0))
	await wait(3.0)
	if p.seated_on:
		p.stand_up()
	# --- bouncy duck
	var duck := s.spawn_prop("duck", s.world.nav_closest(Vector3(5, 0, 4.9)) + Vector3(0, 1.6, 0), "")
	var low := false
	var bounce_top := 0.0
	for k in 60:
		await wait(0.03)
		var y := duck.global_position.y
		if not low and y < 0.15:
			low = true
		elif low:
			bounce_top = maxf(bounce_top, y)
	check("rubber duck bounces", bounce_top > 0.35, "bounce %.2f m" % bounce_top)
	print("\nPHYSICS TEST: %d passed, %d failed" % [passes, fails])
	get_tree().quit(fails)
