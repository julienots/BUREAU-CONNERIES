class_name OfficeBuilder
## Builds the complete SuperEssence Corp floor into an OfficeWorld. Deterministic for a
## given seed so multiplayer peers produce identical ids and layouts.
##
## Plan (metres, X east, Z south):
##   North row  Z[-14,-8] : archives | toilets | copy_room | meeting | break
##   Corridor   Z[-8,-5]
##   Open space X[-22,14] Z[-5,12]   Hall X[14,22] Z[-5,2]   Boss office X[14,22] Z[2,12]

const T := 0.15
const H := 3.0
const BLOCK := Layers.STATIC | Layers.OCCLUDERS | Layers.SOUND
const DESK_CLUSTERS := [Vector3(-16, 0, 1.6), Vector3(-7, 0, 1.6), Vector3(-16, 0, 8.2), Vector3(-7, 0, 8.2), Vector3(2.2, 0, 1.6), Vector3(2.2, 0, 8.2)]

var w: OfficeWorld
var root: Node3D
var rng := RandomNumberGenerator.new()
var quality := "high"
var _ids := {}
var walls_mat: Material
var doors_root: Node3D


static func build(world: OfficeWorld, seed: int, q := "high", with_props := true) -> void:
	var b := OfficeBuilder.new()
	b.w = world
	b.root = world.static_root
	b.rng.seed = seed
	world.rng.seed = seed + 1
	b.quality = q
	b._build(with_props)


func _id(base: String) -> String:
	var n := int(_ids.get(base, 0))
	_ids[base] = n + 1
	return "%s_%d" % [base, n]


func _build(with_props: bool) -> void:
	walls_mat = Mats.textured("wall_paint", 0.5, 0.9)
	doors_root = Node3D.new()
	doors_root.name = "Doors"
	w.add_child(doors_root)
	_rooms()
	_environment()
	_floors_and_ceilings()
	_walls()
	_lights()
	_open_space()
	_meeting_room()
	_break_room()
	_copy_room()
	_toilets()
	_archives()
	_boss_office()
	_hall_and_corridor()
	_skyline()
	if with_props:
		_props()
	_navigation()


# ------------------------------------------------------------------ rooms
func _rooms() -> void:
	w.add_room("archives", "Archives", Rect2(-22, -14, 10, 6), 0.8)
	w.add_room("toilets", "Toilettes", Rect2(-12, -14, 6, 6), 1.1)
	w.add_room("copy_room", "Reprographie", Rect2(-6, -14, 6, 6), 1.0)
	w.add_room("meeting", "Salle Synergie", Rect2(0, -14, 12, 6), 1.0)
	w.add_room("break", "Salle de pause", Rect2(12, -14, 10, 6), 1.1)
	w.add_room("corridor", "Couloir", Rect2(-22, -8, 44, 3), 1.2)
	w.add_room("hall", "Hall", Rect2(14, -5, 8, 7), 1.1)
	w.add_room("boss_office", "Bureau du directeur", Rect2(14, 2, 8, 10), 0.9, true)
	w.add_room("open_space", "Open space", Rect2(-22, -5, 36, 17), 1.0)


func _environment() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.35, 0.55, 0.85)
	sm.sky_horizon_color = Color(0.75, 0.82, 0.9)
	sm.ground_horizon_color = Color(0.6, 0.62, 0.65)
	sm.ground_bottom_color = Color(0.3, 0.3, 0.32)
	sky.sky_material = sm
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55 if quality == "high" else 0.85
	env.ambient_light_sky_contribution = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_white = 6.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.05
	if quality == "high" and Settings.get_v("ssao"):
		env.ssao_enabled = true
		env.ssao_radius = 0.8
		env.ssao_intensity = 1.6
	if quality != "low" and Settings.get_v("glow"):
		env.glow_enabled = true
		env.glow_intensity = 0.4
		env.glow_bloom = 0.05
		env.glow_hdr_threshold = 1.2
	var we := WorldEnvironment.new()
	we.environment = env
	w.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	w.add_child(sun)
	sun.look_at_from_position(Vector3(10, 14, 20), Vector3(-2, 0, 2), Vector3.UP)
	sun.light_color = Color(1.0, 0.93, 0.8)
	sun.light_energy = 1.5
	sun.shadow_enabled = Settings.get_v("shadows") and quality != "low"
	sun.directional_shadow_max_distance = 45.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL if quality == "low" else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.shadow_blur = 1.5


func _floors_and_ceilings() -> void:
	# one big collision slab
	Furniture.solid(root, Vector3(48, 0.4, 30), Vector3(0, -0.2, -1), Layers.STATIC)
	var floor_mats := {
		"open_space": Mats.textured("carpet", 0.5, 0.95), "corridor": Mats.textured("concrete", 0.25, 0.35),
		"hall": Mats.textured("concrete", 0.25, 0.35), "meeting": Mats.textured("wood", 0.6, 0.45),
		"boss_office": Mats.textured("wood_dark", 0.6, 0.4, 0.0, false), "break": Mats.textured("tile_floor", 0.6, 0.5),
		"toilets": Mats.textured("tile_floor", 0.8, 0.4), "archives": Mats.textured("concrete", 0.3, 0.7),
		"copy_room": Mats.textured("carpet", 0.5, 0.95, 0.0, true, Color(0.85, 0.75, 0.75)),
	}
	for id in w.rooms:
		var r: Rect2 = w.rooms[id].rect
		var c := r.get_center()
		var fm := MeshKit.add(root, MeshKit.rounded_box(Vector3(r.size.x, 0.02, r.size.y), 0.0, 1, 1.0), floor_mats[id], Vector3(c.x, -0.009 + (0.001 if id == "open_space" else 0.0), c.y), Vector3.ZERO, false)
		fm.name = "Floor_" + id
		# ceiling, visible from below only
		var cm := Mats.textured("ceiling", 1.0, 0.9, 0.0, false).duplicate() as StandardMaterial3D
		cm.uv1_scale = Vector3(r.size.x / 1.2, r.size.y / 1.2, 1)
		# light panels bounce light onto the ceiling; fake it (cheap on mobile)
		cm.emission_enabled = true
		cm.emission = Color(0.85, 0.85, 0.82)
		cm.emission_energy_multiplier = 0.45 if quality == "low" else 0.15
		var pm := PlaneMesh.new()
		pm.size = r.size
		pm.flip_faces = true
		var ceil := MeshKit.add(root, pm, cm, Vector3(c.x, H, c.y), Vector3.ZERO, false)
		ceil.name = "Ceiling_" + id
	# open space is larger than the hall rect overlap; hall drawn on top is fine


