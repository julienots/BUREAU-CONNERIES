extends Node
## Central, validated registry of every gameplay datum (characters, items, missions,
## events, dialogue). Loaded once from res://data/*.json. Validation errors are kept in
## `errors` so tests can assert the data is clean.

var archetypes: Dictionary = {}
var coworkers: Array = []
var director: Dictionary = {}
var player_default: Dictionary = {}
var relations: Array = []
var director_profiles: Dictionary = {}
var items: Dictionary = {}          # id -> item (shop items)
var world_items: Dictionary = {}    # id -> item found in the office
var missions: Dictionary = {}       # id -> mission
var mission_order: Array[String] = []
var side_challenges: Array = []
var schedule: Array = []
var random_events: Dictionary = {}
var rumors: Dictionary = {}
var lines: Dictionary = {}
var errors: PackedStringArray = []

const MISSION_RULES := ["move_owned_prop", "action_on_owned", "prop_in_zone", "item_in_container", "zone_crowd",
	"reaction", "count_action", "action_during", "rumor_reach", "action_on_any", "sound_kind", "sanction_other",
	"prank_during", "falls_window", "contradiction", "sound_window", "device_on_time", "disguised_witness", "max_level_day", "meeting_antic", "reaction_during"]
const ZONES := ["open_space", "corridor", "meeting", "boss_office", "break", "toilets", "archives", "copy_room"]


func _ready() -> void:
	reload()


func reload() -> void:
	errors.clear()
	var c: Dictionary = _load("res://data/characters.json")
	archetypes = c.get("archetypes", {})
	coworkers = c.get("coworkers", [])
	director = c.get("director", {})
	player_default = c.get("player_default", {})
	relations = c.get("relations", [])
	director_profiles = c.get("director_profiles", {})
	var it: Dictionary = _load("res://data/items.json")
	items.clear()
	for i in it.get("items", []):
		items[i.id] = i
	world_items.clear()
	for i in it.get("world_items", []):
		world_items[i.id] = i
	var m: Dictionary = _load("res://data/missions.json")
	missions.clear()
	mission_order.clear()
	for mi in m.get("missions", []):
		missions[mi.id] = mi
		mission_order.append(mi.id)
	side_challenges = m.get("side_challenges", [])
	var e: Dictionary = _load("res://data/events.json")
	schedule = e.get("schedule", [])
	random_events.clear()
	for ev in e.get("random_events", []):
		random_events[ev.id] = ev
	rumors.clear()
	for r in e.get("rumors", []):
		rumors[r.id] = r
	lines = _load("res://data/dialogue.json").get("lines", {})
	_validate()
	for err in errors:
		push_error("[Data] " + err)


func _load(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		errors.append("cannot open " + path)
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		errors.append("invalid JSON in " + path)
		return {}
	return parsed


func _validate() -> void:
	var trait_keys := ["denounce", "loyalty", "honesty", "credulity", "observation", "clumsiness", "gossip", "laziness", "grudge", "work", "courage"]
	for a in archetypes:
		for k in trait_keys:
			if not archetypes[a].has(k):
				errors.append("archetype %s missing trait %s" % [a, k])
			elif float(archetypes[a][k]) < 0.0 or float(archetypes[a][k]) > 1.0:
				errors.append("archetype %s trait %s out of [0,1]" % [a, k])
	var ids := {}
	var desks := {}
	for cw in coworkers:
		for k in ["id", "name", "archetype", "voice", "desk", "look"]:
			if not cw.has(k):
				errors.append("coworker missing " + k)
		if ids.has(cw.id):
			errors.append("duplicate character id " + cw.id)
		ids[cw.id] = true
		if not archetypes.has(cw.get("archetype", "")):
			errors.append("unknown archetype for " + cw.id)
		if desks.has(int(cw.desk)):
			errors.append("desk used twice: %d" % int(cw.desk))
		desks[int(cw.desk)] = true
	for r in relations:
		if r.size() != 3:
			errors.append("relation must be [a, b, value]")
	for id in items:
		var i: Dictionary = items[id]
		for k in ["name", "price", "kind", "desc", "effect", "icon", "unlock"]:
			if not i.has(k):
				errors.append("item %s missing %s" % [id, k])
		if int(i.get("price", -1)) < 0:
			errors.append("item %s has negative price" % id)
	for id in missions:
		var mi: Dictionary = missions[id]
		for k in ["title", "desc", "tier", "reward", "risk", "steps", "rule"]:
			if not mi.has(k):
				errors.append("mission %s missing %s" % [id, k])
		var rt: String = mi.get("rule", {}).get("type", "")
		if not rt in MISSION_RULES:
			errors.append("mission %s has unknown rule %s" % [id, rt])
		for need in mi.get("items", []):
			if not items.has(need):
				errors.append("mission %s needs unknown item %s" % [id, need])
		var z: String = mi.get("rule", {}).get("zone", "")
		if z != "" and not z in ZONES:
			errors.append("mission %s unknown zone %s" % [id, z])
	for id in random_events:
		for k in ["title", "weight", "cooldown", "duration", "desc"]:
			if not random_events[id].has(k):
				errors.append("event %s missing %s" % [id, k])
	for cat in lines:
		if typeof(lines[cat]) != TYPE_ARRAY or lines[cat].is_empty():
			errors.append("dialogue category %s empty" % cat)


# ------------------------------------------------------------------ helpers
func coworker(id: String) -> Dictionary:
	for c in coworkers:
		if c.id == id:
			return c
	return {}


func traits_for(archetype: String) -> Dictionary:
	return archetypes.get(archetype, archetypes.get("serious", {}))


func item_info(id: String) -> Dictionary:
	if items.has(id):
		return items[id]
	return world_items.get(id, {})


func item_name(id: String) -> String:
	return item_info(id).get("name", id)


func line(category: String) -> Array:
	return lines.get(category, ["…"])
