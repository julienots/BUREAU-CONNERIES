class_name Session
extends Node3D
## The single source of truth for a working day. In solo it runs locally; in multiplayer
## the server runs it and clients only send intents (see NetSync). Every action goes
## through request_action(): distance, prerequisites and cooldowns are validated here,
## never in the UI. Owns acts (infractions), witnesses, testimonies, interrogations,
## sanctions, rumours, missions, economy, random events and the day clock.

signal notified(text: String, kind: String)
signal action_started(label: String, duration: float)
signal action_ended(ok: bool, msg: String)
signal interrogation_started(info: Dictionary)
signal interrogation_finished(info: Dictionary)
signal day_over(results: Dictionary)
signal hud_changed
signal ui_request(kind: String, info: Dictionary)
signal game_event_emitted(type: String, data: Dictionary)

const MAX_SHEETS := 45
const INTERACT_RANGE := 2.6

var mode := "solo"                  # solo | server | client
var running := false
var world: OfficeWorld
var chars_root: Node3D
var characters: Dictionary = {}     # id -> Character
var brains: Dictionary = {}         # npc id -> CoworkerBrain
var boss_brain: DirectorBrain
var director: Character
var player: Character               # local player character (null on dedicated server)
var human_ids: Array[String] = []   # characters controlled by humans
var day := DayManager.new()
var events := EventDirector.new()
var economy := Economy.new()
var relations := Relations.new()
var barks := Barks.new()
var missions: Dictionary = {}       # char id -> MissionSystem
var human_memory: Dictionary = {}   # human char id -> Memory (what players witnessed)
var llm: LlmProvider
var rng := RandomNumberGenerator.new()
var seed_value := 1234
var profile := "authoritarian"
var day_number := 1

var acts: Array[Dictionary] = []
var _act_by_ent: Dictionary = {}
var _next_act := 1
var testimonies: Dictionary = {}    # act_id -> Array[{witness, accused, kind}]
var rumors: Dictionary = {}         # key -> {id, about, origin, believers: {}}
var warnings: Dictionary = {}
var fines: Dictionary = {}
var stats: Dictionary = {}          # char id -> {}
var diversion: Dictionary = {}
var smell: Dictionary = {}
var interrogation: Dictionary = {}
var _sheets: Array[Prop] = []
var _spotted_t: Dictionary = {}
var _rate: Dictionary = {}          # char id -> [timestamps] (action rate limiting)
var _chat_t: Dictionary = {}
var _smell_t := 0.0
var _hud_t := 0.0
var _clock: Dictionary = {}
var accomplices: Dictionary = {}    # npc id -> human id
var bribes: Dictionary = {}
var day_failed := false
var _ended := false
var net: Node = null                # NetSync when multiplayer
var quiet_until := 0.0              # ignore settling noises right after spawn
var _cardboard_hits: Array = []
var _last_crash := -100.0


func is_authority() -> bool:
	return mode != "client"


func now() -> float:
	return Game.time()


func director_ai_enabled() -> bool:
	return is_authority() and not "boss" in human_ids


# ------------------------------------------------------------------ setup
func setup(p_mode: String, args: Dictionary) -> void:
	mode = p_mode
	seed_value = int(args.get("seed", randi() % 100000))
	rng.seed = seed_value
	barks.rng.seed = seed_value + 7
	day_number = int(args.get("day", SaveGame.data.day if mode == "solo" else 1))
	var profiles: Array = Data.director_profiles.keys()
	profile = String(args.get("profile", profiles[(day_number - 1 + seed_value) % profiles.size()]))
	world = OfficeWorld.new()
	world.name = "World"
	add_child(world)
	OfficeBuilder.build(world, seed_value, Settings.effective_quality(), true)
	chars_root = Node3D.new()
	chars_root.name = "Chars"
	add_child(chars_root)
	_clock = world.get_meta("clock", {})
	day.setup(float(args.get("day_minutes", Settings.get_v("day_minutes"))))
	day.meeting_changed.connect(_on_meeting_changed)
	day.lunch_changed.connect(func(on):
		if on:
			notify_all("Pause déjeuner ! La salle de pause va se remplir.", "event")
		for id in brains:
			brains[id].on_schedule_changed())
	day.finished.connect(func(): end_day(false))
	events.rng.seed = seed_value + 3
	events.started.connect(_on_event_started)
	events.ended.connect(_on_event_ended)
	if mode == "client":
		for p in world.props:
			(p as Prop).remote = true
			(p as Prop).freeze = true
	Game.set_session(self)
	quiet_until = now() + 4.0
	llm = LlmProvider.new()
	llm.barks = barks
	add_child(llm)


## Spawns the cast. `humans`: {char_id: {name, look, role}}; "player" for solo.
func spawn_cast(humans: Dictionary, npc_limit: int) -> void:
	var all_ids: Array = []
	var cw: Array = Data.coworkers.slice(0, clampi(npc_limit, 0, Data.coworkers.size()))
	# boss
	var boss_human: bool = humans.has("boss")
	var bd: Dictionary = Data.director
	director = _spawn_char("boss", bd.name, "director", bd.look, bd.voice, float(bd.pitch), {}, not boss_human and is_authority())
	director.global_position = world.desk_of("boss").get("seat", Vector3(19, 0, 7)) + Vector3(-1.6, 0, 1.6)
	if boss_human:
		human_ids.append("boss")
		director.nick = humans.boss.get("name", bd.name)
	elif is_authority():
		boss_brain = DirectorBrain.new()
		boss_brain.name = "DirectorBrain"
		add_child(boss_brain)
		boss_brain.setup(director, self, profile, seed_value + 11)
	all_ids.append("boss")
	for c in cw:
		var traits: Dictionary = Data.traits_for(c.archetype).duplicate()
		var ch := _spawn_char(c.id, c.name, "employee", c.look, c.voice, float(c.pitch), traits, is_authority())
		ch.archetype = c.archetype
		ch.desk_index = int(c.desk)
		var d := world.desk_of(c.id)
		ch.global_position = d.seat + d.facing * -1.25 if not d.is_empty() else Vector3.ZERO
		all_ids.append(c.id)
		if is_authority():
			var b := CoworkerBrain.new()
			b.name = "Brain_" + c.id
			add_child(b)
			b.setup(ch, self, seed_value + all_ids.size() * 31)
			brains[c.id] = b
	for hid in humans:
		if hid == "boss":
			continue
		var h: Dictionary = humans[hid]
		var ch := _spawn_char(hid, h.get("name", "Toi"), "employee", h.get("look", Data.player_default.look), h.get("voice", "player"), 1.0, {}, false)
		ch.is_player = true
		var desk_i := int(h.get("desk", Data.player_default.desk))
		ch.desk_index = desk_i
		_assign_desk(hid, desk_i)
		var d := world.desk_of(hid)
		ch.global_position = d.seat + d.facing * -1.3 if not d.is_empty() else Vector3(-16, 0, 6)
		human_ids.append(hid)
		all_ids.append(hid)
		human_memory[hid] = Memory.new(20)
		stats[hid] = {"pranks": 0, "caught": 0, "falls_caused": 0, "work": 0, "denounce": 0, "earned": 0}
		warnings[hid] = 0
		ch.apply_cosmetics(h.get("cosmetics", []))
	relations.setup(all_ids, Data.relations, rng, SaveGame.data.affinity if mode == "solo" else {})
	# NPCs and boss also have stats/warnings
	for id in all_ids:
		if not warnings.has(id):
			warnings[id] = 0


func _assign_desk(owner: String, idx: int) -> void:
	for d in world.desks:
		if int(d.index) == idx:
			d.owner = owner
			for key in ["pc_id", "phone_id", "drawer_id", "chair_id"]:
				var e: Node = world.ent(d[key])
				if e:
					e.set("owner_id", owner)
			return


func _spawn_char(id: String, nick: String, role: String, look: Dictionary, voice: String, pitch: float, traits: Dictionary, ai: bool) -> Character:
	var ch := Character.new()
	ch.setup(id, nick, role, look, voice, pitch)
	ch.traits = traits
	ch.ai_driven = ai
	ch.is_remote = mode == "client"
	chars_root.add_child(ch)
	characters[id] = ch
	return ch


func start_day_solo() -> void:
	var p := SaveGame.data
	var mids := MissionSystem.pick_for_day(day_number, rng, p.missions_done, 4)
	var side_ids: Array = []
	for sc in Data.side_challenges:
		side_ids.append(sc.id)
	_setup_missions("player", mids, side_ids)
	economy.setup_solo("player")
	economy.money_changed.connect(func(_w, _a): hud_changed.emit())
	for it in p.owned:
		if Data.items.get(it, {}).get("kind", "") == "passive":
			player.passive.append(it)
	player.apply_cosmetics(p.equipped_cosmetics)
	running = true
	notify(player, "Jour %d — Directeur : %s. %s" % [day_number, Data.director_profiles[profile].label, Data.director_profiles[profile].desc], "event")


func _setup_missions(who: String, mids: Array, side_ids: Array) -> void:
	var ms := MissionSystem.new()
	ms.setup(self, who, mids, side_ids)
	ms.completed.connect(_on_mission_completed)
	ms.progressed.connect(func(o, id, txt):
		if o == "player" or o in human_ids:
			hud_changed.emit())
	missions[who] = ms


# ------------------------------------------------------------------ main loop
func _process(delta: float) -> void:
	if not running:
		return
	if is_authority():
		day.tick(delta)
		var ev_id := events.tick(now(), delta, {"meeting": day.meeting_active, "min_to_meeting": day.minutes_to_next("meeting"),
			"player_level": suspicion_level(human_ids[0]) if not human_ids.is_empty() else 0, "boss_profile": profile})
		if ev_id != "":
			events.start(ev_id, now(), _event_info(ev_id))
		for ms in missions.values():
			ms.poll(delta)
		_update_actions(delta)
		_update_smell(delta)
		_update_productivity(delta)
		if diversion.size() > 0 and now() > float(diversion.until):
			end_diversion(null)
		if interrogation.size() > 0 and now() - float(interrogation.t) > 25.0:
			_resolve_interrogation("deny", {})
	_update_clock()
	_hud_t -= delta
	if _hud_t <= 0.0:
		_hud_t = 0.5
		hud_changed.emit()


