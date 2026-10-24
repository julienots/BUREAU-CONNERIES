class_name CoworkerBrain
extends Node
## Autonomous coworker. Utility-based activity selection (work, coffee, toilets, chat,
## printer, meetings, lunch) driven by needs, schedule and personality; interrupted by
## perception (noises, witnessed pranks, being pranked). Decides to gossip, report to
## the director, protect friends, lie, help the player as an accomplice, or slack off.

var c: Character
var s: Node                          # Session
var mem: Memory
var t: Dictionary                    # traits
var rng := RandomNumberGenerator.new()

var state := "idle"
var step := 0
var timer := 0.0
var data: Dictionary = {}
var needs := {"coffee": 0.0, "bladder": 0.0, "social": 0.0}
var _tick := 0.0
var _resume := ""
var pending: Array[Dictionary] = []          # witnessed acts awaiting a decision
var accomplice_for := ""
var believes_meeting_moved := false
var slacking := false
var bribed_by := ""
var _last_bark := -100.0
var _work_until := 0.0
var _last_noise_react := -100.0


func setup(ch: Character, session: Node, seed: int) -> void:
	c = ch
	s = session
	t = ch.traits
	rng.seed = seed
	mem = Memory.new(10 + int(float(t.get("observation", 0.5)) * 8))
	needs.coffee = rng.randf_range(0.0, 0.6)
	needs.bladder = rng.randf_range(0.0, 0.4)
	needs.social = rng.randf_range(0.0, 0.5)
	_tick = rng.randf() * 0.25


func _physics_process(delta: float) -> void:
	if c == null or not is_instance_valid(c) or s == null or not s.running:
		return
	timer -= delta
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 0.25
	_think(0.25)


# ------------------------------------------------------------------ core loop
func _think(dt: float) -> void:
	var game_dt: float = dt * s.day.time_scale()
	needs.coffee += game_dt / 3600.0 * (0.8 + rng.randf() * 0.4)
	needs.bladder += game_dt / 3600.0 * 0.5
	needs.social += game_dt / 3600.0 * (0.4 + float(t.get("gossip", 0.5)) * 0.6)
	_process_pending()
	if c.is_down():
		if state != "down":
			_switch("down")
		return
	if state == "down":
		_say_cat("react_fall_self", "embarrassed")
		_switch("idle")
	if s.director_interrogating(c.id):
		c.stop()
		return
	_run_state(dt)


func _switch(st: String, d := {}) -> void:
	if state == "work" and st != "work" and c.seated_on:
		c.stand_up()
	if state in ["meeting", "lunch", "slack_sofa", "work"] and c.seated_on and st != state:
		c.stand_up()
	s.world.release_poi(c.id)
	state = st
	step = 0
	data = d
	timer = 0.0
	c.humanoid.typing = false
	slacking = false
	c.set_meta("slacking", false)
	c.face_dir = Vector3.ZERO
	c.clear_look()


func _choose_activity() -> void:
	var day = s.day
	if day.meeting_active and not believes_meeting_moved and not data.get("skip_meeting", false):
		_switch("meeting")
		return
	if day.lunch_active:
		_switch("lunch")
		return
	if s.events.active("croissants") and rng.randf() < 0.7:
		_switch("go_zone", {"zone": "break", "dur": 25.0, "emote": "drink", "cat": "croissants"})
		return
	if s.events.active("lost_item") and s.events.data("lost_item").get("who", "") == c.id:
		_switch("search")
		return
	var scores := {
		"work": 1.0 + float(t.get("work", 0.5)) * 1.2 + float(s.rumor_effect(c.id, "work_harder")) * 0.8,
		"coffee": needs.coffee * 2.2,
		"toilet": needs.bladder * 2.0,
		"chat": needs.social * 1.6 * (1.0 - float(t.get("work", 0.5)) * 0.4) + float(s.rumor_effect(c.id, "relax")) * 0.6,
		"printer": 0.12 + rng.randf() * 0.1,
		"wander": 0.08 + float(t.get("laziness", 0.3)) * 0.2,
	}
	if s.find_device("radio") and s.find_device("radio").state.get("loud", false) and float(t.get("laziness", 0.3)) > 0.5:
		scores["party"] = 1.2
	var best := "work"
	var bv := -1.0
	for k in scores:
		var v: float = scores[k] + rng.randf() * 0.35
		if v > bv:
			bv = v
			best = k
	_switch(best)


