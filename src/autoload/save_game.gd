extends Node
## Versioned local save (solo progression). Multiplayer rewards are validated by the
## server and never written from the client UI.

signal saved

var PATH := "user://office_mayhem_save.json"
const VERSION := 2

var data: Dictionary = {}


func _ready() -> void:
	load_game()


## Tests use their own file so they never touch the player's progression.
func use_test_file() -> void:
	PATH = "user://test_save.json"
	data = default_data()


func default_data() -> Dictionary:
	return {
		"version": VERSION,
		"money": 60,
		"day": 1,
		"reputation": 50,
		"tier_unlocked": 1,
		"owned": {},             # item_id -> count (consumables) or 1 (passive/cosmetic)
		"equipped_cosmetics": [],
		"appearance": Data.player_default.get("look", {}).duplicate(true),
		"stats": {"days_played": 0, "days_won": 0, "missions_done": 0, "times_caught": 0, "warnings": 0,
			"falls_caused": 0, "money_earned": 0, "denunciations": 0, "best_day_score": 0},
		"missions_done": [],     # ids completed at least once
		"affinity": {},          # npc_id -> affinity with the player, persists between days
		"rematch": false,        # previous day failed -> revenge challenge
		"boss_trust": 50.0,
		"profile_seen": [],
	}


func load_game() -> void:
	data = default_data()
	if not FileAccess.file_exists(PATH):
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("save corrupted, starting fresh")
		return
	data = migrate(parsed)


## Brings an older save up to the current version, filling any missing keys.
func migrate(d: Dictionary) -> Dictionary:
	var v := int(d.get("version", 1))
	if v < 2:
		# v1 stored owned items as an array of ids
		if typeof(d.get("owned")) == TYPE_ARRAY:
			var o := {}
			for id in d.owned:
				o[id] = int(o.get(id, 0)) + 1
			d.owned = o
	var def := default_data()
	for k in def.keys():
		if not d.has(k):
			d[k] = def[k]
	for k in def.stats.keys():
		if not d.stats.has(k):
			d.stats[k] = def.stats[k]
	d.version = VERSION
	return d


func save_game() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		push_error("cannot write save")
		return
	f.store_string(JSON.stringify(data, "  "))
	saved.emit()


func reset() -> void:
	data = default_data()
	save_game()


func money() -> int:
	return int(data.money)


func add_stat(key: String, amount: int = 1) -> void:
	data.stats[key] = int(data.stats.get(key, 0)) + amount


func owned_count(item_id: String) -> int:
	return int(data.owned.get(item_id, 0))