func _update_clock() -> void:
	if _clock.is_empty():
		return
	var m := day.minutes
	(_clock.hour as Node3D).rotation.z = -fmod(m / 60.0, 12.0) / 12.0 * TAU
	(_clock.minute as Node3D).rotation.z = -fmod(m, 60.0) / 60.0 * TAU


func _update_productivity(delta: float) -> void:
	for id in human_ids:
		var ch: Character = characters.get(id)
		if ch == null or ch.is_director():
			continue
		ch.productivity = maxf(0.0, ch.productivity - delta * 0.09)


# ------------------------------------------------------------------ queries
func npc_ids() -> Array:
	return brains.keys()


func employees() -> Array:
	var out: Array = []
	for id in characters:
		var ch: Character = characters[id]
		if not ch.is_director():
			out.append(ch)
	return out


func is_employee(id: String) -> bool:
	return characters.has(id) and not (characters[id] as Character).is_director()


func char_name(id: String) -> String:
	if characters.has(id):
		return (characters[id] as Character).nick
	return id


func boss_near(pos: Vector3, r: float) -> bool:
	return director != null and director.global_position.distance_to(pos) < r


func find_device(kind: String) -> Device:
	for e in world.interactables:
		if e is Device and (e as Device).kind == kind:
			return e
	return null


func phone_of(owner: String) -> Device:
	var d := world.desk_of(owner)
	if d.is_empty():
		return null
	return world.ent(d.phone_id) as Device


func owner_away(owner: String, pos: Vector3) -> bool:
	var ch: Character = characters.get(owner)
	if ch == null:
		return true
	return ch.global_position.distance_to(pos) > 1.6 or ch.seated_on == null


func suspicion_level(id: String) -> int:
	if boss_brain:
		return boss_brain.sus.level(id)
	if net and net.has_method("suspicion_level"):
		return net.suspicion_level(id)
	return 0


func suspicion_of(id: String) -> Suspicion:
	if boss_brain:
		return boss_brain.sus
	if net and net.get("sus"):
		return net.sus
	return null


func director_interrogating(id: String) -> bool:
	return interrogation.size() > 0 and interrogation.get("who", "") == id


func diversion_active_for(owner: String) -> bool:
	return diversion.size() > 0 and diversion.get("for", "") == owner and now() < float(diversion.until)


func player_spotted_recently(id: String) -> bool:
	return now() - float(_spotted_t.get(id, -999.0)) < 30.0 or suspicion_level(id) >= 4


func containers_near(pos: Vector3, r: float) -> Array:
	var out: Array = []
	for e in world.interactables:
		if e is Device and (e as Device).is_container() and (e as Device).global_position.distance_to(pos) < r:
			out.append(e)
	return out


func act_by_id(id: int) -> Dictionary:
	for a in acts:
		if int(a.id) == id:
			return a
	return {}


func act_for_entity(ent_id: String) -> Dictionary:
	return _act_by_ent.get(ent_id, {})


func recent_act_in_zone(zone: String, window: float) -> Dictionary:
	for i in range(acts.size() - 1, -1, -1):
		var a: Dictionary = acts[i]
		if now() - float(a.time) > window:
			break
		if a.zone == zone:
			return a
	return {}


# ------------------------------------------------------------------ notifications / speech
func notify(actor: Node, text: String, kind := "info") -> void:
	if actor == null:
		return
	if actor == player:
		notified.emit(text, kind)
	elif net and actor is Character:
		net.send_notify((actor as Character).id, text, kind)


func notify_all(text: String, kind := "info") -> void:
	if player:
		notified.emit(text, kind)
	if net:
		net.broadcast_notify(text, kind)


func npc_say(c: Character, text: String, emotion := "neutral") -> void:
	c.say(text, emotion)
	if net:
		net.broadcast_say(c.id, text, emotion)


func game_event(type: String, d: Dictionary) -> void:
	for ms in missions.values():
		ms.on_event(type, d)
	game_event_emitted.emit(type, d)


func on_suspicion_changed(id: String) -> void:
	if characters.get(id) == player:
		hud_changed.emit()


func update_alert(_boss: Character, emp: Character, aw: float) -> void:
	if emp != player or director == null:
		return
	if aw > 0.75:
		director.set_alert("!", Color(1, 0.25, 0.2))
	elif aw > 0.25:
		director.set_alert("?", Color(1, 0.85, 0.2))
	elif director.alert_icon.visible and boss_brain and boss_brain.state != "confront":
		director.set_alert("")


func notify_caught(e: Character, text: String) -> void:
	if e == null:
		return
	_spotted_t[e.id] = now()
	if stats.has(e.id):
		stats[e.id].caught += 1
	if e == player:
		director.set_alert("!", Color(1, 0.2, 0.2))
		SoundFx.ui("alert_sting")
	notify(e, text, "danger")


# ------------------------------------------------------------------ sound
const SFX_KIND := {"door_slam": "slam", "boxes_crash": "crash", "chair_fall": "crash", "break_ceramic": "break", "papers_fall": "papers",
	"printer_jam": "printer", "paper_eject": "printer", "phone_ring": "phone", "buzzer": "buzzer", "confetti_pop": "confetti", "body_fall": "fall",
	"duck_squeak": "impact", "slip_whoosh": "fall", "smell_waft": "smell", "coffee_machine": "coffee"}


func emit_sound(pos: Vector3, loud: float, sfx: String, actor_id: String, source_ent: String, kind := "") -> void:
	if sfx != "":
		SoundFx.play_at(sfx, pos, loud)
		if net and is_authority():
			net.broadcast_sound(sfx, pos, loud)
	if not is_authority() or now() < quiet_until:
		return
	if kind == "":
		kind = SFX_KIND.get(sfx, "")
		if kind == "" and sfx.begins_with("fart"):
			kind = "fart"
		elif kind == "" and sfx.begins_with("hit_"):
			kind = "impact"
		elif kind == "":
			kind = "misc"
	var zone := world.zone_at(pos)
	var by := actor_id
	if by == "" and source_ent != "":
		var src: Node = world.ent(source_ent)
		if src is Prop and now() - (src as Prop).last_touched_time < 8.0:
			by = (src as Prop).last_touched_by
		elif src is Device:
			by = String((src as Device).state.get("by", ""))
	var ev := {"pos": pos, "loud": loud, "kind": kind, "sfx": sfx, "zone": zone, "actor": actor_id, "source": source_ent, "time": now(),
		"victim": "", "loud_radio": kind == "radio" and loud > 60.0}
	if kind == "radio":
		ev["loud"] = loud
	if loud >= 12.0:
		_propagate(ev)
	if sfx == "hit_cardboard":
		_cardboard_hits.append([now(), pos, by])
		_cardboard_hits = _cardboard_hits.filter(func(x): return now() - float(x[0]) < 1.6)
		if _cardboard_hits.size() >= 3 and now() - _last_crash > 8.0:
			_last_crash = now()
			var who := ""
			for x in _cardboard_hits:
				if String(x[2]) != "":
					who = x[2]
			emit_sound(pos, 82.0, "boxes_crash", who, source_ent, "crash")
	if kind != "footstep":
		game_event("sound", {"sfx": sfx, "kind": kind, "zone": zone, "loud": loud, "by": by})


func _propagate(ev: Dictionary) -> void:
	var foot: bool = ev.kind == "footstep"
	for id in characters:
		if id == ev.actor:
			continue
		var ch: Character = characters[id]
		var listener: Node = brains.get(id)
		if id == "boss":
			listener = boss_brain
		if listener == null:
			continue
		var d := ch.global_position.distance_to(ev.pos)
		var quick: float = ev.loud - 20.0 * log(maxf(d, 1.0)) / log(10.0)
		if quick < 16.0:
			continue
		if foot and d > 14.0:
			continue
		var p := Perception.perceived(world, ch.global_position, ev.pos, ev.loud, not foot or d > 4.0)
		if id == "boss":
			p *= 1.0
		if p >= 16.0:
			listener.on_hear(ev, p)


# ------------------------------------------------------------------ actions
func request_action(actor: Character, target_id: String, action_id: String, params := {}) -> Dictionary:
	if mode == "client":
		net.send_request(target_id, action_id, params)
		return {"ok": true, "pending": true}
	var r := _do_request(actor, target_id, action_id, params)
	if not r.get("ok", false) and r.has("msg"):
		notify(actor, r.msg, "warn")
	return r


func _rate_ok(actor: Character) -> bool:
	var arr: Array = _rate.get(actor.id, [])
	var t := now()
	arr = arr.filter(func(x): return t - float(x) < 1.0)
	if arr.size() >= 8:
		return false
	arr.append(t)
	_rate[actor.id] = arr
	return true


func _do_request(actor: Character, target_id: String, action_id: String, params: Dictionary) -> Dictionary:
	if actor == null or not running:
		return {"ok": false, "msg": ""}
	if not _rate_ok(actor):
		return {"ok": false, "msg": "Doucement !"}
	if action_id.begins_with("answer_"):
		return answer_interrogation(actor, action_id.substr(7), params)
	if director_interrogating(actor.id):
		return {"ok": false, "msg": "Le directeur te parle !"}
	if not actor.can_act():
		return {"ok": false, "msg": "Impossible pour l'instant."}
	if actor.action.size() > 0:
		return {"ok": false, "msg": "Tu es occupé."}
	if target_id == actor.id or target_id == "":
		return _self_action(actor, action_id, params)
	var target: Node = world.ent(target_id)
	if target == null:
		target = characters.get(target_id)
	if target == null:
		return {"ok": false, "msg": "Cible introuvable."}
	var reach := INTERACT_RANGE + (0.6 if target is Character else 0.0)
	var tp: Vector3 = target.interact_point()
	if Vector2(actor.global_position.x - tp.x, actor.global_position.z - tp.z).length() > reach:
		return {"ok": false, "msg": "Trop loin."}
	var def := {}
	for a in target.get_actions(actor):
		if a.id == action_id:
			def = a
			break
	if def.is_empty():
		return {"ok": false, "msg": "Action impossible."}
	if String(def.get("blocked", "")) != "":
		return {"ok": false, "msg": def.blocked}
	if float(def.get("time", 0.0)) > 0.0:
		actor.action = {"id": action_id, "target": target_id, "def": def, "t_left": float(def.time), "t_total": float(def.time),
			"params": params, "start": actor.global_position, "noise_t": 0.0}
		if actor == player:
			action_started.emit(String(def.label), float(def.time))
		elif net:
			net.send_action_started(actor.id, String(def.label), float(def.time))
		return {"ok": true, "timed": true}
	return _finish_action(actor, target, def, params)


