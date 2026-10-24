class_name Memory
extends RefCounted
## Bounded episodic memory of one character: witnessed acts, sightings (alibis), noises,
## grievances, known rumours. Old entries are forgotten first when capacity is exceeded.

var capacity := 12
var witnessed: Array[Dictionary] = []    # {act_id, actor, desc, conf, time, zone, kind, reported, shared}
var sightings: Array[Dictionary] = []    # {who, zone, pos, time}
var heard: Array[Dictionary] = []        # {kind, pos, zone, time, loud}
var grievances: Dictionary = {}          # char_id -> float
var rumors: Dictionary = {}              # rumor_key -> {belief, from, time}
var incident_zones: Dictionary = {}      # zone -> count (director: trouble spots)
const SIGHTING_WINDOW := 150.0


func _init(cap := 12) -> void:
	capacity = cap


func remember_act(act: Dictionary, actor_seen: String, desc: String, conf: float, now: float) -> void:
	for w in witnessed:
		if w.act_id == act.id:
			if conf > w.conf:
				w.conf = conf
				w.actor = actor_seen
				w.desc = desc
			return
	witnessed.append({"act_id": act.id, "actor": actor_seen, "desc": desc, "conf": conf, "time": now, "zone": act.zone,
		"kind": act.kind, "reported": false, "shared": false, "victim": act.get("victim", "")})
	incident_zones[act.zone] = int(incident_zones.get(act.zone, 0)) + 1
	while witnessed.size() > capacity:
		witnessed.pop_front()


func knows_act(act_id: int) -> Dictionary:
	for w in witnessed:
		if w.act_id == act_id:
			return w
	return {}


func see(who: String, zone: String, pos: Vector3, now: float) -> void:
	# merge consecutive sightings in the same zone to save space
	for i in range(sightings.size() - 1, maxi(-1, sightings.size() - 12), -1):
		var s: Dictionary = sightings[i]
		if s.who == who:
			if s.zone == zone:
				s.time = now
				s.pos = pos
				return
			break
	sightings.append({"who": who, "zone": zone, "pos": pos, "time": now, "since": now})
	while sightings.size() > 40 + capacity * 4 or (sightings.size() > 0 and now - float(sightings[0].time) > SIGHTING_WINDOW):
		sightings.pop_front()


## Where was `who` around time t? Returns the sighting closest in time (within tolerance) or {}.
func where_was(who: String, t: float, tol := 8.0) -> Dictionary:
	var best: Dictionary = {}
	var best_dt := tol
	for s in sightings:
		if s.who != who:
			continue
		var dt := 0.0
		if t < float(s.since):
			dt = float(s.since) - t
		elif t > float(s.time):
			dt = t - float(s.time)
		if dt <= best_dt:
			best_dt = dt
			best = s
	return best


## People seen in/near a zone around a time window (circumstantial suspects).
func seen_near(zone: String, t: float, window := 25.0) -> Array[String]:
	var out: Array[String] = []
	for s in sightings:
		if s.zone == zone and float(s.time) >= t - window and float(s.since) <= t + window and not s.who in out:
			out.append(s.who)
	return out


func hear(kind: String, pos: Vector3, zone: String, loud: float, now: float) -> void:
	heard.append({"kind": kind, "pos": pos, "zone": zone, "time": now, "loud": loud})
	while heard.size() > 10:
		heard.pop_front()


func add_grievance(who: String, amount: float) -> void:
	if who == "":
		return
	grievances[who] = clampf(float(grievances.get(who, 0.0)) + amount, 0.0, 3.0)


func grievance(who: String) -> float:
	return float(grievances.get(who, 0.0))


func forget_older_than(now: float, age: float) -> void:
	witnessed = witnessed.filter(func(w): return now - float(w.time) < age)