func _run_state(dt: float) -> void:
	match state:
		"idle":
			_choose_activity()
		"work":
			_st_work()
		"fetch_chair":
			_st_fetch_chair()
		"coffee":
			_st_poi("coffee", 4.0, "coffee")
		"toilet":
			_st_poi("toilet", 6.0, "toilet")
		"printer":
			_st_poi("printer", 4.0, "printer")
		"chat":
			_st_chat()
		"wander":
			_st_wander()
		"meeting":
			_st_meeting()
		"lunch":
			_st_go_zone_generic("break", 40.0, "drink")
		"go_zone":
			_st_go_zone_generic(data.zone, float(data.get("dur", 20.0)), String(data.get("emote", "")))
		"investigate":
			_st_investigate()
		"react":
			if timer <= 0.0:
				c.clear_look()
				_switch(_resume if _resume != "" else "idle")
				_resume = ""
		"report":
			_st_report()
		"diversion":
			_st_diversion()
		"party":
			_st_party()
		"search":
			_st_search()
		"wrong_meeting":
			_st_wrong_meeting()
		"follow":
			_st_follow()


# ------------------------------------------------------------------ states
func _desk() -> Dictionary:
	return s.world.desk_of(c.id)


func _st_work() -> void:
	var d := _desk()
	if d.is_empty():
		_switch("wander")
		return
	match step:
		0:
			c.go_to(d.seat + d.facing * -0.35)
			step = 1
		1:
			if c.arrived(0.7):
				var chair: Prop = s.world.ent(d.chair_id)
				if chair == null or not chair.is_available() or chair.global_position.distance_to(d.seat) > 1.6 or chair.held_by:
					_say_cat("victim_chair", "angry")
					s.npc_reaction(c, "chair_missing", {"owner": c.id})
					_switch("fetch_chair")
					return
				if chair.occupant != "":
					_switch("wander")
					return
				c.sit_on(chair)
				_work_until = s.now() + rng.randf_range(35.0, 110.0) * (0.6 + float(t.get("work", 0.5)))
				step = 2
				timer = 1.2
		2:
			if c.seated_on == null:
				_switch("idle")
				return
			if timer > 0.0:
				return
			step = 3
			_check_desk_pranks()
		3:
			if c.seated_on == null:
				_switch("idle")
				return
			var pc: Device = s.world.ent(d.pc_id)
			var it_down: bool = pc != null and pc.state.get("it_down", false)
			# slacking (minor infraction the director can catch and others can denounce)
			if not slacking and rng.randf() < float(t.get("laziness", 0.3)) * 0.01 and not s.boss_near(c.global_position, 9.0):
				slacking = true
				c.set_meta("slacking", true)
				c.do_emote("sleep" if rng.randf() < 0.5 else "phone", 30.0)
				c.humanoid.typing = false
				s.npc_minor_infraction(c, "slacking")
			elif slacking and (s.boss_near(c.global_position, 6.0) and rng.randf() < 0.5 or rng.randf() < 0.02):
				slacking = false
				c.set_meta("slacking", false)
				c.do_emote("", 0.0)
			if not slacking:
				c.humanoid.typing = not it_down
				c.productivity = minf(100.0, c.productivity + 0.02)
			if s.now() > _work_until:
				_switch("idle")


func _check_desk_pranks() -> void:
	var d := _desk()
	var pc: Device = s.world.ent(d.pc_id)
	if pc == null:
		return
	if pc.state.get("wallpaper", "") != "" and not pc.state.get("seen", false):
		pc.state.seen = true
		c.do_emote("angry", 2.5)
		_say_cat("victim_wallpaper", "angry")
		s.npc_reaction(c, "wallpaper_seen", {"owner": c.id, "by": pc.state.get("by_actor", "")})
		pc.state.wallpaper = ""
		pc.apply_state()
		s.set_device_state(pc)
	elif pc.state.get("postits", false) and not pc.state.get("seen_p", false):
		pc.state.seen_p = true
		c.do_emote("angry", 2.5)
		_say_cat("victim_postits", "angry")
		s.npc_reaction(c, "postits_seen", {"owner": c.id})
		pc.state.postits = false
		pc.apply_state()
		s.set_device_state(pc)


