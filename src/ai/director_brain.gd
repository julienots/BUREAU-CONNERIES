class_name DirectorBrain
extends Node
## The director AI. Not omniscient: he only knows what he sees (cone + raycasts +
## progressive attention), hears (attenuated by walls, no identity), finds (displaced
## objects, pranked devices) or is told (testimonies of variable reliability). Five
## profiles change thresholds and priorities. Suspicion builds into confrontations.

var c: Character
var s: Node
var mem: Memory
var sus := Suspicion.new()
var profile_id := "authoritarian"
var prof: Dictionary = {}
var rng := RandomNumberGenerator.new()

var state := "office"
var step := 0
var timer := 0.0
var data: Dictionary = {}
var _tick := 0.0
var _scan_t := 0.0
var _anomaly_t := 0.0
var awareness: Dictionary = {}        # char_id -> 0..1 attention build-up
var stimulus: Dictionary = {}         # pending investigation {pos, kind, loud, time, act_id}
var noticed: Dictionary = {}          # ent_id -> true (anomalies already handled)
var distracted_by := ""
var distracted_until := 0.0
var listening_until := 0.0
var _last_bark := -100.0
var fov := 110.0
var view_range := 17.0
var confront_cooldown := 0.0
var reports_received := 0
var questioned: Dictionary = {}       # act_id -> true
var present_at_meeting: Dictionary = {}
## Human director (multiplayer): perception and ledger only, no autonomous decisions.
var observer := false


func setup(ch: Character, session: Node, profile: String, seed: int) -> void:
	c = ch
	s = session
	profile_id = profile
	prof = Data.director_profiles.get(profile, Data.director_profiles.get("authoritarian", {}))
	rng.seed = seed
	var cap := int(float(prof.get("memory", 12)) * float(Settings.get_v("boss_memory")))
	mem = Memory.new(maxi(3, cap))
	sus.gain = float(prof.get("suspicion_gain", 1.0)) * float(Settings.get_v("difficulty"))
	sus.decay_per_min = 3.0 * float(prof.get("decay", 1.0))


func _physics_process(delta: float) -> void:
	if c == null or s == null or not s.running:
		return
	timer -= delta
	confront_cooldown -= delta
	sus.tick(delta * s.day.time_scale() / 6.0)
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = 0.2
		_scan(0.2)
	if observer:
		return
	_tick -= delta
	if _tick <= 0.0:
		_tick = 0.25
		_think()


# ------------------------------------------------------------------ vision
func _current_fov() -> float:
	if state == "phone":
		return 70.0
	if state == "distracted":
		return 50.0
	if state == "meeting":
		return 60.0 if data.get("board", false) else 120.0
	return fov


func _current_range() -> float:
	var r := view_range
	if state in ["phone", "distracted"]:
		r *= 0.5
	return r


func _scan(dt: float) -> void:
	if c.is_down():
		return
	var now: float = s.now()
	var my_zone: String = s.world.zone_at(c.global_position)
	for e in s.employees():
		var ec: Character = e
		var vis := Perception.visibility(s.world, c, ec, _current_fov(), _current_range())
		var a := float(awareness.get(ec.id, 0.0))
		if vis <= 0.0:
			awareness[ec.id] = maxf(0.0, a - dt * 0.25)
			continue
		mem.see(ec.id, s.world.zone_at(ec.global_position), ec.global_position, now)
		var bad := _badness(ec, my_zone)
		if bad <= 0.0:
			awareness[ec.id] = maxf(0.0, a - dt * 0.4)
		else:
			var gain := 2.4 * float(prof.get("suspicion_gain", 1.0)) * float(Settings.get_v("difficulty"))
			a += vis * bad * gain * dt * (1.6 if c.global_position.distance_to(ec.global_position) < 5.0 else 1.0)
			awareness[ec.id] = a
			if a >= 1.0:
				awareness[ec.id] = 0.25
				_caught(ec, bad)
		s.update_alert(c, ec, float(awareness.get(ec.id, 0.0)))
	# anomalies (moved objects, pranked devices) — slower
	_anomaly_t -= dt
	if _anomaly_t <= 0.0:
		_anomaly_t = 1.0
		_scan_anomalies()


