class_name OfficeWorld
extends Node3D
## The playable office: geometry container + registries used by AI and gameplay
## (rooms, desks, interactables, points of interest) + spatial queries.

const WALL_H := 3.0

## zone id -> {name, rect: Rect2 (x,z), floor, acoustic: float, restricted: bool}
var rooms: Dictionary = {}
var entities: Dictionary = {}            # ent_id -> Node
var interactables: Array[Node] = []
var props: Array[Node] = []
var desks: Array[Dictionary] = []        # {index, pos, rot, seat: Vector3, facing: Vector3, chair_id, pc_id, drawer_id, phone_id, owner}
var doors: Array[Node] = []
var lights: Dictionary = {}              # zone -> Array[Light3D]
var light_meshes: Dictionary = {}        # zone -> Array[MeshInstance3D] (emissive panels)
var lights_on: Dictionary = {}           # zone -> bool
var poi: Dictionary = {}                 # name -> Array[Dictionary{pos, facing, zone, taken_by}]
var nav_region: NavigationRegion3D
var static_root: Node3D
var props_root: Node3D
var rng := RandomNumberGenerator.new()
var _space: PhysicsDirectSpaceState3D


func _ready() -> void:
	static_root = Node3D.new()
	static_root.name = "Static"
	add_child(static_root)
	props_root = Node3D.new()
	props_root.name = "Props"
	add_child(props_root)


func register(ent: Node, id: String) -> void:
	ent.set_meta("ent_id", id)
	entities[id] = ent
	if ent.has_method("get_actions"):
		interactables.append(ent)
	if ent is Prop:
		props.append(ent)


func unregister(id: String) -> void:
	var e: Node = entities.get(id)
	if e:
		interactables.erase(e)
		props.erase(e)
	entities.erase(id)


func ent(id: String) -> Node:
	var e: Node = entities.get(id)
	return e if is_instance_valid(e) else null


func add_room(id: String, name: String, rect: Rect2, acoustic := 1.0, restricted := false) -> void:
	rooms[id] = {"id": id, "name": name, "rect": rect, "acoustic": acoustic, "restricted": restricted}
	lights_on[id] = true


func zone_at(p: Vector3) -> String:
	for id in rooms:
		if (rooms[id].rect as Rect2).has_point(Vector2(p.x, p.z)):
			return id
	return "corridor"


func zone_name(id: String) -> String:
	return rooms.get(id, {}).get("name", id)


func zone_center(id: String) -> Vector3:
	var r: Rect2 = rooms.get(id, {}).get("rect", Rect2())
	var c := r.get_center()
	return Vector3(c.x, 0, c.y)


func random_point_in_zone(id: String) -> Vector3:
	var r: Rect2 = rooms.get(id, {}).get("rect", Rect2())
	var p := Vector3(rng.randf_range(r.position.x + 1.0, r.end.x - 1.0), 0, rng.randf_range(r.position.y + 1.0, r.end.y - 1.0))
	return nav_closest(p)


func add_poi(kind: String, pos: Vector3, facing: Vector3, extra := {}) -> void:
	if not poi.has(kind):
		poi[kind] = []
	var d := {"pos": pos, "facing": facing, "zone": zone_at(pos), "taken_by": ""}
	d.merge(extra)
	poi[kind].append(d)


## Returns a free point of interest of that kind (closest to `near` if given) and reserves it.
func claim_poi(kind: String, who: String, near := Vector3.INF) -> Dictionary:
	var best: Dictionary = {}
	var best_d := INF
	for p in poi.get(kind, []):
		if p.taken_by != "" and p.taken_by != who:
			continue
		var d: float = 0.0 if near == Vector3.INF else near.distance_to(p.pos) + rng.randf() * 2.0
		if near == Vector3.INF:
			d = rng.randf()
		if d < best_d:
			best_d = d
			best = p
	if not best.is_empty():
		best.taken_by = who
	return best


func release_poi(who: String) -> void:
	for kind in poi:
		for p in poi[kind]:
			if p.taken_by == who:
				p.taken_by = ""


func space() -> PhysicsDirectSpaceState3D:
	if _space == null or not is_instance_valid(get_world_3d()):
		_space = get_world_3d().direct_space_state
	return get_world_3d().direct_space_state


## Number of sound-blocking surfaces between two points (max 4).
func count_walls(a: Vector3, b: Vector3) -> int:
	var st := space()
	if st == null:
		return 0
	var n := 0
	var from := a
	var excl: Array[RID] = []
	for i in 4:
		var q := PhysicsRayQueryParameters3D.create(from, b, Layers.SOUND, excl)
		var hit := st.intersect_ray(q)
		if hit.is_empty():
			break
		n += 1
		excl.append(hit.rid)
		from = hit.position + (b - from).normalized() * 0.05
	return n


## True when nothing opaque blocks the segment.
func line_clear(a: Vector3, b: Vector3, exclude: Array[RID] = []) -> bool:
	var st := space()
	if st == null:
		return true
	var q := PhysicsRayQueryParameters3D.create(a, b, Layers.OCCLUDERS, exclude)
	return st.intersect_ray(q).is_empty()


func nav_closest(p: Vector3) -> Vector3:
	if nav_region == null:
		return p
	var map := nav_region.get_navigation_map()
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		return p
	return NavigationServer3D.map_get_closest_point(map, p)


func set_zone_lights(zone: String, on: bool) -> void:
	lights_on[zone] = on
	for l in lights.get(zone, []):
		if is_instance_valid(l):
			l.visible = on
	for m in light_meshes.get(zone, []):
		if is_instance_valid(m):
			m.material_override = Mats.emissive(Color(1.0, 0.98, 0.92), 2.2) if on else Mats.color(Color(0.55, 0.55, 0.55), 0.6)


func zone_lit(zone: String) -> bool:
	return lights_on.get(zone, true)


func desk_of(owner_id: String) -> Dictionary:
	for d in desks:
		if d.owner == owner_id:
			return d
	return {}


func props_with_tag(tag: String) -> Array[Node]:
	var out: Array[Node] = []
	for p in props:
		if is_instance_valid(p) and tag in p.tags:
			out.append(p)
	return out