# ------------------------------------------------------------------ walls
func _seg(x0: float, z0: float, x1: float, z1: float, y0: float, y1: float, mat: Material, layers: int, base := true) -> void:
	var horiz := absf(z1 - z0) < 0.001
	var len := absf(x1 - x0) if horiz else absf(z1 - z0)
	if len < 0.01:
		return
	var size := Vector3(len + T, y1 - y0, T) if horiz else Vector3(T, y1 - y0, len + T)
	var center := Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, (z0 + z1) * 0.5)
	MeshKit.add(root, MeshKit.rounded_box(size, 0.0, 1, 0.5), mat, center)
	Furniture.solid(root, size, center, layers)
	if base and y0 < 0.01:
		var bs := size + (Vector3(0, 0, 0.03) if horiz else Vector3(0.03, 0, 0))
		bs.y = 0.09
		MeshKit.add(root, MeshKit.rounded_box(bs, 0.005, 1), Mats.color(Color(0.22, 0.22, 0.24), 0.5), Vector3(center.x, 0.045, center.z), Vector3.ZERO, false)


func _wall(x0: float, z0: float, x1: float, z1: float) -> void:
	_seg(x0, z0, x1, z1, 0.0, H, walls_mat, BLOCK)


func _glass(x0: float, z0: float, x1: float, z1: float, y0 := 0.0, y1 := H, frosted_band := true) -> void:
	var horiz := absf(z1 - z0) < 0.001
	var len := absf(x1 - x0) if horiz else absf(z1 - z0)
	var center := Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, (z0 + z1) * 0.5)
	var size := Vector3(len, y1 - y0, 0.02) if horiz else Vector3(0.02, y1 - y0, len)
	MeshKit.add(root, MeshKit.rounded_box(size, 0.0, 1), Mats.glass(), center, Vector3.ZERO, false)
	Furniture.solid(root, Vector3(size.x if horiz else T, size.y, T if horiz else size.z), center, Layers.STATIC | Layers.SOUND)
	var frame := Mats.color(Color(0.18, 0.18, 0.2), 0.35, 0.6)
	# mullions every ~1.5 m + top/bottom rails
	var n := maxi(1, int(round(len / 1.5)))
	for i in n + 1:
		var t := float(i) / n
		var p := Vector3(lerpf(x0, x1, t), center.y, lerpf(z0, z1, t))
		MeshKit.add(root, MeshKit.rounded_box(Vector3(0.05, y1 - y0, 0.06) if horiz else Vector3(0.06, y1 - y0, 0.05), 0.005, 1), frame, p)
	for y in [y0 + 0.03, y1 - 0.03]:
		MeshKit.add(root, MeshKit.rounded_box(Vector3(len, 0.06, 0.06) if horiz else Vector3(0.06, 0.06, len), 0.005, 1), frame, Vector3(center.x, y, center.z))
	if frosted_band and y1 - y0 > 2.0:
		var band := Mats.unshaded(Color(0.95, 0.97, 1.0, 0.55))
		var bsz := Vector3(len, 0.35, 0.025) if horiz else Vector3(0.025, 0.35, len)
		MeshKit.add(root, MeshKit.rounded_box(bsz, 0.0, 1), band, Vector3(center.x, 1.3, center.z), Vector3.ZERO, false)


func _window_wall(x0: float, z0: float, x1: float, z1: float) -> void:
	_seg(x0, z0, x1, z1, 0.0, 0.85, walls_mat, BLOCK)
	_seg(x0, z0, x1, z1, 2.55, H, walls_mat, BLOCK, false)
	_glass(x0, z0, x1, z1, 0.85, 2.55, false)
	# window sill
	var horiz := absf(z1 - z0) < 0.001
	var len := absf(x1 - x0) if horiz else absf(z1 - z0)
	MeshKit.add(root, MeshKit.rounded_box(Vector3(len, 0.04, 0.3) if horiz else Vector3(0.3, 0.04, len), 0.01, 2), Mats.color(Color(0.92, 0.92, 0.9), 0.4),
		Vector3((x0 + x1) * 0.5, 0.87, (z0 + z1) * 0.5))