func _update_actions(delta: float) -> void:
	for id in characters:
		var ch: Character = characters[id]
		if ch.action.is_empty():
			continue
		var a := ch.action
		if ch.is_down() or ch.global_position.distance_to(a.start) > 0.7 or director_interrogating(id):
			_cancel_action(ch, "Action interrompue.")
			continue
		a.t_left = float(a.t_left) - delta
		a.noise_t = float(a.noise_t) - delta
		var def: Dictionary = a.def
		if float(def.get("noise", 0.0)) > 0.0 and float(a.noise_t) <= 0.0:
			a.noise_t = 1.0
			var tgt: Node = world.ent(a.target)
			var p: Vector3 = tgt.interact_point() if tgt else ch.global_position
			emit_sound(p, float(def.noise), "", ch.id, String(a.target), "action")
		if float(a.t_left) <= 0.0:
			ch.action = {}
			var target: Node = world.ent(a.target)
			if target == null:
				target = characters.get(a.target)
			var ok_def := {}
			if target:
				for x in target.get_actions(ch):
					if x.id == a.id and String(x.get("blocked", "")) == "":
						ok_def = x
			var r := {"ok": false, "msg": "L'action n'est plus possible."}
			if not ok_def.is_empty():
				r = _finish_action(ch, target, ok_def, a.params)
			if ch == player:
				action_ended.emit(bool(r.get("ok", false)), String(r.get("msg", "")))
			elif net:
				net.send_action_ended(ch.id, bool(r.get("ok", false)), String(r.get("msg", "")))
			if not r.get("ok", false) and r.has("msg"):
				notify(ch, r.msg, "warn")


func _cancel_action(ch: Character, msg: String) -> void:
	ch.action = {}
	if ch == player:
		action_ended.emit(false, msg)
	elif net:
		net.send_action_ended(ch.id, false, msg)


func _finish_action(actor: Character, target: Node, def: Dictionary, params: Dictionary) -> Dictionary:
	var id: String = def.id
	var r := {"ok": true}
	var target_owner := ""
	var ent_id: String = target.ent_id()
	if target.get("owner_id") != null:
		target_owner = String(target.get("owner_id"))
	match id:
		"take":
			var p := target as Prop
			if not actor.add_item(p.item_id):
				return {"ok": false, "msg": "Poches pleines."}
			p.touch(actor)
			p.hide_inside("pocket:" + actor.id)
			_sync_prop(p)
		"hold":
			var p2 := target as Prop
			if not actor.pick_up(p2):
				return {"ok": false, "msg": "Impossible de le porter."}
		"sit":
			if not actor.sit_on(target as Prop):
				return {"ok": false, "msg": "Place occupée."}
		"work":
			r = _start_work(actor, target as Device)
			if not r.ok:
				return r
		"shop":
			r = {"ok": true, "ui": "shop"}
		_:
			if target is Character:
				r = perform_social(actor, target as Character, id, params)
			else:
				r = target.perform(actor, id, params)
	if not r.get("ok", false):
		return r
	var zone := world.zone_at(target.interact_point())
	game_event("action", {"action": id, "actor": actor.id, "target": ent_id, "target_owner": target_owner, "zone": zone, "params": params})
	if String(def.get("act", "")) != "":
		var sev := int(def.get("sev", 1))
		var victim := target_owner if target_owner != actor.id else ""
		var act := record_act(actor, String(def.act), sev, target.interact_point(), ent_id, victim)
		if def.get("prank", false):
			if stats.has(actor.id):
				stats[actor.id].pranks += 1
			game_event("prank", {"actor": actor.id, "act_id": act.id, "kind": def.act})
	if String(def.get("ui", "")) != "" and not r.has("ui"):
		r["ui"] = def.ui
	if not r.has("ui") and r.get("ok", false) and actor == player and String(def.get("label", "")) != "" and float(def.get("time", 0.0)) > 0.0:
		SoundFx.ui("ui_confirm", -8.0)
	return r


func _start_work(actor: Character, pc: Device) -> Dictionary:
	if pc.owner_id != actor.id:
		return {"ok": false, "msg": "Ce n'est pas ton poste."}
	if actor.seated_on == null:
		var d := world.desk_of(actor.id)
		var chair: Prop = world.ent(d.chair_id)
		if chair and chair.occupant == "" and chair.global_position.distance_to(d.seat) < 2.0:
			actor.sit_on(chair)
	actor.humanoid.typing = true
	return {"ok": true, "ui": "work"}


func work_done(actor: Character, params: Dictionary) -> Dictionary:
	# server-side sanity: minimum time between work results, capped score
	var last := float(actor.get_meta("last_work_done", -100.0))
	if now() - last < 4.0:
		return {"ok": false, "msg": "Trop rapide…"}
	actor.set_meta("last_work_done", now())
	var score := clampf(float(params.get("score", 0.5)), 0.0, 1.0)
	actor.productivity = minf(100.0, actor.productivity + 4.0 + 8.0 * score)
	actor.last_work_time = now()
	if stats.has(actor.id):
		stats[actor.id].work += 1
	economy.add(actor.id, int(round(2 + 4 * score)))
	emit_sound(actor.global_position, 14.0, "typing_loop", actor.id, "", "footstep")
	return {"ok": true, "msg": ""}


func start_pretend(actor: Character, _pc: Device) -> void:
	_start_work(actor, _pc)
	actor.pretending_until = now() + 25.0
	notify(actor, "Tu fais semblant de travailler… (le chef peut s'en rendre compte s'il regarde de près)", "info")


# ------------------------------------------------------------------ self / item actions
func item_actions(actor: Character) -> Array:
	var out: Array = []
	for it in actor.items:
		var info := Data.item_info(it)
		var nm: String = info.get("name", it)
		match it:
			"moustache":
				out.append({"id": "wear_moustache", "label": "Mettre la fausse moustache", "item": it})
			"cafe":
				out.append({"id": "drink_cafe", "label": "Boire le café", "item": it})
			"buzzer":
				out.append({"id": "drop_item", "label": "Poser le buzzer", "item": it})
			"banane":
				out.append({"id": "drop_item", "label": "Poser la peau de banane", "item": it})
			"confettis", "post_its":
				pass
			_:
				out.append({"id": "drop_item", "label": "Poser : " + nm, "item": it})
	for p in world.props_with_tag("buzzer"):
		var pr := p as Prop
		if pr.placed_by == actor.id and pr.is_available() and int(pr.get_meta("uses", 3)) > 0:
			out.append({"id": "trigger_buzzer", "label": "Déclencher le buzzer (%d)" % int(pr.get_meta("uses", 3)), "item": "buzzer", "target": pr.ent_id()})
	if actor.held:
		out.append({"id": "throw_held", "label": "Lancer", "item": ""})
		out.append({"id": "drop_held", "label": "Lâcher", "item": ""})
	return out


func _self_action(actor: Character, action_id: String, params: Dictionary) -> Dictionary:
	var item: String = params.get("item", "")
	match action_id:
		"drop_held":
			actor.drop_held(Vector3.ZERO)
		"throw_held":
			if actor.held == null:
				return {"ok": false, "msg": "Tu ne portes rien."}
			var p := actor.held
			var f := actor.forward()
			actor.drop_held((f * 6.0 + Vector3.UP * 2.0) * minf(p.mass, 6.0))
			var act := record_act(actor, "throw", 1 if p.mass < 2.0 else 2, actor.global_position, p.ent_id(), "")
			_act_by_ent[p.ent_id()] = act
		"stand":
			actor.stand_up()
		"drop_item":
			if not item in actor.items:
				return {"ok": false, "msg": "Tu n'as pas cet objet."}
			var kind: String = PropFactory.ITEM_TO_PROP.get(item, "")
			if kind == "":
				return {"ok": false, "msg": "Impossible de poser ça."}
			actor.consume_item(item)
			var pos := actor.global_position + actor.forward() * 0.6 + Vector3(0, 0.3, 0)
			var pr := _find_pocketed(actor, item)
			if pr:
				pr.reveal_at(Transform3D(Basis(Vector3.UP, actor.rotation.y), pos))
			else:
				pr = spawn_prop(kind, pos, actor.id)
			pr.placed_by = actor.id
			pr.touch(actor)
			if item == "buzzer" and not pr.has_meta("uses"):
				pr.set_meta("uses", int(Data.item_info("buzzer").get("uses", 3)))
			if item == "banane":
				var a := record_act(actor, "banana_trap", 2, pos, pr.ent_id(), "")
				_act_by_ent[pr.ent_id()] = a
			game_event("action", {"action": "drop_" + item, "actor": actor.id, "target": pr.ent_id(), "zone": world.zone_at(pos)})
		"trigger_buzzer":
			var b: Prop = world.ent(String(params.get("target", "")))
			if b == null or b.placed_by != actor.id:
				return {"ok": false, "msg": "Aucun buzzer posé."}
			var uses := int(b.get_meta("uses", 3))
			if uses <= 0:
				return {"ok": false, "msg": "Le buzzer est vide."}
			b.set_meta("uses", uses - 1)
			emit_sound(b.global_position, 82.0, "buzzer", actor.id, b.ent_id())
			game_event("action", {"action": "trigger_buzzer", "actor": actor.id, "target": b.ent_id(), "zone": world.zone_at(b.global_position)})
		"wear_moustache":
			if not actor.consume_item("moustache"):
				return {"ok": false, "msg": "Pas de moustache."}
			actor.set_disguise(true, 90.0)
			if net:
				net.broadcast_disguise(actor.id, true)
		"drink_cafe":
			if not actor.consume_item("cafe"):
				return {"ok": false, "msg": "Pas de café."}
			actor.do_emote("drink", 2.0)
			if actor.get_meta("salted_coffee", false):
				actor.set_meta("salted_coffee", false)
				actor.say("Pouah ! Salé !", "angry")
			actor.productivity = minf(100.0, actor.productivity + 3.0)
		"take_stock":
			if not economy.take_from_stock(actor.id, item, actor):
				return {"ok": false, "msg": "Impossible de prendre cet objet."}
		"buy":
			var why := economy.buy(actor.id, item, actor)
			if why != "":
				return {"ok": false, "msg": why}
			if actor == player:
				SoundFx.ui("cash_register")
			notify(actor, "Acheté : " + Data.item_name(item), "good")
			game_event("bought", {"actor": actor.id, "item": item})
		"call_phone_self":
			pass
		_:
			return {"ok": false, "msg": "Action inconnue."}
	return {"ok": true}