func _st_fetch_chair() -> void:
	var d := _desk()
	var chair: Prop = s.world.ent(d.get("chair_id", ""))
	if chair == null or not chair.is_available():
		_switch("wander")
		return
	match step:
		0:
			c.go_to(chair.global_position + (d.seat - chair.global_position).normalized() * 0.7)
			c.do_emote("search", 2.0)
			step = 1
			timer = 25.0
		1:
			if chair.held_by and chair.held_by != c:
				_switch("idle")
				return
			if c.arrived(0.9) or c.global_position.distance_to(chair.global_position) < 1.1:
				if c.pick_up(chair):
					c.go_to(d.seat + d.facing * -0.9)
					step = 2
					timer = 25.0
			elif timer <= 0.0:
				_switch("idle")
		2:
			if c.held == null:
				_switch("idle")
				return
			if c.arrived(0.6) or timer <= 0.0:
				c.drop_held(Vector3.ZERO)
				chair.global_position = Vector3(d.seat.x, chair.global_position.y, d.seat.z)
				chair.linear_velocity = Vector3.ZERO
				_switch("work")


func _st_poi(kind: String, dur: float, what: String) -> void:
	match step:
		0:
			var p: Dictionary = s.world.claim_poi(kind, c.id, c.global_position)
			if p.is_empty():
				_switch("wander")
				return
			data.poi = p
			c.go_to(p.pos)
			step = 1
			timer = 40.0
		1:
			if c.arrived(0.6):
				c.face_dir = data.poi.facing
				timer = dur
				step = 2
				c.humanoid.busy = true
				if what == "coffee":
					var cm: Device = s.find_device("coffee")
					if cm:
						s.emit_sound(cm.interact_point(), 40.0, "coffee_machine", "", cm.ent_id(), "coffee")
			elif timer <= 0.0:
				_switch("idle")
		2:
			if timer <= 0.0:
				c.humanoid.busy = false
				match what:
					"coffee":
						needs.coffee = 0.0
						s.npc_drinks_coffee(c)
						c.do_emote("drink", 3.0)
						if needs.social > 0.4:
							_switch("chat")
							return
					"toilet":
						needs.bladder = 0.0
					"printer":
						pass
				_switch("idle")


func _st_chat() -> void:
	match step:
		0:
			var others: Array = s.npc_ids().filter(func(x): return x != c.id)
			others.append("player")
			var friend: String = s.relations.best_friend(c.id, others)
			if rng.randf() < 0.3:
				friend = others[rng.randi() % others.size()]
			var fc: Character = s.characters.get(friend)
			if fc == null or fc.is_down():
				_switch("wander")
				return
			data.friend = friend
			c.go_to(fc.global_position)
			step = 1
			timer = 30.0
		1:
			var fc: Character = s.characters.get(data.friend)
			if fc == null:
				_switch("idle")
				return
			if c.global_position.distance_to(fc.global_position) < 1.6:
				c.stop()
				c.face_dir = (fc.global_position - c.global_position).normalized()
				c.look_at_point(fc.eye_position())
				step = 2
				timer = rng.randf_range(6.0, 11.0)
				data.lines = 0
			elif timer <= 0.0:
				_switch("idle")
			elif rng.randf() < 0.15:
				c.go_to(fc.global_position)
		2:
			var fc: Character = s.characters.get(data.friend)
			if fc == null:
				_switch("idle")
				return
			c.look_at_point(fc.eye_position())
			if int(data.lines) < 3 and rng.randf() < 0.18:
				data.lines = int(data.lines) + 1
				if not _share_gossip(data.friend):
					_say_cat("chat", "neutral" if rng.randf() < 0.7 else "laugh", {"name": fc.nick})
				var fb: CoworkerBrain = s.brains.get(data.friend)
				if fb and fb.state in ["work", "idle", "chat", "coffee"] and rng.randf() < 0.6:
					fb.reply_chat(c)
			if timer <= 0.0:
				needs.social = 0.0
				s.relations.change(c.id, data.friend, 0.03)
				s.game_event("action", {"action": "npc_chat", "actor": c.id, "target": data.friend})
				_switch("idle")


func reply_chat(other: Character) -> void:
	if c.seated_on == null:
		c.face_dir = (other.global_position - c.global_position).normalized()
	c.look_at_point(other.eye_position())
	_say_cat("chat" if rng.randf() < 0.7 else "react_noise", "laugh" if rng.randf() < 0.4 else "neutral", {"name": other.nick})