func _door(x0: float, z0: float, x1: float, z1: float, name: String, swing := 1.0, with_leaf := true) -> Door:
	_seg(x0, z0, x1, z1, 2.2, H, walls_mat, BLOCK, false)
	var frame := Mats.color(Color(0.3, 0.3, 0.32), 0.4, 0.5)
	var horiz := absf(z1 - z0) < 0.001
	for p in [Vector3(x0, 1.1, z0), Vector3(x1, 1.1, z1)]:
		MeshKit.add(root, MeshKit.rounded_box(Vector3(0.06, 2.2, 0.2) if horiz else Vector3(0.2, 2.2, 0.06), 0.01, 1), frame, p)
	if not with_leaf:
		return null
	var d := Door.new()
	d.display = "Porte (%s)" % name
	doors_root.add_child(d)
	d.position = Vector3(x0, 0, z0)
	if not horiz:
		d.rotation_degrees.y = -90.0 if z1 > z0 else 90.0
	d.setup(absf(x1 - x0) if horiz else absf(z1 - z0), Mats.textured("wood", 1.0, 0.5), swing)
	w.register(d, _id("door"))
	w.doors.append(d)
	return d


func _walls() -> void:
	# exterior
	_wall(-22, -14, 0, -14)
	_window_wall(0, -14, 12, -14)
	_window_wall(12, -14, 22, -14)
	_window_wall(-22, 12, -11, 12)
	_window_wall(-11, 12, 3, 12)
	_window_wall(3, 12, 14, 12)
	_window_wall(14, 12, 22, 12)
	_wall(-22, -14, -22, -8)
	_window_wall(-22, -8, -22, 2)
	_window_wall(-22, 2, -22, 12)
	_window_wall(22, -14, 22, -8)
	_wall(22, -8, 22, -5)
	_window_wall(22, -5, 22, 2)
	_window_wall(22, 2, 22, 12)
	# north rooms / corridor wall (Z = -8)
	_wall(-22, -8, -18, -8)
	_door(-18, -8, -16.9, -8, "archives", -1.0)
	_wall(-16.9, -8, -10, -8)
	_door(-10, -8, -8.9, -8, "toilettes", -1.0)
	_wall(-8.9, -8, -4, -8)
	_door(-4, -8, -2.4, -8, "reprographie", 1.0, false)
	_wall(-2.4, -8, 1, -8)
	_door(1, -8, 2.1, -8, "salle Synergie", -1.0)
	_glass(2.1, -8, 12, -8)
	_wall(12, -8, 15, -8)
	_door(15, -8, 16.1, -8, "salle de pause", -1.0)
	_wall(16.1, -8, 22, -8)
	# partitions between north rooms
	for x in [-12.0, -6.0, 0.0, 12.0]:
		_wall(x, -14, x, -8)
	# boss office
	_glass(14, 2, 14, 3)
	_door(14, 3, 14, 4.1, "bureau du directeur", -1.0)
	_glass(14, 4.1, 14, 12)
	_wall(14, 2, 22, 2)
	# toilet stalls
	for x in [-10.0, -8.0]:
		_seg(x, -14, x, -12.0, 0.1, 2.1, Mats.color(Color(0.55, 0.68, 0.75), 0.4), Layers.STATIC | Layers.OCCLUDERS, false)
	_seg(-12, -12.0, -11.5, -12.0, 0.1, 2.1, Mats.color(Color(0.55, 0.68, 0.75), 0.4), Layers.STATIC | Layers.OCCLUDERS, false)
	_seg(-10.4, -12.0, -9.6, -12.0, 0.1, 2.1, Mats.color(Color(0.55, 0.68, 0.75), 0.4), Layers.STATIC | Layers.OCCLUDERS, false)
	_seg(-8.4, -12.0, -8.0, -12.0, 0.1, 2.1, Mats.color(Color(0.55, 0.68, 0.75), 0.4), Layers.STATIC | Layers.OCCLUDERS, false)
	# two pillars in the open space
	for p in [Vector3(-11.5, 1.5, 4.9), Vector3(2.0, 1.5, 4.9)]:
		MeshKit.add(root, MeshKit.rounded_box(Vector3(0.6, H, 0.6), 0.03, 2, 0.5), Mats.textured("concrete", 0.5, 0.6), p)
		Furniture.solid(root, Vector3(0.6, H, 0.6), p, BLOCK)


# ------------------------------------------------------------------ lights
func _lights() -> void:
	var spacing := 4.0 if quality == "high" else 6.0
	var omni_every := 1 if quality == "high" else 2
	var panel := MeshKit.rounded_box(Vector3(1.2, 0.04, 0.6), 0.01, 1)
	for id in w.rooms:
		w.lights[id] = []
		w.light_meshes[id] = []
		var r: Rect2 = w.rooms[id].rect
		if id == "hall":
			r = Rect2(14, -5, 8, 7)
		var nx := maxi(1, int(r.size.x / spacing))
		var nz := maxi(1, int(r.size.y / spacing))
		var k := 0
		for ix in nx:
			for iz in nz:
				var p := Vector3(r.position.x + (ix + 0.5) * r.size.x / nx, H - 0.03, r.position.y + (iz + 0.5) * r.size.y / nz)
				if id == "open_space" and p.x > 14:
					continue
				var m := MeshKit.add(root, panel, Mats.emissive(Color(1.0, 0.98, 0.92), 2.2), p, Vector3.ZERO, false)
				w.light_meshes[id].append(m)
				if k % omni_every == 0:
					var l := OmniLight3D.new()
					l.position = p - Vector3(0, 0.3, 0)
					l.omni_range = spacing * 1.6 * (1.0 if omni_every == 1 else 1.4)
					l.omni_attenuation = 0.9
					l.light_energy = 0.75 if id != "archives" else 0.45
					l.light_color = Color(1.0, 0.97, 0.9)
					l.shadow_enabled = false
					root.add_child(l)
					w.lights[id].append(l)
				k += 1