## How suspicious what this employee is doing right now looks (0 = nothing).
func _badness(e: Character, my_zone: String) -> float:
	var b := 0.0
	if e.action.size() > 0:
		b = maxf(b, float(e.action.get("def", {}).get("sus", 0.0)))
	var z: String = s.world.zone_at(e.global_position)
	if z == "boss_office" and my_zone != "boss_office":
		b = maxf(b, 0.55)
	elif z == "boss_office":
		b = maxf(b, 0.3)
	if e.held:
		b = maxf(b, e.held.contraband * 0.8)
		if "chair" in e.held.tags and e.held.owner_id != e.id:
			b = maxf(b, 0.3)
	if e.visible_contraband() > 0.4:
		b = maxf(b, e.visible_contraband() * 0.45)
	if e.velocity.length() > 2.6:
		b = maxf(b, 0.22)
	if e.want_crouch and e.seated_on == null:
		b = maxf(b, 0.35)
	if e.get_meta("slacking", false):
		b = maxf(b, 0.6)
	if e.pretending_until > s.now() and s.now() - e.last_work_time > 80.0 and c.global_position.distance_to(e.global_position) < 4.5:
		b = maxf(b, 0.4 * float(prof.get("inspect_bias", 0.5)) + 0.15)
	if e.seated_on and e.humanoid.typing:
		b *= 0.3
	return b


func _caught(e: Character, bad: float) -> void:
	var now: float = s.now()
	if observer:
		var cur: Dictionary = e.action.get("def", {})
		if cur.get("prank", false):
			var a0: Dictionary = s.interrupt_and_commit(e)
			if not a0.is_empty():
				sus.set_confirmed(e.id, int(a0.id), now)
				s.director_note("Tu as surpris %s : %s" % [e.nick, s.act_description(a0).replace("On vous soupçonne de : ", "")])
		else:
			sus.add(e.id, 10.0 + bad * 22.0, "seen", -1, "boss", now)
			s.director_note("%s a un comportement suspect." % e.nick)
		return
	if e.action.size() > 0 and e.action.get("def", {}).get("prank", false):
		# caught red-handed: the act is interrupted and confirmed
		var act: Dictionary = s.interrupt_and_commit(e)
		if not act.is_empty():
			sus.set_confirmed(e.id, int(act.id), now)
			_bark("boss_caught", "angry")
			c.do_emote("angry", 2.0)
			s.change_trust(e.id, -15.0, "pris sur le fait")
			s.notify_caught(e, "Le directeur t'a vu faire !")
			_go_confront(e.id, int(act.id), true)
			return
	if e.get_meta("slacking", false):
		var act2: Dictionary = s.record_act(e, "slacking", 1, e.global_position, "")
		sus.set_confirmed(e.id, int(act2.id), now)
		_go_confront(e.id, int(act2.id), true)
		return
	var z: String = s.world.zone_at(e.global_position)
	var amount := 10.0 + bad * 22.0
	var act_id := -1
	if z == "boss_office":
		var act3: Dictionary = s.record_act(e, "trespass", 2, e.global_position, "")
		act_id = int(act3.id)
		amount += 15.0
	sus.add(e.id, amount, "seen", act_id, "boss", now)
	s.on_suspicion_changed(e.id)
	s.change_trust(e.id, -4.0 - (5.0 if z == "boss_office" else 0.0), "comportement louche")
	c.look_at_point(e.eye_position())
	c.do_emote("suspicious", 2.0)
	_bark("boss_suspicious", "suspicious")


func _scan_anomalies() -> void:
	var eye := c.eye_position()
	for e in s.world.interactables:
		if not is_instance_valid(e):
			continue
		var id: String = e.ent_id()
		if noticed.get(id, false):
			continue
		var p: Vector3 = e.interact_point() if e.has_method("interact_point") else e.global_position
		if p.distance_to(eye) > 7.5:
			continue
		var issue := ""
		if e is Prop:
			var pr := e as Prop
			if not pr.is_available() or pr.held_by:
				continue
			if pr.home_distance() > 1.8 and (("chair" in pr.tags and pr.occupant == "") or "plant" in pr.tags or "duck" in pr.tags or "boss_mug" in pr.tags):
				issue = "moved"
			elif "cushion" in pr.tags or "duck" in pr.tags and s.world.zone_at(pr.global_position) == "meeting":
				issue = "gadget"
		elif e is Device:
			var d := e as Device
			if d.kind == "whiteboard" and d.state.get("caricature", false):
				issue = "caricature"
			elif d.kind == "pc" and d.owner_id != "boss" and (d.state.get("wallpaper", "") != "" or d.state.get("postits", false)):
				issue = "pc"
			elif d.kind == "planning" and d.state.get("fake", false):
				issue = "planning"
			elif d.kind == "shelf_files" and d.state.get("mixed", false):
				issue = "files"
		if issue == "":
			continue
		var to := p - eye
		var f := Perception.view_dir(c)
		if f.dot(Vector3(to.x, 0, to.z).normalized()) < cos(deg_to_rad(_current_fov() * 0.5)):
			continue
		var excl: Array[RID] = [c.get_rid()]
		if not s.world.line_clear(eye, p, excl):
			continue
		noticed[id] = true
		_on_anomaly(e, issue)
		return


