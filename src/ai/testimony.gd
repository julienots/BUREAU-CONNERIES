class_name Testimony
## What a coworker says when the director asks about an incident. The answer depends on
## what they really saw, their honesty/loyalty/courage, their relations and grudges, and
## rumours they believe. The result says whether it is truthful (known only to the server).

## Returns {kind: truth|partial|lie|hearsay|protect|nothing|deny, accused: id, desc: String, truthful: bool}
static func answer(npc_id: String, traits: Dictionary, mem: Memory, rel: Relations, act: Dictionary, candidates: Array, rng: RandomNumberGenerator, pressure := 0.0) -> Dictionary:
	var honesty: float = traits.get("honesty", 0.5)
	var loyalty: float = traits.get("loyalty", 0.5)
	var courage: float = traits.get("courage", 0.5)
	var grudge: float = traits.get("grudge", 0.3)
	var real_actor: String = act.get("actor", "")
	# The culprit being questioned
	if real_actor == npc_id:
		if courage < 0.2 or rng.randf() < pressure * 0.3:
			var scapegoat := rel.worst_enemy(npc_id, candidates.filter(func(c): return c != npc_id))
			if scapegoat != "":
				return {"kind": "lie", "accused": scapegoat, "desc": "", "truthful": false}
		return {"kind": "deny", "accused": "", "desc": "", "truthful": false}
	var w := mem.knows_act(int(act.get("id", -1)))
	if not w.is_empty():
		var seen: String = w.actor
		if seen != "":
			var a := rel.get_aff(npc_id, seen)
			var protect := loyalty * maxf(0.0, a) * (1.2 - honesty * 0.6)
			if mem.grievance(seen) > 0.5:
				protect = 0.0
			# cowards crack under pressure
			if courage < 0.2:
				protect *= 0.2
			if rng.randf() < protect:
				return {"kind": "protect", "accused": "", "desc": "", "truthful": false}
			return {"kind": "truth", "accused": seen, "desc": "", "truthful": seen == real_actor}
		return {"kind": "partial", "accused": "", "desc": w.desc, "truthful": true}
	# Did not witness it: maybe repeat a believed rumour or settle a score.
	for key in mem.rumors:
		var r: Dictionary = mem.rumors[key]
		if r.get("about", "") != "" and r.get("about", "") in candidates and float(r.get("belief", 0.0)) > 0.5 and rng.randf() < 0.6:
			return {"kind": "hearsay", "accused": r.about, "desc": "", "truthful": r.about == real_actor}
	var lie_p := (1.0 - honesty) * 0.55
	var target := ""
	var worst := 0.0
	for c in candidates:
		if c == npc_id:
			continue
		var dislike := -rel.get_aff(npc_id, c) + mem.grievance(c) * grudge
		if dislike > worst:
			worst = dislike
			target = c
	if target != "" and rng.randf() < lie_p * clampf(worst + 0.2, 0.0, 1.5):
		return {"kind": "lie", "accused": target, "desc": "", "truthful": target == real_actor}
	return {"kind": "nothing", "accused": "", "desc": "", "truthful": true}


## Probability that this coworker goes and reports what they saw on their own.
static func report_chance(npc_id: String, traits: Dictionary, rel: Relations, mem: Memory, actor: String, sev: int, victim: String) -> float:
	if actor == "" or actor == npc_id:
		return 0.0
	var p: float = traits.get("denounce", 0.4) * (0.35 + 0.15 * sev)
	p *= 1.0 - maxf(0.0, rel.get_aff(npc_id, actor)) * float(traits.get("loyalty", 0.5))
	p += mem.grievance(actor) * float(traits.get("grudge", 0.3)) * 0.4
	if victim == npc_id:
		p += 0.35
	return clampf(p, 0.0, 0.95)