# ------------------------------------------------------------------ rooms content
func _open_space() -> void:
	var cw_by_desk := {}
	for c in Data.coworkers:
		cw_by_desk[int(c.desk)] = c.id
	cw_by_desk[int(Data.player_default.desk)] = "player"
	var idx := 0
	for ci in DESK_CLUSTERS.size():
		var c: Vector3 = DESK_CLUSTERS[ci]
		var offsets := [[Vector3(-0.82, 0, 0.42), 0.0], [Vector3(0.82, 0, 0.42), 0.0], [Vector3(-0.82, 0, -0.42), 180.0], [Vector3(0.82, 0, -0.42), 180.0]]
		for o in offsets:
			var owner: String = cw_by_desk.get(idx, "")
			var pos: Vector3 = c + o[0]
			var rot: float = o[1]
			var h := Furniture.desk(root, pos, rot, rng, owner != "")
			var basis := Basis(Vector3.UP, deg_to_rad(rot))
			var seat := pos + basis * Vector3(0, 0, 0.72)
			var facing := basis * Vector3(0, 0, -1)
			var d := {"index": idx, "pos": pos, "rot": rot, "seat": seat, "facing": facing, "owner": owner, "chair_id": "", "pc_id": "", "drawer_id": "", "phone_id": "", "papers_pos": pos + basis * Vector3(-0.55, 0.78, 0.05)}
			var pc := _device(h.monitor, "pc", "Ordinateur", owner, Vector3(0, 0.3, 0.3))
			pc.screen = h.screen
			pc.state = {"wallpaper": "", "postits": false, "mail": rng.randf() < 0.4}
			pc.apply_state()
			d.pc_id = pc.ent_id()
			var ph := _device(h.phone, "phone", "Téléphone", owner, Vector3(0, 0.1, 0))
			d.phone_id = ph.ent_id()
			var dr := Node3D.new()
			h.pivot.add_child(dr)
			dr.position = Vector3(0.5, 0.4, 0.25)
			var drawer := _device(dr, "drawer", "Tiroir", owner, Vector3.ZERO)
			d.drawer_id = drawer.ent_id()
			w.desks.append(d)
			idx += 1
		# side partitions + trash per cluster
		var fab := Mats.textured("fabric", 1.5, 0.95)
		for sx in [-1, 1]:
			MeshKit.add_box(root, Vector3(0.05, 0.5, 1.7), fab, c + Vector3(sx * 1.63, 1.0, 0), 0.02)
		Furniture.filing_cabinet(root, c + Vector3(2.0, 0, -0.42), -90, 1.0)
		Furniture.plant_static(root, c + Vector3(-2.1, 0, 0), 0.9)
	# lounge zone (east of the clusters)
	Furniture.sofa(root, Vector3(8.5, 0, 10.6), 0, Color(0.85, 0.45, 0.25), 2.2)
	Furniture.table(root, Vector3(8.5, 0, 9.2), Vector3(1.2, 0.42, 0.6), Furniture.wood())
	Furniture.shelf(root, Vector3(12.8, 0, 7.5), -90, 2.0, 1.9, rng)
	Furniture.shelf(root, Vector3(12.8, 0, 4.5), -90, 2.0, 1.9, rng)
	Furniture.table(root, Vector3(8.5, 0, -2.6), Vector3(1.6, 1.08, 0.7), Mats.color(Color(0.95, 0.95, 0.95), 0.3))
	w.add_poi("boss_stand", Vector3(8.5, 0, -1.85), Vector3(0, 0, -1))
	Furniture.plant_static(root, Vector3(13.2, 0, -3.8), 1.3)
	Furniture.plant_static(root, Vector3(-21.3, 0, 11.3), 1.3)
	Furniture.plant_static(root, Vector3(13.2, 0, 11.3), 1.1)
	Furniture.coat_rack(root, Vector3(-21.4, 0, -4.3))
	Furniture.wall_poster(root, Vector3(-21.9, 1.7, 5.5), -90, "poster_synergy")
	Furniture.wall_poster(root, Vector3(-21.9, 1.7, -2.0), -90, "poster_team")
	var clk := Furniture.wall_clock(root, Vector3(-21.9, 2.35, 1.75), -90)
	w.set_meta("clock", clk)
	for c in DESK_CLUSTERS:
		w.add_poi("chat", c + Vector3(0, 0, 2.6 if c.z > 5 else -2.5), Vector3.FORWARD)
	w.add_poi("chat", Vector3(9, 0, 7.6), Vector3.BACK)
	w.add_poi("chat", Vector3(7.5, 0, 7.6), Vector3.BACK)
	w.add_poi("slack", Vector3(8.0, 0, 10.0), Vector3.FORWARD, {"sit": true})
	w.add_poi("slack", Vector3(9.0, 0, 10.0), Vector3.FORWARD, {"sit": true})


func _device(parent: Node3D, kind: String, display: String, owner: String, offset: Vector3) -> Device:
	var d := Device.new()
	d.kind = kind
	d.display = display if owner == "" or owner == "player" else "%s de %s" % [display, _owner_name(owner)]
	d.owner_id = owner
	d.point_offset = offset
	parent.add_child(d)
	d.zone = w.zone_at(d.global_position)
	w.register(d, _id(kind))
	return d


func _owner_name(id: String) -> String:
	if id == "boss":
		return "M. Lebrun"
	var c := Data.coworker(id)
	return c.get("name", id)


