// Architectural glass: physically-based Fresnel, refraction of what is behind it,
// faint green edge tint, fingerprints / dust breaking up reflections, optional frosting.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D smudge_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec3 tint : source_color = vec3(0.86, 0.93, 0.92);
uniform float refraction = 0.006;
uniform float base_roughness : hint_range(0.0, 1.0) = 0.02;
uniform float smudge_strength : hint_range(0.0, 1.0) = 0.5;
uniform float frost : hint_range(0.0, 1.0) = 0.0;
uniform float frost_lod = 5.0;
uniform float smudge_scale = 0.35;

varying vec3 world_pos;
varying vec3 world_n;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// triplanar dust so the glass never needs UVs
	vec3 an = abs(world_n);
	vec2 puv = an.x > an.z ? world_pos.zy : world_pos.xy;
	float sm = texture(smudge_tex, puv * smudge_scale).r;
	float dirt = clamp((1.0 - sm) * 2.2, 0.0, 1.0) * smudge_strength;

	float ndv = clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0);
	float fresnel = 0.04 + 0.96 * pow(1.0 - ndv, 5.0);

	vec2 bend = (vec2(sm, texture(smudge_tex, puv * smudge_scale * 1.7 + 0.31).r) - 0.5) * refraction;
	bend += NORMAL.xy * refraction * 0.5;
	float lod = frost * frost_lod + dirt * 0.8;
	vec3 behind = textureLod(screen_tex, SCREEN_UV + bend * (1.0 + frost * 4.0), lod).rgb;

	// thicker glass looks greener at grazing angles
	vec3 t = mix(tint, tint * vec3(0.78, 0.92, 0.86), 1.0 - ndv);
	vec3 transmitted = behind * t * (1.0 - fresnel);
	transmitted = mix(transmitted, transmitted * 0.92 + vec3(0.06), frost * 0.8);

	ALBEDO = vec3(0.0) + vec3(0.9) * frost * 0.12 + vec3(dirt * 0.025);
	EMISSION = transmitted;
	METALLIC = 0.0;
	SPECULAR = 0.5;
	ROUGHNESS = clamp(base_roughness + dirt * 0.35 + frost * 0.5, 0.0, 1.0);
	ALPHA = 1.0;
}