func _on_anomaly(e: Node, issue: String) -> void:
	if observer:
		s.director_note("Anomalie repérée : %s (%s)" % [e.display_name(), s.world.zone_name(s.world.zone_at(e.global_position))])
		if issue == "caricature":
			s.npc_reaction(c, "saw_caricature", {"by": String((e as Device).state.get("by", "")) if e is Device else ""})
		var a1: Dictionary = s.act_for_entity(e.ent_id())
		if not a1.is_empty():
			for who in mem.seen_near(a1.zone, float(a1.time), 30.0):
				if s.is_employee(who):
					sus.add(who, 7.0, "near", int(a1.id), "boss", s.now())
		return
	c.look_at_point(e.interact_point() if e.has_method("interact_point") else e.global_position)
	if issue == "caricature":
		_bark("boss_caricature", "angry")
		c.do_emote("angry", 3.0)
		s.npc_reaction(c, "saw_caricature", {"by": String((e as Device).state.get("by", "")) if e is Device else ""})
	else:
		_bark("boss_anomaly", "suspicious")
		c.do_emote("suspicious", 2.5)
	var act: Dictionary = s.act_for_entity(e.ent_id())
	if act.is_empty():
		return
	mem.incident_zones[act.zone] = int(mem.incident_zones.get(act.zone, 0)) + 1
	_incident(act, e.interact_point() if e.has_method("interact_point") else e.global_position)


## An incident is known (found or heard) but the culprit is not: circumstantial
## suspicion on whoever he remembers near the place at that time, then questioning.
func _incident(act: Dictionary, where: Vector3) -> void:
	var now: float = s.now()
	var near: Array[String] = mem.seen_near(act.zone, float(act.time), 30.0)
	for who in near:
		if who == c.id or not s.is_employee(who):
			continue
		sus.add(who, 7.0, "near", int(act.id), "boss", now)
		s.on_suspicion_changed(who)
	if not questioned.get(int(act.id), false) and state in ["office", "patrol", "search", "investigate"]:
		questioned[int(act.id)] = true
		var w := _nearest_witness(where, 12.0)
		if w != "":
			_switch("question", {"who": w, "act": act})


func _nearest_witness(where: Vector3, radius: float) -> String:
	var best := ""
	var bd := radius
	for id in s.npc_ids():
		var nc: Character = s.characters[id]
		var d := nc.global_position.distance_to(where)
		if d < bd and not nc.is_down():
			bd = d
			best = id
	return best


# ------------------------------------------------------------------ hearing
const INTERESTING := ["slam", "fart", "crash", "break", "papers", "printer", "buzzer", "confetti", "fall", "laugh", "radio", "impact", "phone"]


func on_hear(ev: Dictionary, perceived: float) -> void:
	if observer:
		return
	var kind: String = ev.kind
	var threshold := 34.0 / float(prof.get("hearing", 1.0))
	if kind == "footstep":
		if perceived > 30.0 and state in ["office", "patrol"]:
			c.look_at_point(ev.pos + Vector3(0, 1, 0))
		return
	if not kind in INTERESTING or perceived < threshold:
		return
	if kind == "phone" and perceived < 50.0:
		return
	if kind == "radio" and not ev.get("loud", false) and perceived < 45.0:
		return
	mem.hear(kind, ev.pos, ev.zone, perceived, s.now())
	c.look_at_point(ev.pos + Vector3(0, 0.8, 0))
	if state in ["meeting", "confront", "question", "vip", "listen", "escort"]:
		return
	if state == "distracted" and rng.randf() > 0.25:
		return
	if state == "phone" and perceived < 60.0:
		return
	if stimulus.is_empty() or perceived > float(stimulus.get("loud", 0.0)) or s.now() - float(stimulus.get("time", 0.0)) > 20.0:
		stimulus = {"pos": ev.pos, "kind": kind, "loud": perceived, "time": s.now(), "zone": ev.zone, "source": ev.get("source", "")}
		if kind == "fart" and ev.get("victim", "") == c.id:
			return
		_bark("boss_hear", "surprised")


