extends Node
## Unit + static tests (headless, fast). Exit code = number of failures.
## Run: godot --headless --path . res://tests/run_tests.tscn

var fails := 0
var passes := 0


func check(name: String, ok: bool, extra := "") -> void:
	if ok:
		passes += 1
	else:
		fails += 1
		print("FAIL ", name, " ", extra)


func _ready() -> void:
	test_data()
	test_missions_are_implemented()
	test_assets_exist()
	test_suspicion()
	test_memory()
	test_testimony()
	test_economy()
	test_day()
	test_events()
	test_barks()
	test_perception_helpers()
	test_mission_pick()
	print("UNIT RESULT passes=%d fails=%d" % [passes, fails])
	get_tree().quit(fails)


func test_data() -> void:
	check("data has no validation errors", Data.errors.is_empty(), str(Data.errors))
	check("30 missions", Data.missions.size() >= 30, str(Data.missions.size()))
	check("8 archetypes", Data.archetypes.size() == 8)
	check("8 coworkers", Data.coworkers.size() == 8)
	check("5 director profiles", Data.director_profiles.size() == 5)
	check(">= 10 random events", Data.random_events.size() >= 10)
	for id in Data.missions:
		var m: Dictionary = Data.missions[id]
		check("mission %s has steps" % id, m.steps.size() >= 1)
		check("mission %s positive reward" % id, int(m.reward) > 0)


## Every mission must rely on actions/reactions that exist in the game code.
func test_missions_are_implemented() -> void:
	var src := ""
	for f in ["res://src/world/device.gd", "res://src/world/prop.gd", "res://src/world/door.gd", "res://src/gameplay/session.gd", "res://src/ai/coworker_brain.gd", "res://src/ai/director_brain.gd"]:
		src += FileAccess.get_file_as_string(f)
	for id in Data.missions:
		var r: Dictionary = Data.missions[id].rule
		match String(r.type):
			"action_on_owned", "action_on_any", "count_action", "action_during":
				var a: String = r.action
				var ok := src.contains('"id": "%s"' % a) or src.contains('"action": "%s"' % a)
				check("mission %s action '%s' exists" % [id, a], ok)
			"reaction":
				check("mission %s reaction '%s' emitted" % [id, r.reaction], src.contains('"%s"' % r.reaction))
			"sound_kind":
				check("mission %s sound '%s' emitted" % [id, r.kind], src.contains('"%s"' % r.kind))
			"device_on_time":
				check("mission %s device tick" % id, src.contains('"device": "%s"' % r.device))
			"prop_in_zone", "move_owned_prop":
				var tag: String = r.tag
				var pf := FileAccess.get_file_as_string("res://src/world/prop_factory.gd")
				check("mission %s tag '%s' exists" % [id, tag], pf.contains('"%s"' % tag))


func test_assets_exist() -> void:
	for id in Data.items:
		check("icon for %s" % id, ResourceLoader.exists("res://assets/textures/icons/%s.png" % Data.items[id].icon))
	var voices: Array = [Data.director.voice, Data.player_default.voice]
	for c in Data.coworkers:
		voices.append(c.voice)
	for v in voices:
		for e in ["neutral", "happy", "laugh", "angry", "panic", "surprised", "suspicious", "embarrassed"]:
			check("voice %s_%s" % [v, e], ResourceLoader.exists("res://assets/audio/voices/%s_%s_0.wav" % [v, e]))
	for sfx in ["step_boss_0", "fart_0", "boxes_crash", "door_slam", "printer_loop", "confetti_pop", "buzzer", "phone_ring", "typing_loop"]:
		check("sfx " + sfx, ResourceLoader.exists("res://assets/audio/sfx/%s.wav" % sfx))
	check("studio logo", ResourceLoader.exists("res://assets/branding/superessence_logo.png"))


func test_suspicion() -> void:
	var s := Suspicion.new()
	check("level 0 initially", s.level("a") == 0)
	s.add("a", 30.0, "seen", 1, "boss", 0.0)
	check("level 2 at 30", s.level("a") == 2, str(s.level("a")))
	s.add("a", 40.0, "testimony", 1, "marcel", 0.0)
	check("level 4 at 70", s.level("a") == 4)
	check("two sources", s.sources("a") == 2)
	check("not direct yet", not s.has_direct("a"))
	s.set_confirmed("a", 1, 0.0)
	check("confirmed -> level 5", s.level("a") == 5)
	check("strength 1 when direct", s.strength("a", 1) == 1.0)
	check("best act", s.best_act("a") == 1)
	var before := s.score("a")
	s.tick(60.0)
	check("decay", s.score("a") < before)
	s.adjust_trust("marcel", -0.3)
	check("trust lowered", s.trust("marcel") < 0.6)
	var g := Suspicion.new()
	g.gain = 2.0
	g.add("b", 10.0, "seen")
	check("gain applies", is_equal_approx(g.score("b"), 20.0))


func test_memory() -> void:
	var m := Memory.new(3)
	for i in 5:
		m.remember_act({"id": i, "zone": "open_space", "kind": "x"}, "p", "p", 1.0, float(i))
	check("capacity bounded", m.witnessed.size() == 3)
	check("oldest forgotten", m.knows_act(0).is_empty() and not m.knows_act(4).is_empty())
	m.see("kevin", "archives", Vector3.ZERO, 10.0)
	m.see("kevin", "archives", Vector3.ZERO, 14.0)
	m.see("kevin", "break", Vector3.ZERO, 30.0)
	check("alibi found", m.where_was("kevin", 12.0).get("zone", "") == "archives")
	check("alibi later zone", m.where_was("kevin", 31.0).get("zone", "") == "break")
	check("seen near", "kevin" in m.seen_near("archives", 13.0))
	check("not seen near other time", not "kevin" in m.seen_near("archives", 100.0))
	m.add_grievance("x", 5.0)
	check("grievance clamped", m.grievance("x") == 3.0)