func _meeting_room() -> void:
	Furniture.table(root, Vector3(6.6, 0, -11), Vector3(6.8, 0.74, 1.5), Furniture.wood())
	var wb := Furniture.whiteboard(root, Vector3(0.12, 0, -11), -90)
	var wbd := _device(wb.pivot, "whiteboard", "Tableau blanc", "", Vector3(0, 1.4, -0.6))
	wbd.screen = wb.surface
	# TV on the opposite wall
	var tv := Furniture.pivot(root, Vector3(11.88, 0, -11), 90)
	MeshKit.add_box(tv, Vector3(1.6, 0.92, 0.06), Mats.color(Color(0.05, 0.05, 0.06), 0.2), Vector3(0, 1.6, 0), 0.01)
	MeshKit.add(tv, MeshKit.quad(Vector2(1.5, 0.84)), Mats.screen("corp_logo", 0.8), Vector3(0, 1.6, -0.031), Vector3(0, 180, 0), false)
	for i in 6:
		for side in [-1, 1]:
			var x := 3.85 + i * 1.1
			w.add_poi("meeting_seat", Vector3(x, 0, -11 + side * 1.25), Vector3(0, 0, -side))
	w.add_poi("meeting_boss", Vector3(1.0, 0, -11), Vector3.RIGHT)
	var sw := Furniture.pivot(root, Vector3(2.4, 1.2, -8.1), 180)
	MeshKit.add_box(sw, Vector3(0.09, 0.13, 0.02), Mats.color(Color(0.95, 0.95, 0.95), 0.4), Vector3.ZERO, 0.01)
	var lsw := _device(sw, "light_switch", "Interrupteur (salle Synergie)", "", Vector3(0, 0, -0.1))
	lsw.state = {"zone": "meeting"}
	Furniture.plant_static(root, Vector3(11.3, 0, -13.3), 1.0)
	Furniture.wall_poster(root, Vector3(6.5, 1.75, -8.12), 0, "poster_synergy", Vector2(0.5, 0.65))


func _break_room() -> void:
	Furniture.counter(root, Vector3(16.0, 0, -13.55), 180, 6.0)
	var sinkp := Furniture.pivot(root, Vector3(14.5, 0.9, -13.55), 180)
	MeshKit.add_box(sinkp, Vector3(0.5, 0.02, 0.4), Mats.color(Color(0.75, 0.76, 0.78), 0.15, 0.9), Vector3(0, 0.0, 0), 0.01)
	MeshKit.add(sinkp, MeshKit.cylinder(0.015, 0.3, 8), Mats.color(Color(0.8, 0.8, 0.82), 0.15, 1.0), Vector3(0, 0.15, 0.17))
	_device(sinkp, "sink", "Évier", "", Vector3(0, 0.1, -0.5))
	var cm := Furniture.coffee_machine(root, Vector3(16.6, 0.9, -13.6), 180)
	_device(cm, "coffee", "Machine à café", "", Vector3(0, 0.2, -0.55))
	w.add_poi("coffee", Vector3(16.6, 0, -12.6), Vector3.FORWARD)
	w.add_poi("coffee", Vector3(15.7, 0, -12.2), Vector3(0.6, 0, -0.8).normalized())
	w.add_poi("coffee", Vector3(17.5, 0, -12.2), Vector3(-0.6, 0, -0.8).normalized())
	var mw := Furniture.microwave(root, Vector3(18.0, 0.9, -13.6), 180)
	_device(mw, "microwave", "Micro-ondes", "", Vector3(0, 0.15, -0.55))
	var rd := Furniture.radio(root, Vector3(13.5, 0.9, -13.6), 180)
	_device(rd, "radio", "Radio", "", Vector3(0, 0.1, -0.5))
	var fr := Furniture.fridge(root, Vector3(20.6, 0, -13.5), 180)
	_device(fr, "fridge", "Frigo", "", Vector3(0, 1.0, -0.6))
	Furniture.round_table(root, Vector3(16.5, 0, -10.6), 0.65)
	for a in [0.0, 90.0, 180.0, 270.0]:
		var v := Vector3(sin(deg_to_rad(a)), 0, cos(deg_to_rad(a)))
		w.add_poi("break_spot", Vector3(16.5, 0, -10.6) + v * 1.15, -v)
	w.add_poi("break_spot", Vector3(19.5, 0, -12.3), Vector3.FORWARD)
	w.add_poi("break_spot", Vector3(13.6, 0, -12.4), Vector3.FORWARD)
	Furniture.sofa(root, Vector3(21.0, 0, -10.6), 90, Color(0.3, 0.55, 0.5), 1.8)
	Furniture.wall_poster(root, Vector3(12.12, 1.7, -11), -90, "poster_coffee")
	var sw := Furniture.pivot(root, Vector3(14.7, 1.2, -8.1), 180)
	MeshKit.add_box(sw, Vector3(0.09, 0.13, 0.02), Mats.color(Color(0.95, 0.95, 0.95), 0.4), Vector3.ZERO, 0.01)
	var lsw := _device(sw, "light_switch", "Interrupteur (salle de pause)", "", Vector3(0, 0, -0.1))
	lsw.state = {"zone": "break"}


