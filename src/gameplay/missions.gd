class_name MissionSystem
extends RefCounted
## Tracks the day's missions for one employee. Missions are data (data/missions.json);
## each rule type below is a real condition evaluated on authoritative game events or on
## world state (polled once per second). Nothing is completed from the UI.

signal completed(owner: String, mission_id: String, reward: int, spotted: bool)
signal progressed(owner: String, mission_id: String, text: String)

var owner := ""                       # character id the missions belong to
var active: Array[String] = []
var side: Array[String] = []
var done: Dictionary = {}             # mission id -> {spotted}
var progress: Dictionary = {}         # mission id -> Variant
var s: Node
var _poll := 0.0
var _hold: Dictionary = {}            # mission id -> seconds held in place
var _max_level := 0
var _denounced: Dictionary = {}       # accused ids the owner denounced today
var _invited: Dictionary = {}         # npc ids invited for a coffee


func setup(session: Node, who: String, ids: Array, side_ids: Array) -> void:
	s = session
	owner = who
	active.assign(ids)
	side.assign(side_ids)


static func pick_for_day(day: int, rng: RandomNumberGenerator, done_before: Array, count := 4) -> Array:
	var max_tier := 1 if day <= 1 else (2 if day <= 3 else 3)
	var pool: Array = []
	for id in Data.mission_order:
		var m: Dictionary = Data.missions[id]
		if int(m.tier) <= max_tier:
			pool.append(id)
	# prefer missions never completed, then shuffle deterministically
	pool.sort_custom(func(a, b): return int(a in done_before) < int(b in done_before))
	var fresh := pool.filter(func(x): return not x in done_before)
	var out: Array = []
	var src: Array = fresh if fresh.size() >= count else pool
	src = src.duplicate()
	for i in src.size():
		var j := rng.randi_range(i, src.size() - 1)
		var tmp = src[i]
		src[i] = src[j]
		src[j] = tmp
	# guarantee at least one tier-1 mission so a first day is always doable
	var has_t1 := false
	for id in src.slice(0, count):
		if int(Data.missions[id].tier) == 1:
			has_t1 = true
	if not has_t1:
		for id in src:
			if int(Data.missions[id].tier) == 1:
				src.erase(id)
				src.insert(0, id)
				break
	out = src.slice(0, count)
	return out


func rule(id: String) -> Dictionary:
	if Data.missions.has(id):
		return Data.missions[id].rule
	for sc in Data.side_challenges:
		if sc.id == id:
			return sc.rule
	return {}


func reward_of(id: String) -> int:
	if Data.missions.has(id):
		return int(Data.missions[id].reward)
	for sc in Data.side_challenges:
		if sc.id == id:
			return int(sc.reward)
	return 0


func is_done(id: String) -> bool:
	return done.has(id)


func all_ids() -> Array:
	return active + side


func _complete(id: String, bonus := 0) -> void:
	if done.has(id):
		return
	var spotted: bool = s.player_spotted_recently(owner)
	done[id] = {"spotted": spotted}
	var r := reward_of(id) + bonus
	if spotted:
		r = r / 2
	completed.emit(owner, id, r, spotted)


func _by_owner(d: Dictionary) -> bool:
	return String(d.get("actor", d.get("by", ""))) == owner