# ------------------------------------------------------------------ witnessing & reports
func on_witness(act: Dictionary, info: Dictionary) -> void:
	var now: float = s.now()
	mem.remember_act(act, info.id, info.desc, info.conf, now)
	if info.id == "" or not s.is_employee(info.id):
		return
	if observer:
		sus.add(info.id, 25.0 * float(info.conf) + 8.0 * int(act.sev), "seen", int(act.id), "boss", now)
		s.director_note("Tu as vu %s : %s" % [s.char_name(info.id), s.act_description(act).replace("On vous soupçonne de : ", "")])
		return
	s.change_trust(info.id, -8.0, "bêtise repérée")
	if (state == "meeting" and s.day.meeting_active or state == "escort") and float(info.conf) > 0.6:
		# he will not leave his own meeting: noted now, dealt with afterwards
		sus.set_confirmed(info.id, int(act.id), now)
		sus.add(info.id, 10.0 * int(act.sev), "seen", int(act.id), "boss", now)
		s.on_suspicion_changed(info.id)
		s.notify_caught(s.characters.get(info.id), "Le directeur t'a vu ! Il s'occupera de toi plus tard…")
		return
	if float(info.conf) > 0.6:
		sus.set_confirmed(info.id, int(act.id), now)
		_bark("boss_caught", "angry")
		s.notify_caught(s.characters.get(info.id), "Le directeur t'a vu !")
		_go_confront(info.id, int(act.id), true)
	else:
		sus.add(info.id, 25.0 * float(info.conf) + 8.0 * int(act.sev), "seen", int(act.id), "boss", now)
		s.on_suspicion_changed(info.id)


## A coworker (or player) tells him something. Weighted by how much he trusts them.
func on_testimony(witness: String, accused: String, act_id: int, kind: String, now: float) -> void:
	reports_received += 1
	listening_until = now + 3.0
	if observer:
		s.director_note("%s accuse %s." % [s.char_name(witness), s.char_name(accused)])
	if accused == "" or not s.is_employee(accused):
		return
	var act: Dictionary = s.act_by_id(act_id)
	# alibi check: did he see the accused somewhere else at that time?
	if not act.is_empty():
		var seen := mem.where_was(accused, float(act.time), 6.0)
		if not seen.is_empty() and seen.zone != act.zone:
			sus.adjust_trust(witness, -0.25)
			if s.is_employee(witness):
				sus.add(witness, 12.0, "false_accusation", act_id, "boss", now)
				s.change_trust(witness, -10.0, "fausse accusation")
				s.on_suspicion_changed(witness)
			s.game_event("testimony_refuted", {"witness": witness, "accused": accused, "act_id": act_id})
			return
	var w := sus.trust(witness) * (1.0 if kind in ["truth", "report"] else 0.7)
	sus.add(accused, 30.0 * w, "testimony", act_id, witness, now)
	s.on_suspicion_changed(accused)


# ------------------------------------------------------------------ decisions
func _think() -> void:
	if c.is_down():
		if state != "down":
			_switch("down")
		return
	if state == "down":
		_switch("office")
	var now: float = s.now()
	if now < listening_until:
		c.stop()
		return
	if state in ["confront", "interrogating"]:
		_run()
		return
	if distracted_by != "" and now < distracted_until:
		if state != "distracted":
			_switch("distracted")
		_run()
		return
	elif distracted_by != "":
		distracted_by = ""
		s.end_diversion(null)
		_bark("boss_distracted", "neutral")
		_switch("patrol")
	if s.day.meeting_active:
		if state != "meeting":
			_switch("meeting")
		_run()
		return
	if s.pdg_active():
		if state != "escort":
			_switch("escort")
		_run()
		return
	if s.events.active("boss_call"):
		if state != "phone":
			_switch("phone")
		_run()
		return
	if s.events.active("vip_visit"):
		if state != "vip":
			_switch("vip")
		_run()
		return
	if s.events.active("inspection"):
		if state != "inspection":
			_switch("inspection")
		_run()
		return
	if s.events.active("boss_stays") and state != "stay":
		_switch("stay")
	if s.events.active("croissants") and float(prof.get("distraction_time", 1.0)) > 1.2 and state in ["patrol", "office"] and rng.randf() < 0.02:
		_switch("go_croissants")
	# confrontation when the evidence is strong enough
	if confront_cooldown <= 0.0 and state in ["office", "patrol", "search", "investigate", "stay", "trap"]:
		var who := _confrontable()
		if who != "":
			_go_confront(who, sus.best_act(who), false)
			_run()
			return
	if not stimulus.is_empty() and state in ["office", "patrol", "stay", "trap", "search"] and now - float(stimulus.time) < 25.0:
		_switch("investigate", stimulus)
		stimulus = {}
	_run()


