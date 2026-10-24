class_name Mats
## Shared material library (one instance per look, reused everywhere for batching).

static var _cache: Dictionary = {}
const TEX := "res://assets/textures/"


static func tex(name: String) -> Texture2D:
	var p := TEX + name + ".png"
	if ResourceLoader.exists(p):
		return load(p)
	return null


static func textured(name: String, uv_scale := 1.0, rough := 0.8, metal := 0.0, normal := true, tint := Color.WHITE) -> StandardMaterial3D:
	var key := "tx_%s_%.2f_%.2f_%.2f_%s_%s" % [name, uv_scale, rough, metal, normal, tint]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex(name + "_albedo") if tex(name + "_albedo") else tex(name)
	m.albedo_color = tint
	m.roughness = rough
	m.metallic = metal
	m.uv1_scale = Vector3(uv_scale, uv_scale, uv_scale)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if normal and tex(name + "_normal"):
		m.normal_enabled = true
		m.normal_texture = tex(name + "_normal")
		m.normal_scale = 0.7
	_cache[key] = m
	return m


static func color(c: Color, rough := 0.7, metal := 0.0) -> StandardMaterial3D:
	var key := "c_%s_%.2f_%.2f" % [c.to_html(), rough, metal]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	_cache[key] = m
	return m


static func hex(h: String, rough := 0.7, metal := 0.0) -> StandardMaterial3D:
	return color(Color(h), rough, metal)


static func emissive(c: Color, energy := 2.0) -> StandardMaterial3D:
	var key := "e_%s_%.2f" % [c.to_html(), energy]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	_cache[key] = m
	return m


static func screen(tex_name: String, energy := 1.1) -> StandardMaterial3D:
	var key := "scr_%s_%.2f" % [tex_name, energy]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	var t := tex(tex_name)
	m.albedo_texture = t
	m.albedo_color = Color.BLACK
	m.emission_enabled = true
	m.emission_texture = t
	m.emission_energy_multiplier = energy
	m.roughness = 0.2
	_cache[key] = m
	return m


static func glass() -> StandardMaterial3D:
	if _cache.has("glass"):
		return _cache.glass
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.75, 0.88, 0.95, 0.18)
	m.roughness = 0.05
	m.metallic = 0.2
	m.metallic_specular = 0.9
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cache.glass = m
	return m


static func decal_tex(name: String, unshaded := false) -> StandardMaterial3D:
	var key := "dt_%s_%s" % [name, unshaded]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex(name)
	m.roughness = 0.6
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_cache[key] = m
	return m


## Ceiling: visible from below only (so a high camera never sees it from above).
static func ceiling() -> StandardMaterial3D:
	if _cache.has("ceiling"):
		return _cache.ceiling
	var m := textured("ceiling", 1.0, 0.9, 0.0, false).duplicate() as StandardMaterial3D
	m.cull_mode = BaseMaterial3D.CULL_BACK
	_cache.ceiling = m
	return m


static func unshaded(c: Color) -> StandardMaterial3D:
	var key := "u_%s" % c.to_html()
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_cache[key] = m
	return m