func _copy_room() -> void:
	var pr := Furniture.printer(root, Vector3(-3.0, 0, -13.4), 180)
	var prd := _device(pr, "printer", "Imprimante partagée", "", Vector3(0, 0.9, -0.7))
	prd.state = {"pages": 0, "jammed": false}
	w.add_poi("printer", Vector3(-3.0, 0, -12.3), Vector3.FORWARD)
	var sup := Furniture.filing_cabinet(root, Vector3(-5.6, 0, -11.5), -90, 1.6)
	var supd := _device(sup, "supply", "Armoire à fournitures", "", Vector3(0, 1.0, -0.6))
	supd.state = {"stock": 4}
	Furniture.shelf(root, Vector3(-0.4, 0, -11.5), 90, 2.2, 1.9, rng, true)
	var shred := Furniture.pivot(root, Vector3(-1.2, 0, -13.5))
	MeshKit.add_box(shred, Vector3(0.4, 0.65, 0.35), Mats.color(Color(0.2, 0.2, 0.22), 0.4), Vector3(0, 0.325, 0), 0.02)
	Furniture.solid(shred, Vector3(0.4, 0.65, 0.35), Vector3(0, 0.325, 0))
	Furniture.wall_poster(root, Vector3(-5.88, 1.8, -9.6), -90, "poster_safety", Vector2(0.45, 0.6))


func _toilets() -> void:
	for x in [-11.0, -9.0]:
		var t := Furniture.toilet(root, Vector3(x, 0, -13.55), 180)
		_device(t, "toilet", "Toilettes", "", Vector3(0, 0.6, -0.7))
		w.add_poi("toilet", Vector3(x, 0, -12.7), Vector3.BACK)
	for z in [-12.8, -11.2]:
		var s := Furniture.sink(root, Vector3(-6.35, 0, z), 90)
		_device(s, "sink", "Lavabo", "", Vector3(0, 0.9, -0.5))
	MeshKit.add(root, MeshKit.quad(Vector2(5.6, 1.4)), Mats.textured("tile_wall", 1.0, 0.3, 0.0, true), Vector3(-9, 0.75, -13.92), Vector3.ZERO, false)


func _archives() -> void:
	var rows := [Vector3(-18.5, 0, -13.55), Vector3(-18.5, 0, -11.4), Vector3(-18.5, 0, -9.6)]
	for i in rows.size():
		var s := Furniture.shelf(root, rows[i], 180 if i == 0 else 0, 4.5, 2.2, rng, true)
		var d := _device(s, "shelf_files", "Étagère d'archives %d" % (i + 1), "", Vector3(0, 1.0, -0.6 if i == 0 else -0.6))
		d.state = {"mixed": false}
		w.add_poi("archives_search", rows[i] + Vector3(0, 0, 0.9 if i == 0 else -0.9), Vector3.FORWARD if i == 0 else Vector3.BACK)
	Furniture.shelf(root, Vector3(-21.55, 0, -11.0), -90, 2.5, 2.2, rng, true)
	var sw := Furniture.pivot(root, Vector3(-16.6, 1.2, -8.1), 180)
	MeshKit.add_box(sw, Vector3(0.09, 0.13, 0.02), Mats.color(Color(0.95, 0.95, 0.95), 0.4), Vector3.ZERO, 0.01)
	var lsw := _device(sw, "light_switch", "Interrupteur (archives)", "", Vector3(0, 0, -0.1))
	lsw.state = {"zone": "archives"}


func _boss_office() -> void:
	var p := Furniture.pivot(root, Vector3(19.4, 0, 7.0), 90)  # front faces west (-X)
	var dark := Furniture.wood()
	MeshKit.add_box(p, Vector3(2.0, 0.06, 0.95), Mats.textured("wood_dark", 1.2, 0.35, 0.0, false), Vector3(0, 0.76, 0), 0.02)
	MeshKit.add_box(p, Vector3(2.0, 0.7, 0.06), Mats.textured("wood_dark", 1.2, 0.35, 0.0, false), Vector3(0, 0.38, -0.44), 0.02)
	for sx in [-1, 1]:
		MeshKit.add_box(p, Vector3(0.5, 0.72, 0.9), Mats.textured("wood_dark", 1.2, 0.35, 0.0, false), Vector3(sx * 0.72, 0.37, 0), 0.02)
	Furniture.solid(p, Vector3(2.0, 0.8, 0.95), Vector3(0, 0.4, 0))
	var mon := Node3D.new()
	p.add_child(mon)
	mon.position = Vector3(0.2, 0.79, -0.15)
	MeshKit.add_box(mon, Vector3(0.75, 0.45, 0.03), Mats.color(Color(0.08, 0.08, 0.09), 0.3), Vector3(0, 0.38, 0), 0.012)
	MeshKit.add_box(mon, Vector3(0.05, 0.2, 0.04), Mats.color(Color(0.2, 0.2, 0.2)), Vector3(0, 0.1, 0.03), 0.01)
	var scr := MeshKit.add(mon, MeshKit.quad(Vector2(0.71, 0.41)), Mats.screen("screen_boss"), Vector3(0, 0.38, 0.0165), Vector3.ZERO, false)
	var pc := _device(mon, "pc", "Ordinateur du directeur", "boss", Vector3(0, 0.3, 0.4))
	pc.screen = scr
	pc.state = {"wallpaper": "screen_boss"}
	pc.apply_state()
	var dr := Node3D.new()
	p.add_child(dr)
	dr.position = Vector3(0.72, 0.5, 0.3)
	_device(dr, "boss_drawer", "Tiroir du directeur", "boss", Vector3.ZERO)
	w.desks.append({"index": 99, "pos": p.position, "rot": 90.0, "seat": Vector3(20.3, 0, 7.0), "facing": Vector3.LEFT, "owner": "boss",
		"chair_id": "", "pc_id": pc.ent_id(), "drawer_id": "", "phone_id": "", "papers_pos": Vector3(18.95, 0.8, 6.4)})
	Furniture.shelf(root, Vector3(18.0, 0, 2.3), 180, 3.0, 2.2, rng)
	Furniture.sofa(root, Vector3(16.6, 0, 11.2), 0, Color(0.2, 0.18, 0.18), 2.0)
	Furniture.table(root, Vector3(16.6, 0, 10.0), Vector3(1.0, 0.4, 0.5), Mats.glass())
	Furniture.plant_static(root, Vector3(21.3, 0, 2.7), 1.3)
	Furniture.wall_poster(root, Vector3(21.88, 1.8, 7.0), 90, "poster_boss", Vector2(0.55, 0.75))
	w.add_poi("boss_phone", Vector3(21.0, 0, 9.5), Vector3.LEFT)
	w.add_poi("boss_desk", Vector3(20.3, 0, 7.0), Vector3.LEFT)


