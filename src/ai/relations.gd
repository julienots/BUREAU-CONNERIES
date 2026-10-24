class_name Relations
extends RefCounted
## Directed affinity between characters (-1 hate .. +1 friend). Evolves with events.

var aff: Dictionary = {}   # "a>b" -> float


func setup(ids: Array, data_relations: Array, rng: RandomNumberGenerator, saved_player: Dictionary) -> void:
	for a in ids:
		for b in ids:
			if a != b:
				aff[a + ">" + b] = rng.randf_range(-0.15, 0.2)
	for r in data_relations:
		set_pair(r[0], r[1], float(r[2]))
	for npc in saved_player:
		set_pair(npc, "player", float(saved_player[npc]))


func set_pair(a: String, b: String, v: float) -> void:
	aff[a + ">" + b] = clampf(v, -1.0, 1.0)
	aff[b + ">" + a] = clampf(v, -1.0, 1.0)


func get_aff(a: String, b: String) -> float:
	return float(aff.get(a + ">" + b, 0.0))


func change(a: String, b: String, delta: float) -> void:
	aff[a + ">" + b] = clampf(get_aff(a, b) + delta, -1.0, 1.0)


func best_friend(a: String, among: Array) -> String:
	var best := ""
	var bv := -2.0
	for b in among:
		if b != a and get_aff(a, b) > bv:
			bv = get_aff(a, b)
			best = b
	return best


func worst_enemy(a: String, among: Array) -> String:
	var best := ""
	var bv := 2.0
	for b in among:
		if b != a and get_aff(a, b) < bv:
			bv = get_aff(a, b)
			best = b
	return best