func _confrontable() -> String:
	var need_level := int(prof.get("confront_level", 4))
	var need_src := int(prof.get("evidence_needed", 1))
	var best := ""
	var bs := 0.0
	for e in s.employees():
		var id: String = e.id
		if sus.level(id) >= need_level and (sus.sources(id) >= need_src or sus.has_direct(id)) and sus.best_act(id) >= 0:
			if sus.score(id) > bs:
				bs = sus.score(id)
				best = id
	return best


func _go_confront(who: String, act_id: int, urgent: bool) -> void:
	if state in ["confront", "interrogating"] or act_id < 0:
		return
	_switch("confront", {"who": who, "act_id": act_id, "urgent": urgent})


func _switch(st: String, d := {}) -> void:
	if c.seated_on and st != "office":
		c.stand_up()
	s.world.release_poi(c.id)
	state = st
	step = 0
	data = d
	timer = 0.0
	c.clear_look()
	c.face_dir = Vector3.ZERO
	c.want_crouch = false
	c.humanoid.typing = false


func _run() -> void:
	match state:
		"office":
			_st_office()
		"patrol":
			_st_patrol()
		"investigate":
			_st_investigate()
		"search":
			_st_search()
		"question":
			_st_question()
		"confront":
			_st_confront()
		"interrogating":
			c.stop()
		"meeting":
			_st_meeting()
		"escort":
			_st_escort()
		"phone":
			_st_spot("boss_phone", "phone", "boss_phone")
		"vip":
			_st_spot("boss_desk", "", "")
		"stay":
			_st_stay()
		"inspection":
			_st_inspection()
		"distracted":
			_st_distracted()
		"trap":
			_st_trap()
		"go_croissants":
			_st_croissants()
		"down":
			pass


func _st_office() -> void:
	var desk: Dictionary = s.world.desk_of("boss")
	match step:
		0:
			c.go_to(desk.seat + Vector3(-0.6, 0, 0))
			step = 1
			timer = 40.0
		1:
			if c.arrived(0.8) or timer <= 0.0:
				var chair: Prop = s.world.ent(desk.chair_id)
				if chair and chair.occupant == "" and chair.global_position.distance_to(desk.seat) < 2.5:
					c.sit_on(chair)
				timer = rng.randf_range(15.0, 35.0) / float(prof.get("patrol_rate", 1.0))
				step = 2
				_check_mug()
		2:
			c.humanoid.typing = c.seated_on != null
			if rng.randf() < 0.01:
				s.boss_opens_drawer(c)
			if timer <= 0.0:
				var trap_p := float(prof.get("trap_bias", 0.0))
				_switch("trap" if rng.randf() < trap_p * 0.5 else "patrol")


func _check_mug() -> void:
	for p in s.world.props_with_tag("boss_mug"):
		if (p as Prop).home_distance() > 1.5 or not (p as Prop).is_available():
			if not noticed.get("mug_missing", false):
				noticed["mug_missing"] = true
				_bark("boss_mug", "angry")
				c.do_emote("angry", 2.5)
				var act: Dictionary = s.act_for_entity(p.ent_id())
				if not act.is_empty():
					_incident(act, p.home.origin)