func test_testimony() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var rel := Relations.new()
	rel.setup(["a", "b", "c", "player"], [["a", "player", 0.9]], rng, {})
	var act := {"id": 7, "actor": "player", "zone": "open_space", "kind": "wallpaper", "sev": 2}
	var loyal := Data.traits_for("loyal")
	var snitch := Data.traits_for("snitch")
	var mem := Memory.new()
	mem.remember_act(act, "player", "Toi", 1.0, 0.0)
	var protects := 0
	var truths := 0
	for i in 100:
		var r := Testimony.answer("a", loyal, mem, rel, act, ["a", "b", "c", "player"], rng)
		if r.kind == "protect":
			protects += 1
		elif r.kind == "truth":
			truths += 1
	check("loyal friend often protects", protects > 40, "protect=%d truth=%d" % [protects, truths])
	rel.set_pair("b", "player", -0.5)
	var t2 := 0
	for i in 100:
		var r := Testimony.answer("b", snitch, mem, rel, act, ["a", "b", "c", "player"], rng)
		if r.kind == "truth" and r.accused == "player":
			t2 += 1
	check("snitch who dislikes you tells the truth", t2 > 90, str(t2))
	var empty := Memory.new()
	var r3 := Testimony.answer("c", Data.traits_for("serious"), empty, rel, act, ["a", "b", "c", "player"], rng)
	check("honest non-witness says nothing", r3.kind == "nothing", str(r3))
	var coward := Data.traits_for("coward")
	var act2 := {"id": 8, "actor": "b", "zone": "open_space", "kind": "x", "sev": 1}
	var lies := 0
	for i in 50:
		if Testimony.answer("b", coward, empty, rel, act2, ["a", "b", "c", "player"], rng, 1.0).kind == "lie":
			lies += 1
	check("guilty coward blames someone", lies > 25, str(lies))
	check("report chance higher for snitch than loyal", Testimony.report_chance("x", snitch, rel, empty, "c", 2, "") > Testimony.report_chance("x", loyal, rel, empty, "c", 2, ""))


func test_economy() -> void:
	var e := Economy.new()
	e.setup_peer("p", 100, 1)
	check("tier lock", e.can_buy("p", "confettis") != "")
	check("affordable", e.can_buy("p", "canard") == "")
	e.setup_peer("q", 10, 3)
	check("too expensive", e.can_buy("q", "coussin_peteur") != "")
	var c := Character.new()
	add_child(c)
	e.setup_peer("r", 500, 3)
	check("buy ok", e.buy("r", "canard", c) == "" and c.has_item("canard") and e.money("r") == 480)
	check("passive owned once", e.buy("r", "sac_sport", c) == "" and e.can_buy("r", "sac_sport") != "")
	check("pocket capacity +2 with bag", c.add_item("a") and c.add_item("b") and c.add_item("c") and c.add_item("d") and c.add_item("e"))
	e.return_pocket("r", c)
	check("pocket returned to stock", c.items.is_empty() and int(e.stock.r.get("canard", 0)) == 1)
	c.queue_free()


func test_day() -> void:
	var d := DayManager.new()
	d.setup(9.0)
	check("time scale 60x for 9 min", is_equal_approx(d.time_scale(), 60.0))
	d.tick(90.0)
	check("10:30 meeting active", d.meeting_active, d.clock_text())
	d.tick(41.0 * 60.0 / 60.0)
	check("meeting over at 11:11", not d.meeting_active, d.clock_text())
	d.tick(1000.0)
	check("day over", d.is_over())


func test_events() -> void:
	var ed := EventDirector.new()
	ed.rng.seed = 3
	for i in 50:
		var id := ed.pick(1000.0 + i * 1000.0, {"meeting": true, "player_level": 0})
		if id != "":
			check("no 'not_meeting' event during meeting (%s)" % id, not Data.random_events[id].get("requires", {}).get("not_meeting", false))
	var ed2 := EventDirector.new()
	ed2.start("inspection", 0.0)
	var id2 := ed2.pick(5000.0, {"meeting": false})
	check("no two hard events in a row", id2 == "" or int(Data.random_events[id2].difficulty) < 2, id2)
	check("timed event active", ed2.active("inspection"))
	ed2.tick(1000.0, 0.1, {})
	check("timed event ends", not ed2.active("inspection"))


func test_barks() -> void:
	var b := Barks.new()
	b.rng.seed = 5
	var prev := ""
	var repeats := 0
	for i in 40:
		var l := b.pick("chat", {"name": "X"})
		if l == prev:
			repeats += 1
		prev = l
	check("no immediate repetition", repeats == 0)
	check("slot filling", not b.pick("testimony_truth", {"name": "Kévin"}).contains("{name}"))


func test_perception_helpers() -> void:
	check("color blue", Perception.color_name(Color("#2f4f8f")) == "bleue")
	check("color white", Perception.color_name(Color("#f2f2f2")) == "claire")
	check("color orange", Perception.color_name(Color("#e07a2e")) == "orange")


func test_mission_pick() -> void:
	var rng := RandomNumberGenerator.new()
	for d in [1, 2, 5]:
		rng.seed = d
		var ids := MissionSystem.pick_for_day(d, rng, [], 4)
		check("4 missions day %d" % d, ids.size() == 4)
		var t1 := false
		for id in ids:
			if int(Data.missions[id].tier) == 1:
				t1 = true
			if d == 1:
				check("day 1 only tier 1 (%s)" % id, int(Data.missions[id].tier) == 1)
		check("at least one tier-1 mission", t1)
