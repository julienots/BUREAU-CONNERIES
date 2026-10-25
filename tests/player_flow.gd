extends Node
## End-to-end gameplay test with a scripted player (headless). Every step goes through
## Session.request_action() exactly like real input. Prints PASS/FAIL, exit code = fails.
## Run: godot --headless --path . res://tests/player_flow.tscn

var game: Node
var s: Session
var p: Character
var fails := 0
var passes := 0
var log_events: Array = []


func _ready() -> void:
	Settings.values.tutorial_done = true
	Settings.values.day_minutes = 20.0
	SaveGame.data = SaveGame.default_data()
	SaveGame.data.money = 300
	Game.start_args = {"mode": "solo", "seed": 99}
	game = load("res://src/gameplay/game_scene.tscn").instantiate()
	add_child(game)
	s = game.session
	p = s.player
	s.events.enabled = false
	game.pc.set_physics_process(false)   # the script drives the character directly
	s.missions.player.active.assign(["fond_ecran", "chaise_baladeuse", "canard_reunion", "agrafeuse_frigo", "melange_dossiers"])
	s.game_event_emitted.connect(func(t, d):
		log_events.append([t, d])
		if t in ["fall", "stumble"]:
			print("    [%s] %s" % [t, d]))
	s.notified.connect(func(t, k): print("    [notif/%s] %s" % [k, t]))
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


func tp(pos: Vector3) -> void:
	p.global_position = s.world.nav_closest(pos)
	p.velocity = Vector3.ZERO
	await wait(0.2)
	for i in 20:
		if p.can_act():
			break
		await wait(0.2)


func act(target: String, action: String, params := {}) -> Dictionary:
	var r := s.request_action(p, target, action, params)
	if r.get("timed", false):
		var dur: float = p.action.get("t_total", 0.0)
		await wait(dur + 0.4)
	return r


func boss_away() -> void:
	# keep the director busy far away so the logic steps are not interrupted
	s.director.global_position = Vector3(20.5, 0, 9.5)
	s.boss_brain._switch("phone")
	s.events.start("boss_call", s.now())