func _st_patrol() -> void:
	match step:
		0:
			var pts: Array = s.world.poi.get("patrol", []) + s.world.poi.get("patrol_rooms", [])
			# zones with past trouble are visited more often
			var best: Dictionary = pts[rng.randi() % pts.size()]
			for i in 3:
				var cand: Dictionary = pts[rng.randi() % pts.size()]
				if int(mem.incident_zones.get(cand.zone, 0)) > int(mem.incident_zones.get(best.zone, 0)):
					best = cand
			c.go_to(best.pos)
			data.n = int(data.get("n", 0))
			step = 1
			timer = 35.0
		1:
			if c.arrived(0.8) or timer <= 0.0:
				timer = rng.randf_range(1.5, 3.5)
				step = 2
				if rng.randf() < 0.25:
					_bark("boss_patrol", "neutral")
		2:
			var a: float = sin(s.now() * 1.3) * 1.4
			c.look_at_point(c.global_position + Vector3(sin(c.rotation.y + a), 0, cos(c.rotation.y + a)) * -4.0 + Vector3(0, 1.4, 0))
			if timer <= 0.0:
				data.n = int(data.n) + 1
				if int(data.n) >= 3 + rng.randi() % 3:
					_switch("office")
				else:
					step = 0
					c.clear_look()


func _st_investigate() -> void:
	match step:
		0:
			c.go_to(s.world.nav_closest(data.pos), float(data.get("loud", 0.0)) > 65.0)
			step = 1
			timer = 30.0
		1:
			if c.global_position.distance_to(data.pos) < 3.0 or c.arrived(1.2) or timer <= 0.0:
				c.stop()
				_switch("search", {"pos": data.pos, "zone": data.get("zone", ""), "source": data.get("source", "")})


func _st_search() -> void:
	match step:
		0:
			timer = 4.0 / float(prof.get("distraction_time", 1.0)) + 1.0
			step = 1
			c.do_emote("suspicious", 2.0)
			_bark("boss_investigate", "angry")
		1:
			var a: float = s.now() * 1.7
			c.look_at_point(data.pos + Vector3(sin(a) * 3.0, 0.8, cos(a) * 3.0))
			if timer <= 0.0:
				# the noise came from an act? -> incident with circumstantial suspects
				var act: Dictionary = s.recent_act_in_zone(String(data.zone), 40.0)
				if not act.is_empty():
					var now: float = s.now()
					for e in s.employees():
						var ec: Character = e
						if ec.global_position.distance_to(data.pos) < 7.0 and Perception.visibility(s.world, c, ec, 200.0, 9.0) > 0.0:
							sus.add(ec.id, 9.0, "near", int(act.id), "boss", now)
							s.on_suspicion_changed(ec.id)
					_incident(act, data.pos)
					if state == "search":
						_switch("patrol")
				else:
					_switch("patrol")


func _st_question() -> void:
	var w: Character = s.characters.get(data.who)
	if w == null:
		_switch("patrol")
		return
	match step:
		0:
			c.go_to(w.global_position)
			step = 1
			timer = 25.0
		1:
			if c.global_position.distance_to(w.global_position) < 1.9:
				c.stop()
				c.face_dir = (w.global_position - c.global_position).normalized()
				c.look_at_point(w.eye_position())
				_bark("boss_investigate", "suspicious")
				timer = 1.6
				step = 2
			elif timer <= 0.0:
				_switch("patrol")
			elif rng.randf() < 0.25:
				c.go_to(w.global_position)
		2:
			if timer <= 0.0:
				s.question_witness(c, w, data.act)
				timer = 3.0
				step = 3
		3:
			if timer <= 0.0:
				_switch("patrol")


func _st_confront() -> void:
	var who: Character = s.characters.get(data.who)
	if who == null:
		_switch("patrol")
		return
	match step:
		0:
			c.go_to(who.global_position, bool(data.get("urgent", false)))
			step = 1
			timer = 40.0
			data.repath = 0.0
		1:
			data.repath = float(data.repath) - 0.25
			if float(data.repath) <= 0.0:
				data.repath = 0.8
				c.go_to(who.global_position, bool(data.get("urgent", false)) or c.global_position.distance_to(who.global_position) > 8.0)
			if c.global_position.distance_to(who.global_position) < 1.9 and not who.is_down():
				c.stop()
				c.face_dir = (who.global_position - c.global_position).normalized()
				c.look_at_point(who.eye_position())
				state = "interrogating"
				s.start_interrogation(c, who, int(data.act_id), sus.strength(who.id, int(data.act_id)))
			elif timer <= 0.0:
				confront_cooldown = 20.0
				_switch("patrol")