func _find_pocketed(actor: Character, item: String) -> Prop:
	for p in world.props:
		var pr := p as Prop
		if pr.inside_of == "pocket:" + actor.id and pr.item_id == item:
			return pr
	return null


# ------------------------------------------------------------------ world object helpers
func spawn_prop(kind: String, pos: Vector3, placed_by: String) -> Prop:
	var p := PropFactory.make(kind)
	p.placed_by = placed_by
	world.props_root.add_child(p)
	p.global_position = pos
	p.home = p.global_transform
	world.register(p, "dyn_%s_%d" % [kind, _next_act * 1000 + world.props.size()])
	if mode == "client":
		p.remote = true
		p.freeze = true
	if net:
		net.on_prop_spawned(p)
	return p


func despawn_prop(p: Prop) -> void:
	if not is_instance_valid(p):
		return
	world.unregister(p.ent_id())
	_sheets.erase(p)
	if net:
		net.on_prop_despawned(p.ent_id())
	p.queue_free()


func spawn_paper_mess(pos: Vector3, n: int, by: String) -> void:
	for i in n:
		var sheet := spawn_prop("paper_sheet", pos + Vector3(rng.randf_range(-0.3, 0.3), 0.3 + i * 0.03, rng.randf_range(-0.3, 0.3)), by)
		sheet.last_touched_by = by
		sheet.last_touched_time = now()
		sheet.rotation = Vector3(rng.randf_range(-0.3, 0.3), rng.randf() * TAU, rng.randf_range(-0.3, 0.3))
		sheet.linear_velocity = Vector3(rng.randf_range(-1.5, 1.5), rng.randf_range(0.5, 1.5), rng.randf_range(-1.5, 1.5))
		_track_sheet(sheet)


func eject_sheet(printer: Device) -> void:
	var f := -printer.global_basis.z
	var sheet := spawn_prop("paper_sheet", printer.global_position + Vector3(0, 0.9, 0) + f * 0.45, String(printer.state.get("by", "")))
	sheet.linear_velocity = f * rng.randf_range(1.5, 2.6) + Vector3(rng.randf_range(-0.5, 0.5), 0.6, 0)
	sheet.last_touched_by = String(printer.state.get("by", ""))
	sheet.last_touched_time = now()
	_track_sheet(sheet)


func _track_sheet(s: Prop) -> void:
	_sheets.append(s)
	while _sheets.size() > MAX_SHEETS:
		despawn_prop(_sheets[0])
	get_tree().create_timer(rng.randf_range(100.0, 140.0)).timeout.connect(func(): despawn_prop(s))


func on_prop_broken(p: Prop) -> void:
	for i in 4:
		var sh := spawn_prop("shard", p.global_position + Vector3(0, 0.05, 0), "")
		sh.linear_velocity = Vector3(rng.randf_range(-1.5, 1.5), 1.0, rng.randf_range(-1.5, 1.5))
		_track_sheet(sh)
	if now() - p.last_touched_time < 8.0 and p.last_touched_by != "":
		var a := record_act(characters.get(p.last_touched_by), "break", 2, p.global_position, p.ent_id(), p.owner_id)
		if not a.is_empty():
			_act_by_ent[p.ent_id()] = a
	if net:
		net.on_prop_despawned(p.ent_id())


func set_device_state(d: Device) -> void:
	if net and is_authority():
		net.broadcast_device(d)


func _sync_prop(p: Prop) -> void:
	if net and is_authority():
		net.broadcast_prop_state(p)


func cushion_triggered(sitter: Character, cushion: Prop, chair: Prop) -> void:
	var fart := "fart_%d" % rng.randi_range(0, 2)
	emit_sound(chair.global_position + Vector3(0, 0.5, 0), 88.0, fart, cushion.placed_by, cushion.ent_id(), "fart")
	sitter.do_emote("embarrassed", 3.0)
	npc_say(sitter, barks.pick("boss_fart" if sitter.is_director() else "victim_fart"), "angry" if sitter.is_director() else "embarrassed")
	npc_reaction(sitter, "sat_on_cushion", {"by": cushion.placed_by})
	var a := act_for_entity(chair.ent_id())
	if not a.is_empty():
		_act_by_ent[cushion.ent_id()] = a
	if sitter.is_director() and boss_brain and not a.is_empty():
		boss_brain._incident(a, chair.global_position)
	get_tree().create_timer(4.0).timeout.connect(func(): despawn_prop(cushion))


func low_seat_triggered(sitter: Character, chair: Prop) -> void:
	var a := act_for_entity(chair.ent_id())
	emit_sound(chair.global_position, 40.0, "chair_squeak", "", chair.ent_id())
	sitter.do_emote("surprised", 2.0)
	if not sitter.is_player:
		npc_say(sitter, barks.pick("victim_lowseat"), "surprised")
	npc_reaction(sitter, "low_seat_drop", {"by": String(a.get("actor", "")) if not a.is_empty() else ""})


func give_coffee(actor: Character, machine: Device) -> void:
	if actor.is_player or actor in human_list():
		if not actor.add_item("cafe"):
			notify(actor, "Tu n'as plus de place pour un café.", "warn")
			return
		if machine.state.get("salted", false):
			actor.set_meta("salted_coffee", true)


func human_list() -> Array:
	var out: Array = []
	for id in human_ids:
		out.append(characters.get(id))
	return out


func npc_drinks_coffee(c: Character) -> void:
	var m := find_device("coffee")
	if m == null:
		return
	if m.state.get("salted", false):
		var by: String = m.state.get("by", "")
		m.state.salted_uses = int(m.state.get("salted_uses", 0)) + 1
		if int(m.state.salted_uses) >= 2:
			m.state.salted = false
			m.state.salted_uses = 0
		c.do_emote("disgust", 3.0)
		npc_say(c, barks.pick("victim_salt"), "angry")
		emit_sound(c.global_position, 30.0, "drink_slurp", "", "")
		npc_reaction(c, "drank_salted", {"by": by})
		var b: CoworkerBrain = brains.get(c.id)
		var a := act_for_entity(m.ent_id())
		if b and not a.is_empty():
			b.mem.add_grievance(String(a.actor), 0.5)
	else:
		emit_sound(c.global_position, 18.0, "drink_slurp", "", "")


func drink_coffee(actor: Character, cup: Prop) -> void:
	actor.do_emote("drink", 2.0)
	despawn_prop(cup)


func satisfy_need(actor: Character, need: String, amount := 1.0) -> void:
	var b: CoworkerBrain = brains.get(actor.id)
	if b:
		b.needs[need] = maxf(0.0, float(b.needs.get(need, 0.0)) - amount)


func spend(actor: Character, amount: int) -> bool:
	if economy.money(actor.id) < amount:
		return false
	economy.add(actor.id, -amount)
	return true


func set_zone_lights(zone: String, on: bool, by: String) -> void:
	world.set_zone_lights(zone, on)
	if net:
		net.broadcast_lights(zone, on)
	if not on:
		game_event("action", {"action": "light_off", "actor": by, "zone": zone, "light_zone": zone})
		for id in brains:
			var c: Character = characters[id]
			if world.zone_at(c.global_position) == zone:
				brains[id].react_to("surprised", "lights_off", "surprised", 2.0)
		if day.meeting_active and zone == "meeting":
			emit_sound(world.zone_center("meeting"), 55.0, "", "", "", "laugh")
		get_tree().create_timer(45.0).timeout.connect(func():
			if not world.zone_lit(zone):
				world.set_zone_lights(zone, true)
				if net:
					net.broadcast_lights(zone, true))


func start_smell(pos: Vector3, by: String) -> void:
	smell = {"pos": pos, "until": now() + 50.0, "by": by}
	emit_sound(pos, 20.0, "smell_waft", by, "", "smell")


func _update_smell(delta: float) -> void:
	if smell.is_empty():
		return
	if now() > float(smell.until):
		smell = {}
		return
	_smell_t -= delta
	if _smell_t > 0.0:
		return
	_smell_t = 3.0
	for id in brains:
		var c: Character = characters[id]
		if c.global_position.distance_to(smell.pos) < 11.0 and rng.randf() < 0.35:
			brains[id].react_to("disgust", "smell_fish", "angry", 2.5, smell.pos)
			npc_reaction(c, "smelled_fish", {"by": smell.by})
	if boss_brain and director.global_position.distance_to(smell.pos) < 14.0 and boss_brain.stimulus.is_empty():
		boss_brain.stimulus = {"pos": smell.pos, "kind": "smell", "loud": 50.0, "time": now(), "zone": world.zone_at(smell.pos), "source": ""}


func open_container(actor: Character, dev: Device) -> Dictionary:
	if dev.state.get("confetti", false):
		_confetti_burst(actor, dev)
		return {"ok": true}
	if dev.contents.is_empty():
		return {"ok": true, "msg": "C'est vide."}
	var pid: String = dev.contents.pop_back()
	var p: Prop = world.ent(pid)
	if p == null:
		return {"ok": true}
	dev.contents.erase(pid)
	if p.pocketable and actor.add_item(p.item_id):
		p.inside_of = "pocket:" + actor.id
		p.touch(actor)
		notify(actor, "Tu récupères : " + p.display, "good")
	else:
		p.reveal_at(Transform3D(Basis(), actor.global_position + actor.forward() * 0.6 + Vector3(0, 0.5, 0)))
	return {"ok": true}


func hide_in_container(actor: Character, dev: Device, item: String) -> Dictionary:
	if item == "" and not actor.items.is_empty():
		item = actor.items[0]
	if not actor.consume_item(item):
		return {"ok": false, "msg": "Tu n'as pas cet objet."}
	var pr := _find_pocketed(actor, item)
	if pr == null:
		var kind: String = PropFactory.ITEM_TO_PROP.get(item, "")
		if kind == "":
			actor.add_item(item)
			return {"ok": false, "msg": "Impossible de cacher ça ici."}
		pr = spawn_prop(kind, dev.global_position, actor.id)
	pr.global_position = dev.global_position
	pr.hide_inside(dev.ent_id())
	pr.touch(actor)
	dev.contents.append(pr.ent_id())
	notify(actor, "%s caché(e) dans : %s" % [Data.item_name(item), dev.display], "info")
	return {"ok": true}