## Share a rumour or a witnessed act with a friend. Returns true if something was said.
func _share_gossip(friend: String) -> bool:
	if rng.randf() > float(t.get("gossip", 0.4)):
		return false
	# rumours first
	for key in mem.rumors:
		var r: Dictionary = mem.rumors[key]
		if float(r.belief) > 0.3 and not friend in r.get("told", []):
			r["told"] = r.get("told", []) + [friend]
			s.npc_say(c, s.barks.pick("rumor_tell", {"rumor": s.rumor_text(key)}), "neutral")
			s.spread_rumor(c.id, friend, key)
			return true
	for w in mem.witnessed:
		if not w.shared and w.actor != "" and w.actor != friend:
			w.shared = true
			var an: String = s.char_name(w.actor)
			s.npc_say(c, s.barks.pick("gossip", {"name": an}), "laugh")
			s.share_witness(c.id, friend, w)
			return true
	return false


func _st_wander() -> void:
	match step:
		0:
			var zones := ["open_space", "hall", "corridor", "break"]
			c.go_to(s.world.random_point_in_zone(zones[rng.randi() % zones.size()]))
			step = 1
			timer = 25.0
		1:
			if c.arrived(0.8) or timer <= 0.0:
				c.do_emote("stretch" if rng.randf() < 0.3 else "", 2.0)
				timer = rng.randf_range(2.0, 5.0)
				step = 2
		2:
			if timer <= 0.0:
				_switch("idle")


func _st_meeting() -> void:
	if not s.day.meeting_active:
		_switch("idle")
		return
	match step:
		0:
			# credulous coworkers trust a fake planning board
			var pl: Device = s.find_device("planning")
			if pl and pl.state.get("fake", false) and float(t.get("credulity", 0.5)) > 0.45 and not data.get("checked", false):
				data.checked = true
				believes_meeting_moved = true
				s.npc_reaction(c, "wrong_meeting", {"by": pl.state.get("by", "")})
				_say_cat("lie_believed", "happy")
				_switch("work")
				return
			var p: Dictionary = s.world.claim_poi("meeting_seat", c.id, Vector3(6, 0, -11))
			if p.is_empty():
				_switch("go_zone", {"zone": "meeting", "dur": 30.0})
				return
			data.poi = p
			c.go_to(p.pos - p.facing * 0.2, s.day.meeting_late(c.id))
			step = 1
			timer = 50.0
		1:
			if c.arrived(0.8) or timer <= 0.0:
				var chair: Prop = s.world.ent(data.poi.get("chair_id", ""))
				if chair and chair.occupant == "" and chair.global_position.distance_to(c.global_position) < 1.5:
					c.sit_on(chair)
				else:
					c.face_dir = data.poi.facing
				s.day.mark_present(c.id)
				step = 2
		2:
			var boss: Character = s.director
			if boss:
				c.look_at_point(boss.eye_position())
			if rng.randf() < 0.01:
				_say_cat("meeting", "neutral")


func _st_go_zone_generic(zone: String, dur: float, emote: String) -> void:
	match step:
		0:
			var spot: Dictionary = s.world.claim_poi("break_spot", c.id, c.global_position) if zone == "break" else {}
			var p: Vector3 = spot.get("pos", s.world.random_point_in_zone(zone))
			data.facing = spot.get("facing", Vector3.ZERO)
			c.go_to(p)
			step = 1
			timer = 40.0
			if data.has("cat"):
				_say_cat(data.cat, "happy")
		1:
			if c.arrived(0.8) or timer <= 0.0:
				if data.facing != Vector3.ZERO:
					c.face_dir = data.facing
				if emote != "":
					c.do_emote(emote, dur)
				timer = dur
				step = 2
		2:
			if rng.randf() < 0.02:
				_say_cat("chat", "laugh")
			if timer <= 0.0 or (state == "lunch" and not s.day.lunch_active):
				_switch("idle")


func _st_investigate() -> void:
	match step:
		0:
			c.go_to(s.world.nav_closest(data.pos), false)
			step = 1
			timer = 20.0
		1:
			if c.global_position.distance_to(data.pos) < 2.5 or c.arrived(1.0) or timer <= 0.0:
				c.stop()
				c.do_emote("search", 3.0)
				c.look_at_point(data.pos)
				timer = 3.0
				step = 2
		2:
			if timer <= 0.0:
				_switch("idle")


