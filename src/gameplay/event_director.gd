class_name EventDirector
extends RefCounted
## Unpredictable office events with causes, conditions, cooldowns and durations.
## Selection is weighted and balanced: when the player is under heavy suspicion the
## director favours helpful events; it never chains two hard events.

signal started(id: String, info: Dictionary)
signal ended(id: String)

var rng := RandomNumberGenerator.new()
var _active: Dictionary = {}       # id -> {until, data}
var _last_time: Dictionary = {}    # id -> real time of last start
var _next := 45.0
var _last_difficulty := 0
var enabled := true


func active(id: String) -> bool:
	return _active.has(id)


func data(id: String) -> Dictionary:
	return _active.get(id, {}).get("data", {})


func any_active() -> Array:
	return _active.keys()


func start(id: String, now: float, info := {}) -> void:
	var ev: Dictionary = Data.random_events.get(id, {})
	var dur := float(ev.get("duration", 0.0))
	_last_time[id] = now
	if dur > 0.0:
		_active[id] = {"until": now + dur, "data": info}
	_last_difficulty = int(ev.get("difficulty", 0))
	started.emit(id, info)


func finish(id: String) -> void:
	if _active.erase(id):
		ended.emit(id)


## Called every frame by the session; `ctx` gives the conditions.
func tick(now: float, dt: float, ctx: Dictionary) -> String:
	for id in _active.keys():
		if now >= float(_active[id].until):
			finish(id)
	if not enabled:
		return ""
	_next -= dt
	if _next > 0.0:
		return ""
	_next = rng.randf_range(40.0, 75.0)
	var id := pick(now, ctx)
	return id


func pick(now: float, ctx: Dictionary) -> String:
	var player_level: int = ctx.get("player_level", 0)
	var total := 0.0
	var cands: Array = []
	for id in Data.random_events:
		var ev: Dictionary = Data.random_events[id]
		if _active.has(id):
			continue
		if now - float(_last_time.get(id, -9999.0)) < float(ev.cooldown):
			continue
		var req: Dictionary = ev.get("requires", {})
		if req.get("not_meeting", false) and ctx.get("meeting", false):
			continue
		if req.has("before_meeting_min") and float(ctx.get("min_to_meeting", INF)) > float(req.before_meeting_min):
			continue
		var diff := int(ev.get("difficulty", 0))
		if diff >= 2 and _last_difficulty >= 2:
			continue
		var w := float(ev.weight)
		if player_level >= 3:
			w *= 2.0 if diff < 0 else (0.4 if diff > 0 else 1.0)
		if ctx.get("boss_profile", "") == "authoritarian" and id == "inspection":
			w *= 2.0
		cands.append([id, w])
		total += w
	if cands.is_empty():
		return ""
	var r := rng.randf() * total
	for c in cands:
		r -= c[1]
		if r <= 0.0:
			return c[0]
	return cands[-1][0]