func _confetti_burst(victim: Character, dev: Device) -> void:
	dev.state.confetti = false
	var by: String = dev.state.get("by", "")
	emit_sound(dev.global_position + Vector3(0, 0.5, 0), 86.0, "confetti_pop", by, dev.ent_id(), "confetti")
	_spawn_confetti_fx(dev.global_position + Vector3(0, 0.6, 0))
	if net:
		net.broadcast_fx("confetti", dev.global_position + Vector3(0, 0.6, 0))
	victim.do_emote("surprised", 2.5)
	npc_say(victim, barks.pick("confetti"), "surprised")
	npc_reaction(victim, "confetti_burst", {"by": by})
	if victim.is_director() and boss_brain:
		var a := act_for_entity(dev.ent_id())
		if not a.is_empty():
			boss_brain._incident(a, dev.global_position)


func _spawn_confetti_fx(pos: Vector3) -> void:
	if Settings.get_v("reduce_effects"):
		return
	var p := CPUParticles3D.new()
	p.amount = 160
	p.one_shot = true
	p.explosiveness = 0.95
	p.lifetime = 3.0
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 6.0
	p.gravity = Vector3(0, -3.0, 0)
	p.damping_min = 1.0
	p.damping_max = 2.0
	var q := QuadMesh.new()
	q.size = Vector2(0.04, 0.025)
	p.mesh = q
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	q.material = m
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(1, 0.2, 0.3), Color(1, 0.85, 0.1), Color(0.2, 0.6, 1), Color(0.3, 0.9, 0.3)])
	g.offsets = PackedFloat32Array([0.0, 0.33, 0.66, 1.0])
	p.color_initial_ramp = g
	p.angular_velocity_min = -400
	p.angular_velocity_max = 400
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(4.0).timeout.connect(p.queue_free)


func boss_opens_drawer(boss: Character) -> void:
	for e in world.interactables:
		if e is Device and (e as Device).kind == "boss_drawer" and (e as Device).state.get("confetti", false):
			_confetti_burst(boss, e)


func reveal_boss_intel(actor: Character) -> void:
	var top := ""
	if boss_brain:
		top = boss_brain.sus.top_suspect()
	var next_in := day.minutes_to_next("meeting")
	var txt := "Écran du chef — Principal suspect : %s. " % (char_name(top) if top != "" else "personne")
	if next_in < INF:
		txt += "Prochaine réunion dans %d min." % int(next_in)
	if boss_brain:
		txt += " Ton niveau : %s." % boss_brain.sus.level_name(actor.id)
	notify(actor, txt, "event")


func npc_searches_container(c: Character, dev: Device) -> void:
	if dev.state.get("confetti", false):
		_confetti_burst(c, dev)
		return
	if dev.contents.is_empty():
		return
	for pid in dev.contents:
		var p: Prop = world.ent(pid)
		if p and p.contraband >= 0.5:
			dev.contents.erase(pid)
			p.reveal_at(p.home)
			npc_say(c, "Tiens ? Qu'est-ce que %s fait là ?" % p.display.to_lower(), "surprised")
			var a := act_for_entity(pid)
			var b: CoworkerBrain = brains.get(c.id)
			if b and not a.is_empty():
				b.mem.remember_act(a, "", "personne", 0.2, now())
			return


# ------------------------------------------------------------------ characters events
func on_character_stumble(c: Character, cause: String, by: String) -> void:
	if not is_authority():
		return
	if not c.is_player:
		npc_say(c, barks.pick("react_stumble"), "surprised")
	game_event("stumble", {"who": c.id, "by": by, "cause": cause})


func on_character_fell(c: Character, cause: String, by: String) -> void:
	if not is_authority():
		return
	game_event("fall", {"who": c.id, "by": by, "cause": cause})
	if by != "" and stats.has(by) and by != c.id:
		stats[by].falls_caused += 1
	if c.is_director():
		npc_say(c, barks.pick("boss_slip"), "panic")
		if cause == "banana":
			npc_reaction(c, "slipped", {"by": by})
	elif not c.is_player:
		npc_say(c, barks.pick("react_fall_self"), "panic")
	# witnesses laugh
	for id in brains:
		var o: Character = characters[id]
		if o != c and o.global_position.distance_to(c.global_position) < 9.0 and rng.randf() < 0.7:
			brains[id].react_to("laugh", "react_fall_other", "laugh", 2.5, c.global_position)
	if by != "" and by != c.id and characters.has(by):
		var a := record_act(characters[by], "trip", 2 if not c.is_director() else 3, c.global_position, "", c.id)
		if not a.is_empty() and stats.has(by):
			pass


func npc_reaction(c: Character, reaction: String, d: Dictionary) -> void:
	var data := d.duplicate()
	data["reaction"] = reaction
	data["npc"] = c.id
	data["is_director"] = c.is_director()
	if not data.has("by"):
		data["by"] = ""
	game_event("npc_reaction", data)


func npc_minor_infraction(c: Character, kind: String) -> void:
	record_act(c, kind, 1, c.global_position, "", "")


func rumor_effect(id: String, effect: String) -> float:
	var b: CoworkerBrain = brains.get(id)
	if b == null:
		return 0.0
	for key in b.mem.rumors:
		var r: Dictionary = rumors.get(key, {})
		if Data.rumors.get(r.get("id", ""), {}).get("effect", "") == effect and float(b.mem.rumors[key].belief) > 0.4:
			return 1.0
	return 0.0


# ------------------------------------------------------------------ acts & witnesses
func record_act(actor: Character, kind: String, sev: int, pos: Vector3, target_id: String, victim := "") -> Dictionary:
	if actor == null or not is_authority():
		return {}
	var act := {"id": _next_act, "kind": kind, "actor": actor.id, "pos": pos, "zone": world.zone_at(pos), "time": now(),
		"sev": sev, "target": target_id, "victim": victim}
	_next_act += 1
	acts.append(act)
	if acts.size() > 200:
		acts.pop_front()
	if target_id != "":
		_act_by_ent[target_id] = act
	_witness(act, actor)
	return act


func _witness(act: Dictionary, actor: Character) -> void:
	for id in characters:
		if id == actor.id:
			continue
		var w: Character = characters[id]
		var fov := 140.0
		var rng_m := 12.0
		if id == "boss" and boss_brain:
			fov = boss_brain._current_fov()
			rng_m = boss_brain._current_range()
		elif brains.has(id):
			rng_m = 9.0 + 7.0 * float(w.traits.get("observation", 0.5))
		elif id in human_ids:
			rng_m = 14.0
			fov = 120.0
		var vis := Perception.visibility(world, w, actor, fov, rng_m)
		if vis < 0.08:
			continue
		var dist := w.global_position.distance_to(actor.global_position)
		var info := Perception.describe(actor, dist, vis)
		info["conf"] = clampf(vis * 1.6, 0.1, 1.0)
		if id == "boss" and boss_brain:
			boss_brain.on_witness(act, info)
		elif brains.has(id):
			brains[id].on_witness(act, info)
		elif human_memory.has(id):
			(human_memory[id] as Memory).remember_act(act, info.id, info.desc, info.conf, now())
			if net and id == "boss":
				net.send_director_note(act, info)
		game_event("witness", {"actor": actor.id, "witness": id, "desc": info.desc, "act_id": act.id})


## Director catches someone during a timed prank: cancel it and record the act.
func interrupt_and_commit(e: Character) -> Dictionary:
	if e.action.is_empty():
		return {}
	var a := e.action
	var def: Dictionary = a.def
	_cancel_action(e, "Pris sur le fait !")
	var tgt: Node = world.ent(a.target)
	var pos: Vector3 = tgt.interact_point() if tgt else e.global_position
	var owner := ""
	if tgt and tgt.get("owner_id") != null:
		owner = String(tgt.get("owner_id"))
	return record_act(e, String(def.get("act", "prank")), int(def.get("sev", 1)), pos, String(a.target), owner)


func share_witness(from: String, to: String, w: Dictionary) -> void:
	var b: CoworkerBrain = brains.get(to)
	var act := act_by_id(int(w.act_id))
	if b == null or act.is_empty():
		return
	b.mem.remember_act(act, String(w.actor), String(w.desc), float(w.conf) * 0.6, now())
	if rng.randf() < 0.4:
		b.pending.append({"act": act, "decide_at": now() + rng.randf_range(5.0, 20.0), "who": w.actor})


func npc_report(brain: CoworkerBrain, w: Dictionary) -> void:
	var accused: String = w.get("actor", "")
	npc_say(brain.c, barks.pick("report_tell", {"name": char_name(accused)}), "angry")
	_add_testimony(int(w.act_id), brain.c.id, accused, "report")
	if boss_brain:
		boss_brain.on_testimony(brain.c.id, accused, int(w.act_id), "report", now())
		director.look_at_point(brain.c.eye_position())
	elif net:
		net.send_director_testimony(brain.c.id, accused, int(w.act_id), "report")


func question_witness(boss: Character, w: Character, act: Dictionary) -> void:
	var b: CoworkerBrain = brains.get(w.id)
	if b == null:
		return
	var cands: Array = []
	for e in employees():
		cands.append(e.id)
	var ans := Testimony.answer(w.id, w.traits, b.mem, relations, act, cands, rng, 0.3)
	var line := ""
	match String(ans.kind):
		"truth":
			line = barks.pick("testimony_truth", {"name": char_name(ans.accused)})
		"lie", "hearsay":
			line = barks.pick("testimony_lie", {"name": char_name(ans.accused)})
		"partial":
			line = barks.pick("testimony_partial", {"desc": ans.desc})
			_partial_description(String(ans.desc), act)
			game_event("witness", {"actor": act.actor, "witness": w.id, "desc": ans.desc, "act_id": act.id})
		"protect":
			line = barks.pick("testimony_protect")
		_:
			line = barks.pick("testimony_nothing")
	w.look_at_point(boss.eye_position())
	npc_say(w, line, "neutral" if ans.kind != "lie" else "suspicious")
	if String(ans.accused) != "":
		w.do_emote("point", 2.0)
		_add_testimony(int(act.id), w.id, String(ans.accused), String(ans.kind))
		if boss_brain:
			boss_brain.on_testimony(w.id, String(ans.accused), int(act.id), String(ans.kind), now())