func _st_report() -> void:
	var boss: Character = s.director
	if boss == null:
		_switch("idle")
		return
	match step:
		0:
			_say_cat("report_go", "angry")
			step = 1
			timer = 60.0
			data.repath = 0.0
		1:
			data.repath = float(data.repath) - 0.25
			if float(data.repath) <= 0.0:
				data.repath = 1.0
				c.go_to(boss.global_position)
			if c.global_position.distance_to(boss.global_position) < 2.0 and not boss.is_down():
				c.stop()
				c.face_dir = (boss.global_position - c.global_position).normalized()
				c.look_at_point(boss.eye_position())
				c.do_emote("point", 2.5)
				s.npc_report(self, data.w)
				step = 2
				timer = 3.5
			elif timer <= 0.0:
				_switch("idle")
		2:
			if timer <= 0.0:
				_switch("idle")


## Accomplice diversion: go talk loudly to the director to keep him busy.
func _st_diversion() -> void:
	var boss: Character = s.director
	if boss == null:
		_switch("idle")
		return
	match step:
		0:
			c.go_to(boss.global_position, true)
			step = 1
			timer = 45.0
		1:
			if c.global_position.distance_to(boss.global_position) < 2.2:
				c.stop()
				c.face_dir = (boss.global_position - c.global_position).normalized()
				c.look_at_point(boss.eye_position())
				_say_cat("diversion", "panic")
				c.do_emote("panic", 3.0)
				s.start_diversion(c, accomplice_for)
				step = 2
				timer = 22.0
			elif timer <= 0.0:
				_switch("idle")
			elif rng.randf() < 0.2:
				c.go_to(boss.global_position, true)
		2:
			if boss:
				c.look_at_point(boss.eye_position())
			if rng.randf() < 0.06:
				_say_cat("diversion", "panic")
			if timer <= 0.0:
				s.end_diversion(c)
				_switch("idle")


func _st_party() -> void:
	var r: Device = s.find_device("radio")
	if r == null or not r.state.get("on", false):
		_switch("idle")
		return
	match step:
		0:
			c.go_to(s.world.nav_closest(r.interact_point() + Vector3(rng.randf_range(-1.5, 1.5), 0, 2.0)))
			step = 1
			timer = 30.0
			_say_cat("radio", "happy")
		1:
			if c.arrived(1.0) or timer <= 0.0:
				c.do_emote("dance", 12.0)
				timer = 12.0
				step = 2
		2:
			if timer <= 0.0:
				_switch("idle")


func _st_search() -> void:
	match step:
		0:
			var targets: Array = s.containers_near(c.global_position, 25.0)
			if targets.is_empty():
				_switch("idle")
				return
			data.target = targets[rng.randi() % targets.size()]
			c.go_to(s.world.nav_closest(data.target.interact_point()))
			step = 1
			timer = 20.0
			c.do_emote("search", 2.0)
		1:
			if c.arrived(1.0) or timer <= 0.0:
				c.humanoid.busy = true
				timer = 2.5
				step = 2
		2:
			if timer <= 0.0:
				c.humanoid.busy = false
				s.npc_searches_container(c, data.target)
				if not s.events.active("lost_item"):
					_switch("idle")
				else:
					step = 0


func _st_wrong_meeting() -> void:
	match step:
		0:
			c.go_to(s.world.random_point_in_zone("meeting"))
			step = 1
			timer = 40.0
		1:
			if c.arrived(1.0) or timer <= 0.0:
				c.do_emote("shrug", 3.0)
				s.npc_say(c, "Euh… il n'y a personne ?", "surprised")
				s.npc_reaction(c, "wrong_meeting", {})
				timer = 4.0
				step = 2
		2:
			if timer <= 0.0:
				believes_meeting_moved = false
				_switch("idle")


func _st_follow() -> void:
	var who: Character = s.characters.get(data.get("who", ""))
	if who == null or timer <= 0.0:
		_switch("idle")
		return
	if c.global_position.distance_to(who.global_position) > 2.0:
		c.go_to(who.global_position)
	else:
		c.stop()
		c.look_at_point(who.eye_position())