func _run() -> void:
	await wait(5.0)
	boss_away()
	# --- shop
	var m0 := s.economy.money("player")
	var r := await act("player", "buy", {"item": "canard"})
	check("buy duck", r.get("ok", false) and p.has_item("canard") and s.economy.money("player") == m0 - 20, str(r))
	r = await act("player", "buy", {"item": "confettis"})
	check("locked item refused", not r.get("ok", false), str(r.get("msg", "")))
	SaveGame.data.money = 0
	s.economy.wallets["player"] = 5
	r = await act("player", "buy", {"item": "coussin_peteur"})
	check("not enough money refused", not r.get("ok", false), str(r.get("msg", "")))
	s.economy.wallets["player"] = 300
	# --- wallpaper prank on Lucie's PC while she is in the break room
	var lucie: Character = s.characters["lucie"]
	s.brains["lucie"]._switch("go_zone", {"zone": "break", "dur": 120.0})
	lucie.global_position = s.world.nav_closest(Vector3(16, 0, -10))
	var d := s.world.desk_of("lucie")
	await tp(d.seat + d.facing * -0.3)
	var pc: Device = s.world.ent(d.pc_id)
	r = await act(d.pc_id, "change_wallpaper")
	check("wallpaper changed", pc.state.get("wallpaper", "") != "", str(r))
	check("mission fond_ecran", s.missions.player.is_done("fond_ecran"))
	# --- drag Lucie's chair 5 m away
	var chair: Prop = s.world.ent(d.chair_id)
	await tp(chair.global_position - d.facing * -0.8)
	r = await act(d.chair_id, "hold")
	check("hold chair", p.held == chair, str(r))
	p.move_dir = Vector3(0, 0, 1)
	for i in 8:
		await wait(0.5)
		print("    drag t=%.1f player=%s held=%s chair=%s vel=%s" % [i * 0.5, p.global_position.snapped(Vector3.ONE * 0.01), p.held != null, chair.global_position.snapped(Vector3.ONE * 0.01), p.velocity.snapped(Vector3.ONE * 0.01)])
	p.move_dir = Vector3.ZERO
	await act("player", "drop_held")
	await wait(1.5)
	check("chair moved >= 4m", chair.home_distance() >= 4.0, "dist=%.2f" % chair.home_distance())
	check("mission chaise_baladeuse", s.missions.player.is_done("chaise_baladeuse"))
	# --- duck on the meeting table
	await tp(Vector3(6.5, 0, -9.6))
	r = await act("player", "drop_item", {"item": "canard"})
	await wait(6.5)
	check("mission canard_reunion", s.missions.player.is_done("canard_reunion"), str(r))
	# --- steal Gérard's stapler and hide it in the fridge
	var stapler: Prop = s.world.props_with_tag("stapler")[0]
	s.brains["gerard"]._switch("go_zone", {"zone": "hall", "dur": 120.0})
	s.characters["gerard"].global_position = s.world.nav_closest(Vector3(18, 0, -3))
	await tp(stapler.global_position + Vector3(0, 0, 0.9))
	r = await act(stapler.ent_id(), "take")
	check("take stapler", p.has_item("agrafeuse"), str(r))
	var fridge: Device = s.find_device("fridge")
	await tp(fridge.interact_point() + Vector3(0, 0, 1.0))
	print("    player kd=%d down=%s" % [p.kd, p.is_down()])
	r = await act(fridge.ent_id(), "hide", {"item": "agrafeuse"})
	await wait(1.5)
	check("mission agrafeuse_frigo", s.missions.player.is_done("agrafeuse_frigo"), str(r))
	# --- mix 3 archive shelves
	var shelves := s.world.interactables.filter(func(e): return e is Device and e.kind == "shelf_files")
	for sh in shelves:
		await tp((sh as Device).interact_point() + (sh as Device).global_basis * Vector3(0, 0, -0.6))
		r = await act(sh.ent_id(), "mix_files")
	check("mission melange_dossiers", s.missions.player.is_done("melange_dossiers"), "shelves=%d" % shelves.size())
	check("money increased by missions", s.economy.money("player") > 300, "money=%d" % s.economy.money("player"))
	# --- denounce Nadia to the director
	s.events.finish("boss_call")
	s.boss_brain._switch("office")
	await wait(0.5)
	await tp(s.director.global_position + Vector3(-1.2, 0, 0))
	var n_before := s.testimonies.size()
	r = await act("boss", "denounce", {"accused": "nadia", "act_id": -1})
	check("denounce recorded", r.get("ok", false) and s.testimonies.size() >= n_before, str(r))
	# --- the director sees a prank in progress
	s.boss_brain._switch("office")
	var marcel_d := s.world.desk_of("marcel")
	s.brains["marcel"]._switch("go_zone", {"zone": "break", "dur": 120.0})
	s.characters["marcel"].global_position = s.world.nav_closest(Vector3(16, 0, -10))
	await tp(marcel_d.seat + marcel_d.facing * -0.3)
	s.director.global_position = s.world.nav_closest(marcel_d.seat + marcel_d.facing * -3.5)
	s.director.rotation.y = atan2(-(p.global_position - s.director.global_position).x, -(p.global_position - s.director.global_position).z)
	s.boss_brain._switch("stay")
	s.events.start("boss_stays", s.now())
	var vis := Perception.visibility(s.world, s.director, p, 110.0, 17.0)
	check("director can see the player", vis > 0.2, "vis=%.2f" % vis)
	s.request_action(p, marcel_d.pc_id, "change_wallpaper")
	var interrogated := false
	for i in 40:
		await wait(0.25)
		if s.interrogation.size() > 0 and s.interrogation.who == "player":
			interrogated = true
			break
		if s.boss_brain.state == "interrogating":
			interrogated = true
			break
	var lvl := s.suspicion_level("player")
	check("caught red-handed -> high suspicion", lvl >= 4 or interrogated, "level=%d state=%s" % [lvl, s.boss_brain.state])
	for i in 60:
		if s.interrogation.size() > 0:
			break
		await wait(0.25)
	check("interrogation started", s.interrogation.size() > 0 and s.interrogation.who == "player", "boss=%s" % s.boss_brain.state)
	var w0 := int(s.warnings.get("player", 0))
	r = await act("boss", "answer_deny")
	await wait(0.5)
	check("interrogation resolved", s.interrogation.is_empty(), str(r))
	check("caught -> sanction", int(s.warnings.get("player", 0)) == w0 + 1, "warnings=%d" % int(s.warnings.get("player", 0)))
	s.events.finish("boss_stays")
	# --- hearing: a loud crash far from him makes him investigate
	await tp(Vector3(-20, 0, 10))
	s.boss_brain.sus.scores.clear()
	s.boss_brain.sus.evidence.clear()
	s.boss_brain.confront_cooldown = 60.0
	s.boss_brain._switch("office")
	s.emit_sound(Vector3(-3, 0.5, -11), 85.0, "boxes_crash", "", "")
	var heard := not s.boss_brain.stimulus.is_empty()
	await wait(1.0)
	check("director hears a loud noise and goes to investigate", heard and (s.boss_brain.state in ["investigate", "search", "confront"]), "heard=%s state=%s" % [heard, s.boss_brain.state])
	check("hearing attenuated by walls", Perception.perceived(s.world, Vector3(-3, 0, -6.5), Vector3(-3, 0.6, -11), 60.0) < Perception.perceived(s.world, Vector3(-3, 0, -10.5), Vector3(-3, 0.6, -11), 60.0),
		"behind wall=%.1f in room=%.1f" % [Perception.perceived(s.world, Vector3(-3, 0, -6.5), Vector3(-3, 0.6, -11), 60.0), Perception.perceived(s.world, Vector3(-3, 0, -10.5), Vector3(-3, 0.6, -11), 60.0)])
	# --- vision: walls block, glass does not
	var glass_ok := s.world.line_clear(Vector3(6, 1.5, -6.5), Vector3(6, 1.5, -10))
	var wall_block := not s.world.line_clear(Vector3(-9, 1.5, -6.5), Vector3(-9, 1.5, -11))
	check("glass is see-through, walls block sight", glass_ok and wall_block, "glass=%s wall_block=%s" % [glass_ok, wall_block])
	# --- physics: the archive box tower stays stable while untouched
	var boxes := s.world.props_with_tag("boxes").filter(func(b): return String(b.ent_id()).begins_with("archive_box"))
	var maxd := 0.0
	for b in boxes:
		maxd = maxf(maxd, (b as Prop).home_distance())
	check("box tower stable at rest", maxd < 0.35, "max drift=%.2f over %d boxes" % [maxd, boxes.size()])
	# push the tower hard -> it collapses and makes a crash
	await tp(Vector3(-13.3, 0, -11.0))
	var crash := {"n": 0}
	s.game_event_emitted.connect(func(t, dd): if t == "sound" and String(dd.get("sfx", "")) == "boxes_crash": crash.n += 1)
	for b in boxes:
		if (b as Prop).global_position.y > 1.0:
			(b as Prop).apply_central_impulse(Vector3(0, 0, 12))
	await wait(3.0)
	var fallen := 0
	for b in boxes:
		if (b as Prop).home_distance() > 0.5:
			fallen += 1
	check("tower collapses when shoved -> crash", fallen >= 3 and int(crash.n) > 0, "fallen=%d crash_events=%d" % [fallen, int(crash.n)])
	# --- save round trip
	SaveGame.data.money = 1234
	SaveGame.save_game()
	SaveGame.data.money = 0
	SaveGame.load_game()
	check("save/load round trip", int(SaveGame.data.money) == 1234 and int(SaveGame.data.version) == SaveGame.VERSION)
	var old := {"version": 1, "money": 5, "owned": ["canard", "canard", "banane"]}
	var mig := SaveGame.migrate(old)
	check("save migration v1->v2", typeof(mig.owned) == TYPE_DICTIONARY and int(mig.owned.canard) == 2 and mig.has("stats"))
	print("RESULT passes=%d fails=%d" % [passes, fails])
	get_tree().quit(fails)