## Called by the session once an interrogation is resolved.
func on_interrogation_done(who: String, act_id: int, outcome: String) -> void:
	confront_cooldown = 25.0 + rng.randf() * 15.0
	match outcome:
		"sanctioned":
			sus.clear_act(who, act_id)
			sus.scores[who] = maxf(0.0, sus.score(who) - 40.0)
			_bark("boss_sanction", "angry")
		"cleared":
			sus.clear_act(who, act_id)
			sus.scores[who] = maxf(0.0, sus.score(who) - 25.0)
			_bark("boss_clear", "neutral")
		"redirected":
			sus.clear_act(who, act_id)
			sus.scores[who] = maxf(0.0, sus.score(who) - 20.0)
	_switch("patrol")


func _st_meeting() -> void:
	match step:
		0:
			var p: Dictionary = s.world.poi.get("meeting_boss", [{}])[0]
			c.go_to(p.get("pos", Vector3(1, 0, -11)))
			step = 1
			timer = 40.0
			present_at_meeting.clear()
		1:
			if c.arrived(0.8) or timer <= 0.0:
				c.face_dir = Vector3.RIGHT
				step = 2
				timer = 55.0
				_bark("boss_meeting", "neutral")
		2:
			# alternates between talking to the table and writing on the whiteboard (back turned:
			# that is the window for meeting antics)
			var now: float = s.now()
			if not data.has("ph_until"):
				data.ph_until = now + rng.randf_range(6.0, 10.0)
				data.board = false
			if now >= float(data.ph_until):
				_set_board(not data.get("board", false))
			if data.get("board", false):
				c.look_at_point(Vector3(0.3, 1.5, -11.0 + sin(now * 0.8) * 0.6))
				if rng.randf() < 0.2:
					s.emit_sound(c.global_position + Vector3(-0.6, 1.4, 0), 24.0, "marker_squeak", "", "")
			else:
				c.look_at_point(Vector3(6.5, 1.2, -11) + Vector3(sin(now * 0.5) * 2.5, 0, 0))
				if rng.randf() < 0.012:
					_bark("boss_meeting", "neutral")
					c.do_emote("point", 1.5)
			if timer <= 0.0 and not data.get("roll_call", false):
				# absentees are noted (that is the price of using the meeting as cover)
				data.roll_call = true
				for e in s.employees():
					var ec: Character = e
					if s.world.zone_at(ec.global_position) != "meeting":
						sus.add(ec.id, 6.0, "absent_meeting", -1, "boss", s.now())
						s.on_suspicion_changed(ec.id)
						s.change_trust(ec.id, -6.0, "absent en réunion")
					else:
						s.change_trust(ec.id, 4.0, "présent en réunion")


## CEO visit: sticks to the CEO, sucks up, and keeps an eye out for trouble around him.
func _st_escort() -> void:
	var p: Character = s.pdg
	if p == null:
		_switch("patrol")
		return
	var back := -p.forward()
	var spot: Vector3 = p.global_position + back * 1.3 + back.cross(Vector3.UP) * 0.7
	if c.global_position.distance_to(spot) > 1.2:
		if timer <= 0.0:
			timer = 0.6
			c.go_to(s.world.nav_closest(spot), c.global_position.distance_to(spot) > 5.0)
	else:
		c.stop()
		c.look_at_point(p.eye_position() if rng.randf() < 0.6 else c.global_position + c.forward() * 4.0 + Vector3(0, 1.4, 0))
	if rng.randf() < 0.012:
		_bark("boss_pdg", "happy")


func _set_board(on: bool) -> void:
	data.board = on
	data.ph_until = s.now() + (rng.randf_range(5.0, 8.0) if on else rng.randf_range(8.0, 15.0))
	c.face_dir = Vector3.LEFT if on else Vector3.RIGHT
	if on:
		_bark("boss_board", "neutral")
	s.on_board_phase(on)


## Laughter / noise in the meeting: the director turns around at once.
func meeting_disrupted(suspect: String) -> void:
	if observer or state != "meeting" or step < 2:
		return
	if data.get("board", false):
		_set_board(false)
	_last_bark = -100.0
	_bark("boss_meeting_disrupt", "angry")
	c.do_emote("angry", 2.0)
	if suspect != "" and rng.randf() < 0.5:
		sus.add(suspect, 4.0, "meeting_disrupt", -1, "boss", s.now())
		s.on_suspicion_changed(suspect)