# ------------------------------------------------------------------ perception hooks
func on_hear(ev: Dictionary, perceived: float) -> void:
	if c.is_down() or state in ["report", "diversion", "react"]:
		return
	var kind: String = ev.kind
	if kind == "footstep":
		return
	mem.hear(kind, ev.pos, ev.zone, perceived, s.now())
	var now: float = s.now()
	if perceived > 30.0:
		c.look_at_point(ev.pos + Vector3(0, 0.8, 0))
	if perceived > 42.0 and now - _last_noise_react > 6.0:
		_last_noise_react = now
		match kind:
			"fart":
				c.do_emote("laugh", 3.0)
				_say_cat("witness_fart", "laugh")
			"radio":
				if float(t.get("work", 0.5)) > 0.7:
					_say_cat("radio", "angry")
			"printer":
				_say_cat("printer_spam", "surprised")
			_:
				if rng.randf() < 0.5:
					_say_cat("react_noise", "surprised")
		if state in ["work", "idle", "wander"] and float(t.get("observation", 0.5)) > 0.55 and perceived > 50.0 and rng.randf() < 0.5:
			_resume = ""
			_switch("investigate", {"pos": ev.pos})


func on_witness(act: Dictionary, info: Dictionary) -> void:
	mem.remember_act(act, info.id, info.desc, info.conf, s.now())
	if c.is_down() or state in ["report", "diversion"]:
		return
	var actor_c: Character = s.characters.get(act.actor)
	if actor_c:
		c.look_at_point(actor_c.eye_position())
	if act.get("victim", "") == c.id:
		c.do_emote("angry", 2.5)
		_say_cat("victim_" + _victim_cat(act.kind), "angry")
		mem.add_grievance(info.id, 1.0)
	elif int(act.sev) <= 2 and rng.randf() < 0.6:
		c.do_emote("laugh" if rng.randf() < 0.6 else "suspicious", 2.0)
		_say_cat("witness_prank", "laugh")
	else:
		c.do_emote("suspicious", 2.0)
	if bribed_by != "" and bribed_by == info.id:
		return
	pending.append({"act": act, "decide_at": s.now() + rng.randf_range(4.0, 14.0), "who": info.id})


func _victim_cat(kind: String) -> String:
	match kind:
		"wallpaper":
			return "wallpaper"
		"postits":
			return "postits"
		"lower_seat":
			return "lowseat"
		"salt_coffee":
			return "salt"
	return "chair"


func _process_pending() -> void:
	if pending.is_empty() or state in ["report", "meeting", "diversion"] or c.is_down():
		return
	var p: Dictionary = pending[0]
	if s.now() < float(p.decide_at):
		return
	pending.pop_front()
	var act: Dictionary = p.act
	var w := mem.knows_act(int(act.id))
	if w.is_empty() or w.reported:
		return
	var chance := Testimony.report_chance(c.id, t, s.relations, mem, String(w.actor), int(act.sev), String(act.get("victim", "")))
	if rng.randf() < chance and s.director:
		w.reported = true
		_resume = ""
		_switch("report", {"w": w})
	elif rng.randf() < float(t.get("gossip", 0.4)) * 0.6:
		needs.social += 0.5


# ------------------------------------------------------------------ social hooks (from player)
func talked_to(by: Character) -> void:
	if state in ["work", "idle", "wander", "coffee", "chat", "lunch", "go_zone"] or c.seated_on:
		c.face_dir = (by.global_position - c.global_position).normalized() if c.seated_on == null else Vector3.ZERO
		c.look_at_point(by.eye_position())
		if c.seated_on == null and state != "react":
			c.stop()
			_resume = state if state != "react" else ""
			state = "react"
			timer = 3.0


func ask_diversion(for_id: String) -> void:
	accomplice_for = for_id
	_switch("diversion")


func believe_meeting_moved() -> void:
	believes_meeting_moved = true


func on_meeting_started() -> void:
	if believes_meeting_moved:
		s.npc_reaction(c, "wrong_meeting", {})
		if rng.randf() < 0.5:
			_switch("wrong_meeting")


func react_to(what: String, cat: String, emotion: String, dur := 2.5, look_pos := Vector3.INF) -> void:
	if c.is_down():
		return
	if state != "react":
		_resume = state if state in ["work", "meeting", "lunch", "chat", "coffee"] else ""
	if c.seated_on == null:
		c.stop()
	state = "react"
	timer = dur
	if look_pos != Vector3.INF:
		c.look_at_point(look_pos)
	c.do_emote(what, dur)
	if cat != "":
		_say_cat(cat, emotion)


func _say_cat(cat: String, emotion := "neutral", slots := {}) -> void:
	var now: float = s.now()
	if now - _last_bark < 2.5:
		return
	_last_bark = now
	s.npc_say(c, s.barks.pick(cat, slots), emotion)
