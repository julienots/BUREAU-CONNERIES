class_name MeshKit
## Procedural modelling toolkit. Builds bevelled / rounded meshes so furniture and
## characters do not look like raw cubes. Meshes are cached by parameters and shared.

static var _cache: Dictionary = {}


## Box with rounded edges and corners (radius r). Smooth normals, box-projected UVs (1 unit = uv_scale).
static func rounded_box(size: Vector3, r: float = 0.02, arc_steps: int = 3, uv_scale: float = 1.0) -> ArrayMesh:
	r = minf(r, minf(size.x, minf(size.y, size.z)) * 0.5 - 0.0005)
	r = maxf(r, 0.0)
	var key := "rbox_%s_%.4f_%d_%.3f" % [size, r, arc_steps, uv_scale]
	if _cache.has(key):
		return _cache[key]
	var h := size * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var inner := h - Vector3(r, r, r)
	# Each face: grid in (u,v) over its two tangent axes, coordinates concentrated at edges.
	var faces := [
		[Vector3.RIGHT, Vector3.BACK, Vector3.UP], [Vector3.LEFT, Vector3.FORWARD, Vector3.UP],
		[Vector3.UP, Vector3.RIGHT, Vector3.BACK], [Vector3.DOWN, Vector3.RIGHT, Vector3.FORWARD],
		[Vector3.BACK, Vector3.RIGHT, Vector3.UP], [Vector3.FORWARD, Vector3.LEFT, Vector3.UP],
	]
	for f in faces:
		var n: Vector3 = f[0]
		var tu: Vector3 = f[1]
		var tv: Vector3 = f[2]
		var hu := absf(h.dot(tu))
		var hv := absf(h.dot(tv))
		var cu := _coords(hu, r, arc_steps)
		var cv := _coords(hv, r, arc_steps)
		var hn := absf(h.dot(n))
		var grid: Array = []
		for j in cv.size():
			var row: Array = []
			for i in cu.size():
				var p: Vector3 = n * hn + tu * cu[i] + tv * cv[j]
				var q := Vector3(clampf(p.x, -inner.x, inner.x), clampf(p.y, -inner.y, inner.y), clampf(p.z, -inner.z, inner.z))
				var d := p - q
				var nn := d.normalized() if d.length() > 0.00001 else n
				var v := q + nn * r
				row.append([v, nn])
			grid.append(row)
		for j in cv.size() - 1:
			for i in cu.size() - 1:
				var a: Array = grid[j][i]
				var b: Array = grid[j][i + 1]
				var c: Array = grid[j + 1][i + 1]
				var d2: Array = grid[j + 1][i]
				for tri in [[a, b, c], [a, c, d2]]:
					# Godot treats clockwise triangles as front faces: enforce it from the normal.
					var fn: Vector3 = (tri[1][0] - tri[0][0]).cross(tri[2][0] - tri[0][0])
					if fn.length_squared() < 1e-14:
						continue
					if fn.dot(tri[0][1] + tri[1][1] + tri[2][1]) > 0.0:
						tri = [tri[0], tri[2], tri[1]]
					for vtx in tri:
						st.set_normal(vtx[1])
						st.set_uv(_box_uv(vtx[0], vtx[1]) * uv_scale)
						st.add_vertex(vtx[0])
	st.generate_tangents()
	var m := st.commit()
	_cache[key] = m
	return m


static func _coords(half: float, r: float, steps: int) -> PackedFloat32Array:
	var c := PackedFloat32Array()
	if r <= 0.0001:
		c.append(-half)
		c.append(half)
		return c
	for i in steps + 1:
		var a := float(i) / steps * PI * 0.5
		c.append(-half + r - r * cos(a))
	for i in steps + 1:
		var a := float(i) / steps * PI * 0.5
		var v := half - r + r * sin(a)
		if v > c[c.size() - 1] + 0.00001:
			c.append(v)
	return c


static func _box_uv(p: Vector3, n: Vector3) -> Vector2:
	var an := n.abs()
	if an.x >= an.y and an.x >= an.z:
		return Vector2(p.z * signf(n.x), -p.y)
	if an.y >= an.z:
		return Vector2(p.x, p.z * signf(n.y))
	return Vector2(-p.x * signf(n.z), -p.y)


static func cylinder(radius: float, height: float, segments: int = 16, top_r: float = -1.0) -> CylinderMesh:
	var key := "cyl_%.3f_%.3f_%d_%.3f" % [radius, height, segments, top_r]
	if _cache.has(key):
		return _cache[key]
	var m := CylinderMesh.new()
	m.bottom_radius = radius
	m.top_radius = radius if top_r < 0.0 else top_r
	m.height = height
	m.radial_segments = segments
	m.rings = 1
	_cache[key] = m
	return m


static func sphere(radius: float, segs: int = 16, height_scale: float = 1.0) -> SphereMesh:
	var key := "sph_%.3f_%d_%.3f" % [radius, segs, height_scale]
	if _cache.has(key):
		return _cache[key]
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0 * height_scale
	m.radial_segments = segs
	m.rings = maxi(segs / 2, 4)
	_cache[key] = m
	return m


static func capsule(radius: float, height: float, segs: int = 12) -> CapsuleMesh:
	var key := "cap_%.3f_%.3f_%d" % [radius, height, segs]
	if _cache.has(key):
		return _cache[key]
	var m := CapsuleMesh.new()
	m.radius = radius
	m.height = maxf(height, radius * 2.0)
	m.radial_segments = segs
	m.rings = 4
	_cache[key] = m
	return m


static func torus(inner: float, outer: float, segs: int = 16) -> TorusMesh:
	var key := "tor_%.3f_%.3f_%d" % [inner, outer, segs]
	if _cache.has(key):
		return _cache[key]
	var m := TorusMesh.new()
	m.inner_radius = inner
	m.outer_radius = outer
	m.rings = segs
	m.ring_segments = 8
	_cache[key] = m
	return m


static func quad(size: Vector2) -> QuadMesh:
	var key := "quad_%s" % size
	if _cache.has(key):
		return _cache[key]
	var m := QuadMesh.new()
	m.size = size
	_cache[key] = m
	return m


static func plane(size: Vector2, subdiv: int = 0) -> PlaneMesh:
	var key := "plane_%s_%d" % [size, subdiv]
	if _cache.has(key):
		return _cache[key]
	var m := PlaneMesh.new()
	m.size = size
	m.subdivide_width = subdiv
	m.subdivide_depth = subdiv
	_cache[key] = m
	return m


## Adds a MeshInstance3D child; returns it for further tweaking.
static func add(parent: Node3D, mesh: Mesh, mat: Material, pos := Vector3.ZERO, rot_deg := Vector3.ZERO, shadows := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func add_box(parent: Node3D, size: Vector3, mat: Material, pos := Vector3.ZERO, r := 0.015, rot_deg := Vector3.ZERO, uv := 1.0) -> MeshInstance3D:
	return add(parent, rounded_box(size, r, 2 if r < 0.03 else 3, uv), mat, pos, rot_deg)


static func clear_cache() -> void:
	_cache.clear()
