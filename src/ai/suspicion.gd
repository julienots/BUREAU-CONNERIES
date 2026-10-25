class_name Suspicion
extends RefCounted
## The director's suspicion ledger. One score per employee mapped to 6 levels, plus the
## list of evidence (direct sight, testimonies, circumstantial, physical) behind it.

const LEVELS := ["Aucun soupçon", "Comportement inhabituel", "Suspect à surveiller", "Enquête active", "Preuves solides", "Infraction confirmée"]
const THRESHOLDS := [0.0, 10.0, 25.0, 45.0, 65.0, 85.0]

var scores: Dictionary = {}        # char_id -> float 0..100
var evidence: Dictionary = {}      # char_id -> Array[{type, act_id, weight, source, time}]
var gain := 1.0
var decay_per_min := 3.0
var max_evidence := 12
var reliability: Dictionary = {}   # witness id -> 0..1 (how much the director trusts them)
var person_gain: Dictionary = {}   # char_id -> multiplier from the director's opinion of them


func level(who: String) -> int:
	var s := float(scores.get(who, 0.0))
	for i in range(THRESHOLDS.size() - 1, -1, -1):
		if s >= THRESHOLDS[i]:
			return i
	return 0


func level_name(who: String) -> String:
	return LEVELS[level(who)]


func score(who: String) -> float:
	return float(scores.get(who, 0.0))


func add(who: String, amount: float, type: String, act_id := -1, source := "", now := 0.0) -> void:
	if who == "":
		return
	var a := amount * gain * float(person_gain.get(who, 1.0)) if amount > 0.0 else amount
	scores[who] = clampf(score(who) + a, 0.0, 100.0)
	if not evidence.has(who):
		evidence[who] = []
	if amount > 0.0:
		evidence[who].append({"type": type, "act_id": act_id, "weight": a, "source": source, "time": now})
		while evidence[who].size() > max_evidence:
			evidence[who].pop_front()


func set_confirmed(who: String, act_id: int, now: float) -> void:
	add(who, maxf(0.0, THRESHOLDS[5] + 5.0 - score(who)) / maxf(gain, 0.01), "direct", act_id, "boss", now)


## Number of independent evidence sources about an act (or overall if act_id < 0).
func sources(who: String, act_id := -1) -> int:
	var seen := {}
	for e in evidence.get(who, []):
		if act_id >= 0 and int(e.act_id) != act_id:
			continue
		seen[str(e.type) + ":" + str(e.source)] = true
	return seen.size()


func has_direct(who: String, act_id := -1) -> bool:
	for e in evidence.get(who, []):
		if e.type == "direct" and (act_id < 0 or int(e.act_id) == act_id):
			return true
	return false


## Strongest act the director can confront `who` about (most weight), or -1.
func best_act(who: String) -> int:
	var w := {}
	for e in evidence.get(who, []):
		if int(e.act_id) >= 0:
			w[int(e.act_id)] = float(w.get(int(e.act_id), 0.0)) + float(e.weight)
	var best := -1
	var bw := 0.0
	for k in w:
		if w[k] > bw:
			bw = w[k]
			best = k
	return best


## 0..1 confidence used during interrogations.
func strength(who: String, act_id := -1) -> float:
	if has_direct(who, act_id):
		return 1.0
	var total := 0.0
	for e in evidence.get(who, []):
		if act_id < 0 or int(e.act_id) == act_id:
			total += float(e.weight)
	return clampf(total / 80.0 + score(who) / 300.0, 0.0, 0.95)


func clear_act(who: String, act_id: int) -> void:
	if evidence.has(who):
		evidence[who] = evidence[who].filter(func(e): return int(e.act_id) != act_id)


func trust(witness: String) -> float:
	return float(reliability.get(witness, 0.6))


func adjust_trust(witness: String, delta: float) -> void:
	reliability[witness] = clampf(trust(witness) + delta, 0.05, 1.0)


func tick(dt: float) -> void:
	var d := decay_per_min * dt / 60.0
	for k in scores.keys():
		# confirmed infractions decay slower
		var f := 0.35 if level(k) >= 5 else 1.0
		scores[k] = maxf(0.0, float(scores[k]) - d * f)


func top_suspect(exclude: Array = []) -> String:
	var best := ""
	var bs := 0.0
	for k in scores:
		if k in exclude:
			continue
		if float(scores[k]) > bs:
			bs = scores[k]
			best = k
	return best