# ------------------------------------------------------------------ events
func on_event(type: String, d: Dictionary) -> void:
	if type == "sanction" and d.get("target", "") == owner:
		pass
	if type == "denounce" and d.get("actor", "") == owner:
		_denounced[d.get("accused", "")] = true
	if type == "coffee_invite" and d.get("actor", "") == owner:
		_invited[d.get("target", "")] = true
	for id in all_ids():
		if done.has(id):
			continue
		var r := rule(id)
		match String(r.get("type", "")):
			"action_on_owned":
				if type == "action" and d.get("action", "") == r.action and _by_owner(d):
					var tgt_owner: String = d.get("target_owner", "")
					if tgt_owner != "" and tgt_owner != owner and tgt_owner != "player":
						progress[id] = int(progress.get(id, 0)) + 1
						progressed.emit(owner, id, "%d/%d" % [progress[id], int(r.get("count", 1))])
						if int(progress[id]) >= int(r.get("count", 1)):
							_complete(id)
			"action_on_any":
				if type == "action" and d.get("action", "") == r.action and _by_owner(d):
					_complete(id)
			"count_action":
				if type == "action" and d.get("action", "") == r.action and _by_owner(d):
					var key := String(d.get("target", "")) if r.get("distinct", false) else str(progress.get(id + "_n", 0))
					var seen: Dictionary = progress.get(id, {})
					seen[key] = true
					progress[id] = seen
					if not r.get("distinct", false):
						progress[id + "_n"] = int(progress.get(id + "_n", 0)) + 1
					progressed.emit(owner, id, "%d/%d" % [seen.size(), int(r.count)])
					if seen.size() >= int(r.count):
						_complete(id)
			"action_during":
				if type == "action" and d.get("action", "") == r.action and _by_owner(d):
					var ok: bool = (r.condition == "meeting" and s.day.meeting_active) or (r.condition == "inspection" and s.events.active("inspection"))
					if ok and (not r.has("zone") or d.get("zone", "") == r.zone or d.get("light_zone", "") == r.zone):
						_complete(id)
			"reaction":
				if type == "npc_reaction" and d.get("reaction", "") == r.reaction and String(d.get("by", "")) == owner:
					if r.get("who", "") == "director" and not d.get("is_director", false):
						continue
					_complete(id)
			"rumor_reach":
				if type == "rumor_spread" and d.get("origin", "") == owner and int(d.get("count", 0)) >= int(r.count):
					_complete(id)
			"sound_kind":
				if type == "sound" and d.get("sfx", "") == r.kind and String(d.get("by", "")) == owner and (not r.has("zone") or d.get("zone", "") == r.zone):
					_complete(id)
			"sanction_other":
				if type == "sanction" and d.get("target", "") != owner and _denounced.has(d.get("target", "")):
					_complete(id)
			"prank_during":
				if type == "prank" and d.get("actor", "") == owner:
					var cond_ok: bool = (r.condition == "inspection" and s.events.active("inspection")) or (r.condition == "diversion" and s.diversion_active_for(owner))
					if cond_ok and s.suspicion_level(owner) <= int(r.max_level):
						_complete(id)
			"falls_window":
				if type in ["fall", "stumble"] and String(d.get("by", "")) == owner and d.get("who", "") != owner:
					var arr: Array = progress.get(id, [])
					var now: float = s.now()
					arr = arr.filter(func(x): return now - float(x[1]) < float(r.window) and x[0] != d.who)
					arr.append([d.who, now])
					progress[id] = arr
					progressed.emit(owner, id, "%d/%d" % [arr.size(), int(r.count)])
					if arr.size() >= int(r.count):
						_complete(id)
			"contradiction":
				if type == "contradiction" and (d.get("actor", "") == owner or owner in d.get("involved", [])):
					_complete(id)
			"sound_window":
				if type == "sound" and String(d.get("by", "")) == owner and float(d.get("loud", 0.0)) >= float(r.min_loudness):
					var arr2: Array = progress.get(id, [])
					var now2: float = s.now()
					arr2 = arr2.filter(func(x): return now2 - float(x[1]) < float(r.window))
					arr2.append([d.get("zone", ""), now2])
					progress[id] = arr2
					var zones := {}
					for x in arr2:
						zones[x[0]] = true
					progressed.emit(owner, id, "%d/%d bruits, %d/%d pièces" % [arr2.size(), int(r.count), zones.size(), int(r.zones)])
					if arr2.size() >= int(r.count) and zones.size() >= int(r.zones):
						_complete(id)
			"device_on_time":
				if type == "device_tick" and d.get("device", "") == r.device and String(d.get("by", "")) == owner:
					progress[id] = float(progress.get(id, 0.0)) + float(d.get("dt", 0.0))
					progressed.emit(owner, id, "%d/%d s" % [int(progress[id]), int(r.seconds)])
					if float(progress[id]) >= float(r.seconds):
						_complete(id)
			"disguised_witness":
				if type == "witness" and d.get("actor", "") == owner and String(d.get("desc", "")).contains("moustache"):
					_complete(id)
		# bonus reactions on already-tracked missions
		if r.has("bonus_reaction") and type == "npc_reaction" and d.get("reaction", "") == r.bonus_reaction:
			pass


## Polled conditions on world state (once per second).
func poll(dt: float) -> void:
	_poll -= dt
	if _poll > 0.0:
		return
	_poll = 1.0
	_max_level = maxi(_max_level, s.suspicion_level(owner))
	for id in all_ids():
		if done.has(id):
			continue
		var r := rule(id)
		match String(r.get("type", "")):
			"move_owned_prop":
				for p in s.world.props_with_tag(r.tag):
					var pr := p as Prop
					if pr.owner_id != "" and pr.owner_id != owner and pr.owner_id != "player" and pr.last_touched_by == owner \
							and pr.home_distance() >= float(r.min_dist) and pr.held_by == null:
						_complete(id)
						break
			"prop_in_zone":
				var found := false
				for p in s.world.props_with_tag(r.tag):
					var pr := p as Prop
					if s.world.zone_at(pr.global_position) == r.zone and pr.held_by == null and (pr.last_touched_by == owner or pr.placed_by == owner):
						if r.get("foreign", false) and pr.home_distance() < 2.0:
							continue
						found = true
				if found:
					_hold[id] = float(_hold.get(id, 0.0)) + 1.0
					progressed.emit(owner, id, "Encore %d s" % maxi(0, int(r.hold - _hold[id])))
					if float(_hold[id]) >= float(r.hold):
						_complete(id)
				else:
					_hold[id] = 0.0
			"item_in_container":
				for e in s.world.interactables:
					if e is Device and r.container in [e.kind] and not e.contents.is_empty():
						for pid in e.contents:
							var pr: Prop = s.world.ent(pid)
							if pr and pr.item_id == r.item and pr.last_touched_by == owner:
								_complete(id)
			"zone_crowd":
				var n := 0
				for npc in _invited:
					var c: Character = s.characters.get(npc)
					if c and s.world.zone_at(c.global_position) == r.zone:
						n += 1
				if n >= int(r.count):
					_complete(id)


func end_of_day() -> void:
	for id in all_ids():
		if done.has(id):
			continue
		var r := rule(id)
		if r.get("type", "") == "max_level_day" and _max_level <= int(r.max_level):
			_complete(id)


func title(id: String) -> String:
	if Data.missions.has(id):
		return Data.missions[id].title
	for sc in Data.side_challenges:
		if sc.id == id:
			return sc.title
	return id


func desc(id: String) -> String:
	if Data.missions.has(id):
		return Data.missions[id].desc
	for sc in Data.side_challenges:
		if sc.id == id:
			return sc.desc
	return ""
