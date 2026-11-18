// LCD monitor: emissive image seen through an RGB sub-pixel grid (faded with distance
// to avoid moire), IPS-like angle falloff, backlight bleed, and a glossy coating that
// reflects the office (specular from probes / SSR / lights).
shader_type spatial;
render_mode specular_schlick_ggx;

uniform sampler2D image : source_color, filter_linear_mipmap_anisotropic;
uniform float energy = 1.15;
uniform vec2 pixels = vec2(480.0, 280.0);
uniform float coating_roughness : hint_range(0.0, 1.0) = 0.14;
uniform float flicker = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

void fragment() {
	vec3 c = texture(image, UV).rgb;
	vec2 g = UV * pixels;
	float fw = max(length(fwidth(g)), 1e-4);
	float near_k = clamp(1.6 - fw * 2.2, 0.0, 1.0);
	// three vertical stripes per pixel + dark pixel gaps
	float sx = fract(g.x) * 3.0;
	vec3 stripes = vec3(
		smoothstep(0.0, 0.25, sx) * (1.0 - smoothstep(0.75, 1.0, sx)),
		smoothstep(1.0, 1.25, sx) * (1.0 - smoothstep(1.75, 2.0, sx)),
		smoothstep(2.0, 2.25, sx) * (1.0 - smoothstep(2.75, 3.0, sx)));
	float gap = smoothstep(0.0, 0.12, fract(g.y)) * (1.0 - smoothstep(0.88, 1.0, fract(g.y)));
	vec3 mask = mix(vec3(1.0), stripes * gap * 2.6, near_k * 0.85);
	c *= mask;
	// viewing angle: contrast & brightness fall off, slight warm shift
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float ang = pow(ndv, 0.6);
	c = mix(vec3(dot(c, vec3(0.33))) * vec3(1.05, 1.0, 0.92), c, ang) * mix(0.45, 1.0, ang);
	// backlight bleed on the edges, blacks never fully black
	vec2 e = min(UV, 1.0 - UV);
	float bleed = (1.0 - smoothstep(0.0, 0.06, min(e.x, e.y))) * 0.05;
	c += vec3(0.012, 0.014, 0.02) + bleed;
	c *= 1.0 - flicker * hash(vec2(floor(TIME * 30.0), 1.0)) * 0.08;
	ALBEDO = vec3(0.012);
	EMISSION = c * energy;
	ROUGHNESS = coating_roughness;
	SPECULAR = 0.35;
	METALLIC = 0.0;
}