func _st_spot(kind: String, emote: String, cat: String) -> void:
	match step:
		0:
			var p: Array = s.world.poi.get(kind, [])
			if p.is_empty():
				_switch("office")
				return
			c.go_to(p[0].pos)
			data.facing = p[0].facing
			step = 1
			timer = 40.0
		1:
			if c.arrived(0.7) or timer <= 0.0:
				c.face_dir = data.facing
				step = 2
		2:
			if emote != "":
				c.do_emote(emote, 1.0)
			if cat != "" and rng.randf() < 0.03:
				_bark(cat, "happy" if rng.randf() < 0.5 else "neutral")


func _st_stay() -> void:
	if not s.events.active("boss_stays"):
		_switch("patrol")
		return
	match step:
		0:
			var p: Array = s.world.poi.get("boss_stand", [])
			c.go_to(p[0].pos if not p.is_empty() else Vector3(5, 0, 1.7))
			step = 1
			timer = 40.0
		1:
			if c.arrived(0.7) or timer <= 0.0:
				c.face_dir = Vector3(0, 0, 1).rotated(Vector3.UP, PI * 0.25)
				step = 2
		2:
			var a: float = sin(s.now() * 0.4) * 1.2
			c.look_at_point(c.global_position + Vector3(-sin(a) * 5.0, 1.2, 4.0))


func _st_inspection() -> void:
	match step:
		0:
			_bark("boss_inspection", "angry")
			var list: Array = []
			for d in s.world.desks:
				if d.owner != "" and d.owner != "boss":
					list.append(d)
			list.shuffle()
			data.list = list
			data.i = 0
			step = 1
		1:
			if int(data.i) >= data.list.size():
				s.events.finish("inspection")
				_switch("patrol")
				return
			var d: Dictionary = data.list[int(data.i)]
			c.go_to(d.seat + d.facing * -1.0)
			data.cur = d
			step = 2
			timer = 25.0
		2:
			if c.arrived(0.8) or timer <= 0.0:
				c.stop()
				c.look_at_point(data.cur.pos + Vector3(0, 0.9, 0))
				timer = 2.5
				step = 3
		3:
			if timer <= 0.0:
				s.inspect_desk(c, data.cur, self)
				data.i = int(data.i) + 1
				step = 1


func _st_distracted() -> void:
	var dc: Character = s.characters.get(distracted_by)
	c.stop()
	if dc:
		c.face_dir = (dc.global_position - c.global_position).normalized()
		c.look_at_point(dc.eye_position())
		if rng.randf() < 0.03:
			_bark("boss_suspicious" if rng.randf() < 0.3 else "boss_patrol", "neutral")


func _st_trap() -> void:
	# Manipulator: pretends to leave, then sneaks back to watch from cover.
	match step:
		0:
			s.npc_say(c, "Je m'absente une heure. Soyez sages !", "happy")
			c.go_to(Vector3(-20.5, 0, -6.5))
			step = 1
			timer = 40.0
		1:
			if c.arrived(1.0) or timer <= 0.0:
				timer = 8.0
				step = 2
		2:
			if timer <= 0.0:
				c.want_crouch = true
				c.go_to(Vector3(-11.5, 0, 6.0))
				timer = 30.0
				step = 3
		3:
			if c.arrived(1.0) or timer <= 0.0:
				c.stop()
				c.face_dir = Vector3(1, 0, -1).normalized()
				timer = 30.0
				step = 4
		4:
			var a: float = sin(s.now() * 0.6) * 1.0
			c.look_at_point(c.global_position + Vector3(cos(a) * 6.0, 1.0, -sin(a) * 6.0))
			if timer <= 0.0:
				c.want_crouch = false
				_switch("patrol")


func _st_croissants() -> void:
	match step:
		0:
			c.go_to(s.world.random_point_in_zone("break"))
			step = 1
			timer = 30.0
			_bark("boss_distracted", "happy")
		1:
			if c.arrived(1.0) or timer <= 0.0:
				c.do_emote("drink", 10.0)
				timer = 12.0 * float(prof.get("distraction_time", 1.0))
				step = 2
		2:
			if timer <= 0.0:
				_switch("patrol")


func distract(by: String, dur: float) -> void:
	distracted_by = by
	distracted_until = s.now() + dur * float(prof.get("distraction_time", 1.0))


func _bark(cat: String, emotion: String) -> void:
	if observer:
		return
	var now: float = s.now()
	if now - _last_bark < 3.0:
		return
	_last_bark = now
	s.npc_say(c, s.barks.pick(cat), emotion)