## A vague description ("une chemise bleue") still points the director at matching people.
func _partial_description(desc: String, act: Dictionary) -> void:
	if boss_brain == null or desc.contains("moustache"):
		return
	for e in employees():
		var ec: Character = e
		var my := "une chemise " + Perception.color_name(Color(ec.appearance.get("shirt", "#888888")))
		if my == desc:
			boss_brain.sus.add(ec.id, 6.0, "description", int(act.id), "desc", now())
			on_suspicion_changed(ec.id)


func _add_testimony(act_id: int, witness: String, accused: String, kind: String) -> void:
	if not testimonies.has(act_id):
		testimonies[act_id] = []
	var arr: Array = testimonies[act_id]
	for t in arr:
		if t.witness == witness:
			return
	arr.append({"witness": witness, "accused": accused, "kind": kind})
	game_event("testimony", {"act_id": act_id, "witness": witness, "accused": accused})
	var accused_set := {}
	for t in arr:
		if String(t.accused) != "":
			accused_set[t.accused] = true
	if accused_set.size() >= 2:
		var act := act_by_id(act_id)
		game_event("contradiction", {"act_id": act_id, "actor": act.get("actor", ""), "involved": accused_set.keys()})
		if boss_brain:
			for k in accused_set:
				boss_brain.sus.add(k, -8.0, "contradiction", act_id, "", now())


# ------------------------------------------------------------------ rumours
func rumor_text(key: String) -> String:
	var r: Dictionary = rumors.get(key, {})
	var base: String = Data.rumors.get(r.get("id", ""), {}).get("text", "…")
	return base.replace("{about}", char_name(r.get("about", "")))


func start_rumor(origin: String, rumor_id: String, about: String, first: String) -> String:
	var key := rumor_id + ":" + about
	if not rumors.has(key):
		rumors[key] = {"id": rumor_id, "about": about, "origin": origin, "believers": {}}
	spread_rumor(origin, first, key)
	return key


func spread_rumor(from: String, to: String, key: String) -> void:
	var r: Dictionary = rumors.get(key, {})
	if r.is_empty():
		return
	var b: CoworkerBrain = brains.get(to)
	if b == null:
		return
	var cred: float = b.t.get("credulity", 0.5)
	var trust := 0.5 + 0.5 * relations.get_aff(to, from)
	var belief := clampf(cred * (0.6 + 0.6 * trust), 0.05, 1.0)
	if b.mem.rumors.has(key):
		b.mem.rumors[key].belief = maxf(float(b.mem.rumors[key].belief), belief)
		return
	b.mem.rumors[key] = {"belief": belief, "from": from, "about": r.about, "time": now()}
	if belief > 0.35:
		r.believers[to] = true
		var eff: String = Data.rumors.get(r.id, {}).get("effect", "")
		match eff:
			"wrong_meeting":
				b.believe_meeting_moved()
				npc_reaction(b.c, "wrong_meeting_planted", {"by": r.origin})
			"go_break":
				b._switch("go_zone", {"zone": "break", "dur": 15.0, "cat": "croissants"})
			"blame":
				relations.change(to, String(r.about), -0.25)
				b.mem.add_grievance(String(r.about), 0.4)
	game_event("rumor_spread", {"origin": r.origin, "count": r.believers.size(), "key": key})
	# a widely believed accusation reaches the director's ears
	if r.believers.size() >= 3 and Data.rumors.get(r.id, {}).get("effect", "") == "blame" and boss_brain and not r.get("reached_boss", false):
		r["reached_boss"] = true
		var k := 2.0 if profile == "manipulator" else 1.0
		boss_brain.sus.add(String(r.about), 10.0 * k, "rumor", -1, "rumor", now())
		on_suspicion_changed(String(r.about))


# ------------------------------------------------------------------ diversion
func start_diversion(npc: Character, for_id: String) -> void:
	diversion = {"npc": npc.id, "for": for_id, "until": now() + 22.0}
	if boss_brain:
		boss_brain.distract(npc.id, 22.0)
	if characters.has(for_id):
		notify(characters[for_id], "%s distrait le directeur ! Tu as ~20 secondes." % npc.nick, "good")


func end_diversion(_npc: Character) -> void:
	diversion = {}


# ------------------------------------------------------------------ social actions
func social_actions(actor: Character, target: Character) -> Array:
	var out: Array = []
	if target.is_down():
		return out
	if target.is_director():
		if actor.is_director():
			return out
		out.append({"id": "flatter", "label": "Faire du lèche-bottes", "time": 2.0})
		out.append({"id": "denounce", "label": "Dénoncer un collègue…", "time": 0.0, "ui": "denounce"})
		return out
	if actor.is_director():
		out.append({"id": "interrogate", "label": "Interroger", "time": 0.0, "ui": "boss_interrogate"})
		out.append({"id": "sanction", "label": "Sanctionner", "time": 0.0, "ui": "boss_sanction"})
		return out
	var b: CoworkerBrain = brains.get(target.id)
	out.append({"id": "chat", "label": "Discuter avec " + target.nick, "time": 2.0})
	if b == null:
		return out
	out.append({"id": "coffee_invite", "label": "Proposer une pause café", "time": 0.0})
	out.append({"id": "rumor", "label": "Lancer une rumeur…", "time": 0.0, "ui": "rumor"})
	out.append({"id": "lie_meeting", "label": "Mentir : « la réunion est reportée »", "time": 0.0, "sus": 0.2})
	if accomplices.get(target.id, "") == actor.id:
		out.append({"id": "diversion", "label": "Demander une diversion", "time": 0.0})
	else:
		out.append({"id": "recruit", "label": "Proposer d'être complice", "time": 0.0})
	if _witnessed_by(b, actor.id):
		out.append({"id": "bribe", "label": "Acheter son silence (25 €)", "time": 0.0})
	if actor.has_item("cafe"):
		out.append({"id": "give_coffee", "label": "Offrir ton café", "time": 0.0})
	return out


func _witnessed_by(b: CoworkerBrain, actor_id: String) -> bool:
	for w in b.mem.witnessed:
		if w.actor == actor_id and not w.reported:
			return true
	return false


func perform_social(actor: Character, target: Character, act: String, params: Dictionary) -> Dictionary:
	var b: CoworkerBrain = brains.get(target.id)
	if b:
		b.talked_to(actor)
	var aff := relations.get_aff(target.id, actor.id)
	match act:
		"chat":
			var key := actor.id + ">" + target.id
			if now() - float(_chat_t.get(key, -999.0)) > 45.0:
				relations.change(target.id, actor.id, 0.06)
				_chat_t[key] = now()
			npc_say(target, barks.pick("chat", {"name": actor.nick}), "happy" if aff > 0.2 else "neutral")
		"coffee_invite":
			var p: float = 0.25 + aff * 0.5 + (1.0 - float(target.traits.get("work", 0.5))) * 0.3
			if b and rng.randf() < p:
				npc_say(target, barks.pick("coffee_yes"), "happy")
				b._switch("go_zone", {"zone": "break", "dur": 30.0, "emote": "drink"})
				game_event("coffee_invite", {"actor": actor.id, "target": target.id})
			else:
				npc_say(target, barks.pick("coffee_no"), "neutral")
				return {"ok": true, "msg": target.nick + " refuse."}
		"rumor":
			var rid: String = params.get("rumor", "meeting_moved")
			if not Data.rumors.has(rid):
				return {"ok": false, "msg": "Rumeur inconnue."}
			var about: String = params.get("about", "")
			if Data.rumors[rid].get("about", "") == "target" and not characters.has(about):
				return {"ok": false, "msg": "Choisis une cible."}
			start_rumor(actor.id, rid, about, target.id)
			var believed: bool = b.mem.rumors.get(rid + ":" + about, {}).get("belief", 0.0) > 0.35
			npc_say(target, barks.pick("lie_believed" if believed else "lie_doubted"), "surprised" if believed else "suspicious")
			if Data.rumors[rid].get("about", "") == "target":
				record_act(actor, "rumor", 1, actor.global_position, "", about)
		"lie_meeting":
			var cred: float = target.traits.get("credulity", 0.5)
			if rng.randf() < cred * (0.7 + 0.3 * maxf(0.0, aff)) + 0.1:
				b.believe_meeting_moved()
				npc_say(target, barks.pick("lie_believed"), "happy")
				npc_reaction(target, "wrong_meeting_planted", {"by": actor.id})
				target.set_meta("lied_by", actor.id)
			else:
				npc_say(target, barks.pick("lie_doubted"), "suspicious")
				b.mem.add_grievance(actor.id, 0.2)
				relations.change(target.id, actor.id, -0.08)
		"recruit":
			var ok: bool = aff > 0.35 or (float(target.traits.get("loyalty", 0.5)) > 0.8 and aff > 0.0) or (target.archetype == "opportunist" and rng.randf() < 0.5)
			if ok:
				accomplices[target.id] = actor.id
				npc_say(target, barks.pick("accomplice_yes"), "laugh")
				notify(actor, target.nick + " accepte d'être ton complice !", "good")
			else:
				npc_say(target, barks.pick("accomplice_no"), "angry")
				relations.change(target.id, actor.id, -0.03)
				return {"ok": true, "msg": "Il faut d'abord gagner sa confiance (discute avec lui)."}
		"diversion":
			if accomplices.get(target.id, "") != actor.id:
				return {"ok": false, "msg": "Ce n'est pas ton complice."}
			if director == null:
				return {"ok": false, "msg": "Pas de directeur."}
			b.ask_diversion(actor.id)
			npc_say(target, "OK, j'y vais !", "laugh")
		"bribe":
			if not spend(actor, 25):
				return {"ok": false, "msg": "Pas assez d'argent."}
			if rng.randf() < 0.35 + (1.0 - float(target.traits.get("honesty", 0.5))) * 0.6:
				for w in b.mem.witnessed:
					if w.actor == actor.id:
						w.reported = true
				b.pending = b.pending.filter(func(p): return p.get("who", "") != actor.id)
				b.bribed_by = actor.id
				npc_say(target, barks.pick("bribe_yes"), "happy")
			else:
				npc_say(target, barks.pick("bribe_no"), "angry")
				b.pending.append({"act": act_by_id(int(b.mem.witnessed[-1].act_id)) if not b.mem.witnessed.is_empty() else {}, "decide_at": now() + 2.0, "who": actor.id})
		"give_coffee":
			if not actor.consume_item("cafe"):
				return {"ok": false, "msg": "Pas de café."}
			relations.change(target.id, actor.id, 0.2)
			target.do_emote("drink", 2.5)
			if actor.get_meta("salted_coffee", false):
				actor.set_meta("salted_coffee", false)
				npc_say(target, barks.pick("victim_salt"), "angry")
				relations.change(target.id, actor.id, -0.4)
				npc_reaction(target, "drank_salted", {"by": actor.id})
			else:
				npc_say(target, "Oh, merci !", "happy")
		"flatter":
			var key2 := actor.id + ">flatter"
			if now() - float(_chat_t.get(key2, -999.0)) > 90.0 and boss_brain:
				_chat_t[key2] = now()
				boss_brain.sus.add(actor.id, -6.0, "flatter", -1, "", now())
				npc_say(target, "Hmm. Bon travail… je suppose.", "neutral")
			else:
				npc_say(target, "Vous n'avez pas du travail, vous ?", "suspicious")
		"denounce":
			return denounce(actor, String(params.get("accused", "")), int(params.get("act_id", -1)))
		_:
			return {"ok": false, "msg": "Action inconnue."}
	return {"ok": true}


