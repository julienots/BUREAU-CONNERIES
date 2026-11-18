// Cinematic camera post-process (runs on the tonemapped image, under the HUD):
// lens distortion, chromatic aberration, contrast-adaptive sharpening, bloom lens dirt,
// split-tone grading, filmic toe, vignette, animated luminance-weighted film grain.
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D lens_dirt : hint_default_black, filter_linear;
uniform float distortion = 0.035;
uniform float aberration = 0.0011;
uniform float sharpen = 0.35;
uniform float dirt_strength = 0.0;   // lens dirt is done by the environment glow map
uniform float vignette = 0.42;
uniform float grain = 0.028;
uniform vec3 shadow_tint : source_color = vec3(0.94, 0.98, 1.05);
uniform vec3 highlight_tint : source_color = vec3(1.05, 1.0, 0.93);
uniform float grade_strength = 1.0;
uniform float saturation = 1.04;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

vec3 tap(vec2 uv) { return texture(screen_tex, clamp(uv, vec2(0.001), vec2(0.999))).rgb; }

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 c = uv - 0.5;
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 ca = c * vec2(aspect, 1.0);
	float r2 = dot(ca, ca);
	// barrel distortion that pulls the edges inward (never samples outside the frame)
	vec2 duv = 0.5 + c * (1.0 - distortion * r2) / (1.0 - distortion * 0.25);

	vec2 dir = c * aberration * (0.4 + r2 * 3.0);
	vec3 col;
	col.r = tap(duv + dir).r;
	col.g = tap(duv).g;
	col.b = tap(duv - dir * 1.4).b;

	// contrast-adaptive sharpening (CAS-like): sharpen less where local contrast is already high
	vec2 px = SCREEN_PIXEL_SIZE;
	vec3 n = tap(duv + vec2(0.0, -px.y));
	vec3 s = tap(duv + vec2(0.0, px.y));
	vec3 e = tap(duv + vec2(px.x, 0.0));
	vec3 w = tap(duv + vec2(-px.x, 0.0));
	vec3 mn = min(col, min(min(n, s), min(e, w)));
	vec3 mx = max(col, max(max(n, s), max(e, w)));
	vec3 amp = clamp(min(mn, 1.0 - mx) / max(mx, vec3(1e-4)), 0.0, 1.0);
	vec3 wgt = sqrt(amp) * -sharpen * 0.2;
	col = clamp((col + (n + s + e + w) * wgt) / (1.0 + 4.0 * wgt), 0.0, 1.0);

	// lens dirt lit by the bright parts of the image (blurred screen mip as bloom source)
	vec3 bloom = textureLod(screen_tex, duv, 5.5).rgb + textureLod(screen_tex, duv, 3.5).rgb * 0.5;
	vec3 hot = max(bloom - 0.55, 0.0);
	col += hot * texture(lens_dirt, uv).r * dirt_strength;

	// grading: cool shadows, warm highlights, gentle saturation
	float l = dot(col, vec3(0.2126, 0.7152, 0.0722));
	vec3 graded = col * mix(shadow_tint, highlight_tint, smoothstep(0.05, 0.75, l));
	graded = mix(vec3(l), graded, saturation);
	col = mix(col, graded, grade_strength);

	// optical vignette (cos^4 falloff)
	float v = 1.0 - smoothstep(0.25, 1.15, length(ca) * 1.25);
	col *= mix(1.0, v, vignette);

	// film grain, stronger in the shadows, re-seeded 24 times a second
	float t = floor(TIME * 24.0);
	float g = hash13(vec3(FRAGCOORD.xy, t)) + hash13(vec3(FRAGCOORD.yx * 1.37, t + 17.0)) - 1.0;
	col += g * grain * mix(1.0, 0.35, l);

	COLOR = vec4(col, 1.0);
}
