class_name PdgBrain
extends Node
## The CEO's visit: walks a tour of the office (open space, meeting room, break room, the
## director's office where he sits in the boss chair), comments in corporate jargon, then
## takes the lift back. Pranks on him are handled by the Session (big bonus, big risk).

var c: Character
var s: Node                       # Session
var rng := RandomNumberGenerator.new()
var route: Array = []             # Vector3 or "boss_chair"
var i := 0
var wait := 0.0
var leaving := false
var _going := -1
var _tick := 0.0
var _seat_t := 0.0
var _last_pos := Vector3.ZERO
var _stuck := 0.0


func setup(ch: Character, session: Node, seed: int) -> void:
	c = ch
	s = session
	rng.seed = seed
	for p in [Vector3(18.5, 0, -1.5), Vector3(5.0, 0, 4.9), Vector3(-2.4, 0, 4.9), Vector3(-11.5, 0, 4.9),
			Vector3(-4.0, 0, -6.5), Vector3(6.5, 0, -9.3), Vector3(16.0, 0, -10.0)]:
		route.append(s.world.nav_closest(p))
	route.append("boss_chair")
	route.append(s.world.nav_closest(Vector3(20.5, 0, -1.5)))


## Cut the tour short and head for the lift.
func leave() -> void:
	if leaving:
		return
	leaving = true
	if c.seated_on:
		c.stand_up()
	wait = 0.0
	i = route.size() - 1
	_going = -1


func _physics_process(delta: float) -> void:
	if c == null or not is_instance_valid(c) or s == null or not s.running:
		return
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 0.25
	if c.is_down():
		return
	if c.seated_on:
		_seat_t -= 0.25
		if _seat_t <= 0.0:
			c.stand_up()
			i += 1
		return
	if wait > 0.0:
		wait -= 0.25
		var near := _nearest_employee(7.0)
		if near:
			c.look_at_point(near.eye_position())
		if wait <= 0.0:
			i += 1
		return
	if i >= route.size():
		s.end_pdg_visit()
		return
	var target = route[i]
	if typeof(target) == TYPE_STRING:
		_go_sit()
		return
	if _going != i:
		_going = i
		_stuck = 0.0
		c.go_to(target)
	# blocked (someone standing in the way…): give up on this stop after a few seconds
	if c.global_position.distance_to(_last_pos) < 0.15:
		_stuck += 0.25
		if _stuck >= 4.0:
			_stuck = 0.0
			s.npc_say(c, "Bon, passons. On ne va pas y passer la journée.", "neutral")
			i += 1
			return
	else:
		_stuck = 0.0
	_last_pos = c.global_position
	if c.arrived(0.9):
		c.stop()
		if i == route.size() - 1:
			s.end_pdg_visit()
			return
		wait = rng.randf_range(4.0, 7.0)
		c.do_emote("point" if rng.randf() < 0.5 else "shrug", 2.0)
		s.npc_say(c, s.barks.pick("pdg_comment"), "neutral")
		s.pdg_stop(c.global_position)


func _go_sit() -> void:
	var chair: Prop = null
	for p in s.world.props_with_tag("boss_chair"):
		chair = p
	if chair == null or chair.occupant != "" or not chair.is_available():
		i += 1
		return
	if _going != i:
		_going = i
		_stuck = 0.0
		c.go_to(s.world.nav_closest(chair.global_position + (-chair.global_basis.z) * -0.6))
	if c.global_position.distance_to(_last_pos) < 0.15:
		_stuck += 0.25
		if _stuck >= 4.0:
			i += 1
			return
	else:
		_stuck = 0.0
	_last_pos = c.global_position
	if c.arrived(0.8) or c.global_position.distance_to(chair.global_position) < 1.0:
		if c.sit_on(chair):
			_seat_t = 6.0
			s.npc_say(c, "Voyons voir si ce fauteuil est aussi confortable qu'on le dit…", "happy")
		else:
			i += 1


func _nearest_employee(r: float) -> Character:
	var best: Character = null
	var bd := r
	for e in s.employees():
		var d: float = (e as Character).global_position.distance_to(c.global_position)
		if d < bd:
			bd = d
			best = e
	return best