## Player → director testimony. Truthful if the accused really committed that act.
func denounce(actor: Character, accused: String, act_id: int) -> Dictionary:
	if not is_employee(accused) or accused == actor.id:
		return {"ok": false, "msg": "Dénonciation invalide."}
	var act := act_by_id(act_id)
	if act.is_empty():
		# vague accusation: attach it to the latest unresolved incident
		act = acts[-1] if not acts.is_empty() else {}
		if act.is_empty():
			return {"ok": false, "msg": "Il ne s'est rien passé… pour l'instant."}
	var truthful: bool = act.actor == accused
	if stats.has(actor.id):
		stats[actor.id].denounce += 1
	if mode == "solo":
		SaveGame.add_stat("denunciations")
	_add_testimony(int(act.id), actor.id, accused, "truth" if truthful else "lie")
	game_event("denounce", {"actor": actor.id, "accused": accused, "act_id": act.id, "truthful": truthful})
	npc_say(actor, barks.pick("accuse", {"name": char_name(accused)}), "neutral")
	if boss_brain:
		boss_brain.on_testimony(actor.id, accused, int(act.id), "truth" if truthful else "lie", now())
		npc_say(director, "Intéressant. Je vais m'en occuper.", "suspicious")
	elif net:
		net.send_director_testimony(actor.id, accused, int(act.id), "player")
	# the accused may learn about it through gossip
	if brains.has(accused) and rng.randf() < 0.5:
		brains[accused].mem.add_grievance(actor.id, 0.6)
		relations.change(accused, actor.id, -0.3)
	return {"ok": true}


# ------------------------------------------------------------------ interrogation & sanctions
func start_interrogation(boss: Character, who: Character, act_id: int, strength: float) -> void:
	var act := act_by_id(act_id)
	interrogation = {"boss": boss.id, "who": who.id, "act_id": act_id, "strength": strength, "t": now()}
	who.stop()
	if who.held:
		who.drop_held(Vector3.ZERO)
	if who.action.size() > 0:
		_cancel_action(who, "Le directeur t'interpelle.")
	npc_say(boss, barks.pick("interrogate_open"), "angry")
	who.look_at_point(boss.eye_position())
	var info := {"act_id": act_id, "act_text": act_description(act), "strength": strength, "hint": _strength_hint(strength),
		"candidates": _accusable(who.id), "boss": boss.nick}
	if who == player:
		interrogation_started.emit(info)
	elif who.id in human_ids and net:
		net.send_interrogation(who.id, info)
	else:
		# NPC answers by itself
		get_tree().create_timer(2.5).timeout.connect(func(): _npc_answer(who))


func _accusable(except: String) -> Array:
	var out: Array = []
	for e in employees():
		if e.id != except:
			out.append({"id": e.id, "name": e.nick})
	return out


func _strength_hint(s: float) -> String:
	if s >= 0.95:
		return "Il t'a vu de ses propres yeux."
	if s > 0.6:
		return "Il a l'air très sûr de lui."
	if s > 0.35:
		return "Il a des soupçons, sans plus."
	return "Il tâtonne."


func act_description(act: Dictionary) -> String:
	var k: String = act.get("kind", "")
	var txt: String = {"wallpaper": "changer le fond d'écran d'un collègue", "postits": "couvrir un écran de post-it", "lower_seat": "saboter un siège",
		"cushion": "poser un coussin péteur", "salt_coffee": "saler le café", "heat_fish": "faire chauffer du poisson", "caricature": "dessiner une caricature",
		"lights_off": "éteindre la lumière en réunion", "print_spam": "lancer une impression géante", "mix_files": "mettre le bazar aux archives",
		"fake_planning": "falsifier le planning", "steal": "voler un objet", "trespass": "fouiner dans mon bureau", "spy": "fouiller mon ordinateur",
		"slam_door": "claquer les portes", "throw": "lancer des objets", "kick_chair": "jouer avec les chaises", "vandalism": "renverser une poubelle",
		"confetti_trap": "piéger un tiroir", "banana_trap": "poser une peau de banane", "trip": "faire tomber quelqu'un", "slacking": "tirer au flanc",
		"break": "casser quelque chose", "radio": "mettre la radio à fond", "rumor": "répandre des rumeurs"}.get(k, "faire une bêtise")
	return "On vous soupçonne de : %s (%s)." % [txt, world.zone_name(String(act.get("zone", "")))]


func _npc_answer(who: Character) -> void:
	if interrogation.is_empty() or interrogation.who != who.id:
		return
	var act := act_by_id(int(interrogation.act_id))
	var guilty: bool = act.get("actor", "") == who.id
	var t := who.traits
	var choice := "deny"
	var params := {}
	if guilty and float(t.get("honesty", 0.5)) > 0.8:
		choice = "confess"
	elif float(t.get("courage", 0.5)) < 0.2 or (not guilty and rng.randf() < 0.3):
		var b: CoworkerBrain = brains.get(who.id)
		var ans := Testimony.answer(who.id, t, b.mem if b else Memory.new(), relations, act, _accusable("").map(func(x): return x.id), rng, 1.0)
		if String(ans.accused) != "" and ans.accused != who.id:
			choice = "accuse"
			params = {"accused": ans.accused}
	elif rng.randf() < 0.5:
		choice = "excuse"
	var line: String = {"deny": "deny", "confess": "confess", "excuse": "excuse", "accuse": "accuse"}[choice]
	npc_say(who, barks.pick(line, {"name": char_name(String(params.get("accused", "")))}), "panic" if choice != "confess" else "embarrassed")
	_resolve_interrogation(choice, params)


func answer_interrogation(actor: Character, choice: String, params: Dictionary) -> Dictionary:
	if interrogation.is_empty() or interrogation.who != actor.id:
		return {"ok": false, "msg": ""}
	if not choice in ["deny", "excuse", "confess", "accuse"]:
		return {"ok": false, "msg": "Réponse invalide."}
	if actor.is_player:
		var line: String = {"deny": "deny", "confess": "confess", "excuse": "excuse", "accuse": "accuse"}[choice]
		npc_say(actor, barks.pick(line, {"name": char_name(String(params.get("accused", "")))}), "panic")
	_resolve_interrogation(choice, params)
	return {"ok": true}


func _resolve_interrogation(choice: String, params: Dictionary) -> void:
	if interrogation.is_empty():
		return
	var iv := interrogation
	interrogation = {}
	var who: Character = characters.get(iv.who)
	var act := act_by_id(int(iv.act_id))
	var strength := float(iv.strength)
	var guilty: bool = act.get("actor", "") == iv.who
	var outcome := "cleared"
	var sus := suspicion_of(iv.who)
	match choice:
		"confess":
			outcome = "sanctioned"
		"deny":
			var p_clear := (1.0 - strength) * 0.85 + (0.25 if not guilty else 0.0)
			outcome = "sanctioned" if strength >= 0.95 or rng.randf() > p_clear else "cleared"
		"excuse":
			var plaus := 0.5
			if who and who.seated_on:
				plaus += 0.2
			if who and now() - who.last_work_time < 60.0:
				plaus += 0.15
			if who and world.zone_at(who.global_position) == "boss_office":
				plaus -= 0.35
			if who:
				plaus -= who.visible_contraband() * 0.5
			var p := clampf(plaus, 0.05, 0.95) * (1.0 - strength * 0.8) + (0.2 if not guilty else 0.0)
			outcome = "cleared" if rng.randf() < p and strength < 0.95 else "sanctioned"
		"accuse":
			var accused: String = params.get("accused", "")
			if not is_employee(accused) or accused == iv.who:
				outcome = "sanctioned"
			else:
				_add_testimony(int(iv.act_id), iv.who, accused, "accuse")
				var alibi := {}
				var near := false
				if boss_brain:
					alibi = boss_brain.mem.where_was(accused, float(act.get("time", 0.0)), 6.0)
					near = accused in boss_brain.mem.seen_near(String(act.get("zone", "")), float(act.get("time", 0.0)), 30.0)
				if not alibi.is_empty() and alibi.zone != act.get("zone", ""):
					outcome = "sanctioned"
					if sus:
						sus.add(iv.who, 15.0, "false_accusation", int(iv.act_id), "boss", now())
					npc_say(director, "%s était ailleurs, je l'ai vu. Vous mentez !" % char_name(accused), "angry")
				elif strength < 0.95 and (near or act.get("actor", "") == accused or rng.randf() < 0.3):
					outcome = "redirected"
					if sus:
						sus.add(accused, 28.0, "testimony", int(iv.act_id), iv.who, now())
					if brains.has(accused):
						brains[accused].mem.add_grievance(iv.who, 1.0)
						relations.change(accused, iv.who, -0.4)
				else:
					outcome = "sanctioned"
	var info := {"who": iv.who, "outcome": outcome, "act_id": iv.act_id, "guilty": guilty, "choice": choice}
	if outcome == "sanctioned":
		info.merge(_sanction(who, act, guilty))
	if boss_brain:
		boss_brain.on_interrogation_done(iv.who, int(iv.act_id), outcome)
	if who == player:
		interrogation_finished.emit(info)
	elif who and who.id in human_ids and net:
		net.send_interrogation_result(who.id, info)
	if net:
		net.on_interrogation_resolved(info)
	if who and not who.is_player and outcome != "sanctioned":
		who.do_emote("shrug", 2.0)


