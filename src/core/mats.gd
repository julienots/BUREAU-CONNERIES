class_name Mats
## Shared material library (one instance per look, reused everywhere for batching).

static var _cache: Dictionary = {}
const TEX := "res://assets/textures/"
const GLASS_SHADER := "res://assets/shaders/glass.gdshader"
const LCD_SHADER := "res://assets/shaders/lcd_screen.gdshader"

## Graphics tier the materials are built for (see RenderFx). Changing it drops the cache
## so the menu (built first) and the game never share materials of different tiers.
static var quality := "high"


static func set_quality(q: String) -> void:
	if q != quality:
		_cache.clear()
		quality = q


static func pbr() -> bool:
	return RenderFx.at_least(quality, "medium")


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
		m.normal_scale = 0.7 if not pbr() else 1.0
	var orm := tex(name + "_orm") if pbr() else null
	if orm:
		# G = roughness (multiplied by the requested roughness), R = cavity occlusion
		m.roughness_texture = orm
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		m.roughness = clampf(rough * 1.25, 0.0, 1.0)
		m.ao_enabled = true
		m.ao_texture = orm
		m.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		m.ao_light_affect = 0.35
		if metal > 0.0:
			m.metallic_specular = 0.6
	_cache[key] = m
	return m


## Breaks up perfectly uniform roughness on flat-colour surfaces (finger marks, wear):
## world-space triplanar so procedural meshes need no UVs.
static func _micro(m: StandardMaterial3D, rough: float) -> void:
	if not RenderFx.at_least(quality, "high"):
		return
	var t := tex("micro_rough")
	if t == null:
		return
	m.roughness_texture = t
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.roughness = clampf(rough * 1.15, 0.0, 1.0)
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(0.6, 0.6, 0.6)
	m.uv1_triplanar_sharpness = 2.0


static func color(c: Color, rough := 0.7, metal := 0.0) -> StandardMaterial3D:
	var key := "c_%s_%.2f_%.2f" % [c.to_html(), rough, metal]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	_micro(m, rough)
	if metal > 0.5 and pbr():
		m.metallic_specular = 0.6
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


static func screen(tex_name: String, energy := 1.1) -> Material:
	var key := "scr_%s_%.2f" % [tex_name, energy]
	if _cache.has(key):
		return _cache[key]
	var t := tex(tex_name)
	if pbr() and ResourceLoader.exists(LCD_SHADER):
		var sm := ShaderMaterial.new()
		sm.shader = load(LCD_SHADER)
		sm.set_shader_parameter("image", t)
		sm.set_shader_parameter("energy", energy)
		if t:
			sm.set_shader_parameter("pixels", Vector2(t.get_width(), t.get_height()))
		_cache[key] = sm
		return sm
	var m := StandardMaterial3D.new()
	m.albedo_texture = t
	m.albedo_color = Color.BLACK
	m.emission_enabled = true
	m.emission_texture = t
	m.emission_energy_multiplier = energy
	m.roughness = 0.2
	_cache[key] = m
	return m


## Bright outdoor backdrop seen through the windows (no LCD grid).
static func exterior(tex_name: String, energy: float) -> StandardMaterial3D:
	var key := "ext_%s_%.2f" % [tex_name, energy]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	var t := tex(tex_name)
	m.albedo_texture = t
	m.albedo_color = Color.BLACK
	m.emission_enabled = true
	m.emission_texture = t
	m.emission_energy_multiplier = energy
	m.roughness = 1.0
	m.disable_receive_shadows = true
	_cache[key] = m
	return m


static func glass(frost := 0.0) -> Material:
	var key := "glass_%.2f" % frost
	if _cache.has(key):
		return _cache[key]
	if pbr() and ResourceLoader.exists(GLASS_SHADER):
		var sm := ShaderMaterial.new()
		sm.shader = load(GLASS_SHADER)
		sm.set_shader_parameter("smudge_tex", tex("micro_rough"))
		sm.set_shader_parameter("frost", frost)
		sm.set_shader_parameter("smudge_strength", 0.45 if RenderFx.at_least(quality, "high") else 0.0)
		_cache[key] = sm
		return sm
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.75, 0.88, 0.95, 0.18) if frost <= 0.0 else Color(0.95, 0.97, 1.0, 0.55)
	m.roughness = 0.05
	m.metallic = 0.2
	m.metallic_specular = 0.9
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if frost > 0.0:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_cache[key] = m
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
