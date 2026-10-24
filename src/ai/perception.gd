class_name Perception
## Vision: cone + range + multi-point line-of-sight raycasts + lighting + posture.
## Hearing: distance + wall attenuation. Pure functions so they are easy to test.

const IDENTIFY_RANGE := 9.0


## 0..1 visibility of `tgt` for `obs`. 0 when out of cone/range or fully occluded.
static func visibility(world: OfficeWorld, obs: Character, tgt: Character, fov_deg: float, view_range: float) -> float:
	if obs == tgt or not is_instance_valid(tgt):
		return 0.0
	if obs.is_down():
		return 0.0
	var eye := obs.eye_position()
	var head := tgt.eye_position()
	var to := head - eye
	var dist := to.length()
	if dist > view_range or dist < 0.01:
		return 0.0 if dist > view_range else 1.0
	var fwd := view_dir(obs)
	var flat_to := Vector3(to.x, 0, to.z).normalized()
	var ang := rad_to_deg(acos(clampf(fwd.dot(flat_to), -1.0, 1.0)))
	var half := fov_deg * 0.5
	if ang > half and dist > 1.2:
		return 0.0
	var pts := [head, tgt.global_position + Vector3(0, 1.05, 0), tgt.global_position + Vector3(0, 0.55, 0)]
	if tgt.want_crouch and not tgt.seated_on:
		pts = [head, tgt.global_position + Vector3(0, 0.6, 0), tgt.global_position + Vector3(0, 0.3, 0)]
	var excl: Array[RID] = [obs.get_rid(), tgt.get_rid()]
	var seen := 0
	for p in pts:
		if world.line_clear(eye, p, excl):
			seen += 1
	if seen == 0:
		return 0.0
	var f := float(seen) / pts.size()
	var dist_f := 1.0 - pow(dist / view_range, 2.0) * 0.85
	var ang_f := 1.0 - 0.55 * pow(ang / half, 2.0) if ang <= half else 0.5
	var light := 1.0 if world.zone_lit(world.zone_at(tgt.global_position)) else 0.4
	var posture := 0.65 if tgt.want_crouch else 1.0
	return clampf(f * dist_f * ang_f * light * posture, 0.0, 1.0)


## Where the character is looking (body forward, turned by an explicit look target).
static func view_dir(c: Character) -> Vector3:
	if c.humanoid and c.humanoid.look_target != Vector3.INF:
		var d := c.humanoid.look_target - c.global_position
		d.y = 0
		if d.length() > 0.1:
			var f := c.forward()
			f.y = 0
			return f.normalized().slerp(d.normalized(), 0.6).normalized()
	var f2 := c.forward()
	f2.y = 0
	return f2.normalized()


## Perceived loudness (dB-like) of a sound at a listener.
static func perceived(world: OfficeWorld, listener_pos: Vector3, src: Vector3, loud: float, check_walls := true) -> float:
	var d := listener_pos.distance_to(src)
	var p := loud - 20.0 * log(maxf(d, 1.0)) / log(10.0)
	if check_walls and d > 1.5:
		p -= 11.0 * world.count_walls(listener_pos + Vector3(0, 1.5, 0), src + Vector3(0, 0.6, 0))
	return p


## What a witness can tell about an actor: identity if close/clear, else a description.
static func describe(actor: Character, dist: float, vis: float) -> Dictionary:
	if actor.is_disguised() and dist > 3.0:
		return {"id": "", "desc": "une grosse moustache"}
	if dist < IDENTIFY_RANGE and vis > 0.25:
		return {"id": actor.id, "desc": actor.nick}
	var shirt := Color(actor.appearance.get("shirt", "#888888"))
	return {"id": "", "desc": "une chemise " + color_name(shirt)}


static func color_name(c: Color) -> String:
	if c.s < 0.2:
		return "claire" if c.v > 0.7 else ("grise" if c.v > 0.35 else "sombre")
	var h := c.h * 360.0
	if h < 20 or h >= 340:
		return "rouge"
	if h < 45:
		return "orange"
	if h < 70:
		return "jaune"
	if h < 165:
		return "verte"
	if h < 255:
		return "bleue"
	if h < 300:
		return "violette"
	return "rose"