func _hall_and_corridor() -> void:
	var wc := Furniture.water_cooler(root, Vector3(21.5, 0, -4.4))
	_device(wc, "water", "Fontaine à eau", "", Vector3(-0.5, 1.0, 0))
	w.add_poi("water", Vector3(20.8, 0, -4.2), Vector3.RIGHT)
	var vd := Furniture.vending(root, Vector3(21.5, 0, -2.4), 90)
	_device(vd, "vending", "Distributeur", "", Vector3(0, 1.0, -0.7))
	Furniture.sofa(root, Vector3(18.0, 0, 1.4), 0, Color(0.25, 0.4, 0.65), 2.0)
	w.add_poi("chat", Vector3(19.6, 0, -3.6), Vector3.RIGHT)
	w.add_poi("chat", Vector3(18.2, 0, -0.3), Vector3.BACK)
	# planning board next to the meeting room (corridor side) and notice board
	var pl := Furniture.pivot(root, Vector3(13.5, 1.55, -7.91), 0)
	MeshKit.add_box(pl, Vector3(0.84, 0.6, 0.02), Mats.color(Color(0.15, 0.15, 0.18), 0.3), Vector3.ZERO, 0.01)
	var pls := MeshKit.add(pl, MeshKit.quad(Vector2(0.78, 0.52)), Mats.decal_tex("sign_meeting_ok"), Vector3(0, 0, 0.011), Vector3.ZERO, false)
	var pld := _device(pl, "planning", "Planning des réunions", "", Vector3(0, -0.5, 0.5))
	pld.screen = pls
	var nb := Furniture.pivot(root, Vector3(19.0, 1.6, -7.91), 0)
	MeshKit.add_box(nb, Vector3(1.6, 1.0, 0.03), Mats.color(Color(0.3, 0.2, 0.12), 0.6), Vector3.ZERO, 0.01)
	MeshKit.add(nb, MeshKit.quad(Vector2(1.5, 0.94)), Mats.decal_tex("notice_board"), Vector3(0, 0, 0.016), Vector3.ZERO, false)
	_device(nb, "notice", "Panneau d'affichage", "", Vector3(0, -0.6, 0.5))
	Furniture.wall_poster(root, Vector3(-14.5, 1.7, -7.91), 180, "poster_coffee", Vector2(0.5, 0.65))
	Furniture.wall_poster(root, Vector3(-6.5, 1.7, -7.91), 180, "poster_safety", Vector2(0.5, 0.65))
	var logo := Furniture.pivot(root, Vector3(18.0, 1.9, 1.91), 180)
	MeshKit.add(logo, MeshKit.quad(Vector2(2.0, 0.62)), Mats.screen("corp_logo", 0.6), Vector3.ZERO, Vector3.ZERO, false)
	Furniture.extinguisher(root, Vector3(-11.8, 0.3, -7.75))
	Furniture.extinguisher(root, Vector3(11.8, 0.3, -7.75))
	# exit sign
	var ex := Furniture.pivot(root, Vector3(-21.85, 2.6, -6.5), -90)
	MeshKit.add_box(ex, Vector3(0.5, 0.18, 0.05), Mats.emissive(Color(0.1, 0.9, 0.3), 1.5), Vector3.ZERO, 0.01)
	# patrol route
	for p in [Vector3(-18, 0, -6.5), Vector3(-9, 0, -6.5), Vector3(0, 0, -6.5), Vector3(10, 0, -6.5), Vector3(18, 0, -6.5),
			Vector3(-19.5, 0, 4.9), Vector3(-11.5, 0, 6.6), Vector3(-2.5, 0, 4.9), Vector3(4.5, 0, 5.0), Vector3(-11.5, 0, -2.6),
			Vector3(-19.5, 0, 11), Vector3(-2.5, 0, 11), Vector3(17, 0, -2)]:
		w.add_poi("patrol", p, Vector3.FORWARD)
	for p in [Vector3(-17, 0, -10.5), Vector3(-9, 0, -10.6), Vector3(-3, 0, -10.6), Vector3(6, 0, -9.0), Vector3(16, 0, -9.0)]:
		w.add_poi("patrol_rooms", p, Vector3.FORWARD)


func _skyline() -> void:
	var m := Mats.screen("skyline", 1.0)
	m = m.duplicate()
	m.emission_energy_multiplier = 0.9
	for spec in [[Vector3(0, 2, 34), 180.0, 140.0], [Vector3(0, 2, -36), 0.0, 140.0], [Vector3(46, 2, -1), -90.0, 110.0], [Vector3(-46, 2, -1), 90.0, 110.0]]:
		var q := MeshKit.add(root, MeshKit.quad(Vector2(spec[2], 40)), m, spec[0], Vector3(0, spec[1], 0), false)