func _sanction(who: Character, act: Dictionary, guilty: bool) -> Dictionary:
	if who == null:
		return {}
	var sev := int(act.get("sev", 1))
	warnings[who.id] = int(warnings.get(who.id, 0)) + 1
	var fine := 10 + sev * 8
	var res := {"warning": warnings[who.id], "fine": fine, "confiscated": ""}
	if who.id in human_ids:
		economy.add(who.id, -fine)
		fines[who.id] = int(fines.get(who.id, 0)) + fine
		for it in who.items:
			if float(Data.item_info(it).get("contraband", 0.0)) >= 0.5:
				who.consume_item(it)
				res.confiscated = Data.item_name(it)
				break
		if mode == "solo":
			SaveGame.add_stat("warnings")
			SaveGame.add_stat("times_caught")
			SaveGame.data.reputation = maxi(0, int(SaveGame.data.reputation) - 4)
	else:
		who.do_emote("embarrassed", 3.0)
		var b: CoworkerBrain = brains.get(who.id)
		if b:
			for t in testimonies.get(int(act.get("id", -1)), []):
				b.mem.add_grievance(String(t.witness), 0.8)
	game_event("sanction", {"target": who.id, "act_kind": act.get("kind", ""), "correct": guilty})
	if who == player:
		SoundFx.ui("warning_sting")
	if who.id in human_ids and int(warnings[who.id]) >= 3 and mode == "solo":
		day_failed = true
		get_tree().create_timer(2.5).timeout.connect(func(): end_day(true))
	return res


# ------------------------------------------------------------------ inspection
func inspect_desk(boss: Character, desk: Dictionary, brain: DirectorBrain) -> void:
	var owner: String = desk.owner
	var oc: Character = characters.get(owner)
	if oc == null:
		return
	var t := now()
	if oc.global_position.distance_to(desk.seat) > 3.0 and not day.meeting_active:
		brain.sus.add(owner, 6.0, "absent", -1, "boss", t)
		npc_say(boss, "Et %s, il est où ?" % oc.nick, "suspicious")
	elif oc.get_meta("slacking", false):
		var a := record_act(oc, "slacking", 1, oc.global_position, "", "")
		brain.sus.set_confirmed(owner, int(a.id), t)
	elif oc.pretending_until > t and t - oc.last_work_time > 60.0 and float(brain.prof.get("inspect_bias", 0.5)) > 0.4:
		brain.sus.add(owner, 12.0, "pretend", -1, "boss", t)
		npc_say(boss, "Votre écran affiche la même chose depuis une heure…", "suspicious")
	else:
		npc_say(boss, "Bien. Continuez.", "neutral")
	# drawers: contraband is found (even if someone else planted it!)
	var dr: Device = world.ent(desk.drawer_id)
	if dr and not dr.contents.is_empty() and rng.randf() < 0.5 + float(brain.prof.get("inspect_bias", 0.5)) * 0.5:
		for pid in dr.contents.duplicate():
			var p: Prop = world.ent(pid)
			if p and p.contraband >= 0.5:
				dr.contents.erase(pid)
				p.reveal_at(p.home)
				brain.sus.add(owner, 18.0, "drawer", -1, "boss", t)
				var ma := act_for_entity(pid)
				if not ma.is_empty():
					brain.sus.add(owner, 10.0, "drawer", int(ma.id), "boss", t)
				npc_say(boss, "Qu'est-ce que %s fait dans votre tiroir ?!" % p.display.to_lower(), "angry")
				notify(oc, "Le directeur a trouvé %s dans ton tiroir !" % p.display.to_lower(), "danger")
				break
	if dr and dr.state.get("confetti", false):
		_confetti_burst(boss, dr)
	on_suspicion_changed(owner)


# ------------------------------------------------------------------ events
func _event_info(id: String) -> Dictionary:
	match id:
		"lost_item":
			var ids := npc_ids()
			return {"who": ids[rng.randi() % ids.size()]} if not ids.is_empty() else {}
	return {}


func _on_event_started(id: String, info: Dictionary) -> void:
	var ev: Dictionary = Data.random_events.get(id, {})
	notify_all("%s — %s" % [ev.get("title", id), ev.get("desc", "")], "event")
	SoundFx.ui("notify")
	match id:
		"early_meeting":
			day.start_meeting_now(30.0)
		"printer_jam":
			var pr := find_device("printer")
			if pr:
				pr.state.jammed = true
				pr.apply_state()
				emit_sound(pr.interact_point(), 55.0, "printer_jam", "", pr.ent_id())
		"papers_drop":
			var ids := npc_ids()
			if not ids.is_empty():
				var c: Character = characters[ids[rng.randi() % ids.size()]]
				if not c.seated_on:
					spawn_paper_mess(c.global_position + c.forward() * 0.5, 7, "")
					emit_sound(c.global_position, 52.0, "papers_fall", "", "")
					npc_say(c, barks.pick("react_stumble"), "surprised")
		"it_intervention":
			_set_it(true)
		"credible_rumor":
			var ids2 := npc_ids()
			if ids2.size() >= 2:
				var a: String = ids2[rng.randi() % ids2.size()]
				var b: String = ids2[rng.randi() % ids2.size()]
				var about: String = ids2[rng.randi() % ids2.size()]
				var rid: String = ["yogurt_thief", "boss_promotion", "boss_leaving"][rng.randi() % 3]
				var key := start_rumor(a, rid, about if rid == "yogurt_thief" else "", a)
				if brains.has(a):
					brains[a].mem.rumors[key] = {"belief": 1.0, "from": a, "about": about, "time": now()}
				spread_rumor(a, b, key)
		"boxes_fall":
			var boxes := world.props_with_tag("boxes")
			var best: Prop = null
			for p in boxes:
				if best == null or (p as Prop).global_position.y > best.global_position.y:
					best = p
			if best:
				best.sleeping = false
				best.apply_impulse(Vector3(rng.randf_range(-1, 1), 0, 1).normalized() * 8.0, Vector3(0, 0.15, 0))
		"rolling_chair":
			var chairs := world.props_with_tag("chair").filter(func(p): return (p as Prop).occupant == "" and not "boss_chair" in p.tags)
			if not chairs.is_empty():
				var ch: Prop = chairs[rng.randi() % chairs.size()]
				ch.sleeping = false
				ch.apply_central_impulse(Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized() * 40.0)
				emit_sound(ch.global_position, 30.0, "chair_squeak", "", ch.ent_id())


func _on_event_ended(id: String) -> void:
	if id == "it_intervention":
		_set_it(false)


func _set_it(down: bool) -> void:
	for e in world.interactables:
		if e is Device and (e as Device).kind == "pc" and (e as Device).owner_id != "boss":
			(e as Device).state.it_down = down
			(e as Device).apply_state()
			set_device_state(e)


func _on_meeting_changed(active: bool) -> void:
	if active:
		notify_all("Réunion d'équipe en salle Synergie !", "event")
		SoundFx.ui("notify")
		for id in brains:
			brains[id].on_meeting_started()


# ------------------------------------------------------------------ missions & end of day
func _on_mission_completed(owner: String, id: String, reward: int, spotted: bool) -> void:
	economy.add(owner, reward)
	if stats.has(owner):
		stats[owner].earned += reward
	var ch: Character = characters.get(owner)
	var title: String = missions[owner].title(id)
	notify(ch, "Mission réussie : %s  +%d €%s" % [title, reward, " (repéré : moitié)" if spotted else ""], "good")
	if ch == player:
		SoundFx.ui("mission_complete")
	if net:
		net.on_mission_completed(owner, id, reward)
	hud_changed.emit()


func end_day(fired: bool) -> void:
	if _ended:
		return
	_ended = true
	running = false
	for ms in missions.values():
		ms.end_of_day()
	if mode == "solo":
		_end_day_solo(fired or day_failed)
	elif net:
		net.on_day_over()


func _end_day_solo(fired: bool) -> void:
	var ms: MissionSystem = missions.get("player")
	var done_main := 0
	for id in ms.active:
		if ms.is_done(id):
			done_main += 1
	var prod := player.productivity
	var salary := 0 if fired else int(25 + prod * 0.5)
	economy.add("player", salary)
	economy.return_pocket("player", player)
	var won := not fired and done_main >= 2 and prod >= 35.0 and int(warnings.get("player", 0)) < 3
	var d := SaveGame.data
	d.stats.days_played = int(d.stats.days_played) + 1
	if won:
		d.stats.days_won = int(d.stats.days_won) + 1
		d.tier_unlocked = mini(3, int(d.tier_unlocked) + (1 if int(d.stats.days_won) % 2 == 1 else 0))
		d.day = int(d.day) + 1
		d.rematch = false
	else:
		d.rematch = true
	for id in ms.done:
		if not id in d.missions_done:
			d.missions_done.append(id)
	d.stats.missions_done = int(d.stats.missions_done) + ms.done.size()
	d.stats.falls_caused = int(d.stats.falls_caused) + int(stats.player.falls_caused)
	for id in brains:
		d.affinity[id] = relations.get_aff(id, "player")
	var score := done_main * 100 + int(prod) + int(stats.player.earned) - int(warnings.get("player", 0)) * 50
	d.stats.best_day_score = maxi(int(d.stats.best_day_score), score)
	SaveGame.save_game()
	var results := {
		"won": won, "fired": fired, "missions_done": done_main, "missions_total": ms.active.size(),
		"side_done": ms.side.filter(func(x): return ms.is_done(x)).size(), "productivity": int(prod), "salary": salary,
		"earned": int(stats.player.earned), "fines": int(fines.get("player", 0)), "warnings": int(warnings.get("player", 0)),
		"pranks": int(stats.player.pranks), "caught": int(stats.player.caught), "falls": int(stats.player.falls_caused),
		"money": economy.money("player"), "score": score, "profile": Data.director_profiles[profile].label,
		"missions": ms.active.map(func(x): return {"title": ms.title(x), "done": ms.is_done(x)}),
	}
	day_over.emit(results)