# ------------------------------------------------------------------ props
func _spawn(kind: String, pos: Vector3, rot_y := 0.0, owner := "", id_base := "") -> Prop:
	var p := PropFactory.make(kind)
	p.owner_id = owner
	w.props_root.add_child(p)
	p.global_position = pos
	p.rotation.y = deg_to_rad(rot_y)
	p.home = p.global_transform
	w.register(p, _id(id_base if id_base != "" else kind))
	return p


func _props() -> void:
	for d in w.desks:
		if d.owner == "boss":
			var bc := _spawn("chair_boss", d.seat, -90, "boss", "boss_chair")
			d.chair_id = bc.ent_id()
			var mug := _spawn("mug_boss", Vector3(18.9, 0.82, 7.6), 0, "boss")
			mug.display = "Mug « Meilleur Chef »"
			_spawn("papers", d.papers_pos, 90, "boss")
			continue
		var basis := Basis(Vector3.UP, deg_to_rad(d.rot))
		var chair := _spawn("chair", d.seat + Vector3(0, 0.02, 0), d.rot, d.owner, "chair_desk%d" % d.index)
		d.chair_id = chair.ent_id()
		if d.owner != "" or rng.randf() < 0.5:
			_spawn("papers", d.papers_pos, d.rot + rng.randf_range(-8, 8), d.owner)
		if d.owner != "" and rng.randf() < 0.8:
			_spawn("mug", d.pos + basis * Vector3(0.35, 0.78, 0.15), 0, d.owner)
		if d.owner == "gerard":
			_spawn("stapler", d.pos + basis * Vector3(0.1, 0.78, -0.05), d.rot + 20, "gerard")
	for c in DESK_CLUSTERS:
		_spawn("trash", c + Vector3(1.75, 0.02, 0.9), 0)
	# meeting chairs
	for s in w.poi.get("meeting_seat", []):
		var ch := _spawn("chair_meeting", s.pos + Vector3(0, 0.02, 0), rad_to_deg(atan2(-s.facing.x, -s.facing.z)), "", "meeting_chair")
		s["chair_id"] = ch.ent_id()
	# break room
	for s in w.poi.get("break_spot", []).slice(0, 4):
		var ch := _spawn("chair_meeting", s.pos + Vector3(0, 0.02, 0), rad_to_deg(atan2(-s.facing.x, -s.facing.z)), "", "break_chair")
		s["chair_id"] = ch.ent_id()
	_spawn("salt", Vector3(15.2, 0.93, -13.6), 0)
	_spawn("mug", Vector3(17.3, 0.93, -13.5), 0)
	_spawn("trash", Vector3(12.5, 0.02, -9.0), 0)
	_spawn("marker", Vector3(0.25, 0.92, -11.4), 90)
	var fish := _spawn("fish_box", Vector3(20.6, 0.5, -13.2), 0, "gerard")
	var fridge := _find_device("fridge")
	if fridge:
		fish.hide_inside(fridge.ent_id())
		fridge.contents.append(fish.ent_id())
	# archive box tower: deliberately a bit wobbly
	var base := Vector3(-13.6, 0.0, -12.2)
	for lvl in 5:
		for col in 2:
			var off := Vector3(col * 0.48 + rng.randf_range(-0.04, 0.04), 0.36 * lvl + 0.01, rng.randf_range(-0.05, 0.05) + lvl * 0.015)
			_spawn("box", base + off, rng.randf_range(-6, 6), "", "archive_box")
	for i in 4:
		_spawn("box_small", Vector3(-20.8 + i * 0.4, 0.01, -8.8), rng.randf_range(0, 40), "", "box")
	# plants that can be carried
	for p in [Vector3(-12.5, 0.01, -4.3), Vector3(-1.2, 0.01, -4.3), Vector3(6.0, 0.01, 11.2), Vector3(20.3, 0.01, -7.0)]:
		_spawn("plant_small", p, 0)
	_spawn("plant_big", Vector3(10.8, 0.01, -4.3), 0)
	_spawn("trash", Vector3(-2.0, 0.02, -12.6), 0)
	_spawn("trash", Vector3(15.0, 0.02, 3.0), 0, "boss")
	_spawn("folder", Vector3(-0.9, 0.77, -10.6), 0)
	_spawn("binder", Vector3(5.2, 1.1, 1.0), 0)


func _find_device(kind: String) -> Device:
	for e in w.interactables:
		if e is Device and e.kind == kind:
			return e
	return null


# ------------------------------------------------------------------ navigation
func _navigation() -> void:
	var region := NavigationRegion3D.new()
	region.name = "Nav"
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = Layers.STATIC
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	nm.geometry_source_group_name = Layers.GROUP_NAV
	nm.cell_size = 0.1
	nm.cell_height = 0.1
	nm.agent_radius = 0.3
	nm.agent_height = 1.7
	nm.agent_max_climb = 0.2
	nm.agent_max_slope = 30.0
	nm.region_min_size = 1.0
	nm.filter_baking_aabb = AABB(Vector3(-22.5, -1, -14.5), Vector3(45, 4, 27))
	region.navigation_mesh = nm
	w.add_child(region)
	root.add_to_group(Layers.GROUP_NAV)
	var map := w.get_world_3d().navigation_map
	NavigationServer3D.map_set_cell_size(map, 0.1)
	NavigationServer3D.map_set_cell_height(map, 0.1)
	region.bake_navigation_mesh(false)
	w.nav_region = region
